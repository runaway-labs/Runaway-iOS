import Foundation

/// Deterministic starting sessions, not inferred lifting history or model output.
enum StrengthSessionPrescription {
    static func exercises(for type: WorkoutType, profile: TrainingProfile) -> [Exercise]? {
        guard type.isStrength else { return nil }
        let sets = profile.strengthExperience == .beginner ? 2 : 3
        let equipment = profile.strengthEquipment
        let loaded = equipment == .dumbbells || equipment == .fullGym
        let upper: [(String, String)] = loaded
            ? [("Dumbbell floor press", "8-12"), ("One-arm dumbbell row", "8-12 each side"), ("Dumbbell lateral raise", "10-15")]
            : [("Wall push-up", "8-12"), ("Prone W raise", "8-12"), ("Bird dog", "6-8 each side")]
        let lower: [(String, String)] = loaded
            ? [("Goblet squat", "8-10"), ("Dumbbell Romanian deadlift", "8-10"), ("Standing calf raise", "12-15")]
            : [("Bodyweight squat", "8-12"), ("Glute bridge", "10-15"), ("Standing calf raise", "12-15")]
        let movements: [(String, String)]
        switch type {
        case .upperBody: movements = upper
        case .lowerBody: movements = lower
        default: movements = Array(lower.prefix(2)) + Array(upper.prefix(2))
        }
        var result = [Exercise(
            id: "strength-warmup", name: "Warm up", reps: "5 min",
            notes: "Easy movement, then rehearse each exercise without load. Use a comfortable, pain-free range."
        )]
        result += movements.enumerated().map { index, movement in
            Exercise(
                id: "strength-\(type.rawValue)-\(equipment.rawValue)-\(index)",
                name: movement.0, sets: sets, reps: movement.1,
                notes: "Rest 60-90 seconds between sets. Finish with 2-3 good reps left; no prescribed weight until your working loads are known. Stop if painful."
            )
        }
        result.append(Exercise(id: "strength-cooldown", name: "Cool down", reps: "3 min", notes: "Easy walking and relaxed breathing."))
        return result
    }
}
