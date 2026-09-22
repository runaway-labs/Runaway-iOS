import Foundation

enum TodayWorkoutChoicePolicy {
    struct Context {
        let profile: TrainingProfile
        let date: Date
        let recommendedWorkout: DailyWorkout?
        let hasStrengthBenchmarks: Bool

        init(
            profile: TrainingProfile,
            date: Date = Date(),
            recommendedWorkout: DailyWorkout? = nil,
            hasStrengthBenchmarks: Bool = true
        ) {
            self.profile = profile
            self.date = date
            self.recommendedWorkout = recommendedWorkout
            self.hasStrengthBenchmarks = hasStrengthBenchmarks
        }
    }

    static func choices(context: Context) -> [TodayWorkoutChoice] {
        let enabled = context.profile.activities
            .filter { $0.sessionsPerWeek > 0 }
            .map { choice(for: $0.activity, context: context) }
        let recovery = TodayWorkoutChoice(
            id: "recovery", activity: nil, workoutType: .stretchMobility,
            title: "Recovery", reason: "Keep the habit while reducing training load.",
            availability: .available,
            isRecommended: context.recommendedWorkout?.workoutType == .stretchMobility
        )
        let rest = TodayWorkoutChoice(
            id: "rest", activity: nil, workoutType: .rest,
            title: "Rest", reason: "Protect recovery and move the week's useful work forward.",
            availability: .available,
            isRecommended: context.recommendedWorkout?.workoutType == .rest
        )
        return enabled + [recovery, rest]
    }

    static func draft(for choice: TodayWorkoutChoice, context: Context) -> TodayWorkoutDraft? {
        guard choice.availability == .available else { return nil }
        if let recommended = context.recommendedWorkout,
           recommended.workoutType == choice.workoutType
            || (choice.activity != nil && recommended.workoutType.activity == choice.activity) {
            return TodayWorkoutDraft(workout: sanitized(recommended), source: .recommendation, reason: choice.reason)
        }

        let day = Calendar.current.startOfDay(for: context.date)
        let details = prescription(for: choice.workoutType, equipment: context.profile.strengthEquipment)
        let workout = DailyWorkout(
            id: "today-choice-\(Int(day.timeIntervalSince1970))-\(choice.workoutType.rawValue)",
            date: day,
            dayOfWeek: .from(date: day),
            workoutType: choice.workoutType,
            title: choice.title,
            description: choice.reason,
            duration: details.duration,
            distance: details.distance,
            targetPace: choice.workoutType.isRunning ? details.targetPace : nil,
            exercises: details.exercises,
            isCompleted: false,
            completedActivityId: nil
        )
        return TodayWorkoutDraft(workout: workout, source: .alternative, reason: choice.reason)
    }

    private static func choice(for activity: TrainingActivity, context: Context) -> TodayWorkoutChoice {
        let type = workoutType(for: activity)
        let blocker: TodayWorkoutChoice.Availability = activity == .strength && !context.hasStrengthBenchmarks
            ? .blocked(.missingStrengthBenchmarks)
            : .available
        return TodayWorkoutChoice(
            id: activity.rawValue,
            activity: activity,
            workoutType: type,
            title: title(for: activity),
            reason: reason(for: activity),
            availability: blocker,
            isRecommended: context.recommendedWorkout?.workoutType.activity == activity
        )
    }

    private static func workoutType(for activity: TrainingActivity) -> WorkoutType {
        switch activity {
        case .running: return .easyRun
        case .strength: return .fullBody
        case .cycling: return .cycling
        case .swimming: return .swimming
        case .walking: return .walking
        case .hiking: return .hiking
        case .mobility: return .stretchMobility
        }
    }

    private static func title(for activity: TrainingActivity) -> String {
        switch activity {
        case .running: return "Run"
        case .strength: return "Full Body Strength"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        case .mobility: return "Mobility"
        }
    }

    private static func reason(for activity: TrainingActivity) -> String {
        switch activity {
        case .running: return "Build aerobic fitness with a controlled, conversational effort."
        case .strength: return "Build durable strength that supports your broader training goals."
        case .cycling: return "Add aerobic work with less impact than running."
        case .swimming: return "Build aerobic capacity while unloading your joints."
        case .walking: return "Add low-stress aerobic volume and support recovery."
        case .hiking: return "Build time on feet with varied terrain and moderate load."
        case .mobility: return "Restore range of motion and prepare for the week's next session."
        }
    }

    private struct Prescription {
        let duration: Int?
        let distance: Double?
        let targetPace: String?
        let exercises: [Exercise]?
    }

    private static func prescription(for type: WorkoutType, equipment: StrengthEquipment) -> Prescription {
        switch type {
        case .easyRun:
            return Prescription(duration: 30, distance: nil, targetPace: "Conversational effort", exercises: nil)
        case .fullBody, .strengthTraining, .upperBody, .lowerBody:
            let load = equipment == .bodyweight ? "Bodyweight" : "Comfortable working load"
            let exercises = [
                Exercise(name: "Squat", sets: 3, reps: "8-10", weight: load),
                Exercise(name: "Push", sets: 3, reps: "8-10", weight: load),
                Exercise(name: "Hinge", sets: 3, reps: "8-10", weight: load),
                Exercise(name: "Pull", sets: 3, reps: "8-10", weight: load),
            ]
            return Prescription(duration: 45, distance: nil, targetPace: nil, exercises: exercises)
        case .cycling: return Prescription(duration: 45, distance: nil, targetPace: nil, exercises: nil)
        case .swimming: return Prescription(duration: 30, distance: nil, targetPace: nil, exercises: nil)
        case .walking: return Prescription(duration: 40, distance: nil, targetPace: nil, exercises: nil)
        case .hiking: return Prescription(duration: 60, distance: nil, targetPace: nil, exercises: nil)
        case .yoga, .stretchMobility: return Prescription(duration: 20, distance: nil, targetPace: nil, exercises: nil)
        case .rest: return Prescription(duration: nil, distance: nil, targetPace: nil, exercises: nil)
        default: return Prescription(duration: 30, distance: nil, targetPace: nil, exercises: nil)
        }
    }

    private static func sanitized(_ workout: DailyWorkout) -> DailyWorkout {
        DailyWorkout(
            id: workout.id, date: workout.date, dayOfWeek: workout.dayOfWeek,
            workoutType: workout.workoutType, title: workout.title, description: workout.description,
            duration: workout.duration, distance: workout.distance,
            targetPace: workout.displayTargetPace, exercises: workout.exercises,
            isCompleted: workout.isCompleted, completedActivityId: workout.completedActivityId,
            acceptedPrescription: workout.acceptedPrescription,
            acceptedCompletion: workout.acceptedCompletion,
            commitment: workout.commitment
        )
    }
}
