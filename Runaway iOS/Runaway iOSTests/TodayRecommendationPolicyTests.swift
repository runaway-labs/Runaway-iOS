import Foundation
import Testing
@testable import Runaway_iOS

@Suite(.serialized)
struct TodayRecommendationPolicyTests {
    @Test func poorReadinessRecommendsRecovery() {
        let recommendation = TodayRecommendationPolicy.recommendation(readinessScore: 29)

        #expect(recommendation.directive == .recover)
        #expect(recommendation.status == "Recovery")
        #expect(recommendation.title == "Recovery Day")
    }

    @Test func lowReadinessRecommendsRecovery() {
        let recommendation = TodayRecommendationPolicy.recommendation(readinessScore: 30)

        #expect(recommendation.directive == .recover)
    }

    @Test func moderateReadinessReducesIntensity() {
        let recommendation = TodayRecommendationPolicy.recommendation(readinessScore: 50)

        #expect(recommendation.directive == .reduceIntensity)
        #expect(recommendation.status == "Adjusted")
    }

    @Test func goodReadinessPreservesThePlan() {
        let recommendation = TodayRecommendationPolicy.recommendation(readinessScore: 70)

        #expect(recommendation.directive == .proceed)
    }

    @Test func missingReadinessDoesNotInventRecoveryAdvice() {
        let recommendation = TodayRecommendationPolicy.recommendation(readinessScore: nil)

        #expect(recommendation.directive == .unknown)
        #expect(recommendation.status == "Check In")
    }

    @Test func runningAndStrengthRecommendsUpperBodyAfterYesterdayLongRun() throws {
        let date = testDate
        let previous = workout(type: .longRun, date: date.addingTimeInterval(-86_400), title: "Long Run")
        let recommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: nil,
            profile: profile([(.running, .primary, 3), (.strength, .supporting, 2)]),
            recentCompletedWorkouts: [previous],
            readinessScore: 82,
            schedulingContext: context(on: date)
        )

        #expect(recommendation.workoutType == .upperBody)
        #expect(recommendation.title == "Upper Body")
        #expect(recommendation.reason == "Placed after yesterday's long run to preserve leg recovery.")
        #expect(recommendation.schedulingReason == .preservesLegRecovery)
    }

    @Test func runningOnlyFallbackExcludesUnselectedSupportingActivities() throws {
        let recommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: nil,
            profile: profile([(.running, .primary, 4)]),
            recentCompletedWorkouts: [],
            readinessScore: 78,
            schedulingContext: context(on: testDate)
        )
        let workoutType = try #require(recommendation.workoutType)

        #expect(workoutType.isRunning || workoutType == .rest)
        #expect(!workoutType.isStrength)
        #expect(workoutType != .cycling)
        #expect(workoutType != .swimming)
    }

    @Test func lowReadinessChoosesSelectedRecoveryWithoutHighOrLowerBodyLoad() throws {
        let recommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: workout(type: .tempoRun, date: testDate, title: "Tempo Run"),
            profile: profile([
                (.running, .primary, 3),
                (.strength, .supporting, 2),
                (.mobility, .supporting, 1)
            ]),
            recentCompletedWorkouts: [],
            readinessScore: 38,
            schedulingContext: context(on: testDate)
        )
        let workoutType = try #require(recommendation.workoutType)

        #expect(workoutType.activity == .mobility)
        #expect(workoutType.isRecoveryCompatible)
        #expect(!workoutType.isHighIntensity)
        #expect(!workoutType.isLowerBodyDemanding)
        #expect(recommendation.adjustment == .recoveryDay)
    }

    @Test func selectedPlannedWorkoutSurvivesProceedReadinessUnchanged() {
        let planned = workout(type: .tempoRun, date: testDate, title: "Threshold Progression")
        let recommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: planned,
            profile: profile([(.running, .primary, 4)]),
            recentCompletedWorkouts: [],
            readinessScore: 84,
            schedulingContext: context(on: testDate)
        )

        #expect(recommendation.directive == .proceed)
        #expect(recommendation.workoutType == planned.workoutType)
        #expect(recommendation.title == planned.title)
        #expect(recommendation.schedulingReason == .requiredPrimary)
        #expect(recommendation.reason == "Scheduled in your plan.")
        #expect(recommendation.adjustment == .keepPlan)
    }

    @Test func moderateReadinessReturnsEasierSelectedWorkoutInsteadOfPlannedType() throws {
        let planned = workout(type: .tempoRun, date: testDate, title: "Threshold Progression")
        let recommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: planned,
            profile: profile([(.running, .primary, 4)]),
            recentCompletedWorkouts: [],
            readinessScore: 58,
            schedulingContext: context(on: testDate)
        )
        let workoutType = try #require(recommendation.workoutType)

        #expect(recommendation.directive == .reduceIntensity)
        #expect(workoutType != planned.workoutType)
        #expect(workoutType.activity == .running)
        #expect(workoutType.loadClass < planned.workoutType.loadClass)
        #expect(recommendation.title == workoutType.displayName)
        #expect(recommendation.adjustment == .easierWorkout)
    }

    @Test func productionContextConvertsActualLongRunAndDeduplicatesSynchronizedPlanWorkout() throws {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: testDate)!
        let syncedPlanWorkout = workout(
            type: .easyRun,
            date: yesterday,
            title: "Planned Run",
            completedActivityId: 7_001
        )
        let activity = Activity(
            id: 7_001,
            name: "Sunday Long Run",
            type: "Run",
            distance: 18_000,
            elapsed_time: 6_000,
            activity_date: yesterday.addingTimeInterval(12 * 60 * 60).timeIntervalSince1970
        )

        let built = TodayRecommendationContextBuilder.build(
            date: testDate,
            profile: profile([(.running, .primary, 3), (.strength, .supporting, 2)]),
            plannedWorkout: nil,
            planWorkouts: [syncedPlanWorkout],
            activities: [activity],
            readinessScore: 80
        )
        let completed = try #require(built.recentCompletedWorkouts.first)

        #expect(built.recentCompletedWorkouts.count == 1)
        #expect(completed.workoutType == .longRun)
        #expect(completed.isCompleted)
        #expect(completed.completedActivityId == activity.id)
        #expect(built.schedulingContext.previousWorkout == .longRun)
        #expect(built.schedulingContext.assignedWorkoutTypes.filter { $0 == .longRun }.count == 1)
        #expect(built.schedulingContext.assignedWorkoutTypes.count == 1)
    }

    @Test func presentationUsesDisplayNameSemanticAccentAndPlannedReason() {
        let planned = workout(type: .tempoRun, date: testDate, title: "Threshold Progression")
        let plannedRecommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: planned,
            profile: profile([(.running, .primary, 4)]),
            recentCompletedWorkouts: [],
            readinessScore: 82,
            schedulingContext: context(on: testDate)
        )
        let plannedPresentation = TodayRecommendationPresentation(recommendation: plannedRecommendation)

        #expect(plannedPresentation.badgeText == WorkoutType.tempoRun.displayName)
        #expect(plannedPresentation.accent == .runningPrimary)
        #expect(plannedPresentation.reason == "Scheduled in your plan.")

        let aerobicRecommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: nil,
            profile: profile([(.cycling, .primary, 3)]),
            recentCompletedWorkouts: [],
            readinessScore: 82,
            schedulingContext: context(on: testDate)
        )
        let aerobicPresentation = TodayRecommendationPresentation(recommendation: aerobicRecommendation)
        #expect(aerobicPresentation.badgeText == WorkoutType.cycling.displayName)
        #expect(aerobicPresentation.accent == .aerobic)

        let recoveryRecommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: nil,
            profile: profile([(.mobility, .primary, 3)]),
            recentCompletedWorkouts: [],
            readinessScore: 35,
            schedulingContext: context(on: testDate)
        )
        let recoveryPresentation = TodayRecommendationPresentation(recommendation: recoveryRecommendation)
        #expect(!recoveryPresentation.badgeText.contains("_"))
        #expect(recoveryPresentation.accent == .recovery)
        #expect(recoveryPresentation.reason?.isEmpty == false)
    }

    @Test func unselectedPlannedSupportIsReplacedBySelectedAlternative() throws {
        let recommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: workout(type: .cycling, date: testDate, title: "Aerobic Ride"),
            profile: profile([(.running, .primary, 4)]),
            recentCompletedWorkouts: [],
            readinessScore: 80,
            schedulingContext: context(on: testDate)
        )
        let workoutType = try #require(recommendation.workoutType)

        #expect(workoutType.isRunning)
        #expect(workoutType != .cycling)
        #expect(recommendation.title == workoutType.displayName)
    }

    @Test func generatedRecommendationLabelsAreHumanReadable() throws {
        let recommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: nil,
            profile: profile([(.running, .primary, 4), (.strength, .supporting, 2)]),
            recentCompletedWorkouts: [],
            readinessScore: 80,
            schedulingContext: context(on: testDate)
        )
        let workoutType = try #require(recommendation.workoutType)

        #expect(recommendation.title == workoutType.displayName)
        #expect(recommendation.badgeTitle == workoutType.displayName)
        #expect(!recommendation.title.contains("_"))
        #expect(!recommendation.badgeTitle.contains("_"))
    }

    @Test func recoveryChoiceOnlyReplacesTargetDayAndRecalculatesMileage() throws {
        let fixture = makePlan()
        let result = try #require(TodayRecommendationPolicy.applying(
            .recoveryDay,
            to: fixture.plan,
            on: fixture.today,
            readinessScore: 42
        ))

        #expect(result.updatedWorkout.workoutType == WorkoutType.rest)
        #expect(result.updatedWorkout.distance == nil)
        #expect(result.plan.workouts[1].id == "tomorrow")
        #expect(result.plan.workouts[1].distance == 4)
        #expect(result.plan.totalMileage == 4)
        #expect(result.receiptDetail.contains("42"))
    }

    @Test func userSelectedRecoveryRemainsVisibleWhenReadinessImproves() throws {
        let fixture = makePlan()
        let result = try #require(TodayRecommendationPolicy.applying(
            .recoveryDay,
            to: fixture.plan,
            on: fixture.today,
            readinessScore: 42
        ))

        let recommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: result.updatedWorkout,
            profile: profile([(.running, .primary, 3), (.mobility, .supporting, 1)]),
            recentCompletedWorkouts: [],
            readinessScore: 73,
            schedulingContext: context(on: fixture.today)
        )

        #expect(recommendation.workoutType == .rest)
        #expect(recommendation.title == result.updatedWorkout.title)
        #expect(recommendation.status == "Your Choice")
        #expect(recommendation.adjustment == .keepPlan)
    }

    @Test func easierChoiceReducesDistanceAndRemovesIntensity() throws {
        let fixture = makePlan()
        let result = try #require(TodayRecommendationPolicy.applying(
            .easierWorkout,
            to: fixture.plan,
            on: fixture.today,
            readinessScore: 58
        ))

        #expect(result.updatedWorkout.workoutType == WorkoutType.recoveryRun)
        #expect(abs((result.updatedWorkout.distance ?? 0) - 3.9) < 0.001)
        #expect(result.updatedWorkout.duration == 34)
        #expect(result.updatedWorkout.targetPace == "Conversational effort")
        #expect(abs(result.plan.totalMileage - 7.9) < 0.001)
    }

    @Test func keepingPlanDoesNotCreateAnAdjustment() {
        let fixture = makePlan()
        let result = TodayRecommendationPolicy.applying(
            .keepPlan,
            to: fixture.plan,
            on: fixture.today,
            readinessScore: 40
        )

        #expect(result == nil)
    }

    @Test func moderateReadinessOffersProfileSelectedWorkoutAlternatives() {
        let alternatives = TodayRecommendationPolicy.workoutAlternatives(
            profile: profile([
                (.running, .primary, 3),
                (.strength, .supporting, 2),
                (.mobility, .optional, 1)
            ]),
            readinessScore: 58
        )

        #expect(alternatives.contains(.recoveryRun))
        #expect(alternatives.contains(.upperBody))
        #expect(!alternatives.contains {
            $0.isHighIntensity || ($0.isLowerBodyDemanding && !$0.isRecoveryCompatible)
        })
    }

    @Test func allSafeProfileActivitiesAppearAsWorkoutAlternatives() {
        let alternatives = TodayRecommendationPolicy.workoutAlternatives(
            profile: profile([
                (.running, .primary, 3),
                (.strength, .supporting, 2),
                (.walking, .supporting, 1),
                (.mobility, .supporting, 1)
            ]),
            readinessScore: 73
        )

        #expect(alternatives == [.easyRun, .stretchMobility, .upperBody, .walking])
    }

    @Test func normalPlannedWorkoutStillOffersTrainingChoice() {
        let plannedWorkout = makePlan().plan.workouts.first

        #expect(TodayRecommendationPolicy.canChooseTodaysTraining(
            plannedWorkout: plannedWorkout,
            hasCompletedActivity: false
        ))
        #expect(!TodayRecommendationPolicy.canChooseTodaysTraining(
            plannedWorkout: plannedWorkout,
            hasCompletedActivity: true
        ))
    }

    @Test func missingTrainingProfileBlocksWorkoutAlternatives() {
        #expect(TrainingChoiceAvailabilityPolicy.requiresProfileSetup(
            needsPersonalization: true
        ))
        #expect(!TrainingChoiceAvailabilityPolicy.requiresProfileSetup(
            needsPersonalization: false
        ))
    }

    @Test func chosenWorkoutCanReplaceAPlannedRestDay() throws {
        let fixture = makePlan()
        let original = fixture.plan.workouts[0]
        let rest = DailyWorkout(
            id: original.id,
            date: original.date,
            dayOfWeek: original.dayOfWeek,
            workoutType: .rest,
            title: "Rest Day",
            description: "Recover.",
            duration: nil,
            distance: nil,
            targetPace: nil,
            exercises: nil,
            isCompleted: false,
            completedActivityId: nil
        )
        var workouts = fixture.plan.workouts
        workouts[0] = rest
        let restPlan = WeeklyTrainingPlan(
            id: fixture.plan.id,
            athleteId: fixture.plan.athleteId,
            weekStartDate: fixture.plan.weekStartDate,
            weekEndDate: fixture.plan.weekEndDate,
            workouts: workouts,
            weekNumber: fixture.plan.weekNumber,
            totalMileage: workouts.filter { $0.workoutType.isRunning }.compactMap(\.distance).reduce(0, +),
            focusArea: fixture.plan.focusArea,
            notes: fixture.plan.notes,
            generatedAt: fixture.plan.generatedAt,
            goalId: fixture.plan.goalId
        )

        let result = try #require(TodayRecommendationPolicy.applying(
            .chosenWorkout(.upperBody),
            to: restPlan,
            on: fixture.today,
            readinessScore: 58
        ))

        #expect(result.updatedWorkout.workoutType == .upperBody)
        #expect(result.updatedWorkout.duration != nil)
        #expect(result.plan.workouts[1].id == restPlan.workouts[1].id)
    }

    @Test func chosenWorkoutCanFillAnEmptyPlanDay() throws {
        let fixture = makePlan()
        let emptyDate = Calendar.current.date(
            byAdding: .day,
            value: 2,
            to: fixture.today
        )!

        let result = try #require(TodayRecommendationPolicy.applying(
            .chosenWorkout(.upperBody),
            to: fixture.plan,
            on: emptyDate,
            readinessScore: 73
        ))

        #expect(result.plan.workouts.count == fixture.plan.workouts.count + 1)
        #expect(result.updatedWorkout.workoutType == .upperBody)
        #expect(Calendar.current.isDate(result.updatedWorkout.date, inSameDayAs: emptyDate))
    }

    @Test func adaptiveChoiceUsesRemainingWeekRegeneratorAndReportsFutureChanges() async throws {
        let fixture = makePlan()
        let local = try #require(TodayRecommendationPolicy.applying(
            .recoveryDay,
            to: fixture.plan,
            on: fixture.today,
            readinessScore: 42
        ))
        let originalTomorrow = local.plan.workouts[1]
        let revisedTomorrow = DailyWorkout(
            id: originalTomorrow.id,
            date: originalTomorrow.date,
            dayOfWeek: originalTomorrow.dayOfWeek,
            workoutType: .stretchMobility,
            title: "Mobility",
            description: "Rebalanced.",
            duration: 20,
            distance: nil,
            targetPace: nil,
            exercises: nil,
            isCompleted: false,
            completedActivityId: nil
        )
        var revisedWorkouts = local.plan.workouts
        revisedWorkouts[1] = revisedTomorrow
        let revisedPlan = WeeklyTrainingPlan(
            id: local.plan.id,
            athleteId: local.plan.athleteId,
            weekStartDate: local.plan.weekStartDate,
            weekEndDate: local.plan.weekEndDate,
            workouts: revisedWorkouts,
            weekNumber: local.plan.weekNumber,
            totalMileage: revisedWorkouts.filter { $0.workoutType.isRunning }.compactMap(\.distance).reduce(0, +),
            focusArea: local.plan.focusArea,
            notes: local.plan.notes,
            generatedAt: local.plan.generatedAt,
            goalId: local.plan.goalId
        )

        let adapted = try await TodayRecommendationPolicy.adaptingRemainingWeek(
            local,
            profile: profile([(.running, .primary, 4)]),
            on: fixture.today,
            regenerate: { input, _ in
                #expect(input.workouts[0].workoutType == .rest)
                return revisedPlan
            }
        )

        #expect(adapted.plan.workouts[1].workoutType == .stretchMobility)
        #expect(adapted.receiptDetail.contains("Rebalanced"))
    }

    @Test func genericRecordedRunCannotDowngradeLinkedPlannedLongRun() throws {
        let calendar = Calendar(identifier: .gregorian)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: testDate))
        let activeProfile = profile([
            (.running, .primary, 4),
            (.strength, .supporting, 2),
        ])
        let plannedLongRun = workout(
            type: .longRun,
            date: yesterday,
            title: "Planned Long Run",
            completedActivityId: 7001
        )
        let genericRecordedRun = Activity(
            id: 7001,
            name: "Morning Run",
            type: "Run",
            distance: 16_093.44,
            start_date: yesterday.timeIntervalSince1970,
            elapsed_time: 4_800,
            athlete_id: 1,
            activity_date: yesterday.timeIntervalSince1970
        )

        let context = TodayRecommendationContextBuilder.build(
            date: testDate,
            profile: activeProfile,
            plannedWorkout: nil,
            planWorkouts: [plannedLongRun],
            activities: [genericRecordedRun],
            readinessScore: 82,
            calendar: calendar
        )

        #expect(context.recentCompletedWorkouts.count == 1)
        #expect(context.recentCompletedWorkouts.first?.workoutType == .longRun)
        #expect(context.schedulingContext.previousWorkout == .longRun)
        #expect(context.schedulingContext.assignedWorkoutTypes.filter { $0 == .longRun }.count == 1)
        #expect(context.schedulingContext.assignedWorkoutTypes.count == 1)

        let recommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: nil,
            profile: activeProfile,
            recentCompletedWorkouts: context.recentCompletedWorkouts,
            readinessScore: 82,
            schedulingContext: context.schedulingContext
        )

        #expect(recommendation.workoutType == .upperBody)
        #expect(recommendation.schedulingReason == .preservesLegRecovery)
        #expect(recommendation.reason == "Placed after yesterday's long run to preserve leg recovery.")
    }

    @Test func explicitlyRecordedLongRunWinsEqualSpecificityPlannedQualityTypes() throws {
        let calendar = Calendar(identifier: .gregorian)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: testDate))
        let activeProfile = profile([(.running, .primary, 4)])

        for (index, plannedType) in [WorkoutType.tempoRun, .intervalRun, .hillRun].enumerated() {
            let activityID = 7_101 + index
            let plannedWorkout = workout(
                type: plannedType,
                date: yesterday,
                title: "Planned \(plannedType.displayName)",
                completedActivityId: activityID
            )
            let recordedLongRun = Activity(
                id: activityID,
                name: "Long Run",
                type: "Run",
                distance: 16_093.44,
                start_date: yesterday.timeIntervalSince1970,
                elapsed_time: 4_800,
                athlete_id: 1,
                activity_date: yesterday.timeIntervalSince1970
            )

            let context = TodayRecommendationContextBuilder.build(
                date: testDate,
                profile: activeProfile,
                plannedWorkout: nil,
                planWorkouts: [plannedWorkout],
                activities: [recordedLongRun],
                readinessScore: 82,
                calendar: calendar
            )

            #expect(context.recentCompletedWorkouts.count == 1)
            #expect(context.recentCompletedWorkouts.first?.workoutType == .longRun)
            #expect(context.schedulingContext.previousWorkout == .longRun)
            #expect(context.schedulingContext.assignedWorkoutTypes == [.longRun])
        }
    }

    @Test func genericRecordedRunNeverDowngradesSpecificPlannedRunTypes() throws {
        let calendar = Calendar(identifier: .gregorian)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: testDate))
        let activeProfile = profile([(.running, .primary, 4)])

        for (index, plannedType) in [WorkoutType.longRun, .tempoRun, .intervalRun, .hillRun].enumerated() {
            let activityID = 7_201 + index
            let plannedWorkout = workout(
                type: plannedType,
                date: yesterday,
                title: "Planned \(plannedType.displayName)",
                completedActivityId: activityID
            )
            let genericRecordedRun = Activity(
                id: activityID,
                name: "Morning Run",
                type: "Run",
                distance: 8_046.72,
                start_date: yesterday.timeIntervalSince1970,
                elapsed_time: 2_400,
                athlete_id: 1,
                activity_date: yesterday.timeIntervalSince1970
            )

            let context = TodayRecommendationContextBuilder.build(
                date: testDate,
                profile: activeProfile,
                plannedWorkout: nil,
                planWorkouts: [plannedWorkout],
                activities: [genericRecordedRun],
                readinessScore: 82,
                calendar: calendar
            )

            #expect(context.recentCompletedWorkouts.count == 1)
            #expect(context.recentCompletedWorkouts.first?.workoutType == plannedType)
            #expect(context.schedulingContext.previousWorkout == plannedType)
            #expect(context.schedulingContext.assignedWorkoutTypes == [plannedType])
        }
    }

    @Test @MainActor func adjustmentReceiptCanBeUndoneAndRestoredPlanReplacesCache() throws {
        let fixture = makePlan()
        let profile = profile([(.running, .primary, 4)])
        let manager = DataManager.shared
        let originalActive = manager.currentWeeklyPlan
        let restoreCache = snapshotStandardCache()
        defer {
            manager.currentWeeklyPlan = originalActive
            restoreCache()
        }
        manager.currentWeeklyPlan = fixture.plan
        let adjustment = try #require(TodayRecommendationPolicy.applying(
            .easierWorkout,
            to: fixture.plan,
            on: fixture.today,
            readinessScore: 58
        ))

        try manager.updateCurrentWeeklyPlan(adjustment.plan, profile: profile)
        #expect(manager.currentWeeklyPlan?.workouts.first?.workoutType == .recoveryRun)
        #expect(!adjustment.receiptTitle.isEmpty)
        #expect(!adjustment.receiptDetail.isEmpty)

        try manager.updateCurrentWeeklyPlan(fixture.plan, profile: profile)
        #expect(manager.currentWeeklyPlan?.id == fixture.plan.id)
        #expect(manager.currentWeeklyPlan?.workouts.map(\.id) == fixture.plan.workouts.map(\.id))
        #expect(manager.currentWeeklyPlan?.workouts.map(\.workoutType) == fixture.plan.workouts.map(\.workoutType))
        guard case let .valid(cached) = TrainingPlanService.cachedPlanStatus(for: profile) else {
            Issue.record("Expected Undo to restore the cached original plan")
            return
        }
        #expect(cached.id == fixture.plan.id)
        #expect(cached.workouts.map(\.id) == fixture.plan.workouts.map(\.id))
        #expect(cached.workouts.map(\.workoutType) == fixture.plan.workouts.map(\.workoutType))
    }

    @Test @MainActor func profilelessProductionUpdateRestoresActiveAndCachedPrescriptionOnUndo() throws {
        let fixture = makePlan()
        let activeProfile = profile([(.running, .primary, 4)])
        let manager = DataManager.shared
        let originalActive = manager.currentWeeklyPlan
        let restoreCache = snapshotStandardCache()
        let restoreProfile = snapshotStandardTrainingProfile()
        defer {
            manager.currentWeeklyPlan = originalActive
            restoreCache()
            restoreProfile()
        }

        try TrainingProfileStore().save(activeProfile)
        manager.currentWeeklyPlan = fixture.plan
        try manager.updateCurrentWeeklyPlan(fixture.plan)
        let adjustment = try #require(TodayRecommendationPolicy.applying(
            .easierWorkout,
            to: fixture.plan,
            on: fixture.today,
            readinessScore: 58
        ))

        try manager.updateCurrentWeeklyPlan(adjustment.plan)
        try manager.updateCurrentWeeklyPlan(fixture.plan)

        let restoredActive = try #require(manager.currentWeeklyPlan)
        #expect(restoredActive.id == fixture.plan.id)
        #expect(restoredActive.workouts.map(\.id) == fixture.plan.workouts.map(\.id))
        #expect(restoredActive.workouts.map(\.workoutType) == fixture.plan.workouts.map(\.workoutType))
        #expect(restoredActive.workouts.map(\.duration) == fixture.plan.workouts.map(\.duration))
        #expect(restoredActive.workouts.map(\.distance) == fixture.plan.workouts.map(\.distance))
        #expect(restoredActive.workouts.map(\.targetPace) == fixture.plan.workouts.map(\.targetPace))
        #expect(restoredActive.workouts.map(\.title) == fixture.plan.workouts.map(\.title))
        #expect(restoredActive.workouts.map(\.description) == fixture.plan.workouts.map(\.description))

        let storedProfile = TrainingProfileStore().profile
        #expect(storedProfile == activeProfile.validated(existingPlan: fixture.plan).profile)
        guard case let .valid(cached) = TrainingPlanService.cachedPlanStatus(for: storedProfile) else {
            Issue.record("Expected profile-less Undo to restore a cache-valid original plan")
            return
        }
        #expect(cached.id == fixture.plan.id)
        #expect(cached.workouts.map(\.id) == fixture.plan.workouts.map(\.id))
        #expect(cached.workouts.map(\.workoutType) == fixture.plan.workouts.map(\.workoutType))
        #expect(cached.workouts.map(\.duration) == fixture.plan.workouts.map(\.duration))
        #expect(cached.workouts.map(\.distance) == fixture.plan.workouts.map(\.distance))
        #expect(cached.workouts.map(\.targetPace) == fixture.plan.workouts.map(\.targetPace))
        #expect(cached.workouts.map(\.title) == fixture.plan.workouts.map(\.title))
        #expect(cached.workouts.map(\.description) == fixture.plan.workouts.map(\.description))
    }

    private var testDate: Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 8, day: 27))!
    }

    private func profile(
        _ preferences: [(TrainingActivity, TrainingActivityRole, Int)]
    ) -> TrainingProfile {
        TrainingProfile(
            schemaVersion: TrainingProfile.currentSchemaVersion,
            activities: preferences.map {
                TrainingActivityPreference(activity: $0.0, role: $0.1, sessionsPerWeek: $0.2)
            },
            trainingDaysPerWeek: 6,
            preferredLongRunWeekday: 1,
            unavailableWeekdays: [],
            strengthEquipment: .dumbbells,
            strengthExperience: .intermediate
        )
    }

    private func context(on date: Date) -> SchedulingDayContext {
        SchedulingDayContext(
            date: date,
            weekday: DayOfWeek.from(date: date),
            profile: .runningFirstDefault,
            plannedOrFixedWorkout: nil,
            previousWorkout: nil,
            nextWorkout: nil,
            readiness: .normal,
            assignedWorkoutTypes: [],
            isCompletedProtected: false,
            isUnavailable: false,
            isTaperProtected: false
        )
    }

    private func workout(
        type: WorkoutType,
        date: Date,
        title: String,
        completedActivityId: Int? = nil
    ) -> DailyWorkout {
        DailyWorkout(
            id: "\(type.rawValue)-\(date.timeIntervalSince1970)",
            date: date,
            dayOfWeek: DayOfWeek.from(date: date),
            workoutType: type,
            title: title,
            description: "Test workout",
            duration: 45,
            distance: type.isRunning ? 5 : nil,
            targetPace: type.isRunning ? "Conversational effort" : nil,
            exercises: nil,
            isCompleted: true,
            completedActivityId: completedActivityId
        )
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

    private func snapshotStandardTrainingProfile() -> () -> Void {
        let defaults = UserDefaults.standard
        let profile = defaults.object(forKey: "trainingProfile.v1")
        let personalized = defaults.object(forKey: "trainingProfile.personalized.v1")
        return {
            if let profile { defaults.set(profile, forKey: "trainingProfile.v1") }
            else { defaults.removeObject(forKey: "trainingProfile.v1") }
            if let personalized { defaults.set(personalized, forKey: "trainingProfile.personalized.v1") }
            else { defaults.removeObject(forKey: "trainingProfile.personalized.v1") }
        }
    }

    private func makePlan() -> (plan: WeeklyTrainingPlan, today: Date) {
        let calendar = Calendar(identifier: .gregorian)
        let currentDay = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: currentDay)
        let weekStart = calendar.date(byAdding: .day, value: -(weekday - 1), to: currentDay)!
        let today = calendar.date(byAdding: .day, value: 3, to: weekStart)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let workouts = [
            DailyWorkout(
                id: "today",
                date: today,
                dayOfWeek: DayOfWeek.from(date: today),
                workoutType: .tempoRun,
                title: "Tempo Run",
                description: "Planned quality session",
                duration: 45,
                distance: 6,
                targetPace: "8:00/mi",
                exercises: nil,
                isCompleted: false,
                completedActivityId: nil
            ),
            DailyWorkout(
                id: "tomorrow",
                date: tomorrow,
                dayOfWeek: DayOfWeek.from(date: tomorrow),
                workoutType: .easyRun,
                title: "Easy Run",
                description: "Easy miles",
                duration: 36,
                distance: 4,
                targetPace: "10:00/mi",
                exercises: nil,
                isCompleted: false,
                completedActivityId: nil
            )
        ]
        return (
            WeeklyTrainingPlan(
                id: "week",
                athleteId: 1,
                weekStartDate: weekStart,
                weekEndDate: calendar.date(byAdding: .day, value: 6, to: weekStart)!,
                workouts: workouts,
                weekNumber: 1,
                totalMileage: 10,
                focusArea: "Base",
                notes: nil,
                generatedAt: today,
                goalId: nil
            ),
            today
        )
    }
}
