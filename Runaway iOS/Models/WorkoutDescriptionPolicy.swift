import Foundation

enum WorkoutDescriptionPolicy {
    /// Only replace the total-distance prefix produced by our plan generator.
    /// Interval instructions, user notes and embedded distances stay untouched.
    static func reconciled(_ description: String, distanceLabel: String) -> String {
        let pattern = #"^\d+(?:[.,]\d+)? miles(?= (?:at conversational pace|at easy effort|with middle portion at tempo pace|very easy))"#
        guard let range = description.range(of: pattern, options: .regularExpression) else {
            return description
        }
        var result = description
        result.replaceSubrange(range, with: distanceLabel)
        return result
    }
}

extension DailyWorkout {
    var displayDescription: String {
        guard workoutType.isRunning, let distance, distance.isFinite, distance >= 0 else {
            return description
        }
        return WorkoutDescriptionPolicy.reconciled(
            description,
            distanceLabel: UnitFormatter.formatDistance(distance * 1609.344, decimals: 1, includeUnit: true)
        )
    }
}
