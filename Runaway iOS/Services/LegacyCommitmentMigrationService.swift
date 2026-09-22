import Foundation

enum LegacyCommitmentMigrationService {
    struct Proposal {
        let draft: TodayWorkoutDraft
        let requiresConfirmation: Bool
    }

    static func proposal(
        legacy: DailyCommitment,
        plan: WeeklyTrainingPlan,
        profile: TrainingProfile,
        calendar: Calendar = .current
    ) -> Proposal? {
        guard !legacy.isFulfilled,
              let workout = plan.workouts.first(where: {
                  calendar.isDate($0.date, inSameDayAs: legacy.commitmentDateAsDate)
              }),
              workout.commitment == nil else { return nil }

        let mapping: (TrainingActivity?, WorkoutType, String)
        switch legacy.activityType {
        case .run: mapping = (.running, .easyRun, "Run")
        case .workout: mapping = (.strength, .fullBody, "Full Body Strength")
        case .walk: mapping = (.walking, .walking, "Walking")
        case .yoga: mapping = (.mobility, .yoga, "Yoga")
        }
        let choice = TodayWorkoutChoice(
            id: "legacy-\(legacy.activityType.rawValue)", activity: mapping.0,
            workoutType: mapping.1, title: mapping.2,
            reason: "Review your earlier commitment as a complete workout before adding it to the plan.",
            availability: .available, isRecommended: false
        )
        let context = TodayWorkoutChoicePolicy.Context(
            profile: profile, date: workout.date, recommendedWorkout: workout
        )
        guard let draft = TodayWorkoutChoicePolicy.draft(for: choice, context: context) else { return nil }
        return Proposal(draft: draft, requiresConfirmation: true)
    }
}
