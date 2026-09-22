import Foundation
import Testing
@testable import Runaway_iOS

@MainActor
@Suite("Today decision view model")
struct TodayWorkoutDecisionViewModelTests {
    @Test func recommendationRequiresExplicitCommit() throws {
        let plan = planFixture()
        let model = TodayWorkoutDecisionViewModel(
            plan: plan, profile: .runningFirstDefault,
            recommendedWorkout: plan.workouts[0], date: plan.workouts[0].date
        )
        model.load()
        #expect(model.phase == .recommended)
        try model.select(model.recommendedChoiceID)
        #expect(model.phase == .editing)
        #expect(plan.workouts[0].commitment == nil)
        try model.buildPreview()
        #expect(model.phase == .previewing)
        #expect(plan.workouts[0].commitment == nil)
        try model.commit { _ in }
        #expect(model.phase == .committed)
    }

    @Test func blockedChoiceExplainsWhyAndCannotPreview() throws {
        var profile = TrainingProfile.runningFirstDefault
        profile.activities.append(.init(activity: .strength, role: .supporting, sessionsPerWeek: 1))
        let plan = planFixture()
        let model = TodayWorkoutDecisionViewModel(
            plan: plan, profile: profile, recommendedWorkout: plan.workouts[0],
            date: plan.workouts[0].date, hasStrengthBenchmarks: false
        )
        model.load()
        model.select("strength")
        #expect(model.blockerMessage == "Add current strength benchmarks to build a complete strength prescription.")
        #expect(model.canPreview == false)
    }

    private func planFixture() -> WeeklyTrainingPlan {
        let date = Calendar.current.startOfDay(for: Date())
        let workout = DailyWorkout(
            id: "today", date: date, dayOfWeek: .from(date: date), workoutType: .easyRun,
            title: "Easy Run", description: "Aerobic base", duration: 30, distance: 3,
            targetPace: "10:00 /mi", exercises: nil, isCompleted: false, completedActivityId: nil
        )
        return WeeklyTrainingPlan(
            id: "week", athleteId: 42, weekStartDate: date, weekEndDate: date,
            workouts: [workout], weekNumber: 1, totalMileage: 3, focusArea: nil,
            notes: nil, generatedAt: date, goalId: nil
        )
    }
}
