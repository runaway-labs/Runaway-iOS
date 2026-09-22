import Foundation
import Testing
@testable import Runaway_iOS

@Suite(.serialized)
struct TrainingProfileIntegrationTests {
    private let calendar = Calendar.current

    @Test func generatedDistanceCopyUsesCurrentPrescriptionWithoutRewritingIntervals() {
        #expect(WorkoutDescriptionPolicy.reconciled(
            "2.8 miles at conversational pace. Keep it easy.", distanceLabel: "8.8 mi"
        ) == "8.8 mi at conversational pace. Keep it easy.")
        #expect(WorkoutDescriptionPolicy.reconciled(
            "Run 2 miles, then 4 x 400m.", distanceLabel: "8.8 mi"
        ) == "Run 2 miles, then 4 x 400m.")
    }

    @Test func recommendationDetailDoesNotBorrowAnUnrelatedPlannedWorkout() throws {
        let rest = try #require(makePlan().workouts.first { !$0.workoutType.isRunning })
        let recommendation = TodayRecommendation(
            directive: .proceed, status: "Ready", title: "Easy Run",
            detail: "Keep the effort conversational.", systemImage: "figure.run", workoutType: .easyRun
        )
        let detail = try #require(TodayRecommendationDetailPolicy.workout(
            recommendation: recommendation, plannedWorkout: rest, date: rest.date
        ))
        #expect(detail.workoutType == .easyRun)
        #expect(detail.id != rest.id)
        #expect(detail.distance == nil)
        #expect(detail.duration == nil)
        #expect(!detail.isCompleted)
    }

    @Test func recommendationDetailPreservesMatchingPlanButNotItsLoadWhenReduced() throws {
        let run = try #require(makePlan().workouts.first { $0.workoutType == .easyRun })
        let matching = TodayRecommendation(
            directive: .proceed, status: "Ready", title: run.title,
            detail: "Follow your plan.", systemImage: "figure.run", workoutType: run.workoutType
        )
        let detail = try #require(TodayRecommendationDetailPolicy.workout(
            recommendation: matching, plannedWorkout: run, date: run.date
        ))
        expectExactlyEqual(detail, run)
        let reduced = TodayRecommendation(
            directive: .reduceIntensity, status: "Ease back", title: "Easy session",
            detail: "Reduce today's effort.", systemImage: "figure.run", workoutType: run.workoutType
        )
        let lighter = try #require(TodayRecommendationDetailPolicy.workout(
            recommendation: reduced, plannedWorkout: run, date: run.date
        ))
        #expect(lighter.distance == nil)
        #expect(lighter.id != run.id)
    }

    @Test func todayAndWeeklyCandidatePoliciesAgreeForEquivalentContext() throws {
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 27))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: date)!
        let profile = makeProfile([(.running, .primary, 3), (.strength, .supporting, 2)], trainingDays: 5)
        let activity = Activity(
            id: 7_002,
            name: "Actual Long Run",
            type: "Run",
            distance: 16_000,
            elapsed_time: 5_400,
            activity_date: yesterday.addingTimeInterval(12 * 60 * 60).timeIntervalSince1970
        )
        let built = TodayRecommendationContextBuilder.build(
            date: date,
            profile: profile,
            plannedWorkout: nil,
            planWorkouts: [],
            activities: [activity],
            readinessScore: 80
        )
        let weeklyCandidate = try #require(
            ComplementarySchedulingPolicy.rankedCandidates(for: built.schedulingContext).first
        )
        let today = TodayRecommendationPolicy.recommendation(
            plannedWorkout: nil,
            profile: profile,
            recentCompletedWorkouts: built.recentCompletedWorkouts,
            readinessScore: 80,
            schedulingContext: built.schedulingContext
        )

        #expect(built.recentCompletedWorkouts.first?.workoutType == .longRun)
        #expect(today.workoutType == weeklyCandidate.workoutType)
        #expect(today.schedulingReason == weeklyCandidate.reason)
    }

    @Test func runningAndStrengthProfileUsesRequestedFrequenciesWithSafeAdjacency() async throws {
        let profile = makeProfile([(.running, .primary, 4), (.strength, .supporting, 2)], trainingDays: 6)
        let plan = try await TrainingPlanService.generatePlan(
            profile: profile,
            scope: .nextWeek,
            existingPlan: makePlan(),
            runningPlanGenerator: { makePlan() }
        )

        #expect(plan.workouts.filter { $0.workoutType.isRunning }.count == 4)
        #expect(plan.workouts.filter { $0.workoutType.isStrength }.count == 2)
        #expect(!hasUnsafeStrengthAdjacency(plan.workouts))
    }

    @Test func mixedProfileIncludesOnlySelectedSupportingActivities() async throws {
        let profile = makeProfile(
            [(.running, .primary, 4), (.strength, .supporting, 2), (.cycling, .supporting, 1)],
            trainingDays: 7
        )
        let plan = try await TrainingPlanService.generatePlan(
            profile: profile,
            scope: .nextWeek,
            existingPlan: makePlan(),
            runningPlanGenerator: { makePlan() }
        )

        let selected = Set(profile.activities.map(\.activity))
        #expect(plan.workouts.compactMap { $0.workoutType.activity }.allSatisfy(selected.contains))
        #expect(plan.workouts.filter { $0.workoutType.isRunning }.count == 4)
        #expect(plan.workouts.filter { $0.workoutType.isStrength }.count == 2)
        #expect(plan.workouts.filter { $0.workoutType == .cycling }.count == 1)
    }

    @Test func remainingWeekPreservesProtectedWorkoutsAndRebuildsOnlyFutureSlots() async throws {
        let existing = makePlan(includeCompletedValues: true)
        let originalBytes = try encoded(existing)
        let today = calendar.startOfDay(for: Date())
        let protected = existing.workouts.filter { $0.isCompleted || $0.date <= today }
        let futureSupporting = existing.workouts.filter {
            !$0.isCompleted && $0.date > today && !$0.workoutType.isRunning
        }

        let regenerated = try await TrainingPlanService.generatePlan(
            profile: makeProfile([(.running, .primary, 4), (.strength, .supporting, 2)], trainingDays: 6),
            scope: .remainingCurrentWeek,
            existingPlan: existing
        )

        for original in protected {
            let copy = try #require(regenerated.workouts.first { $0.id == original.id })
            expectExactlyEqual(copy, original)
        }
        #expect(futureSupporting.allSatisfy { old in
            regenerated.workouts.contains { $0.date == old.date && $0.id != old.id }
        })
        #expect(try encoded(existing) == originalBytes)
    }

    @Test func remainingWeekPreservesEveryRunningPrescriptionIncludingFutureTaperDetails() async throws {
        let weekStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 6)))
        let regenerationDate = try #require(calendar.date(byAdding: .day, value: 3, to: weekStart))
        let existing = makePlan(includeCompletedValues: true, weekStart: weekStart, today: regenerationDate)
        let futureRun = try #require(existing.workouts.last {
            $0.workoutType.isRunning && !$0.isCompleted && $0.date > regenerationDate
        })

        let regenerated = try await TrainingPlanService.generatePlan(
            profile: makeProfile([(.running, .primary, 4), (.strength, .supporting, 2)], trainingDays: 6),
            scope: .remainingCurrentWeek,
            existingPlan: existing,
            regenerationDate: regenerationDate
        )

        let retained = try #require(regenerated.workouts.first { $0.id == futureRun.id })
        expectExactlyEqual(retained, futureRun)
        #expect(regenerated.workouts.filter { $0.workoutType.isRunning }.map(\.id) == existing.workouts.filter { $0.workoutType.isRunning }.map(\.id))
        #expect(regenerated.focusArea == existing.focusArea)
        #expect(regenerated.notes == existing.notes)
        #expect(regenerated.weekNumber == existing.weekNumber)
        #expect(regenerated.goalId == existing.goalId)
    }

    @Test func nextWeekPreservesProgressionAndTaperPrescriptionsFromEstablishedGenerator() async throws {
        let current = makePlan()
        let nextBoundary = calendar.date(byAdding: .day, value: 7, to: TrainingPlanService.currentWeekSunday())!
        let runningPlan = shiftedPlan(current, to: nextBoundary, focusArea: "Race Week", notes: "Taper: preserve every run")

        let generated = try await TrainingPlanService.generatePlan(
            profile: makeProfile([(.running, .primary, 4), (.strength, .supporting, 2)], trainingDays: 6),
            scope: .nextWeek,
            existingPlan: current,
            runningPlanGenerator: { runningPlan }
        )

        let expectedRuns = runningPlan.workouts.filter { $0.workoutType.isRunning }
        let actualRuns = generated.workouts.filter { $0.workoutType.isRunning }
        #expect(actualRuns.map(\.id) == expectedRuns.map(\.id))
        for expected in expectedRuns {
            expectExactlyEqual(try #require(actualRuns.first { $0.id == expected.id }), expected)
        }
        #expect(generated.totalMileage == runningPlan.totalMileage)
        #expect(generated.focusArea == "Race Week")
    }

    @Test func nextWeekStartsAtNextBoundaryWithoutChangingCurrentPlan() async throws {
        let existing = shiftedPlan(
            makePlan(),
            to: calendar.date(byAdding: .day, value: -21, to: TrainingPlanService.currentWeekSunday())!
        )
        let originalBytes = try encoded(existing)
        let expectedStart = calendar.date(byAdding: .day, value: 7, to: TrainingPlanService.currentWeekSunday())!

        let next = try await TrainingPlanService.generatePlan(
            profile: makeProfile([(.running, .primary, 4)], trainingDays: 4),
            scope: .nextWeek,
            existingPlan: existing
        )

        #expect(calendar.isDate(next.weekStartDate, inSameDayAs: expectedStart))
        #expect(try encoded(existing) == originalBytes)
    }

    @Test @MainActor func nextWeekFacadeLeavesActiveAndCacheStateUntouched() async throws {
        let profile = makeProfile([(.running, .primary, 4)], trainingDays: 4)
        let oldPlan = makePlan()
        let nextPlan = shiftedPlan(oldPlan, to: calendar.date(byAdding: .day, value: 7, to: oldPlan.weekStartDate)!)
        let defaults = isolatedDefaults()
        let manager = DataManager.shared
        let originalActive = manager.currentWeeklyPlan
        defer {
            manager.currentWeeklyPlan = originalActive
            clear(defaults)
        }
        manager.currentWeeklyPlan = oldPlan
        try TrainingPlanService.cachePlan(oldPlan, profile: profile, defaults: defaults)

        _ = try await manager.generateTrainingPlan(
            profile: profile,
            scope: .nextWeek,
            defaults: defaults,
            generator: { _, _, _ in nextPlan }
        )

        #expect(manager.currentWeeklyPlan?.id == oldPlan.id)
        guard case let .valid(cached) = TrainingPlanService.cachedPlanStatus(for: profile, defaults: defaults) else {
            Issue.record("Expected current cache to remain valid")
            return
        }
        #expect(cached.id == oldPlan.id)
    }

    @Test @MainActor func failedGenerationKeepsActiveAndCachedPlan() async throws {
        let profile = makeProfile([(.running, .primary, 4)], trainingDays: 4)
        let oldPlan = makePlan()
        let manager = DataManager.shared
        let originalActive = manager.currentWeeklyPlan
        let restoreCache = snapshotStandardCache()
        defer {
            manager.currentWeeklyPlan = originalActive
            restoreCache()
        }
        manager.currentWeeklyPlan = oldPlan
        try TrainingPlanService.cachePlan(oldPlan, profile: profile)

        do {
            _ = try await manager.generateTrainingPlan(
                profile: profile,
                scope: .remainingCurrentWeek,
                generator: { _, _, _ in throw TestFailure.expected }
            )
            Issue.record("Expected generation to fail")
        } catch TestFailure.expected {
        }

        #expect(manager.currentWeeklyPlan?.id == oldPlan.id)
        guard case let .valid(cached) = TrainingPlanService.cachedPlanStatus(for: profile) else {
            Issue.record("Expected the old cache entry to remain valid")
            return
        }
        #expect(cached.id == oldPlan.id)
    }

    @Test @MainActor func cacheEncodingFailureDoesNotPublishGeneratedPlan() async throws {
        let profile = makeProfile([(.running, .primary, 4)], trainingDays: 4)
        let oldPlan = makePlan()
        let invalidPlan = replacingTotalMileage(oldPlan, with: .nan, id: "invalid-generated")
        let defaults = isolatedDefaults()
        let manager = DataManager.shared
        let originalActive = manager.currentWeeklyPlan
        defer {
            manager.currentWeeklyPlan = originalActive
            clear(defaults)
        }
        manager.currentWeeklyPlan = oldPlan
        try TrainingPlanService.cachePlan(oldPlan, profile: profile, defaults: defaults)

        do {
            _ = try await manager.generateTrainingPlan(
                profile: profile,
                scope: .remainingCurrentWeek,
                defaults: defaults,
                generator: { _, _, _ in invalidPlan }
            )
            Issue.record("Expected cache encoding to fail")
        } catch {
        }

        #expect(manager.currentWeeklyPlan?.id == oldPlan.id)
        guard case let .valid(cached) = TrainingPlanService.cachedPlanStatus(for: profile, defaults: defaults) else {
            Issue.record("Expected prior cache to remain valid")
            return
        }
        #expect(cached.id == oldPlan.id)
    }

    @Test func fingerprintMismatchMarksCacheStaleWithoutDeletingIt() throws {
        let cachedProfile = makeProfile([(.running, .primary, 4)], trainingDays: 4)
        let changedProfile = makeProfile([(.running, .primary, 4), (.strength, .supporting, 2)], trainingDays: 6)
        let plan = makePlan()
        let restoreCache = snapshotStandardCache()
        try TrainingPlanService.cachePlan(plan, profile: cachedProfile)
        defer { restoreCache() }

        guard case let .stale(stalePlan) = TrainingPlanService.cachedPlanStatus(for: changedProfile) else {
            Issue.record("Expected a stale cache result")
            return
        }
        #expect(stalePlan.id == plan.id)
        guard case let .valid(retainedPlan) = TrainingPlanService.cachedPlanStatus(for: cachedProfile) else {
            Issue.record("Expected stale inspection not to delete the cache")
            return
        }
        #expect(retainedPlan.id == plan.id)
    }

    @Test func matchingSchemaAndFingerprintAcceptsCache() throws {
        let profile = makeProfile([(.running, .primary, 4), (.cycling, .supporting, 1)], trainingDays: 5)
        let plan = makePlan()
        let restoreCache = snapshotStandardCache()
        try TrainingPlanService.cachePlan(plan, profile: profile)
        defer { restoreCache() }

        guard case let .valid(cached) = TrainingPlanService.cachedPlanStatus(for: profile) else {
            Issue.record("Expected a valid cache result")
            return
        }
        #expect(cached.id == plan.id)
    }

    @Test @MainActor func normalizedLegacyProfileRoundTripsThroughDataManager() async throws {
        var legacyProfile = makeProfile([(.running, .primary, 4), (.cycling, .supporting, 1)], trainingDays: 5)
        legacyProfile.schemaVersion = 0
        let plan = makePlan()
        let defaults = isolatedDefaults()
        let manager = DataManager.shared
        let originalActive = manager.currentWeeklyPlan
        defer {
            manager.currentWeeklyPlan = originalActive
            clear(defaults)
        }
        manager.currentWeeklyPlan = nil
        try TrainingPlanService.cachePlan(plan, profile: legacyProfile, defaults: defaults)

        await manager.loadCurrentWeeklyPlan(profile: legacyProfile, defaults: defaults)

        #expect(manager.currentWeeklyPlan?.id == plan.id)
        guard case .valid = TrainingPlanService.cachedPlanStatus(for: legacyProfile, defaults: defaults) else {
            Issue.record("Expected validated legacy profile to accept normalized cache metadata")
            return
        }
    }

    @Test func schemaMismatchIsStaleAndRawPlanMigrationRemainsInspectable() throws {
        let profile = makeProfile([(.running, .primary, 4)], trainingDays: 4)
        let plan = makePlan()
        let defaults = isolatedDefaults()
        defer { clear(defaults) }
        try TrainingPlanService.cachePlan(plan, profile: profile, defaults: defaults)

        let envelopeData = try #require(defaults.data(forKey: TrainingPlanService.cacheKey))
        var envelope = try #require(JSONSerialization.jsonObject(with: envelopeData) as? [String: Any])
        envelope["profileSchemaVersion"] = 0
        defaults.set(try JSONSerialization.data(withJSONObject: envelope), forKey: TrainingPlanService.cacheKey)
        guard case let .stale(schemaPlan) = TrainingPlanService.cachedPlanStatus(for: profile, defaults: defaults) else {
            Issue.record("Expected schema mismatch to be stale")
            return
        }
        #expect(schemaPlan.id == plan.id)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        defaults.set(try encoder.encode(plan), forKey: TrainingPlanService.cacheKey)
        guard case let .stale(rawPlan) = TrainingPlanService.cachedPlanStatus(for: profile, defaults: defaults) else {
            Issue.record("Expected legacy raw plan to remain inspectable")
            return
        }
        #expect(rawPlan.id == plan.id)
    }

    @Test @MainActor func productionNextWeekReconcilesRequestedRunCountAndMileageDeterministically() async throws {
        let baseline = try await TrainingPlanService.generatePlan(
            profile: makeProfile([(.running, .primary, 5)], trainingDays: 5),
            scope: .nextWeek,
            existingPlan: nil
        )
        let intendedMileage = baseline.workouts
            .filter { $0.workoutType.isRunning }
            .compactMap(\.distance)
            .reduce(0, +)

        for requestedRuns in [4, 6] {
            let profile = makeProfile([(.running, .primary, requestedRuns)], trainingDays: requestedRuns)
            let first = try await TrainingPlanService.generatePlan(
                profile: profile,
                scope: .nextWeek,
                existingPlan: nil
            )
            let second = try await TrainingPlanService.generatePlan(
                profile: profile,
                scope: .nextWeek,
                existingPlan: nil
            )
            let firstRuns = first.workouts.filter { $0.workoutType.isRunning }.sorted { $0.date < $1.date }
            let secondRuns = second.workouts.filter { $0.workoutType.isRunning }.sorted { $0.date < $1.date }

            #expect(firstRuns.count == requestedRuns)
            #expect(firstRuns.filter { $0.workoutType == .longRun }.count == 1)
            #expect(firstRuns.contains { $0.workoutType == .tempoRun || $0.workoutType == .intervalRun })
            #expect(abs(firstRuns.compactMap(\.distance).reduce(0, +) - intendedMileage) < 0.001)
            #expect(zip(firstRuns, secondRuns).allSatisfy { lhs, rhs in
                lhs.date == rhs.date && lhs.workoutType == rhs.workoutType && lhs.distance == rhs.distance
            })
        }
    }

    @Test @MainActor func activityRegenerationPublishesRecordedCompletionBeforeSupportRebalance() async throws {
        let restoreCache = snapshotStandardCache()
        defer { restoreCache() }
        let plan = makePlan()
        let target = try #require(plan.workouts.first {
            $0.workoutType.isRunning && !$0.isCompleted && $0.date <= Date()
        })
        let activity = Activity(
            id: 4242,
            name: "Recorded Run",
            type: "Run",
            distance: 8_046.72,
            elapsed_time: 2_700,
            activity_date: target.date.addingTimeInterval(12 * 60 * 60).timeIntervalSince1970
        )

        let regenerated = try await TrainingPlanService.regeneratePlanWithActivities(
            athleteId: plan.athleteId,
            currentPlan: plan,
            completedActivities: [activity],
            goal: nil,
            profile: makeProfile([(.running, .primary, 2), (.strength, .supporting, 2)], trainingDays: 4)
        )
        let completed = try #require(regenerated.workouts.first { $0.id == target.id })

        #expect(completed.isCompleted)
        #expect(completed.completedActivityId == activity.id)
        #expect(abs((completed.distance ?? 0) - 5) < 0.001)
        #expect(completed.duration == 45)
        #expect(completed.workoutType == target.workoutType)
        #expect(try JSONEncoder().encode(completed.exercises) == JSONEncoder().encode(target.exercises))
    }

    @Test @MainActor func activityRegenerationPreservesAlreadyCompletedRunExactly() async throws {
        let restoreCache = snapshotStandardCache()
        defer { restoreCache() }
        let plan = makePlan(includeCompletedValues: true)
        let completedRun = try #require(plan.workouts.first {
            $0.workoutType.isRunning && $0.isCompleted
        })
        let conflictingSync = Activity(
            id: 9_001,
            name: "Duplicate Sync",
            type: "Run",
            distance: 16_093.44,
            elapsed_time: 7_200,
            activity_date: completedRun.date.addingTimeInterval(12 * 60 * 60).timeIntervalSince1970
        )

        let regenerated = try await TrainingPlanService.regeneratePlanWithActivities(
            athleteId: plan.athleteId,
            currentPlan: plan,
            completedActivities: [conflictingSync],
            goal: nil,
            profile: makeProfile([(.running, .primary, 4)], trainingDays: 4)
        )
        let preserved = try #require(regenerated.workouts.first { $0.id == completedRun.id })
        expectExactlyEqual(preserved, completedRun)
    }

    @Test @MainActor func nonRunningActivityCannotCompleteRunAndPolicyStillSchedulesSelectedSupport() async throws {
        let restoreCache = snapshotStandardCache()
        defer { restoreCache() }
        let plan = runningOnlyPlan()
        let targetRun = try #require(plan.workouts.first {
            !$0.isCompleted && $0.date <= Date()
        })
        let ride = Activity(
            id: 9_002,
            name: "Recorded Ride",
            type: "Ride",
            distance: 32_186.88,
            elapsed_time: 3_600,
            activity_date: targetRun.date.addingTimeInterval(12 * 60 * 60).timeIntervalSince1970
        )

        let regenerated = try await TrainingPlanService.regeneratePlanWithActivities(
            athleteId: plan.athleteId,
            currentPlan: plan,
            completedActivities: [ride],
            goal: nil,
            profile: makeProfile(
                [(.running, .primary, 4), (.cycling, .supporting, 1)],
                trainingDays: 5
            )
        )
        let untouchedRun = try #require(regenerated.workouts.first { $0.id == targetRun.id })

        expectExactlyEqual(untouchedRun, targetRun)
        #expect(regenerated.workouts.filter { $0.workoutType == .cycling }.count == 1)
        #expect(regenerated.workouts.filter { $0.workoutType.isStrength }.isEmpty)
        #expect(abs(regenerated.totalMileage - plan.totalMileage) < 0.001)
    }

    @Test @MainActor func establishedActivityRegenerationAnchorsRecordedRunAndAppliesProfilePolicy() async throws {
        let restoreCache = snapshotStandardCache()
        defer { restoreCache() }
        let plan = runningOnlyPlan()
        let targetRun = try #require(plan.workouts.first {
            !$0.isCompleted && $0.date <= Date()
        })
        let run = Activity(
            id: 9_003,
            name: "Recorded Run",
            type: "Run",
            distance: 8_046.72,
            elapsed_time: 2_700,
            activity_date: targetRun.date.addingTimeInterval(12 * 60 * 60).timeIntervalSince1970
        )

        let regenerated = try await TrainingPlanService.regeneratePlanWithActivities(
            athleteId: plan.athleteId,
            currentPlan: plan,
            completedActivities: [run],
            goal: nil,
            profile: makeProfile(
                [(.running, .primary, 4), (.cycling, .supporting, 1)],
                trainingDays: 5
            )
        )
        let anchor = try #require(regenerated.workouts.first { $0.id == targetRun.id })

        #expect(anchor.date == targetRun.date)
        #expect(anchor.workoutType == targetRun.workoutType)
        #expect(anchor.isCompleted)
        #expect(anchor.completedActivityId == run.id)
        #expect(abs((anchor.distance ?? 0) - 5) < 0.001)
        #expect(anchor.duration == 45)
        #expect(regenerated.workouts.filter { $0.workoutType == .cycling }.count == 1)
        #expect(regenerated.workouts.filter { $0.workoutType.isStrength }.isEmpty)
    }

    @Test @MainActor func finalCalendarDayActivityAfterMidnightIsIncludedByProductionRegeneration() async throws {
        let restoreCache = snapshotStandardCache()
        defer { restoreCache() }
        let plan = runningOnlyPlan()
        let saturdayRun = try #require(plan.workouts.first {
            $0.dayOfWeek == .saturday && $0.workoutType.isRunning
        })
        let lateSaturday = try #require(calendar.date(
            bySettingHour: 22,
            minute: 30,
            second: 0,
            of: saturdayRun.date
        ))
        let activity = Activity(
            id: 9_004,
            name: "Late Saturday Run",
            type: "Run",
            distance: 8_046.72,
            elapsed_time: 2_700,
            activity_date: lateSaturday.timeIntervalSince1970
        )

        #expect(TrainingPlanService.shouldRegeneratePlan(
            currentPlan: plan,
            newActivity: activity
        ))

        let regenerated = try await TrainingPlanService.regeneratePlanWithActivities(
            athleteId: plan.athleteId,
            currentPlan: plan,
            completedActivities: [activity],
            goal: nil,
            profile: makeProfile([(.running, .primary, 4)], trainingDays: 4)
        )
        let anchor = try #require(regenerated.workouts.first { $0.id == saturdayRun.id })

        #expect(anchor.isCompleted)
        #expect(anchor.completedActivityId == activity.id)
        #expect(abs((anchor.distance ?? 0) - 5) < 0.001)
        #expect(anchor.duration == 45)
    }

    @Test @MainActor func addedRunUsesAvailablePolicyValidAlternative() async throws {
        let monday = DayOfWeek.monday.calendarWeekday
        let friday = DayOfWeek.friday.calendarWeekday
        let profile = makeProfile(
            [(.running, .primary, 6)],
            trainingDays: 6,
            unavailableWeekdays: [monday]
        )

        let generated = try await TrainingPlanService.generatePlan(
            profile: profile,
            scope: .nextWeek,
            existingPlan: nil
        )
        let runWeekdays = Set(generated.workouts.filter { $0.workoutType.isRunning }.map {
            $0.dayOfWeek.calendarWeekday
        })

        #expect(generated.workouts.filter { $0.workoutType.isRunning }.count == 6)
        #expect(!runWeekdays.contains(monday))
        #expect(runWeekdays.contains(friday))
    }

    @Test @MainActor func unavailableExtraSlotsReduceRequestedFrequencyDeterministically() async throws {
        let unavailable = Set([
            DayOfWeek.monday.calendarWeekday,
            DayOfWeek.friday.calendarWeekday
        ])
        let profile = makeProfile(
            [(.running, .primary, 6)],
            trainingDays: 6,
            unavailableWeekdays: unavailable
        )

        let first = try await TrainingPlanService.generatePlan(
            profile: profile,
            scope: .nextWeek,
            existingPlan: nil
        )
        let second = try await TrainingPlanService.generatePlan(
            profile: profile,
            scope: .nextWeek,
            existingPlan: nil
        )
        let firstRuns = first.workouts.filter { $0.workoutType.isRunning }.sorted { $0.date < $1.date }
        let secondRuns = second.workouts.filter { $0.workoutType.isRunning }.sorted { $0.date < $1.date }

        #expect(firstRuns.count == 5)
        #expect(firstRuns.allSatisfy { !unavailable.contains($0.dayOfWeek.calendarWeekday) })
        #expect(zip(firstRuns, secondRuns).allSatisfy { lhs, rhs in
            lhs.date == rhs.date && lhs.workoutType == rhs.workoutType && lhs.distance == rhs.distance
        })
    }

    @Test @MainActor func profilelessCompatibilityCacheNeverReturnsAValidPlan() async throws {
        let restoreCache = snapshotStandardCache()
        defer { restoreCache() }
        let plan = makePlan()
        let cachedProfile = makeProfile([(.running, .primary, 4)], trainingDays: 4)
        let changedProfile = makeProfile([(.running, .primary, 4), (.strength, .supporting, 1)], trainingDays: 5)
        try TrainingPlanService.cachePlan(plan, profile: cachedProfile)

        #expect(TrainingPlanService.getCachedPlan() == nil)
        #expect(try await TrainingPlanService.getWeeklyPlan(
            athleteId: plan.athleteId,
            weekStartDate: plan.weekStartDate
        ) == nil)
        #expect(try await TrainingPlanService.getWeeklyPlan(
            athleteId: plan.athleteId,
            weekStartDate: plan.weekStartDate,
            profile: cachedProfile
        )?.id == plan.id)
        #expect(try await TrainingPlanService.getWeeklyPlan(
            athleteId: plan.athleteId,
            weekStartDate: plan.weekStartDate,
            profile: changedProfile
        ) == nil)
    }

    @Test @MainActor func establishedGenerateWeeklyPlanUsesProfilePolicy() async throws {
        let profile = makeProfile([(.running, .primary, 4), (.cycling, .supporting, 1)], trainingDays: 7)
        let restoreCache = snapshotStandardCache()
        defer { restoreCache() }

        let plan = try await TrainingPlanService.generateWeeklyPlan(
            athleteId: 42,
            goal: nil,
            weekStartDate: TrainingPlanService.currentWeekSunday(),
            profile: profile
        )

        #expect(plan.workouts.contains { $0.workoutType == .cycling })
        #expect(!plan.workouts.contains { $0.workoutType.isStrength || $0.workoutType == .yoga })
        #expect(plan.workouts.compactMap { $0.workoutType.activity }.allSatisfy { $0 == .running || $0 == .cycling })
    }

    @Test @MainActor func firstOnboardingGenerationPersistsProfilePublishesCurrentPlanThenCompletes() async throws {
        let defaults = isolatedDefaults()
        defer { clear(defaults) }
        let store = TrainingProfileStore(defaults: defaults)
        let manager = DataManager.shared
        let originalCurrent = manager.currentWeeklyPlan
        let originalPending = manager.pendingNextWeekPlan
        defer {
            manager.currentWeeklyPlan = originalCurrent
            manager.pendingNextWeekPlan = originalPending
        }
        manager.currentWeeklyPlan = nil
        manager.pendingNextWeekPlan = nil
        let profile = makeProfile([(.running, .primary, 3), (.strength, .supporting, 1)], trainingDays: 4)
        var order: [String] = []

        let completed = try await OnboardingCompletionLifecycle.run(
            saveProfile: {
                try store.save(profile)
                order.append("profile")
            },
            generatePlan: {
                #expect(store.profile.fingerprint == profile.fingerprint)
                let plan = try await OnboardingInitialPlanGenerator.generate(
                    profile: store.profile,
                    athleteId: 42,
                    manager: manager,
                    defaults: defaults
                )
                #expect(manager.currentWeeklyPlan?.id == plan.id)
                #expect(manager.pendingNextWeekPlan == nil)
                order.append("plan")
            },
            complete: {
                #expect(manager.currentWeeklyPlan != nil)
                order.append("complete")
                return true
            },
            clearDraft: {}
        )

        #expect(completed)
        #expect(order == ["profile", "plan", "complete"])
    }

    @Test func nextWeekWithNoRunningSelectionRemovesEveryBaselineRun() async throws {
        let baseline = makePlan()
        let profile = makeProfile([(.strength, .primary, 2)], trainingDays: 2)

        let generated = try await TrainingPlanService.generatePlan(
            profile: profile,
            scope: .nextWeek,
            existingPlan: nil,
            runningPlanGenerator: { baseline }
        )

        #expect(generated.workouts.filter { $0.workoutType.isRunning }.isEmpty)
        #expect(generated.workouts.filter { $0.workoutType.isStrength }.count == 2)
    }

    @Test func nextWeekWithZeroRunningFrequencyRemovesEveryBaselineRun() async throws {
        let baseline = makePlan()
        let profile = makeProfile(
            [(.strength, .primary, 2), (.running, .optional, 0)],
            trainingDays: 2
        )

        let generated = try await TrainingPlanService.generatePlan(
            profile: profile,
            scope: .nextWeek,
            existingPlan: nil,
            runningPlanGenerator: { baseline }
        )

        #expect(generated.workouts.filter { $0.workoutType.isRunning }.isEmpty)
        #expect(generated.workouts.filter { $0.workoutType.isStrength }.count == 2)
    }

    @Test func nextWeekRelocatesBaselineRunOffUnavailableWeekdayWithoutLosingPrescription() async throws {
        let baseline = makePlan()
        let unavailable = DayOfWeek.tuesday.calendarWeekday
        let profile = makeProfile(
            [(.running, .primary, 4)],
            trainingDays: 4,
            unavailableWeekdays: [unavailable]
        )

        let generated = try await TrainingPlanService.generatePlan(
            profile: profile,
            scope: .nextWeek,
            existingPlan: nil,
            runningPlanGenerator: { baseline }
        )
        let baselineTypes = baseline.workouts.filter { $0.workoutType.isRunning }.map(\.workoutType).sorted { $0.rawValue < $1.rawValue }
        let generatedRuns = generated.workouts.filter { $0.workoutType.isRunning }

        #expect(generatedRuns.count == 4)
        #expect(generatedRuns.allSatisfy { $0.dayOfWeek.calendarWeekday != unavailable })
        #expect(generatedRuns.map(\.workoutType).sorted { $0.rawValue < $1.rawValue } == baselineTypes)
    }

    @Test func nextWeekMovesLongRunToPreferredWeekdayWhilePreservingItsPrescription() async throws {
        let baseline = makePlan()
        let baselineLongRun = try #require(baseline.workouts.first { $0.workoutType == .longRun })
        var profile = makeProfile([(.running, .primary, 4)], trainingDays: 4)
        profile.preferredLongRunWeekday = DayOfWeek.wednesday.calendarWeekday

        let generated = try await TrainingPlanService.generatePlan(
            profile: profile,
            scope: .nextWeek,
            existingPlan: nil,
            runningPlanGenerator: { baseline }
        )
        let longRun = try #require(generated.workouts.first { $0.workoutType == .longRun })

        #expect(longRun.dayOfWeek == .wednesday)
        #expect(longRun.id == baselineLongRun.id)
        #expect(longRun.distance == baselineLongRun.distance)
        #expect(longRun.duration == baselineLongRun.duration)
        #expect(longRun.targetPace == baselineLongRun.targetPace)
    }

    @Test func invertedPrimaryAndSupportingRolesHonorBothRequestedFrequencies() async throws {
        let profile = makeProfile(
            [(.strength, .primary, 3), (.running, .supporting, 2)],
            trainingDays: 5
        )

        let generated = try await TrainingPlanService.generatePlan(
            profile: profile,
            scope: .nextWeek,
            existingPlan: nil,
            runningPlanGenerator: { makePlan() }
        )

        #expect(generated.workouts.filter { $0.workoutType.isStrength }.count == 3)
        #expect(generated.workouts.filter { $0.workoutType.isRunning }.count == 2)
    }

    @Test @MainActor func missingAndCorruptProfileMigrationUsesExistingPlanEvidence() throws {
        let existing = planWithLongRun(on: .wednesday)

        for isCorrupt in [false, true] {
            let defaults = isolatedDefaults()
            defer { clear(defaults) }
            if isCorrupt {
                defaults.set(Data("corrupt".utf8), forKey: "trainingProfile.v1")
            }

            let store = TrainingProfileStore(defaults: defaults, existingPlan: existing)

            #expect(store.profile.preference(for: .running)?.sessionsPerWeek == 4)
            #expect(store.profile.preference(for: .strength)?.role == .supporting)
            #expect(store.profile.preference(for: .strength)?.sessionsPerWeek == 2)
            #expect(store.profile.preferredLongRunWeekday == DayOfWeek.wednesday.calendarWeekday)
            #expect(store.needsPersonalization)
        }
    }

    @Test func weekProgressMatchesOnlyCompatibleRunsAndExcludesSupportingSessions() throws {
        let plan = makePlan()
        let run = try #require(plan.workouts.first { $0.workoutType.isRunning })
        let strength = try #require(plan.workouts.first { $0.workoutType.isStrength })
        let rideOnRunDay = Activity(
            id: 8_001,
            name: "Morning Ride",
            type: "Ride",
            distance: 32_186.88,
            elapsed_time: 3_600,
            activity_date: run.date.addingTimeInterval(9 * 3_600).timeIntervalSince1970
        )
        let recordedRun = Activity(
            id: 8_002,
            name: "Morning Run",
            type: "Run",
            distance: 8_046.72,
            elapsed_time: 2_700,
            activity_date: run.date.addingTimeInterval(10 * 3_600).timeIntervalSince1970
        )
        let rideOnStrengthDay = Activity(
            id: 8_003,
            name: "Recovery Ride",
            type: "Ride",
            distance: 16_093.44,
            elapsed_time: 2_400,
            activity_date: strength.date.addingTimeInterval(10 * 3_600).timeIntervalSince1970
        )

        let entries = plan.mergedWithActivities([rideOnRunDay, recordedRun, rideOnStrengthDay])
        let runEntry = try #require(entries.first { $0.plannedWorkout?.id == run.id })
        let stats = plan.weekStats(with: [rideOnRunDay, recordedRun, rideOnStrengthDay])

        #expect(runEntry.actualActivity?.id == recordedRun.id)
        #expect(abs(stats.actualMiles - 5) < 0.001)
        #expect(stats.completedWorkouts == 1)
        #expect(stats.plannedWorkouts == plan.workouts.filter { $0.workoutType.isRunning }.count)
    }

    @Test func noPlanProgressCountsOnlyRecordedRuns() {
        let weekStart = calendar.date(from: DateComponents(year: 2026, month: 8, day: 23))!
        let run = Activity(
            id: 8_101,
            name: "Run",
            type: "Run",
            distance: 8_046.72,
            activity_date: weekStart.addingTimeInterval(86_400).timeIntervalSince1970
        )
        let ride = Activity(
            id: 8_102,
            name: "Ride",
            type: "Ride",
            distance: 32_186.88,
            activity_date: weekStart.addingTimeInterval(2 * 86_400).timeIntervalSince1970
        )

        let stats = WeeklyRunProgress.activitiesOnly(
            [run, ride],
            weekStart: weekStart,
            calendar: calendar
        )

        #expect(abs(stats.actualMiles - 5) < 0.001)
        #expect(stats.completedRuns == 1)
    }

    @Test func todayAdjustmentTotalMileageExcludesDistanceOnNonRunningWorkout() throws {
        let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 26))!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let plan = WeeklyTrainingPlan(
            id: "mixed-adjustment",
            athleteId: 1,
            weekStartDate: calendar.date(byAdding: .day, value: -3, to: today)!,
            weekEndDate: calendar.date(byAdding: .day, value: 3, to: today)!,
            workouts: [
                DailyWorkout(id: "run", date: today, dayOfWeek: .wednesday, workoutType: .tempoRun, title: "Tempo", description: "Run", duration: 45, distance: 6, targetPace: "8:00/mi", exercises: nil, isCompleted: false, completedActivityId: nil),
                DailyWorkout(id: "ride", date: tomorrow, dayOfWeek: .thursday, workoutType: .cycling, title: "Ride", description: "Bike", duration: 60, distance: 30, targetPace: nil, exercises: nil, isCompleted: false, completedActivityId: nil),
            ],
            weekNumber: nil,
            totalMileage: 6,
            focusArea: nil,
            notes: nil,
            generatedAt: today,
            goalId: nil
        )

        let adjusted = try #require(TodayRecommendationPolicy.applying(
            .easierWorkout,
            to: plan,
            on: today,
            readinessScore: 55
        ))

        #expect(abs(adjusted.plan.totalMileage - 3.9) < 0.001)
    }

    @Test @MainActor func planSurfaceReadsLiveDataManagerPlanAndSharedProfileStore() {
        let defaults = isolatedDefaults()
        defer { clear(defaults) }
        let manager = DataManager.shared
        let original = manager.currentWeeklyPlan
        defer { manager.currentWeeklyPlan = original }
        let store = TrainingProfileStore(defaults: defaults)
        let surface = WeeklyTrainingPlanSurface(dataManager: manager, trainingProfileStore: store)
        let first = replacingTotalMileage(makePlan(), with: 20, id: "surface-first")
        let second = replacingTotalMileage(makePlan(), with: 24, id: "surface-second")

        manager.currentWeeklyPlan = first
        #expect(surface.currentPlan?.id == first.id)
        #expect(surface.trainingProfileStore === store)

        manager.currentWeeklyPlan = second
        #expect(surface.currentPlan?.id == second.id)
    }

    @Test @MainActor func laterOverlappingGenerationPreventsOlderPlanFromPublishing() async throws {
        let defaults = isolatedDefaults()
        defer { clear(defaults) }
        let manager = DataManager.shared
        let originalCurrent = manager.currentWeeklyPlan
        defer { manager.currentWeeklyPlan = originalCurrent }
        let oldProfile = makeProfile([(.running, .primary, 4)], trainingDays: 4)
        let newProfile = makeProfile([(.running, .primary, 3), (.strength, .supporting, 2)], trainingDays: 5)
        let input = replacingTotalMileage(makePlan(), with: 20, id: "overlap-input")
        let oldResult = replacingTotalMileage(input, with: 21, id: "older-result")
        let newResult = replacingTotalMileage(input, with: 22, id: "newer-result")
        let gate = PlanGenerationGate()
        manager.currentWeeklyPlan = input

        let older = Task {
            try await manager.generateTrainingPlan(
                profile: oldProfile,
                scope: .remainingCurrentWeek,
                regenerationInput: input,
                defaults: defaults
            ) { _, _, _ in
                await gate.suspendGeneration()
                return oldResult
            }
        }
        await gate.waitUntilSuspended()

        _ = try await manager.generateTrainingPlan(
            profile: newProfile,
            scope: .remainingCurrentWeek,
            regenerationInput: input,
            defaults: defaults
        ) { _, _, _ in newResult }
        await gate.resumeGeneration()

        do {
            _ = try await older.value
            Issue.record("The superseded generation unexpectedly published")
        } catch is CancellationError {
            // Expected: only the latest generation may publish.
        }

        #expect(manager.currentWeeklyPlan?.id == newResult.id)
        guard case let .valid(cached) = TrainingPlanService.cachedPlanStatus(for: newProfile, defaults: defaults) else {
            Issue.record("Expected the latest profile and plan to own the cache")
            return
        }
        #expect(cached.id == newResult.id)
    }

    @Test @MainActor func unchangedEditorSaveConfirmsPersonalizationWithoutRegeneration() {
        let defaults = isolatedDefaults()
        defer { clear(defaults) }
        let store = TrainingProfileStore(defaults: defaults)
        var generations = 0
        let model = TrainingProfileEditorViewModel(
            store: store,
            generatePlan: { _, _ in
                generations += 1
                return makePlan()
            }
        )

        model.save()

        #expect(model.shouldDismiss)
        #expect(generations == 0)
        #expect(store.hasPersonalizedProfile)
        #expect(!store.needsPersonalization)
    }

    @Test func unrelatedActivityTodayCannotSupersedeOutstandingPlannedRun() throws {
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 27))!
        let plannedRun = DailyWorkout(id: "today-run", date: date, dayOfWeek: .thursday, workoutType: .easyRun, title: "Easy Run", description: "Run", duration: 40, distance: 4, targetPace: nil, exercises: nil, isCompleted: false, completedActivityId: nil)
        let ride = Activity(id: 9_100, name: "Lunch Ride", type: "Ride", distance: 20_000, activity_date: date.addingTimeInterval(12 * 3_600).timeIntervalSince1970)
        let run = Activity(id: 9_101, name: "Evening Run", type: "Run", distance: 6_437.36, activity_date: date.addingTimeInterval(18 * 3_600).timeIntervalSince1970)

        #expect(TodayActivityCompletionPolicy.completedActivity(
            for: plannedRun,
            among: [ride],
            on: date,
            calendar: calendar
        ) == nil)
        #expect(TodayActivityCompletionPolicy.completedActivity(
            for: plannedRun,
            among: [ride, run],
            on: date,
            calendar: calendar
        )?.id == run.id)
    }

    @Test func weeklyIntervalIncludesAllOfSaturdayAndExcludesFollowingSunday() throws {
        let plan = makePlan()
        let lateSaturday = try #require(calendar.date(bySettingHour: 23, minute: 59, second: 59, of: plan.weekEndDate))
        let followingSunday = try #require(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: plan.weekEndDate)))

        #expect(plan.contains(date: lateSaturday, calendar: calendar))
        #expect(!plan.contains(date: followingSunday, calendar: calendar))
    }

    @Test func everyLegacyLaterOnboardingStepResumesAtActivityMixUntilProfileAnswersExist() {
        let legacyLaterSteps: [OnboardingStep] = [
            .experienceAssessment,
            .movementTest,
            .locationPermission,
            .coachSelection,
            .completion,
        ]

        for step in legacyLaterSteps {
            #expect(OnboardingStep.resumeStep(
                persistedRawValue: step.rawValue,
                trainingDraftFlowVersion: nil
            ) == .activityMix)
            #expect(OnboardingStep.resumeStep(
                persistedRawValue: step.rawValue,
                trainingDraftFlowVersion: OnboardingAnswers.currentFlowVersion
            ) == step)
        }
    }

    private func snapshotStandardCache() -> () -> Void {
        let defaults = UserDefaults.standard
        let cachedPlan = defaults.object(forKey: TrainingPlanService.cacheKey)
        let expiration = defaults.object(forKey: TrainingPlanService.cacheExpirationKey)
        return {
            if let cachedPlan { defaults.set(cachedPlan, forKey: TrainingPlanService.cacheKey) }
            else { defaults.removeObject(forKey: TrainingPlanService.cacheKey) }
            if let expiration { defaults.set(expiration, forKey: TrainingPlanService.cacheExpirationKey) }
            else { defaults.removeObject(forKey: TrainingPlanService.cacheExpirationKey) }
        }
    }

    private func planWithLongRun(on preferredDay: DayOfWeek) -> WeeklyTrainingPlan {
        let plan = makePlan()
        guard
            let longIndex = plan.workouts.firstIndex(where: { $0.workoutType == .longRun }),
            let targetIndex = plan.workouts.firstIndex(where: { $0.dayOfWeek == preferredDay })
        else { return plan }
        var workouts = plan.workouts
        let long = workouts[longIndex]
        let target = workouts[targetIndex]
        workouts[longIndex] = DailyWorkout(
            id: target.id,
            date: long.date,
            dayOfWeek: long.dayOfWeek,
            workoutType: target.workoutType,
            title: target.title,
            description: target.description,
            duration: target.duration,
            distance: target.distance,
            targetPace: target.targetPace,
            exercises: target.exercises,
            isCompleted: target.isCompleted,
            completedActivityId: target.completedActivityId
        )
        workouts[targetIndex] = DailyWorkout(
            id: long.id,
            date: target.date,
            dayOfWeek: target.dayOfWeek,
            workoutType: long.workoutType,
            title: long.title,
            description: long.description,
            duration: long.duration,
            distance: long.distance,
            targetPace: long.targetPace,
            exercises: long.exercises,
            isCompleted: long.isCompleted,
            completedActivityId: long.completedActivityId
        )
        return WeeklyTrainingPlan(
            id: plan.id,
            athleteId: plan.athleteId,
            weekStartDate: plan.weekStartDate,
            weekEndDate: plan.weekEndDate,
            workouts: workouts,
            weekNumber: plan.weekNumber,
            totalMileage: plan.totalMileage,
            focusArea: plan.focusArea,
            notes: plan.notes,
            generatedAt: plan.generatedAt,
            goalId: plan.goalId
        )
    }

    @Test(arguments: [TrainingActivity.strength, .cycling, .swimming, .walking, .hiking])
    func supportingActivitiesNeverChangeRunningMileageOrCount(_ activity: TrainingActivity) async throws {
        let runningOnly = makeProfile([(.running, .primary, 4)], trainingDays: 4)
        let mixed = makeProfile([(.running, .primary, 4), (activity, .supporting, 1)], trainingDays: 5)
        let existing = makePlan()

        let baseline = try await TrainingPlanService.generatePlan(profile: runningOnly, scope: .nextWeek, existingPlan: existing)
        let supported = try await TrainingPlanService.generatePlan(profile: mixed, scope: .nextWeek, existingPlan: existing)
        let baselineRuns = baseline.workouts.filter { $0.workoutType.isRunning }
        let supportedRuns = supported.workouts.filter { $0.workoutType.isRunning }

        #expect(supportedRuns.count == baselineRuns.count)
        #expect(supported.totalMileage == baseline.totalMileage)
        #expect(supported.totalMileage == supportedRuns.compactMap(\.distance).reduce(0, +))
    }

    @Test @MainActor func nextWeekGenerationPersistsPendingPlanWithoutReplacingCurrentWeek() async throws {
        let defaults = isolatedDefaults()
        defer { clear(defaults) }

        let manager = DataManager.shared
        let originalCurrentPlan = manager.currentWeeklyPlan
        let originalPendingPlan = manager.pendingNextWeekPlan
        defer {
            manager.currentWeeklyPlan = originalCurrentPlan
            manager.pendingNextWeekPlan = originalPendingPlan
        }

        let profile = makeProfile([(.running, .primary, 4)], trainingDays: 4)
        let currentPlan = replacingTotalMileage(makePlan(), with: 24, id: "current-owned")
        let nextWeekStart = calendar.date(
            byAdding: .day,
            value: 7,
            to: TrainingPlanService.currentWeekSunday()
        )!
        let nextPlan = replacingTotalMileage(
            shiftedPlan(currentPlan, to: nextWeekStart),
            with: 28,
            id: "pending-owned"
        )
        manager.currentWeeklyPlan = currentPlan
        manager.pendingNextWeekPlan = nil

        let published = try await manager.generateTrainingPlan(
            profile: profile,
            scope: .nextWeek,
            defaults: defaults
        ) { receivedProfile, receivedScope, existingPlan in
            #expect(receivedProfile.fingerprint == profile.fingerprint)
            #expect(receivedScope == .nextWeek)
            #expect(existingPlan?.id == currentPlan.id)
            return nextPlan
        }

        #expect(published.id == nextPlan.id)
        #expect(manager.currentWeeklyPlan?.id == currentPlan.id)
        #expect(manager.pendingNextWeekPlan?.id == nextPlan.id)
        #expect(
            TrainingPlanService.pendingNextWeekPlan(for: profile, defaults: defaults)?.id
                == nextPlan.id
        )
    }

    @Test @MainActor func loadPromotesPendingPlanWhenItsWeekBecomesCurrent() async throws {
        let defaults = isolatedDefaults()
        defer { clear(defaults) }

        let manager = DataManager.shared
        let originalCurrentPlan = manager.currentWeeklyPlan
        let originalPendingPlan = manager.pendingNextWeekPlan
        defer {
            manager.currentWeeklyPlan = originalCurrentPlan
            manager.pendingNextWeekPlan = originalPendingPlan
        }

        let profile = makeProfile([(.running, .primary, 4)], trainingDays: 4)
        let pendingPlan = replacingTotalMileage(makePlan(), with: 31, id: "pending-now-current")
        try TrainingPlanService.cachePendingNextWeekPlan(
            pendingPlan,
            profile: profile,
            defaults: defaults
        )
        manager.currentWeeklyPlan = nil
        manager.pendingNextWeekPlan = nil

        await manager.loadCurrentWeeklyPlan(profile: profile, defaults: defaults)

        #expect(manager.currentWeeklyPlan?.id == pendingPlan.id)
        #expect(manager.pendingNextWeekPlan == nil)
        #expect(TrainingPlanService.pendingNextWeekPlan(for: profile, defaults: defaults) == nil)
        guard case let .valid(cachedPlan) = TrainingPlanService.cachedPlanStatus(
            for: profile,
            defaults: defaults
        ) else {
            Issue.record("Promoted pending plan should become the valid current cache")
            return
        }
        #expect(cachedPlan.id == pendingPlan.id)
    }

    @Test @MainActor func remainingWeekGenerationUsesPriorProfileStaleCacheOnlyAsInput() async throws {
        let defaults = isolatedDefaults()
        defer { clear(defaults) }

        let manager = DataManager.shared
        let originalCurrentPlan = manager.currentWeeklyPlan
        let originalPendingPlan = manager.pendingNextWeekPlan
        defer {
            manager.currentWeeklyPlan = originalCurrentPlan
            manager.pendingNextWeekPlan = originalPendingPlan
        }

        let oldProfile = makeProfile([(.running, .primary, 4)], trainingDays: 4)
        var newProfile = oldProfile
        newProfile.trainingDaysPerWeek = 5
        let priorPlan = replacingTotalMileage(makePlan(), with: 24, id: "prior-profile-plan")
        let regeneratedPlan = replacingTotalMileage(priorPlan, with: 36, id: "new-profile-plan")
        try TrainingPlanService.cachePlan(priorPlan, profile: oldProfile, defaults: defaults)
        manager.currentWeeklyPlan = nil
        manager.pendingNextWeekPlan = nil

        guard case .stale = TrainingPlanService.cachedPlanStatus(
            for: newProfile,
            defaults: defaults
        ) else {
            Issue.record("Prior-profile plan should be stale after a material profile change")
            return
        }

        _ = try await manager.generateTrainingPlan(
            profile: newProfile,
            scope: .remainingCurrentWeek,
            defaults: defaults
        ) { _, scope, existingPlan in
            #expect(scope == .remainingCurrentWeek)
            #expect(existingPlan?.id == priorPlan.id)
            return regeneratedPlan
        }

        #expect(manager.currentWeeklyPlan?.id == regeneratedPlan.id)
        guard case let .valid(cachedPlan) = TrainingPlanService.cachedPlanStatus(
            for: newProfile,
            defaults: defaults
        ) else {
            Issue.record("Successful regeneration should replace stale cache ownership")
            return
        }
        #expect(cachedPlan.id == regeneratedPlan.id)
    }

    @Test @MainActor func failedRegenerationPreservesCurrentOwnershipAndRetryUsesSameInput() async throws {
        let defaults = isolatedDefaults()
        defer { clear(defaults) }

        let manager = DataManager.shared
        let originalCurrentPlan = manager.currentWeeklyPlan
        let originalPendingPlan = manager.pendingNextWeekPlan
        defer {
            manager.currentWeeklyPlan = originalCurrentPlan
            manager.pendingNextWeekPlan = originalPendingPlan
        }

        let oldProfile = makeProfile([(.running, .primary, 4)], trainingDays: 4)
        var newProfile = oldProfile
        newProfile.trainingDaysPerWeek = 5
        let preservedInput = replacingTotalMileage(makePlan(), with: 24, id: "preserved-input")
        let retryPlan = replacingTotalMileage(preservedInput, with: 35, id: "retry-success")
        try TrainingPlanService.cachePlan(preservedInput, profile: oldProfile, defaults: defaults)
        manager.currentWeeklyPlan = preservedInput
        manager.pendingNextWeekPlan = nil

        do {
            _ = try await manager.generateTrainingPlan(
                profile: newProfile,
                scope: .remainingCurrentWeek,
                regenerationInput: preservedInput,
                defaults: defaults
            ) { _, _, existingPlan in
                #expect(existingPlan?.id == preservedInput.id)
                throw TestFailure.expected
            }
            Issue.record("Expected regeneration failure")
        } catch TestFailure.expected {
            // Expected failure preserves existing ownership.
        }

        #expect(manager.currentWeeklyPlan?.id == preservedInput.id)
        guard case let .stale(stalePlan) = TrainingPlanService.cachedPlanStatus(
            for: newProfile,
            defaults: defaults
        ) else {
            Issue.record("Failure should preserve the prior-profile cache as stale input only")
            return
        }
        #expect(stalePlan.id == preservedInput.id)

        _ = try await manager.generateTrainingPlan(
            profile: newProfile,
            scope: .remainingCurrentWeek,
            regenerationInput: preservedInput,
            defaults: defaults
        ) { _, _, existingPlan in
            #expect(existingPlan?.id == preservedInput.id)
            return retryPlan
        }

        #expect(manager.currentWeeklyPlan?.id == retryPlan.id)
    }

    @Test @MainActor func productionRouteBuildsEditorWithInjectedSharedStore() throws {
        let defaults = isolatedDefaults()
        defer { clear(defaults) }

        let store = TrainingProfileStore(defaults: defaults)
        let route = TrainingProfileRoute(store: store)
        let model = route.makeEditorModel(
            currentPlan: { nil },
            generatePlan: { _, _, _ in makePlan() }
        )

        #expect(model.trainingProfileStore === store)
    }

    @Test @MainActor func editorPreservesPreSavePlanUntilNextWeekPersistenceSucceeds() async throws {
        let defaults = isolatedDefaults()
        defer { clear(defaults) }

        let manager = DataManager.shared
        let originalCurrentPlan = manager.currentWeeklyPlan
        let originalPendingPlan = manager.pendingNextWeekPlan
        defer {
            manager.currentWeeklyPlan = originalCurrentPlan
            manager.pendingNextWeekPlan = originalPendingPlan
        }

        let store = TrainingProfileStore(defaults: defaults)
        let currentPlan = replacingTotalMileage(makePlan(), with: 24, id: "editor-preserved")
        let pendingPlan = replacingTotalMileage(
            shiftedPlan(
                currentPlan,
                to: calendar.date(
                    byAdding: .day,
                    value: 7,
                    to: TrainingPlanService.currentWeekSunday()
                )!
            ),
            with: 30,
            id: "editor-pending"
        )
        manager.currentWeeklyPlan = currentPlan
        manager.pendingNextWeekPlan = nil

        let model = TrainingProfileEditorViewModel(
            store: store,
            currentPlan: { manager.currentWeeklyPlan },
            generatePlan: { profile, scope, regenerationInput in
                try await manager.generateTrainingPlan(
                    profile: profile,
                    scope: scope,
                    regenerationInput: regenerationInput,
                    defaults: defaults
                ) { _, _, existingPlan in
                    #expect(existingPlan?.id == currentPlan.id)
                    return pendingPlan
                }
            }
        )
        model.draft.trainingDaysPerWeek = 5

        model.save()
        await model.regenerate(scope: .nextWeek)

        #expect(model.shouldDismiss)
        #expect(manager.currentWeeklyPlan?.id == currentPlan.id)
        #expect(
            TrainingPlanService.pendingNextWeekPlan(for: store.profile, defaults: defaults)?.id
                == pendingPlan.id
        )
    }

    @Test @MainActor func regenerationLocksEditorInteractionUntilCompletion() async throws {
        let defaults = isolatedDefaults()
        defer { clear(defaults) }

        let gate = PlanGenerationGate()
        let store = TrainingProfileStore(defaults: defaults)
        let model = TrainingProfileEditorViewModel(
            store: store,
            currentPlan: { makePlan() },
            generatePlan: { _, _, _ in
                await gate.suspendGeneration()
                return makePlan()
            }
        )
        model.draft.trainingDaysPerWeek = 5
        model.save()

        let regeneration = Task { await model.regenerate(scope: .nextWeek) }
        await gate.waitUntilSuspended()

        #expect(model.isRegenerating)
        #expect(model.isEditorInteractionDisabled)
        #expect(model.isSavingDisabled)

        await gate.resumeGeneration()
        await regeneration.value

        #expect(!model.isRegenerating)
        #expect(!model.isEditorInteractionDisabled)
    }

    @Test @MainActor func editorRetryUsesTheSamePreservedPreSavePlan() async throws {
        let defaults = isolatedDefaults()
        defer { clear(defaults) }

        let store = TrainingProfileStore(defaults: defaults)
        let preservedPlan = replacingTotalMileage(makePlan(), with: 24, id: "editor-retry-input")
        var receivedInputIDs: [String?] = []
        var attempts = 0
        let model = TrainingProfileEditorViewModel(
            store: store,
            currentPlan: { preservedPlan },
            generatePlan: { _, scope, regenerationInput in
                #expect(scope == .remainingCurrentWeek)
                receivedInputIDs.append(regenerationInput?.id)
                attempts += 1
                if attempts == 1 {
                    throw TestFailure.expected
                }
                return replacingTotalMileage(
                    preservedPlan,
                    with: 30,
                    id: "editor-retry-success"
                )
            }
        )
        model.draft.trainingDaysPerWeek = 5
        model.save()

        await model.regenerate(scope: .remainingCurrentWeek)
        #expect(!model.shouldDismiss)
        #expect(model.canRetry)

        await model.retry()

        #expect(receivedInputIDs == [preservedPlan.id, preservedPlan.id])
        #expect(model.shouldDismiss)
        #expect(!model.canRetry)
    }

    @Test @MainActor func personalizationPromptVisibilityAndRoutesUseInjectedStore() throws {
        let defaults = isolatedDefaults()
        defer { clear(defaults) }
        let store = TrainingProfileStore(defaults: defaults)
        let promptRoute = TrainingPersonalizationRoute(store: store)

        #expect(promptRoute.shouldShowPrompt)
        let promptModel = promptRoute.editorRoute.makeEditorModel(
            currentPlan: { nil },
            generatePlan: { _, _, _ in makePlan() }
        )
        let settingsModel = TrainingProfileRoute(store: store).makeEditorModel(
            currentPlan: { nil },
            generatePlan: { _, _, _ in makePlan() }
        )

        #expect(promptModel.trainingProfileStore === store)
        #expect(settingsModel.trainingProfileStore === store)

        promptRoute.dismiss()
        #expect(!promptRoute.shouldShowPrompt)
    }

    @Test @MainActor func productionPersonalizationPresentationHasOneTodayPromptAndPersistentSettingsStatus() throws {
        let defaults = isolatedDefaults()
        defer { clear(defaults) }
        let store = TrainingProfileStore(defaults: defaults)
        let beforeDismiss = TrainingPersonalizationPresentation.todayPrompts(for: store)

        #expect(beforeDismiss.count == 1)
        let prompt = try #require(beforeDismiss.first)
        #expect(prompt.route.store === store)
        #expect(prompt.personalizeAction.accessibilityLabel == "Personalize training")
        #expect(prompt.dismissAction.accessibilityLabel == "Dismiss training personalization")
        #expect(prompt.personalizeAction.minimumTargetSize >= 44)
        #expect(prompt.dismissAction.minimumTargetSize >= 44)
        #expect(TrainingPersonalizationPresentation.settingsStatus(for: store) == .needsPersonalization)

        prompt.route.dismiss()

        #expect(TrainingPersonalizationPresentation.todayPrompts(for: store).isEmpty)
        #expect(TrainingPersonalizationPresentation.settingsStatus(for: store) == .needsPersonalization)
        let settingsModel = TrainingProfileRoute(store: store).makeEditorModel(
            currentPlan: { nil },
            generatePlan: { _, _, _ in makePlan() }
        )
        #expect(settingsModel.trainingProfileStore === prompt.route.store)
    }

    @Test @MainActor func dismissingPersonalizationPreservesProfilePlansAndCache() throws {
        let defaults = isolatedDefaults()
        defer { clear(defaults) }
        let profile = makeProfile([(.running, .primary, 4), (.strength, .supporting, 2)], trainingDays: 6)
        let active = makePlan()
        let pending = shiftedPlan(
            active,
            to: calendar.date(byAdding: .day, value: 7, to: active.weekStartDate)!
        )
        let manager = DataManager.shared
        let originalActive = manager.currentWeeklyPlan
        let originalPending = manager.pendingNextWeekPlan
        defer {
            manager.currentWeeklyPlan = originalActive
            manager.pendingNextWeekPlan = originalPending
        }

        let seededStore = TrainingProfileStore(defaults: defaults)
        try seededStore.save(profile)
        defaults.set(false, forKey: "trainingProfile.personalized.v1")
        let migratedStore = TrainingProfileStore(defaults: defaults)
        manager.currentWeeklyPlan = active
        manager.pendingNextWeekPlan = pending
        try TrainingPlanService.cachePlan(active, profile: profile, defaults: defaults)

        TrainingPersonalizationRoute(store: migratedStore).dismiss()

        #expect(migratedStore.profile == profile)
        #expect(manager.currentWeeklyPlan?.id == active.id)
        #expect(manager.pendingNextWeekPlan?.id == pending.id)
        guard case let .valid(cached) = TrainingPlanService.cachedPlanStatus(for: profile, defaults: defaults) else {
            Issue.record("Expected cached plan to remain valid")
            return
        }
        #expect(cached.id == active.id)
    }

    @Test @MainActor func staleActivityGenerationCannotMutateNewerActivePendingOrCacheState() async throws {
        let restoreCache = snapshotStandardCache()
        let manager = DataManager.shared
        let originalCurrent = manager.currentWeeklyPlan
        let originalPending = manager.pendingNextWeekPlan
        defer {
            manager.currentWeeklyPlan = originalCurrent
            manager.pendingNextWeekPlan = originalPending
            restoreCache()
        }

        let oldProfile = makeProfile([(.running, .primary, 4)], trainingDays: 4)
        let newProfile = makeProfile(
            [(.strength, .primary, 3), (.running, .supporting, 1)],
            trainingDays: 4
        )
        let input = replacingTotalMileage(makePlan(), with: 20, id: "activity-race-input")
        let newerActive = replacingTotalMileage(input, with: 24, id: "activity-race-newer")
        let newerPending = replacingTotalMileage(
            shiftedPlan(
                input,
                to: calendar.date(byAdding: .day, value: 7, to: input.weekStartDate)!
            ),
            with: 28,
            id: "activity-race-pending"
        )
        let gate = PlanGenerationGate()
        manager.currentWeeklyPlan = input
        manager.pendingNextWeekPlan = newerPending
        try TrainingPlanService.cachePlan(input, profile: oldProfile)
        try TrainingPlanService.cachePendingNextWeekPlan(newerPending, profile: newProfile)

        let older = Task { @MainActor in
            try await manager.generateTrainingPlan(
                profile: oldProfile,
                scope: .remainingCurrentWeek,
                regenerationInput: input
            ) { profile, _, existingPlan in
                await gate.suspendGeneration()
                return try await TrainingPlanService.regeneratePlanWithActivities(
                    athleteId: try #require(existingPlan).athleteId,
                    currentPlan: try #require(existingPlan),
                    completedActivities: [],
                    goal: nil,
                    profile: profile
                )
            }
        }
        await gate.waitUntilSuspended()

        _ = try await manager.generateTrainingPlan(
            profile: newProfile,
            scope: .remainingCurrentWeek,
            regenerationInput: input
        ) { _, _, _ in newerActive }
        await gate.resumeGeneration()

        do {
            _ = try await older.value
            Issue.record("The stale activity generation unexpectedly published")
        } catch is CancellationError {
        }

        #expect(manager.currentWeeklyPlan?.id == newerActive.id)
        #expect(manager.pendingNextWeekPlan?.id == newerPending.id)
        if case let .valid(cached) = TrainingPlanService.cachedPlanStatus(for: newProfile) {
            #expect(cached.id == newerActive.id)
        } else {
            Issue.record("Expected the newer active plan and profile metadata to own the current cache")
        }
        #expect(TrainingPlanService.pendingNextWeekPlan(for: newProfile)?.id == newerPending.id)
    }

    @Test @MainActor func missingOrCorruptMigrationIsRouteIndependentAndDurable() throws {
        let existing = planWithLongRun(on: .wednesday)
        let expected = TrainingProfile.migrationSeed.validated(existingPlan: existing).profile

        for isCorrupt in [false, true] {
            let planFirstDefaults = isolatedDefaults()
            let todayFirstDefaults = isolatedDefaults()
            defer {
                clear(planFirstDefaults)
                clear(todayFirstDefaults)
            }
            for defaults in [planFirstDefaults, todayFirstDefaults] {
                defaults.set(try encoded(existing), forKey: TrainingPlanService.cacheKey)
                if isCorrupt {
                    defaults.set(Data("corrupt".utf8), forKey: "trainingProfile.v1")
                }
            }

            let planFirstStore = TrainingProfileStore(defaults: planFirstDefaults)
            let todayMigrationPlan = try #require(
                TrainingPlanService.cachedPlanForProfileMigration(defaults: todayFirstDefaults)
            )
            let todayFirstStore = TrainingProfileStore(
                defaults: todayFirstDefaults,
                existingPlan: todayMigrationPlan
            )

            #expect(planFirstStore.profile == expected)
            #expect(todayFirstStore.profile == expected)
            #expect(planFirstStore.profile.fingerprint == todayFirstStore.profile.fingerprint)

            planFirstDefaults.removeObject(forKey: TrainingPlanService.cacheKey)
            todayFirstDefaults.removeObject(forKey: TrainingPlanService.cacheKey)
            let reconstructedPlanFirst = TrainingProfileStore(defaults: planFirstDefaults)
            let reconstructedTodayFirst = TrainingProfileStore(defaults: todayFirstDefaults)

            #expect(reconstructedPlanFirst.profile == expected)
            #expect(reconstructedTodayFirst.profile == expected)
            #expect(reconstructedPlanFirst.needsPersonalization)
            #expect(reconstructedTodayFirst.needsPersonalization)
        }
    }

    @Test @MainActor func missingOrCorruptProfileClearsStalePersonalizationUntilSuccessfulSave() throws {
        let existing = planWithLongRun(on: .wednesday)
        let inferred = TrainingProfile.migrationSeed.validated(existingPlan: existing).profile
        let personalized = makeProfile(
            [(.running, .primary, 3), (.strength, .supporting, 2)],
            trainingDays: 5
        )

        for isCorrupt in [false, true] {
            for stalePersonalizedValue in [false, true] {
                let defaults = isolatedDefaults()
                defer { clear(defaults) }
                defaults.set(try encoded(existing), forKey: TrainingPlanService.cacheKey)
                defaults.set(stalePersonalizedValue, forKey: "trainingProfile.personalized.v1")
                defaults.set(true, forKey: "trainingProfile.promptDismissed.v1")
                if isCorrupt {
                    defaults.set(Data("corrupt".utf8), forKey: "trainingProfile.v1")
                }

                let migrated = TrainingProfileStore(defaults: defaults)

                #expect(migrated.profile == inferred)
                #expect(!migrated.hasPersonalizedProfile)
                #expect(migrated.needsPersonalization)
                #expect(!defaults.bool(forKey: "trainingProfile.personalized.v1"))
                #expect(!defaults.bool(forKey: "trainingProfile.promptDismissed.v1"))
                let persistedData = try #require(defaults.data(forKey: "trainingProfile.v1"))
                #expect(try JSONDecoder().decode(TrainingProfile.self, from: persistedData) == inferred)

                let reloaded = TrainingProfileStore(defaults: defaults)
                #expect(!reloaded.hasPersonalizedProfile)
                #expect(reloaded.needsPersonalization)

                try reloaded.save(personalized)

                #expect(reloaded.profile == personalized)
                #expect(reloaded.hasPersonalizedProfile)
                #expect(!reloaded.needsPersonalization)
                #expect(defaults.bool(forKey: "trainingProfile.personalized.v1"))
                let saved = TrainingProfileStore(defaults: defaults)
                #expect(saved.profile == personalized)
                #expect(saved.hasPersonalizedProfile)
                #expect(!saved.needsPersonalization)
            }
        }
    }

    @Test func constrainedSchedulingPreservesPrimaryThenSupportingRolesDeterministically() async throws {
        let unavailable = Set([
            DayOfWeek.monday.calendarWeekday,
            DayOfWeek.friday.calendarWeekday,
            DayOfWeek.saturday.calendarWeekday,
        ])
        let profiles = [
            makeProfile(
                [(.strength, .primary, 3), (.running, .supporting, 2), (.cycling, .optional, 1)],
                trainingDays: 6,
                unavailableWeekdays: unavailable
            ),
            makeProfile(
                [(.running, .primary, 3), (.strength, .supporting, 2), (.cycling, .optional, 1)],
                trainingDays: 6,
                unavailableWeekdays: unavailable
            ),
        ]

        for profile in profiles {
            let first = try await TrainingPlanService.generatePlan(
                profile: profile,
                scope: .nextWeek,
                existingPlan: nil,
                runningPlanGenerator: { makePlan() }
            )
            let second = try await TrainingPlanService.generatePlan(
                profile: profile,
                scope: .nextWeek,
                existingPlan: nil,
                runningPlanGenerator: { makePlan() }
            )
            let primary = try #require(profile.primaryActivity)
            let supporting = try #require(profile.activities.first { $0.role == .supporting }?.activity)
            let signature: (WeeklyTrainingPlan) -> [String] = { plan in
                plan.workouts.map { "\($0.dayOfWeek.rawValue):\($0.workoutType.rawValue)" }
            }

            #expect(first.workouts.filter { $0.workoutType.activity == primary }.count == 3)
            #expect(first.workouts.filter { $0.workoutType.activity == supporting }.count == 1)
            #expect(first.workouts.filter { $0.workoutType.activity == .cycling }.isEmpty)
            #expect(first.workouts.filter { $0.workoutType != .rest }.count == 4)
            #expect(first.workouts.allSatisfy {
                $0.workoutType == .rest || !unavailable.contains($0.dayOfWeek.calendarWeekday)
            })
            #expect(!hasUnsafeStrengthAdjacency(first.workouts))
            #expect(signature(first) == signature(second))
        }
    }

    @Test @MainActor func onboardingOwnershipRejectsMissingAthleteThenRetriesWithoutLosingProfileOrDraft() async throws {
        let defaults = isolatedDefaults()
        let manager = DataManager.shared
        let originalAthlete = manager.athlete
        let originalCurrent = manager.currentWeeklyPlan
        let originalPending = manager.pendingNextWeekPlan
        defer {
            manager.athlete = originalAthlete
            manager.currentWeeklyPlan = originalCurrent
            manager.pendingNextWeekPlan = originalPending
            clear(defaults)
        }

        let athleteID = 731
        let profile = makeProfile(
            [(.running, .primary, 3), (.strength, .supporting, 1)],
            trainingDays: 4
        )
        let answers = OnboardingAnswers(primaryGoal: .running, draft: profile)
        let draftStore = OnboardingTrainingDraftStore(defaults: defaults)
        let profileStore = TrainingProfileStore(defaults: defaults)
        try draftStore.save(answers, for: athleteID)
        manager.athlete = nil
        manager.currentWeeklyPlan = nil
        manager.pendingNextWeekPlan = nil

        do {
            _ = try await OnboardingCompletionLifecycle.run(
                saveProfile: { try profileStore.save(profile) },
                generatePlan: {
                    _ = try await OnboardingInitialPlanGenerator.generate(
                        profile: profileStore.profile,
                        manager: manager,
                        defaults: defaults
                    )
                },
                complete: { true },
                clearDraft: { draftStore.clear(for: athleteID) }
            )
            Issue.record("Expected onboarding plan generation to reject the missing athlete ID")
        } catch {
            #expect(error.localizedDescription == "A positive athlete ID is required to generate a training plan.")
        }

        #expect(profileStore.profile == profile)
        #expect(try draftStore.load(for: athleteID) == answers)
        #expect(manager.currentWeeklyPlan == nil)
        if case .missing = TrainingPlanService.cachedPlanStatus(for: profile, defaults: defaults) {
        } else {
            Issue.record("A plan was cached without a positive athlete ID")
        }

        let authenticatedAthlete = Athlete(
            userId: nil,
            firstname: nil,
            lastname: nil,
            profileMedium: nil,
            profile: nil,
            city: nil,
            state: nil,
            country: nil,
            premium: nil,
            createdAt: nil,
            updatedAt: nil,
            friendCount: nil,
            followerCount: nil,
            mutualFriendCount: nil,
            datePreference: nil,
            email: nil,
            FTP: nil,
            weight: nil
        )
        authenticatedAthlete.id = athleteID
        manager.athlete = authenticatedAthlete
        manager.currentWeeklyPlan = nil

        let completed = try await OnboardingCompletionLifecycle.run(
            saveProfile: { try profileStore.save(profile) },
            generatePlan: {
                _ = try await OnboardingInitialPlanGenerator.generate(
                    profile: profileStore.profile,
                    manager: manager,
                    defaults: defaults
                )
            },
            complete: { true },
            clearDraft: { draftStore.clear(for: athleteID) }
        )

        #expect(completed)
        #expect(manager.currentWeeklyPlan?.athleteId == athleteID)
        #expect(profileStore.profile == profile)
        #expect(try draftStore.load(for: athleteID) == nil)
        if case let .valid(cached) = TrainingPlanService.cachedPlanStatus(for: profile, defaults: defaults) {
            #expect(cached.athleteId == athleteID)
        } else {
            Issue.record("Expected the authenticated athlete to own the cached plan")
        }
    }

    private actor PlanGenerationGate {
        private var isSuspended = false
        private var continuation: CheckedContinuation<Void, Never>?

        func suspendGeneration() async {
            isSuspended = true
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }

        func waitUntilSuspended() async {
            while !isSuspended {
                await Task.yield()
            }
        }

        func resumeGeneration() {
            continuation?.resume()
            continuation = nil
            isSuspended = false
        }
    }

    private enum TestFailure: Error {
        case expected
    }

    private func makeProfile(
        _ preferences: [(TrainingActivity, TrainingActivityRole, Int)],
        trainingDays: Int,
        unavailableWeekdays: Set<Int> = []
    ) -> TrainingProfile {
        TrainingProfile(
            schemaVersion: TrainingProfile.currentSchemaVersion,
            activities: preferences.map {
                TrainingActivityPreference(activity: $0.0, role: $0.1, sessionsPerWeek: $0.2)
            },
            trainingDaysPerWeek: trainingDays,
            preferredLongRunWeekday: 1,
            unavailableWeekdays: unavailableWeekdays,
            strengthEquipment: .dumbbells,
            strengthExperience: .intermediate
        )
    }

    private func runningOnlyPlan() -> WeeklyTrainingPlan {
        let plan = makePlan()
        let runs = plan.workouts.filter { $0.workoutType.isRunning }
        return WeeklyTrainingPlan(
            id: plan.id,
            athleteId: plan.athleteId,
            weekStartDate: plan.weekStartDate,
            weekEndDate: plan.weekEndDate,
            workouts: runs,
            weekNumber: plan.weekNumber,
            totalMileage: runs.compactMap(\.distance).reduce(0, +),
            focusArea: plan.focusArea,
            notes: plan.notes,
            generatedAt: plan.generatedAt,
            goalId: plan.goalId
        )
    }

    private func makePlan(includeCompletedValues: Bool = false, weekStart: Date? = nil, today: Date = Date()) -> WeeklyTrainingPlan {
        let weekStart = weekStart ?? TrainingPlanService.currentWeekSunday()
        let types: [WorkoutType] = [.longRun, .upperBody, .easyRun, .lowerBody, .tempoRun, .yoga, .easyRun]
        let workouts = types.enumerated().map { offset, type in
            let date = calendar.date(byAdding: .day, value: offset, to: weekStart)!
            let completed = includeCompletedValues && (offset == 0 || offset == 1 || calendar.isDate(date, inSameDayAs: today))
            return DailyWorkout(
                id: "original-\(offset)",
                date: date,
                dayOfWeek: DayOfWeek.from(date: date),
                workoutType: type,
                title: "Original \(offset)",
                description: "Recorded original workout \(offset)",
                duration: completed ? 91 + offset : 40 + offset,
                distance: type.isRunning ? (completed ? 10.75 + Double(offset) : 3 + Double(offset)) : nil,
                targetPace: type.isRunning ? "8:\(10 + offset)/mi" : nil,
                exercises: type.isStrength ? [Exercise(id: "exercise-\(offset)", name: "Lift", sets: 3, reps: "8", weight: "25 lb", notes: "Recorded")] : nil,
                isCompleted: completed,
                completedActivityId: completed ? 900 + offset : nil
            )
        }
        return WeeklyTrainingPlan(
            id: "existing-plan",
            athleteId: 42,
            weekStartDate: weekStart,
            weekEndDate: calendar.date(byAdding: .day, value: 6, to: weekStart)!,
            workouts: workouts,
            weekNumber: 12,
            totalMileage: workouts.filter { $0.workoutType.isRunning }.compactMap(\.distance).reduce(0, +),
            focusArea: "Existing focus",
            notes: "Existing notes",
            generatedAt: weekStart,
            goalId: 77
        )
    }

    private func hasUnsafeStrengthAdjacency(_ workouts: [DailyWorkout]) -> Bool {
        let byDay = Dictionary(uniqueKeysWithValues: workouts.map { (calendar.startOfDay(for: $0.date), $0.workoutType) })
        return workouts.contains { workout in
            guard workout.workoutType == .lowerBody || workout.workoutType == .fullBody else { return false }
            let day = calendar.startOfDay(for: workout.date)
            return [-1, 1].contains { delta in
                guard let date = calendar.date(byAdding: .day, value: delta, to: day), let adjacent = byDay[date] else {
                    return false
                }
                return adjacent == .longRun || adjacent.isHighIntensity
            }
        }
    }

    private func expectExactlyEqual(_ actual: DailyWorkout, _ expected: DailyWorkout) {
        #expect(actual.id == expected.id)
        #expect(actual.date == expected.date)
        #expect(actual.dayOfWeek == expected.dayOfWeek)
        #expect(actual.workoutType == expected.workoutType)
        #expect(actual.title == expected.title)
        #expect(actual.description == expected.description)
        #expect(actual.duration == expected.duration)
        #expect(actual.distance == expected.distance)
        #expect(actual.targetPace == expected.targetPace)
        #expect(actual.exercises?.map(\.id) == expected.exercises?.map(\.id))
        #expect(actual.exercises?.map(\.name) == expected.exercises?.map(\.name))
        #expect(actual.exercises?.map(\.sets) == expected.exercises?.map(\.sets))
        #expect(actual.exercises?.map(\.reps) == expected.exercises?.map(\.reps))
        #expect(actual.exercises?.map(\.weight) == expected.exercises?.map(\.weight))
        #expect(actual.exercises?.map(\.notes) == expected.exercises?.map(\.notes))
        #expect(actual.isCompleted == expected.isCompleted)
        #expect(actual.completedActivityId == expected.completedActivityId)
    }

    private func encoded(_ plan: WeeklyTrainingPlan) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(plan)
    }

    private func shiftedPlan(
        _ plan: WeeklyTrainingPlan,
        to weekStart: Date,
        focusArea: String? = nil,
        notes: String? = nil
    ) -> WeeklyTrainingPlan {
        let dayDelta = calendar.dateComponents([.day], from: plan.weekStartDate, to: weekStart).day ?? 0
        let workouts = plan.workouts.map { workout in
            DailyWorkout(
                id: workout.id,
                date: calendar.date(byAdding: .day, value: dayDelta, to: workout.date)!,
                dayOfWeek: workout.dayOfWeek,
                workoutType: workout.workoutType,
                title: workout.title,
                description: workout.description,
                duration: workout.duration,
                distance: workout.distance,
                targetPace: workout.targetPace,
                exercises: workout.exercises,
                isCompleted: workout.isCompleted,
                completedActivityId: workout.completedActivityId
            )
        }
        return WeeklyTrainingPlan(
            id: plan.id,
            athleteId: plan.athleteId,
            weekStartDate: weekStart,
            weekEndDate: calendar.date(byAdding: .day, value: 6, to: weekStart)!,
            workouts: workouts,
            weekNumber: plan.weekNumber,
            totalMileage: plan.totalMileage,
            focusArea: focusArea ?? plan.focusArea,
            notes: notes ?? plan.notes,
            generatedAt: plan.generatedAt,
            goalId: plan.goalId
        )
    }

    private func replacingTotalMileage(_ plan: WeeklyTrainingPlan, with mileage: Double, id: String) -> WeeklyTrainingPlan {
        WeeklyTrainingPlan(
            id: id,
            athleteId: plan.athleteId,
            weekStartDate: plan.weekStartDate,
            weekEndDate: plan.weekEndDate,
            workouts: plan.workouts,
            weekNumber: plan.weekNumber,
            totalMileage: mileage,
            focusArea: plan.focusArea,
            notes: plan.notes,
            generatedAt: plan.generatedAt,
            goalId: plan.goalId
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "TrainingProfileIntegrationTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    private func clear(_ defaults: UserDefaults) {
        defaults.dictionaryRepresentation().keys.forEach(defaults.removeObject(forKey:))
    }
}
