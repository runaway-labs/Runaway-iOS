import Foundation
import Testing
@testable import Runaway_iOS

@Suite("Today workout decision")
struct TodayWorkoutDecisionServiceTests {
    @Test func previewIsNonMutatingAndProtectsCompletedWork() throws {
        let plan = fixturePlan()
        let completedID = try #require(plan.workouts.first { $0.isCompleted }).id
        let draft = TodayWorkoutDraft.customRun(minutes: 35, miles: nil, date: plan.workouts[1].date)
        let preview = try TodayWorkoutDecisionService.preview(draft: draft, currentPlan: plan, now: plan.workouts[1].date)

        #expect(plan.workouts[1].commitment == nil)
        #expect(preview.proposedPlan.workouts.first { $0.id == completedID }?.isCompleted == true)
        #expect(preview.proposedPlan.workout(for: plan.workouts[1].date)?.commitment != nil)
    }

    @Test func stalePreviewCannotCommit() throws {
        let plan = fixturePlan()
        let today = plan.workouts[1].date
        let preview = try TodayWorkoutDecisionService.preview(
            draft: .customRun(minutes: 35, miles: nil, date: today),
            currentPlan: plan,
            now: today
        )
        var changedWorkouts = plan.workouts
        changedWorkouts[2] = replacing(changedWorkouts[2], duration: 99)
        let changed = replacing(plan, workouts: changedWorkouts)
        #expect(throws: TodayWorkoutDecisionError.stalePlan) {
            try TodayWorkoutDecisionService.commit(preview: preview, currentPlan: changed)
        }
    }

    @Test func goalCriticalWorkoutMovesRatherThanDisappears() throws {
        let plan = fixturePlan(todayIsLongRun: true)
        let today = plan.workouts[1].date
        let rest = TodayWorkoutChoice(
            id: "rest", activity: nil, workoutType: .rest, title: "Rest",
            reason: "Recover today.", availability: .available, isRecommended: false
        )
        let context = TodayWorkoutChoicePolicy.Context(profile: .runningFirstDefault, date: today)
        let draft = try #require(TodayWorkoutChoicePolicy.draft(for: rest, context: context))
        let preview = try TodayWorkoutDecisionService.preview(draft: draft, currentPlan: plan, now: today)
        #expect(preview.proposedPlan.workouts.contains { $0.workoutType == .longRun })
        #expect(preview.changes.contains { $0.kind == .moved })
    }

    private func fixturePlan(todayIsLongRun: Bool = false) -> WeeklyTrainingPlan {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let workouts = (0..<7).map { offset -> DailyWorkout in
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            let type: WorkoutType = offset == 1 ? (todayIsLongRun ? .longRun : .easyRun) : (offset == 3 ? .rest : .easyRun)
            return DailyWorkout(
                id: "day-\(offset)", date: date, dayOfWeek: .from(date: date), workoutType: type,
                title: type.displayName, description: "Fixture", duration: type == .rest ? nil : 30,
                distance: type.isRunning ? 3 : nil, targetPace: type.isRunning ? "10:00 /mi" : nil,
                exercises: nil, isCompleted: offset == 0, completedActivityId: offset == 0 ? 1 : nil
            )
        }
        return WeeklyTrainingPlan(
            id: "week", athleteId: 42, weekStartDate: start,
            weekEndDate: calendar.date(byAdding: .day, value: 6, to: start)!, workouts: workouts,
            weekNumber: 1, totalMileage: 18, focusArea: "Build", notes: nil,
            generatedAt: start, goalId: 7
        )
    }

    private func replacing(_ workout: DailyWorkout, duration: Int) -> DailyWorkout {
        DailyWorkout(
            id: workout.id, date: workout.date, dayOfWeek: workout.dayOfWeek,
            workoutType: workout.workoutType, title: workout.title, description: workout.description,
            duration: duration, distance: workout.distance, targetPace: workout.targetPace,
            exercises: workout.exercises, isCompleted: workout.isCompleted,
            completedActivityId: workout.completedActivityId
        )
    }

    private func replacing(_ plan: WeeklyTrainingPlan, workouts: [DailyWorkout]) -> WeeklyTrainingPlan {
        WeeklyTrainingPlan(
            id: plan.id, athleteId: plan.athleteId, weekStartDate: plan.weekStartDate,
            weekEndDate: plan.weekEndDate, workouts: workouts, weekNumber: plan.weekNumber,
            totalMileage: plan.totalMileage, focusArea: plan.focusArea, notes: plan.notes,
            generatedAt: plan.generatedAt, goalId: plan.goalId
        )
    }
}
