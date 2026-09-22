import Foundation

enum TodayWorkoutChoiceBlocker: String, Codable, Equatable, Sendable {
    case missingStrengthBenchmarks

    var message: String {
        switch self {
        case .missingStrengthBenchmarks:
            return "Add current strength benchmarks to build a complete strength prescription."
        }
    }
}

struct TodayWorkoutChoice: Identifiable, Equatable, Sendable {
    enum Availability: Equatable, Sendable {
        case available
        case blocked(TodayWorkoutChoiceBlocker)
    }

    let id: String
    let activity: TrainingActivity?
    let workoutType: WorkoutType
    let title: String
    let reason: String
    let availability: Availability
    let isRecommended: Bool
}

struct TodayWorkoutDraft {
    enum ValidationIssue: Equatable, Sendable {
        case missingRunningDose
        case missingExercises
        case missingSetsOrReps
    }

    let workout: DailyWorkout
    let source: WorkoutCommitment.Source
    let reason: String

    var validationIssues: [ValidationIssue] {
        if workout.workoutType.isRunning {
            let hasDuration = (workout.duration ?? 0) > 0
            let hasDistance = (workout.distance ?? 0) > 0
            return hasDuration || hasDistance ? [] : [.missingRunningDose]
        }
        if workout.workoutType.isStrength {
            guard let exercises = workout.exercises, !exercises.isEmpty else { return [.missingExercises] }
            let incomplete = exercises.contains {
                ($0.sets ?? 0) <= 0 || ($0.reps?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            }
            return incomplete ? [.missingSetsOrReps] : []
        }
        return []
    }

    static func customRun(minutes: Int?, miles: Double?, date: Date = Date()) -> TodayWorkoutDraft {
        let day = Calendar.current.startOfDay(for: date)
        return TodayWorkoutDraft(
            workout: DailyWorkout(
                id: "custom-run-\(Int(day.timeIntervalSince1970))", date: day,
                dayOfWeek: .from(date: day), workoutType: .easyRun,
                title: "Custom Run", description: "Built by you for today.",
                duration: minutes, distance: miles, targetPace: nil, exercises: nil,
                isCompleted: false, completedActivityId: nil
            ),
            source: .custom,
            reason: "A workout you shaped around today's schedule."
        )
    }

    static func customStrength(exercises: [Exercise], date: Date = Date()) -> TodayWorkoutDraft {
        let day = Calendar.current.startOfDay(for: date)
        return TodayWorkoutDraft(
            workout: DailyWorkout(
                id: "custom-strength-\(Int(day.timeIntervalSince1970))", date: day,
                dayOfWeek: .from(date: day), workoutType: .fullBody,
                title: "Custom Strength", description: "Built by you for today.",
                duration: 45, distance: nil, targetPace: nil, exercises: exercises,
                isCompleted: false, completedActivityId: nil
            ),
            source: .custom,
            reason: "A strength session built around your chosen movements."
        )
    }

    func updating(duration: Int?, distance: Double?) -> TodayWorkoutDraft {
        TodayWorkoutDraft(
            workout: DailyWorkout(
                id: workout.id, date: workout.date, dayOfWeek: workout.dayOfWeek,
                workoutType: workout.workoutType, title: workout.title,
                description: workout.description, duration: duration,
                distance: workout.workoutType.isRunning ? distance : nil,
                targetPace: workout.displayTargetPace, exercises: workout.exercises,
                isCompleted: false, completedActivityId: nil,
                acceptedPrescription: workout.acceptedPrescription,
                acceptedCompletion: nil, commitment: nil
            ),
            source: source,
            reason: reason
        )
    }
}
