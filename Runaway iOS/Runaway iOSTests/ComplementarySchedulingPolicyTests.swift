//
//  ComplementarySchedulingPolicyTests.swift
//  Runaway iOSTests
//

import Foundation
import Testing
@testable import Runaway_iOS

@Suite("Complementary Scheduling Policy")
struct ComplementarySchedulingPolicyTests {
    @Test("Heavy lower-body strength cannot border long or quality runs")
    func heavyStrengthCannotBorderProtectedRuns() {
        let profile = makeProfile(
            activities: [
                preference(.running, .primary, 3),
                preference(.strength, .supporting, 2),
            ],
            trainingDays: 5
        )

        for protectedRun in [WorkoutType.longRun, .intervalRun, .hillRun, .tempoRun] {
            let after = makeDayContext(
                profile: profile,
                previousWorkout: protectedRun
            )
            let before = makeDayContext(
                profile: profile,
                nextWorkout: protectedRun
            )

            for context in [after, before] {
                let types = ComplementarySchedulingPolicy.rankedCandidates(for: context).map(\.workoutType)
                #expect(!types.contains(.lowerBody))
                #expect(!types.contains(.fullBody))
            }
        }
    }

    @Test("Upper-body strength is preferred after a long run to preserve leg recovery")
    func upperBodyIsPreferredAfterLongRun() throws {
        let context = makeDayContext(
            profile: makeProfile(
                activities: [preference(.strength, .supporting, 1)],
                trainingDays: 1
            ),
            previousWorkout: .longRun
        )

        let first = try #require(ComplementarySchedulingPolicy.rankedCandidates(for: context).first)

        #expect(first.workoutType == .upperBody)
        #expect(first.reason == .preservesLegRecovery)
    }

    @Test("Low readiness prefers recovery-compatible selected work and excludes high intensity")
    func lowReadinessPrefersRecoveryCompatibleWork() throws {
        let context = makeDayContext(
            profile: makeProfile(
                activities: [
                    preference(.running, .primary, 2),
                    preference(.walking, .supporting, 1),
                ],
                trainingDays: 3
            ),
            readiness: .low
        )

        let candidates = ComplementarySchedulingPolicy.rankedCandidates(for: context)
        let first = try #require(candidates.first)

        #expect(first.workoutType == .recoveryRun || first.workoutType == .walking)
        #expect(first.reason == .supportsRecovery)
        #expect(!candidates.contains { $0.workoutType.isHighIntensity })
    }

    @Test("Running-only profiles produce only running or rest candidates")
    func runningOnlyCandidatesContainOnlyRunsOrRest() {
        let candidates = ComplementarySchedulingPolicy.rankedCandidates(
            for: makeDayContext(profile: .runningFirstDefault)
        )

        #expect(candidates.allSatisfy { $0.workoutType.isRunning || $0.workoutType == .rest })
    }

    @Test("Unselected complementary activities never appear")
    func unselectedActivitiesNeverAppear() {
        let candidates = ComplementarySchedulingPolicy.rankedCandidates(
            for: makeDayContext(
                profile: makeProfile(
                    activities: [
                        preference(.running, .primary, 2),
                        preference(.mobility, .supporting, 1),
                    ],
                    trainingDays: 3
                )
            )
        )
        let types = candidates.map(\.workoutType)

        #expect(!types.contains(.cycling))
        #expect(!types.contains(.swimming))
        #expect(!types.contains { $0.isStrength })
    }

    @Test("Unavailable days remain empty")
    func unavailableDaysRemainEmpty() {
        let context = makeWeeklyContext(
            profile: makeProfile(
                activities: [preference(.running, .primary, 3)],
                trainingDays: 3,
                unavailable: [3]
            ),
            unavailableWeekdays: [3]
        )

        let assignments = ComplementarySchedulingPolicy.buildWeeklyAssignments(context: context)

        #expect(!assignments.contains { $0.weekday == .tuesday })
    }

    @Test("Completed workout identity, type, and completion state are preserved")
    func completedWorkoutIsPreserved() throws {
        let completed = assignment(
            id: "completed-activity-42",
            dayOffset: 2,
            workoutType: .cycling,
            reason: .completedWorkoutProtected,
            isCompleted: true
        )
        let context = makeWeeklyContext(
            profile: makeProfile(
                activities: [
                    preference(.running, .primary, 2),
                    preference(.cycling, .supporting, 1),
                ],
                trainingDays: 3
            ),
            completedWorkouts: [completed]
        )

        let preserved = try #require(
            ComplementarySchedulingPolicy.buildWeeklyAssignments(context: context)
                .first { $0.date == completed.date }
        )

        #expect(preserved.id == "completed-activity-42")
        #expect(preserved.workoutType == .cycling)
        #expect(preserved.isCompleted)
        #expect(preserved.reason == .completedWorkoutProtected)
    }

    @Test("Weekly assignments respect the training-day limit")
    func weeklyAssignmentsRespectTrainingDayLimit() {
        let context = makeWeeklyContext(
            profile: makeProfile(
                activities: [
                    preference(.running, .primary, 4),
                    preference(.strength, .supporting, 3),
                ],
                trainingDays: 4
            )
        )

        let assignments = ComplementarySchedulingPolicy.buildWeeklyAssignments(context: context)

        #expect(assignments.count <= 4)
    }

    @Test("Impossible requested mix preserves fixed primary workouts and reduces support deterministically")
    func impossibleMixPreservesPrimaryWorkouts() {
        let profile = makeProfile(
            activities: [
                preference(.running, .primary, 3),
                preference(.strength, .supporting, 2),
                preference(.mobility, .optional, 1),
            ],
            trainingDays: 4,
            unavailable: [3, 5, 7]
        )
        let fixed = [
            assignment(id: "primary-1", dayOffset: 1, workoutType: .tempoRun, reason: .requiredPrimary),
            assignment(id: "primary-2", dayOffset: 3, workoutType: .longRun, reason: .requiredPrimary),
        ]
        let context = makeWeeklyContext(
            profile: profile,
            fixedPrimaryWorkouts: fixed,
            unavailableWeekdays: [3, 5, 7]
        )

        let assignments = ComplementarySchedulingPolicy.buildWeeklyAssignments(context: context)

        #expect(assignments.count == 4)
        #expect(assignments.contains { $0.id == "primary-1" && $0.workoutType == .tempoRun })
        #expect(assignments.contains { $0.id == "primary-2" && $0.workoutType == .longRun })
        #expect(assignments.filter { !$0.isFixed }.map(\.workoutType) == [.easyRun, .fullBody])
    }

    @Test("Repeated scheduling produces identical ordering and reasons")
    func weeklySchedulingIsDeterministic() {
        let context = makeWeeklyContext(
            profile: makeProfile(
                activities: [
                    preference(.running, .primary, 3),
                    preference(.strength, .supporting, 2),
                ],
                trainingDays: 5
            ),
            fixedPrimaryWorkouts: [
                assignment(id: "long", dayOffset: 0, workoutType: .longRun, reason: .requiredPrimary),
            ]
        )

        let first = ComplementarySchedulingPolicy.buildWeeklyAssignments(context: context)
        let second = ComplementarySchedulingPolicy.buildWeeklyAssignments(context: context)

        #expect(first == second)
    }

    @Test("Candidate ties use workout raw-value ordering")
    func candidateTiesUseRawValueOrdering() {
        let candidates = ComplementarySchedulingPolicy.rankedCandidates(
            for: makeDayContext(
                profile: makeProfile(
                    activities: [
                        preference(.cycling, .supporting, 1),
                        preference(.swimming, .supporting, 1),
                    ],
                    trainingDays: 2
                )
            )
        )
        let tied = candidates.filter { $0.score == 300 }.map(\.workoutType)

        #expect(tied == [.cycling, .swimming])
    }

    @Test("Taper protection rejects moderate and high supporting load")
    func taperProtectionRejectsModerateAndHighSupport() {
        let candidates = ComplementarySchedulingPolicy.rankedCandidates(
            for: makeDayContext(
                profile: makeProfile(
                    activities: [
                        preference(.running, .primary, 2),
                        preference(.strength, .supporting, 1),
                    ],
                    trainingDays: 3
                ),
                isTaperProtected: true
            )
        )

        #expect(candidates.allSatisfy { $0.workoutType.loadClass < .moderate || $0.workoutType == .rest })
    }

    @Test("Long and quality candidates are rejected beside heavy strength")
    func protectedRunsCannotBorderHeavyStrength() {
        let context = makeDayContext(
            profile: .runningFirstDefault,
            previousWorkout: .lowerBody
        )

        for workoutType in [WorkoutType.longRun, .intervalRun, .hillRun, .tempoRun] {
            let evaluation = ComplementarySchedulingPolicy.evaluation(of: workoutType, for: context)
            #expect(evaluation.candidate == nil)
            #expect(evaluation.rejectionReason == .lowerBodyRecoveryConflict)
        }
    }

    @Test("Unsupported fixed workouts are rejected with an observable reason")
    func unsupportedFixedWorkoutIsRejected() {
        let fixed = assignment(
            id: "unsupported-cycling",
            dayOffset: 1,
            workoutType: .cycling,
            reason: .requiredPrimary
        )
        let context = makeWeeklyContext(
            profile: .runningFirstDefault,
            fixedPrimaryWorkouts: [fixed]
        )

        let assignments = ComplementarySchedulingPolicy.buildWeeklyAssignments(context: context)
        let diagnostics = ComplementarySchedulingPolicy.diagnostics(for: context)

        #expect(!assignments.contains { $0.id == "unsupported-cycling" })
        #expect(diagnostics.contains(.rejectedFixedWorkout(
            assignmentID: "unsupported-cycling",
            reason: .unselectedActivity
        )))
    }

    @Test("Fixed workouts consume remaining capacity in earliest-date order")
    func fixedWorkoutsRespectRemainingCapacity() {
        let profile = makeProfile(
            activities: [preference(.running, .primary, 3)],
            trainingDays: 2
        )
        let fixed = [
            assignment(id: "fixed-3", dayOffset: 3, workoutType: .longRun, reason: .requiredPrimary),
            assignment(id: "fixed-1", dayOffset: 0, workoutType: .easyRun, reason: .requiredPrimary),
            assignment(id: "fixed-2", dayOffset: 2, workoutType: .tempoRun, reason: .requiredPrimary),
        ]
        let context = makeWeeklyContext(profile: profile, fixedPrimaryWorkouts: fixed)

        let assignments = ComplementarySchedulingPolicy.buildWeeklyAssignments(context: context)
        let diagnostics = ComplementarySchedulingPolicy.diagnostics(for: context)

        #expect(assignments.map(\.id) == ["fixed-1", "fixed-2"])
        #expect(diagnostics.contains(.rejectedFixedWorkout(
            assignmentID: "fixed-3",
            reason: .trainingDayLimit
        )))
    }

    @Test("Completed history wins over unavailable-day conflicts")
    func completedWorkoutWinsOverUnavailableDay() {
        let completed = assignment(
            id: "completed-unavailable",
            dayOffset: 2,
            workoutType: .cycling,
            reason: .completedWorkoutProtected,
            isCompleted: true
        )
        let profile = makeProfile(
            activities: [preference(.running, .primary, 1)],
            trainingDays: 1,
            unavailable: [3]
        )
        let context = makeWeeklyContext(
            profile: profile,
            completedWorkouts: [completed],
            unavailableWeekdays: [3]
        )

        let assignments = ComplementarySchedulingPolicy.buildWeeklyAssignments(context: context)
        let diagnostics = ComplementarySchedulingPolicy.diagnostics(for: context)

        #expect(assignments == [completed])
        #expect(diagnostics.contains(.unavoidableCompletedConflict(
            assignmentID: "completed-unavailable",
            reason: .unavailableDay
        )))
    }

    @Test("Completed history remains preserved beyond capacity and reports the conflict")
    func completedWorkoutWinsOverCapacity() {
        let first = assignment(
            id: "completed-1",
            dayOffset: 0,
            workoutType: .easyRun,
            reason: .completedWorkoutProtected,
            isCompleted: true
        )
        let second = assignment(
            id: "completed-2",
            dayOffset: 1,
            workoutType: .cycling,
            reason: .completedWorkoutProtected,
            isCompleted: true
        )
        let context = makeWeeklyContext(
            profile: makeProfile(
                activities: [preference(.running, .primary, 1)],
                trainingDays: 1
            ),
            completedWorkouts: [second, first]
        )

        let assignments = ComplementarySchedulingPolicy.buildWeeklyAssignments(context: context)
        let diagnostics = ComplementarySchedulingPolicy.diagnostics(for: context)

        #expect(assignments.map(\.id) == ["completed-1", "completed-2"])
        #expect(diagnostics.contains(.unavoidableCompletedConflict(
            assignmentID: "completed-2",
            reason: .trainingDayLimit
        )))
    }

    @Test("Conflicting completed history is preserved with an adjacency diagnostic")
    func completedWorkoutWinsOverAdjacency() {
        let longRun = assignment(
            id: "completed-long",
            dayOffset: 0,
            workoutType: .longRun,
            reason: .completedWorkoutProtected,
            isCompleted: true
        )
        let lowerBody = assignment(
            id: "completed-strength",
            dayOffset: 1,
            workoutType: .lowerBody,
            reason: .completedWorkoutProtected,
            isCompleted: true
        )
        let context = makeWeeklyContext(
            profile: makeProfile(
                activities: [
                    preference(.running, .primary, 1),
                    preference(.strength, .supporting, 1),
                ],
                trainingDays: 2
            ),
            completedWorkouts: [lowerBody, longRun]
        )

        let assignments = ComplementarySchedulingPolicy.buildWeeklyAssignments(context: context)
        let diagnostics = ComplementarySchedulingPolicy.diagnostics(for: context)

        #expect(assignments.map(\.id) == ["completed-long", "completed-strength"])
        #expect(diagnostics.contains(.unavoidableCompletedConflict(
            assignmentID: "completed-strength",
            reason: .lowerBodyRecoveryConflict
        )))
    }

    @Test("Duplicate penalty applies to the training-activity category")
    func duplicatePenaltyUsesActivityCategory() throws {
        let context = SchedulingDayContext(
            date: Self.weekStart,
            weekday: .sunday,
            profile: .runningFirstDefault,
            plannedOrFixedWorkout: nil,
            previousWorkout: nil,
            nextWorkout: nil,
            readiness: .normal,
            assignedWorkoutTypes: [.tempoRun],
            isCompletedProtected: false,
            isUnavailable: false,
            isTaperProtected: false
        )

        let candidate = try #require(
            ComplementarySchedulingPolicy.rankedCandidates(for: context)
                .first { $0.workoutType == .easyRun }
        )

        #expect(candidate.score == 180)
        #expect(candidate.reason == .profileFrequency)
    }

    @Test("Duplicate calendar dates invalidate a weekly context")
    func duplicateDatesAreInvalid() {
        let valid = makeWeeklyContext(profile: .runningFirstDefault)
        var dates = valid.dates
        dates[6] = dates[5]
        let context = SchedulingContext(
            dates: dates,
            profile: valid.profile,
            fixedPrimaryWorkouts: [],
            completedWorkouts: [],
            unavailableWeekdays: [],
            readinessByWeekday: [:],
            taperProtectedWeekdays: []
        )

        #expect(ComplementarySchedulingPolicy.diagnostics(for: context).contains(.invalidContext))
        #expect(ComplementarySchedulingPolicy.buildWeeklyAssignments(context: context).isEmpty)
    }

    @Test("Missing weekday slots invalidate a weekly context")
    func sixDatesAreInvalid() {
        let valid = makeWeeklyContext(profile: .runningFirstDefault)
        let context = SchedulingContext(
            dates: Array(valid.dates.dropLast()),
            profile: valid.profile,
            fixedPrimaryWorkouts: [],
            completedWorkouts: [],
            unavailableWeekdays: [],
            readinessByWeekday: [:],
            taperProtectedWeekdays: []
        )

        #expect(ComplementarySchedulingPolicy.diagnostics(for: context).contains(.invalidContext))
        #expect(ComplementarySchedulingPolicy.buildWeeklyAssignments(context: context).isEmpty)
    }

    @Test("Candidate rejection reasons are publicly observable")
    func candidateRejectionReasonsAreObservable() {
        let context = makeDayContext(profile: .runningFirstDefault)

        let evaluation = ComplementarySchedulingPolicy.evaluation(of: .cycling, for: context)

        #expect(evaluation.candidate == nil)
        #expect(evaluation.rejectionReason == .unselectedActivity)
    }

    @Test("Explicit non-running activities are not classified as runs")
    func explicitActivityTypesAreNotRuns() {
        for workoutType in [WorkoutType.cycling, .swimming, .walking, .hiking] {
            #expect(!workoutType.isRunning)
        }
    }

    @Test("Explicit activity types map to their matching training activities")
    func explicitActivityTypesMapExactly() {
        let mappings: [(WorkoutType, TrainingActivity)] = [
            (.cycling, .cycling),
            (.swimming, .swimming),
            (.walking, .walking),
            (.hiking, .hiking),
        ]

        for (workoutType, activity) in mappings {
            #expect(workoutType.activity == activity)
        }
    }

    @Test("Lower-body and full-body strength demand the lower body, but upper-body strength does not")
    func strengthLowerBodyDemandIsExplicit() {
        #expect(WorkoutType.lowerBody.isLowerBodyDemanding)
        #expect(WorkoutType.fullBody.isLowerBodyDemanding)
        #expect(!WorkoutType.upperBody.isLowerBodyDemanding)
    }

    @Test("Interval, hill, and tempo workouts are high intensity")
    func highIntensityRunTraitsAreExplicit() {
        for workoutType in [WorkoutType.intervalRun, .hillRun, .tempoRun] {
            #expect(workoutType.isHighIntensity)
        }
    }

    @Test("Long runs carry high load without being high intensity")
    func longRunIsHighLoadButNotHighIntensity() {
        #expect(!WorkoutType.longRun.isHighIntensity)
        #expect(WorkoutType.longRun.loadClass == .high)
    }

    @Test("Explicit complementary activities are not strength workouts")
    func explicitActivityTypesAreNotStrength() {
        for workoutType in [WorkoutType.cycling, .swimming, .walking, .hiking] {
            #expect(!workoutType.isStrength)
        }
    }

    @Test("Restorative workout types are recovery compatible")
    func recoveryCompatibilityIsExplicit() {
        for workoutType in [
            WorkoutType.rest,
            .stretchMobility,
            .yoga,
            .walking,
            .recoveryRun,
        ] {
            #expect(workoutType.isRecoveryCompatible)
        }
    }

    @Test("Every workout type has a human-readable display name")
    func everyWorkoutTypeHasHumanReadableDisplayName() {
        for workoutType in WorkoutType.allCases {
            #expect(!workoutType.displayName.isEmpty)
            #expect(!workoutType.displayName.contains("_"))
        }
    }

    @Test("Representative legacy raw values decode unchanged")
    func representativeLegacyRawValuesDecodeUnchanged() throws {
        let rawValues = ["easy_run", "long_run", "cross_training", "stretch_mobility"]

        for rawValue in rawValues {
            let data = Data("\"\(rawValue)\"".utf8)
            let decoded = try JSONDecoder().decode(WorkoutType.self, from: data)
            #expect(decoded.rawValue == rawValue)
        }
    }

    @Test("New workout type raw values round-trip through Codable")
    func newWorkoutTypeRawValuesRoundTripThroughCodable() throws {
        for workoutType in [WorkoutType.cycling, .swimming, .walking, .hiking] {
            let data = try JSONEncoder().encode(workoutType)
            let decoded = try JSONDecoder().decode(WorkoutType.self, from: data)
            #expect(decoded == workoutType)
        }
    }

    @Test("Supporting strength workouts never inherit a running pace")
    func supportingStrengthNeverInheritsRunningPace() async throws {
        let run = DailyWorkout(
            id: "easy-run",
            date: Self.weekStart,
            dayOfWeek: .sunday,
            workoutType: .easyRun,
            title: "Easy Run",
            description: "Aerobic work",
            duration: 40,
            distance: 4,
            targetPace: "9:22/mi",
            exercises: nil,
            isCompleted: false,
            completedActivityId: nil
        )
        let runningPlan = WeeklyTrainingPlan(
            id: "running-template",
            athleteId: 42,
            weekStartDate: Self.weekStart,
            weekEndDate: Self.calendar.date(byAdding: .day, value: 6, to: Self.weekStart)!,
            workouts: [run],
            weekNumber: 1,
            totalMileage: 4,
            focusArea: "Test",
            notes: nil,
            generatedAt: Self.weekStart,
            goalId: nil
        )
        let profile = makeProfile(
            activities: [
                preference(.running, .primary, 1),
                preference(.strength, .supporting, 1),
            ],
            trainingDays: 2
        )

        let plan = try await TrainingPlanService.generatePlan(
            athleteId: 42,
            profile: profile,
            scope: .initialCurrentWeek,
            existingPlan: nil,
            runningPlanGenerator: { runningPlan },
            regenerationDate: Self.weekStart
        )
        let strength = try #require(plan.workouts.first { $0.workoutType.isStrength })

        #expect(strength.targetPace == nil)
        #expect(strength.distance == nil)
    }

    @Test("Widget details omit running pace for strength workouts")
    @MainActor
    func widgetDetailsOmitRunningPaceForStrength() throws {
        let defaults = try #require(UserDefaults(suiteName: AppConstants.AppGroup.identifier))
        defer { defaults.removeObject(forKey: WidgetPrescriptionSnapshot.cacheKey) }
        let workout = DailyWorkout(
            id: "legacy-strength",
            date: Self.weekStart,
            dayOfWeek: .sunday,
            workoutType: .fullBody,
            title: "Full Body",
            description: "Strength session",
            duration: 45,
            distance: nil,
            targetPace: "9:22/mi",
            exercises: nil,
            isCompleted: false,
            completedActivityId: nil
        )
        let snapshot = BecomingSnapshot(
            headline: "Train with intent",
            detail: "Today's prescription",
            recommendedChoice: .planned,
            paths: []
        )

        WidgetSyncService.shared.updateBecomingData(
            snapshot: snapshot,
            workout: workout,
            readinessScore: nil,
            weatherTitle: nil,
            weatherDetail: nil
        )
        let prescription = try #require(WidgetPrescriptionSnapshot.cached(in: defaults))

        #expect(prescription.detail.contains("45"))
        #expect(!prescription.detail.contains("/mi"))
    }

    private static let calendar = Calendar(identifier: .gregorian)
    private static let weekStart = calendar.date(
        from: DateComponents(year: 2026, month: 8, day: 23)
    )!

    private func preference(
        _ activity: TrainingActivity,
        _ role: TrainingActivityRole,
        _ sessions: Int
    ) -> TrainingActivityPreference {
        TrainingActivityPreference(activity: activity, role: role, sessionsPerWeek: sessions)
    }

    private func makeProfile(
        activities: [TrainingActivityPreference],
        trainingDays: Int,
        unavailable: Set<Int> = []
    ) -> TrainingProfile {
        TrainingProfile(
            schemaVersion: 1,
            activities: activities,
            trainingDaysPerWeek: trainingDays,
            preferredLongRunWeekday: 1,
            unavailableWeekdays: unavailable,
            strengthEquipment: .bodyweight,
            strengthExperience: .intermediate
        )
    }

    private func makeDayContext(
        profile: TrainingProfile,
        previousWorkout: WorkoutType? = nil,
        nextWorkout: WorkoutType? = nil,
        readiness: SchedulingReadiness = .normal,
        isTaperProtected: Bool = false
    ) -> SchedulingDayContext {
        SchedulingDayContext(
            date: Self.weekStart,
            weekday: .sunday,
            profile: profile,
            plannedOrFixedWorkout: nil,
            previousWorkout: previousWorkout,
            nextWorkout: nextWorkout,
            readiness: readiness,
            assignedWorkoutTypes: [],
            isCompletedProtected: false,
            isUnavailable: false,
            isTaperProtected: isTaperProtected
        )
    }

    private func makeWeeklyContext(
        profile: TrainingProfile,
        fixedPrimaryWorkouts: [ScheduledWorkoutAssignment] = [],
        completedWorkouts: [ScheduledWorkoutAssignment] = [],
        unavailableWeekdays: Set<Int> = [],
        readinessByWeekday: [DayOfWeek: SchedulingReadiness] = [:],
        taperProtectedWeekdays: Set<DayOfWeek> = []
    ) -> SchedulingContext {
        let dates = (0..<7).map {
            Self.calendar.date(byAdding: .day, value: $0, to: Self.weekStart)!
        }
        return SchedulingContext(
            dates: dates,
            profile: profile,
            fixedPrimaryWorkouts: fixedPrimaryWorkouts,
            completedWorkouts: completedWorkouts,
            unavailableWeekdays: unavailableWeekdays,
            readinessByWeekday: readinessByWeekday,
            taperProtectedWeekdays: taperProtectedWeekdays
        )
    }

    private func assignment(
        id: String,
        dayOffset: Int,
        workoutType: WorkoutType,
        reason: SchedulingReason,
        isCompleted: Bool = false
    ) -> ScheduledWorkoutAssignment {
        let date = Self.calendar.date(byAdding: .day, value: dayOffset, to: Self.weekStart)!
        return ScheduledWorkoutAssignment(
            id: id,
            weekday: DayOfWeek.from(date: date),
            date: date,
            workoutType: workoutType,
            reason: reason,
            isCompleted: isCompleted,
            isFixed: true
        )
    }
}

extension ComplementarySchedulingPolicyTests {
    @Test func incompletePlannedCandidateStillRequiresSelectionAndAdjacency() {
        let runningOnly = TrainingProfile.runningFirstDefault
        let date = Self.weekStart
        let weekday = DayOfWeek.from(date: date)

        let unselected = SchedulingDayContext(
            date: date,
            weekday: weekday,
            profile: runningOnly,
            plannedOrFixedWorkout: .lowerBody,
            previousWorkout: nil,
            nextWorkout: nil,
            readiness: .normal,
            assignedWorkoutTypes: [],
            isCompletedProtected: false,
            isUnavailable: false,
            isTaperProtected: false
        )
        #expect(ComplementarySchedulingPolicy.evaluation(of: .lowerBody, for: unselected).rejectionReason == .unselectedActivity)

        let adjacent = SchedulingDayContext(
            date: date,
            weekday: weekday,
            profile: runningOnly,
            plannedOrFixedWorkout: .longRun,
            previousWorkout: .lowerBody,
            nextWorkout: nil,
            readiness: .normal,
            assignedWorkoutTypes: [],
            isCompletedProtected: false,
            isUnavailable: false,
            isTaperProtected: false
        )
        #expect(ComplementarySchedulingPolicy.evaluation(of: .longRun, for: adjacent).rejectionReason == .lowerBodyRecoveryConflict)
    }

    @Test func anchorsOutsideContextAreDiagnosedAndExcluded() {
        let fixed = assignment(id: "outside-fixed", dayOffset: 7, workoutType: .longRun, reason: .unselectedActivity)
        let completed = assignment(id: "outside-completed", dayOffset: 8, workoutType: .easyRun, reason: .unselectedActivity, isCompleted: true)
        let context = makeWeeklyContext(
            profile: .runningFirstDefault,
            fixedPrimaryWorkouts: [fixed],
            completedWorkouts: [completed]
        )

        let assignments = ComplementarySchedulingPolicy.buildWeeklyAssignments(context: context)
        let diagnostics = ComplementarySchedulingPolicy.diagnostics(for: context)

        #expect(!assignments.contains(where: { $0.id == fixed.id || $0.id == completed.id }))
        #expect(diagnostics.contains(.anchorOutsideContext(assignmentID: fixed.id)))
        #expect(diagnostics.contains(.anchorOutsideContext(assignmentID: completed.id)))
    }

    @Test func sevenDistinctDatesWithDuplicateWeekdayAreInvalid() {
        let dates = [0, 1, 2, 3, 4, 5, 7].compactMap {
            Self.calendar.date(byAdding: .day, value: $0, to: Self.weekStart)
        }
        let context = SchedulingContext(
            dates: dates,
            profile: .runningFirstDefault,
            fixedPrimaryWorkouts: [],
            completedWorkouts: [],
            unavailableWeekdays: [],
            readinessByWeekday: [:],
            taperProtectedWeekdays: []
        )

        #expect(dates.count == 7)
        #expect(Set(dates.map { Self.calendar.startOfDay(for: $0) }).count == 7)
        #expect(ComplementarySchedulingPolicy.buildWeeklyAssignments(context: context).isEmpty)
        #expect(ComplementarySchedulingPolicy.diagnostics(for: context).contains(.invalidContext))
    }

    @Test func duplicateFixedSlotUsesStableOrderingAndCompletedWins() {
        let laterID = assignment(id: "fixed-b", dayOffset: 2, workoutType: .longRun, reason: .unselectedActivity)
        let earlierID = assignment(id: "fixed-a", dayOffset: 2, workoutType: .easyRun, reason: .unselectedActivity)
        let fixedContext = makeWeeklyContext(
            profile: .runningFirstDefault,
            fixedPrimaryWorkouts: [laterID, earlierID]
        )

        let fixedAssignments = ComplementarySchedulingPolicy.buildWeeklyAssignments(context: fixedContext)
        let fixedDiagnostics = ComplementarySchedulingPolicy.diagnostics(for: fixedContext)
        #expect(fixedAssignments.contains(where: { $0.id == earlierID.id }))
        #expect(!fixedAssignments.contains(where: { $0.id == laterID.id }))
        #expect(fixedDiagnostics.contains(.duplicateFixedSlot(assignmentID: laterID.id)))

        let completed = assignment(id: "completed", dayOffset: 2, workoutType: .longRun, reason: .unselectedActivity, isCompleted: true)
        let completedContext = makeWeeklyContext(
            profile: .runningFirstDefault,
            fixedPrimaryWorkouts: [earlierID],
            completedWorkouts: [completed]
        )
        let completedAssignments = ComplementarySchedulingPolicy.buildWeeklyAssignments(context: completedContext)
        let completedDiagnostics = ComplementarySchedulingPolicy.diagnostics(for: completedContext)
        #expect(completedAssignments.contains(where: { $0.id == completed.id }))
        #expect(!completedAssignments.contains(where: { $0.id == earlierID.id }))
        #expect(completedDiagnostics.contains(.duplicateFixedSlot(assignmentID: earlierID.id)))
    }
}

extension ComplementarySchedulingPolicyTests {
    @Test func plannedRestIsAllowedWithoutASelectedActivity() {
        let date = Self.weekStart
        let context = SchedulingDayContext(
            date: date,
            weekday: DayOfWeek.from(date: date),
            profile: .runningFirstDefault,
            plannedOrFixedWorkout: .rest,
            previousWorkout: .lowerBody,
            nextWorkout: .longRun,
            readiness: .normal,
            assignedWorkoutTypes: [],
            isCompletedProtected: false,
            isUnavailable: false,
            isTaperProtected: false
        )

        let evaluation = ComplementarySchedulingPolicy.evaluation(of: .rest, for: context)

        #expect(evaluation.candidate?.workoutType == .rest)
        #expect(evaluation.rejectionReason == nil)
    }

    @Test func restOwnsItsSlotWithoutConsumingTrainingDayCapacity() {
        let profile = makeProfile(
            activities: [preference(.running, .primary, 1)],
            trainingDays: 1
        )
        let completedRest = assignment(
            id: "completed-rest",
            dayOffset: 0,
            workoutType: .rest,
            reason: .restRequired,
            isCompleted: true
        )
        let conflictingFixed = assignment(
            id: "conflicting-fixed",
            dayOffset: 0,
            workoutType: .easyRun,
            reason: .requiredPrimary
        )
        let completedContext = makeWeeklyContext(
            profile: profile,
            fixedPrimaryWorkouts: [conflictingFixed],
            completedWorkouts: [completedRest]
        )

        let completedAssignments = ComplementarySchedulingPolicy.buildWeeklyAssignments(context: completedContext)
        let completedDiagnostics = ComplementarySchedulingPolicy.diagnostics(for: completedContext)
        let completedRestDay = Self.calendar.startOfDay(for: completedRest.date)

        #expect(completedAssignments.contains(where: { $0.id == completedRest.id }))
        #expect(!completedAssignments.contains(where: { $0.id == conflictingFixed.id }))
        #expect(!completedAssignments.contains(where: {
            Self.calendar.startOfDay(for: $0.date) == completedRestDay && $0.id != completedRest.id
        }))
        #expect(completedAssignments.filter { $0.workoutType != .rest }.count == 1)
        #expect(completedDiagnostics.contains(.duplicateFixedSlot(assignmentID: conflictingFixed.id)))

        let plannedRest = assignment(
            id: "planned-rest",
            dayOffset: 0,
            workoutType: .rest,
            reason: .restRequired
        )
        let plannedRun = assignment(
            id: "planned-run",
            dayOffset: 1,
            workoutType: .easyRun,
            reason: .requiredPrimary
        )
        let plannedContext = makeWeeklyContext(
            profile: profile,
            fixedPrimaryWorkouts: [plannedRest, plannedRun]
        )
        let plannedAssignments = ComplementarySchedulingPolicy.buildWeeklyAssignments(context: plannedContext)

        #expect(plannedAssignments.contains(where: { $0.id == plannedRest.id }))
        #expect(plannedAssignments.contains(where: { $0.id == plannedRun.id }))
        #expect(plannedAssignments.filter { $0.workoutType != .rest }.count == 1)
    }
}
