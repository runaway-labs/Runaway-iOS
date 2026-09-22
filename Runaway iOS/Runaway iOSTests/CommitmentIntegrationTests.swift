import Foundation
import Testing
@testable import Runaway_iOS

@Suite("Commitment integration")
struct CommitmentIntegrationTests {
    @Test func committedPlanAlwaysWinsOverLegacyRow() throws {
        let plan = try planFixture(committed: true)
        let legacy = DailyCommitment(athleteId: 42, activityType: .walk, commitmentDate: plan.workouts[0].date)
        #expect(LegacyCommitmentMigrationService.proposal(
            legacy: legacy, plan: plan, profile: .runningFirstDefault
        ) == nil)
    }

    @Test func legacyRowCreatesReviewableDraftWithoutPersistence() throws {
        let plan = try planFixture(committed: false)
        let legacy = DailyCommitment(athleteId: 42, activityType: .walk, commitmentDate: plan.workouts[0].date)
        let proposal = try #require(LegacyCommitmentMigrationService.proposal(
            legacy: legacy, plan: plan, profile: .runningFirstDefault
        ))
        #expect(proposal.draft.workout.workoutType == .walking)
        #expect(proposal.requiresConfirmation)
        #expect(plan.workouts[0].commitment == nil)
    }

    @Test func importedEvidenceDistinguishesFullPartialAndMismatch() throws {
        let workout = try planFixture(committed: true).workouts[0]
        let date = workout.date.timeIntervalSince1970
        let full = Activity(id: 1, name: "Run", type: "Run", distance: 6_437.376,
                            elapsed_time: 2_400, activity_date: date)
        let partial = Activity(id: 2, name: "Run", type: "Run", distance: 3_218.688,
                               elapsed_time: 1_200, activity_date: date)
        let mismatch = Activity(id: 3, name: "Ride", type: "Ride", distance: 10_000,
                                elapsed_time: 2_400, activity_date: date)
        #expect(CommittedWorkoutCompletionPolicy.status(workout: workout, evidence: [full]) == .complete)
        #expect(CommittedWorkoutCompletionPolicy.status(workout: workout, evidence: [partial]) == .partial)
        #expect(CommittedWorkoutCompletionPolicy.status(workout: workout, evidence: [mismatch]) == .notCompleted)
        #expect(CommittedWorkoutCompletionPolicy.status(workout: workout, evidence: [full, full]) == .complete)
    }

    @Test func offPlanRunReplacesMissedStrengthWithRecordedWork() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Chicago"))
        let monday = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000))
        let sunday = try #require(calendar.date(byAdding: .day, value: -1, to: monday))
        let strength = DailyWorkout(
            id: "sun-strength", date: sunday, dayOfWeek: .from(date: sunday), workoutType: .fullBody,
            title: "Full Body", description: "Planned strength", duration: 45, distance: nil,
            targetPace: nil, exercises: [], isCompleted: false, completedActivityId: nil
        )
        let plan = WeeklyTrainingPlan(
            id: "week", athleteId: 42, weekStartDate: sunday,
            weekEndDate: try #require(calendar.date(byAdding: .day, value: 6, to: sunday)),
            workouts: [strength], weekNumber: 1, totalMileage: 0, focusArea: nil,
            notes: nil, generatedAt: sunday, goalId: nil
        )
        let run = Activity(id: 91, name: "Sunday Run", type: "Run", distance: 6_000,
                           elapsed_time: 2_100, activity_date: sunday.addingTimeInterval(12 * 3_600).timeIntervalSince1970)

        #expect(TrainingPlanService.shouldRegeneratePlan(currentPlan: plan, newActivity: run))
        let reconciled = TrainingPlanService.reconciledPlan(
            currentPlan: plan, completedActivities: [run], now: monday, calendar: calendar
        )
        let recorded = try #require(reconciled.workouts.first)
        #expect(recorded.workoutType.isRunning)
        #expect(recorded.title == "Sunday Run")
        #expect(recorded.isCompleted)
        #expect(recorded.completedActivityId == run.id)
    }

    @Test func backToBackRecordedRunsPullRecoveryModalityAheadOfThirdRun() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Chicago"))
        let monday = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000))
        let sunday = try #require(calendar.date(byAdding: .day, value: -1, to: monday))
        func day(_ offset: Int) throws -> Date { try #require(calendar.date(byAdding: .day, value: offset, to: monday)) }
        let workouts = [
            DailyWorkout(id: "sun", date: sunday, dayOfWeek: .from(date: sunday), workoutType: .easyRun,
                         title: "Sunday Run", description: "Recorded", duration: 35, distance: 3.7,
                         targetPace: nil, exercises: nil, isCompleted: true, completedActivityId: 1),
            DailyWorkout(id: "mon", date: monday, dayOfWeek: .from(date: monday), workoutType: .easyRun,
                         title: "Monday Run", description: "Recorded", duration: 40, distance: 6,
                         targetPace: nil, exercises: nil, isCompleted: true, completedActivityId: 2),
            DailyWorkout(id: "tue", date: try day(1), dayOfWeek: .from(date: try day(1)), workoutType: .easyRun,
                         title: "Easy Run", description: "Planned", duration: 45, distance: 4.5,
                         targetPace: "10:00 /mi", exercises: nil, isCompleted: false, completedActivityId: nil),
            DailyWorkout(id: "wed", date: try day(2), dayOfWeek: .from(date: try day(2)), workoutType: .tempoRun,
                         title: "Tempo Run", description: "Planned", duration: 30, distance: 3.8,
                         targetPace: "8:00 /mi", exercises: nil, isCompleted: false, completedActivityId: nil),
            DailyWorkout(id: "thu", date: try day(3), dayOfWeek: .from(date: try day(3)), workoutType: .fullBody,
                         title: "Full Body", description: "Planned", duration: 45, distance: nil,
                         targetPace: nil, exercises: [], isCompleted: false, completedActivityId: nil)
        ]
        let plan = WeeklyTrainingPlan(
            id: "week", athleteId: 42, weekStartDate: sunday, weekEndDate: try day(5), workouts: workouts,
            weekNumber: 1, totalMileage: 18, focusArea: nil, notes: nil, generatedAt: monday, goalId: nil
        )

        let reconciled = TrainingPlanService.reconciledPlan(
            currentPlan: plan, completedActivities: [], now: monday, calendar: calendar
        )
        #expect(reconciled.workout(for: .tuesday)?.workoutType == .fullBody)
        #expect(reconciled.workout(for: .wednesday)?.workoutType == .tempoRun)
        #expect(reconciled.workout(for: .thursday)?.workoutType == .easyRun)
    }

    private func planFixture(committed: Bool) throws -> WeeklyTrainingPlan {
        let date = Calendar.current.startOfDay(for: Date())
        var workout = DailyWorkout(
            id: "today", date: date, dayOfWeek: .from(date: date), workoutType: .easyRun,
            title: "Four mile run", description: "Aerobic base", duration: 40, distance: 4,
            targetPace: "10:00 /mi", exercises: nil, isCompleted: false, completedActivityId: nil
        )
        if committed {
            workout.commitment = WorkoutCommitment(
                committedAt: date, source: .recommendation,
                prescriptionFingerprint: try WorkoutPrescriptionFingerprint.make(workout),
                originalWorkoutID: workout.id
            )
        }
        return WeeklyTrainingPlan(
            id: "week", athleteId: 42, weekStartDate: date, weekEndDate: date,
            workouts: [workout], weekNumber: 1, totalMileage: 4, focusArea: nil,
            notes: nil, generatedAt: date, goalId: nil
        )
    }
}
