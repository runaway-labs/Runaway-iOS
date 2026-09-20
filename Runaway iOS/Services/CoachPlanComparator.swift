import Foundation

enum CoachPlanComparator {
    struct Comparison {
        let changes: [CoachChange]
        let weeklyLoadDelta: Double
        let replacesKeyWorkout: Bool
    }

    static func compare(before: WeeklyTrainingPlan, after: WeeklyTrainingPlan) throws -> Comparison {
        guard before.athleteId == after.athleteId else {
            throw ProtectedTrainingRepository.RepositoryError.ownershipMismatch
        }
        let beforeByID = Dictionary(uniqueKeysWithValues: before.workouts.map { ($0.id, $0) })
        let afterByID = Dictionary(uniqueKeysWithValues: after.workouts.map { ($0.id, $0) })
        let identifiers = Set(beforeByID.keys).union(afterByID.keys).sorted()
        var changes: [CoachChange] = []
        for id in identifiers {
            let old = beforeByID[id]
            let new = afterByID[id]
            guard try old.map(encoded) != new.map(encoded) else { continue }
            let oldLoad = old.map(load) ?? 0
            let newLoad = new.map(load) ?? 0
            let kind: CoachChange.Kind
            if let old, let new, old.date != new.date {
                kind = .moved
            } else if newLoad < oldLoad {
                kind = .reduced
            } else {
                kind = .replaced
            }
            changes.append(CoachChange(
                kind: kind,
                workoutID: id,
                before: old.map(summary),
                after: new.map(summary) ?? "Removed from the active week",
                weeklyLoadDelta: newLoad - oldLoad,
                isKeyWorkout: old?.workoutType.loadClass == .high || new?.workoutType.loadClass == .high
            ))
        }
        let delta = changes.reduce(0) { $0 + $1.weeklyLoadDelta }
        return Comparison(
            changes: changes,
            weeklyLoadDelta: delta,
            replacesKeyWorkout: changes.contains { $0.kind == .replaced && $0.isKeyWorkout }
        )
    }

    private static func load(_ workout: DailyWorkout) -> Double {
        let minutes = Double(workout.duration ?? 0)
        let intensity: Double = switch workout.workoutType.loadClass {
        case .recovery: 0.35
        case .low: 0.6
        case .moderate: 1
        case .high: 1.4
        }
        return minutes * intensity + (workout.distance ?? 0) * 4
    }

    private static func summary(_ workout: DailyWorkout) -> String {
        let duration = workout.duration.map { ", \($0) minutes" } ?? ""
        let distance = workout.distance.map { String(format: ", %.1f miles", $0) } ?? ""
        return workout.title + duration + distance
    }

    private static func encoded(_ workout: DailyWorkout) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(workout)
    }
}
