import Foundation

enum WorkoutCompletionStatus: String, Equatable, Sendable {
    case notCompleted
    case partial
    case complete
}

enum CommittedWorkoutCompletionPolicy {
    static func status(
        workout: DailyWorkout,
        evidence: [Activity],
        calendar: Calendar = .current
    ) -> WorkoutCompletionStatus {
        guard workout.commitment != nil else { return .notCompleted }
        if workout.isCompleted { return .complete }
        if let completion = workout.acceptedCompletion {
            return completion.isPartial ? .partial : .complete
        }

        var seen = Set<Int>()
        let matching = evidence.filter { activity in
            guard seen.insert(activity.id).inserted,
                  let timestamp = activity.activity_date ?? activity.start_date,
                  calendar.isDate(Date(timeIntervalSince1970: timestamp), inSameDayAs: workout.date) else {
                return false
            }
            return activity.isCompatible(with: workout.workoutType)
        }
        guard !matching.isEmpty else { return .notCompleted }

        let actualMeters = matching.compactMap(\.distance).reduce(0, +)
        let actualSeconds = matching.compactMap(\.elapsed_time).reduce(0, +)
        let distanceRatio = workout.distance.map { miles in
            miles > 0 ? actualMeters / (miles * 1609.344) : 0
        } ?? 0
        let durationRatio = workout.duration.map { minutes in
            minutes > 0 ? actualSeconds / (Double(minutes) * 60) : 0
        } ?? 0
        let doseRatio = max(distanceRatio, durationRatio)
        if doseRatio >= 0.9 { return .complete }
        return doseRatio > 0 ? .partial : .notCompleted
    }
}
