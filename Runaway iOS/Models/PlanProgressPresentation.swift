import Foundation

struct PlanProgressPresentation {
    let plan: WeeklyTrainingPlan
    var scheduledSessions: Int { plan.workouts.filter { $0.workoutType != .rest }.count }
    var completedSessions: Int { plan.workouts.filter { $0.workoutType != .rest && $0.isCompleted }.count }
    var completionLabel: String {
        scheduledSessions == 0 ? "Recovery week" : "\(completedSessions) of \(scheduledSessions) sessions completed"
    }

    static func changes(from before: WeeklyTrainingPlan, to after: WeeklyTrainingPlan) -> [String] {
        after.workouts.compactMap { workout in
            guard let original = before.workouts.first(where: { $0.id == workout.id || Calendar.current.isDate($0.date, inSameDayAs: workout.date) }),
                  !original.isCompleted,
                  original.workoutType != workout.workoutType || original.distance != workout.distance || original.duration != workout.duration else { return nil }
            func detail(_ value: DailyWorkout) -> String {
                let amount = value.distance.map { UnitFormatter.formatMiles($0) }
                    ?? value.duration.map { "\($0) min" }
                return [value.title, amount].compactMap { $0 }.joined(separator: " ")
            }
            return "\(workout.dayOfWeek.shortName): \(detail(original)) → \(detail(workout))"
        }
    }
}
