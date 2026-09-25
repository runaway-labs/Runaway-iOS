import Foundation
import Testing
@testable import Runaway_iOS

@Suite("Today workout choices")
struct TodayWorkoutChoicePolicyTests {
    @Test func everyEnabledActivityIsVisibleAlongsideRecoveryAndRest() {
        let profile = TrainingProfile(
            schemaVersion: TrainingProfile.currentSchemaVersion,
            activities: [
                .init(activity: .running, role: .primary, sessionsPerWeek: 3),
                .init(activity: .strength, role: .supporting, sessionsPerWeek: 2),
                .init(activity: .cycling, role: .optional, sessionsPerWeek: 1),
                .init(activity: .swimming, role: .optional, sessionsPerWeek: 1),
            ],
            trainingDaysPerWeek: 7,
            preferredLongRunWeekday: 7,
            unavailableWeekdays: [],
            strengthEquipment: .dumbbells,
            strengthExperience: .intermediate
        )
        let choices = TodayWorkoutChoicePolicy.choices(context: .init(profile: profile))
        let activities = Set(choices.compactMap(\.activity))
        #expect(activities.isSuperset(of: [.running, .strength, .cycling, .swimming]))
        #expect(choices.contains { $0.workoutType == .stretchMobility })
        #expect(choices.contains { $0.workoutType == .rest })
    }

    @Test func strengthRemainsAvailableWithoutBenchmarks() throws {
        var profile = TrainingProfile.runningFirstDefault
        profile.activities.append(.init(activity: .strength, role: .supporting, sessionsPerWeek: 1))
        let choices = TodayWorkoutChoicePolicy.choices(
            context: .init(profile: profile, hasStrengthBenchmarks: false)
        )
        let strength = try #require(choices.first { $0.activity == .strength })
        #expect(strength.availability == .available)
    }

    @Test func nonRunningDraftNeverCarriesPace() throws {
        var profile = TrainingProfile.runningFirstDefault
        profile.activities.append(.init(activity: .walking, role: .supporting, sessionsPerWeek: 1))
        let context = TodayWorkoutChoicePolicy.Context(profile: profile)
        let choice = try #require(TodayWorkoutChoicePolicy.choices(context: context).first { $0.activity == .walking })
        let draft = try #require(TodayWorkoutChoicePolicy.draft(for: choice, context: context))
        #expect(draft.workout.displayTargetPace == nil)
        #expect(draft.workout.targetPace == nil)
    }

    @Test func customDraftValidationIsModalityAware() {
        #expect(TodayWorkoutDraft.customRun(minutes: 30, miles: nil).validationIssues.isEmpty)
        #expect(TodayWorkoutDraft.customRun(minutes: nil, miles: nil).validationIssues == [.missingRunningDose])
        #expect(TodayWorkoutDraft.customStrength(exercises: []).validationIssues == [.missingExercises])
        let incomplete = Exercise(name: "Squat", sets: nil, reps: nil)
        #expect(TodayWorkoutDraft.customStrength(exercises: [incomplete]).validationIssues == [.missingSetsOrReps])
    }
}
