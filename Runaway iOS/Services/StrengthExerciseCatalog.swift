import Foundation

enum StrengthExerciseCatalog {
    private static let everywhere: Set<StrengthEquipment> = [.bodyweight, .dumbbells, .fullGym]
    private static let weights: Set<StrengthEquipment> = [.dumbbells, .fullGym]
    private static let gym: Set<StrengthEquipment> = [.fullGym]

    static let all: [StrengthExerciseDefinition] = [
        exercise("push_up", "Push-Up", .chest, [.arms], .horizontalPush, everywhere, family: "horizontal_press"),
        exercise("dumbbell_floor_press", "Dumbbell Floor Press", .chest, [.arms], .horizontalPush, weights, family: "horizontal_press"),
        exercise("bench_press", "Bench Press", .chest, [.arms], .horizontalPush, gym, family: "horizontal_press"),

        exercise("prone_lat_pull", "Prone Lat Pull", .back, [], .verticalPull, everywhere, family: "vertical_pull"),
        exercise("one_arm_dumbbell_row", "One-Arm Dumbbell Row", .back, [.arms], .horizontalPull, weights, unilateral: true, family: "row"),
        exercise("seated_cable_row", "Seated Cable Row", .back, [.arms], .horizontalPull, gym, family: "row"),
        exercise("pull_up", "Pull-Up", .back, [.arms], .verticalPull, gym, family: "vertical_pull"),
        exercise("lat_pulldown", "Lat Pulldown", .back, [.arms], .verticalPull, gym, family: "vertical_pull"),

        exercise("wall_handstand_hold", "Wall Handstand Hold", .shoulders, [], .verticalPush, everywhere, family: "overhead_press"),
        exercise("pike_push_up", "Pike Push-Up", .shoulders, [.arms], .verticalPush, everywhere, family: "overhead_press"),
        exercise("dumbbell_overhead_press", "Dumbbell Overhead Press", .shoulders, [.arms], .verticalPush, weights, family: "overhead_press"),
        exercise("dumbbell_lateral_raise", "Dumbbell Lateral Raise", .shoulders, [], .isolation, weights, family: "lateral_raise"),
        exercise("cable_lateral_raise", "Cable Lateral Raise", .shoulders, [], .isolation, gym, unilateral: true, family: "lateral_raise"),

        exercise("bench_triceps_dip", "Bench Triceps Dip", .arms, [], .isolation, everywhere, family: "triceps_extension"),
        exercise("dumbbell_curl", "Dumbbell Curl", .arms, [], .isolation, weights, family: "curl"),
        exercise("dumbbell_overhead_triceps_extension", "Dumbbell Triceps Extension", .arms, [], .isolation, weights, family: "triceps_extension"),
        exercise("cable_curl", "Cable Curl", .arms, [], .isolation, gym, family: "curl"),
        exercise("cable_triceps_pressdown", "Cable Triceps Pressdown", .arms, [], .isolation, gym, family: "triceps_extension"),

        exercise("bodyweight_squat", "Bodyweight Squat", .legs, [], .squat, everywhere, family: "squat"),
        exercise("bodyweight_split_squat", "Split Squat", .legs, [], .squat, everywhere, unilateral: true, family: "split_squat"),
        exercise("single_leg_calf_raise", "Single-Leg Calf Raise", .legs, [], .isolation, everywhere, unilateral: true, family: "calf_raise"),
        exercise("glute_bridge", "Glute Bridge", .legs, [], .hinge, everywhere, family: "hinge"),
        exercise("goblet_squat", "Goblet Squat", .legs, [.core], .squat, weights, family: "squat"),
        exercise("dumbbell_reverse_lunge", "Dumbbell Reverse Lunge", .legs, [.core], .squat, weights, unilateral: true, family: "split_squat"),
        exercise("dumbbell_romanian_deadlift", "Dumbbell Romanian Deadlift", .legs, [], .hinge, weights, family: "hinge"),
        exercise("barbell_back_squat", "Barbell Back Squat", .legs, [.core], .squat, gym, family: "squat"),
        exercise("barbell_romanian_deadlift", "Barbell Romanian Deadlift", .legs, [], .hinge, gym, family: "hinge"),

        exercise("dead_bug", "Dead Bug", .core, [], .antiExtension, everywhere, family: "anti_extension"),
        exercise("front_plank", "Front Plank", .core, [], .antiExtension, everywhere, family: "anti_extension"),
        exercise("side_plank", "Side Plank", .core, [], .lateralStability, everywhere, unilateral: true, family: "lateral_stability"),
        exercise("lying_knee_raise", "Lying Knee Raise", .core, [], .trunkFlexion, everywhere, family: "knee_raise"),
        exercise("dumbbell_suitcase_carry", "Suitcase Carry", .core, [.arms], .loadedCarry, weights, unilateral: true, family: "loaded_carry"),
        exercise("hanging_knee_raise", "Hanging Knee Raise", .core, [], .trunkFlexion, gym, family: "knee_raise"),
        exercise("pallof_press", "Pallof Press", .core, [], .antiRotation, gym, family: "anti_rotation"),
        exercise("back_extension", "Back Extension", .core, [.back], .trunkExtension, gym, family: "trunk_extension")
    ]

    static func definition(id: String) -> StrengthExerciseDefinition? {
        all.first { $0.id == id }
    }

    static func exercises(
        equipment: StrengthEquipment,
        availableZones: Set<StrengthZone>
    ) -> [StrengthExerciseDefinition] {
        let resolvedEquipment: StrengthEquipment = equipment == .unspecified ? .bodyweight : equipment
        return all.filter {
            $0.supportedEquipment.contains(resolvedEquipment)
                && availableZones.contains($0.primaryZone)
                && $0.secondaryZones.isSubset(of: availableZones)
        }
    }

    static func validationIssues() -> [String] {
        var issues: [String] = []
        let ids = all.map(\.id)
        if Set(ids).count != ids.count { issues.append("Exercise IDs must be unique.") }
        for value in all {
            if value.id.isEmpty { issues.append("Exercise IDs cannot be empty.") }
            if value.displayName.isEmpty { issues.append("Exercise names cannot be empty.") }
            if value.progressionFamilyID.isEmpty { issues.append("Progression family IDs cannot be empty.") }
            if value.secondaryZones.contains(value.primaryZone) {
                issues.append("Primary zones cannot be duplicated as secondary zones.")
            }
            if value.supportedEquipment.isEmpty { issues.append("Exercises need supported equipment.") }
        }
        if exercises(equipment: .unspecified, availableZones: Set(StrengthZone.allCases)).isEmpty {
            issues.append("Unspecified equipment needs bodyweight-safe exercises.")
        }
        return issues
    }

    private static func exercise(
        _ id: String,
        _ displayName: String,
        _ primaryZone: StrengthZone,
        _ secondaryZones: Set<StrengthZone>,
        _ movementPattern: StrengthMovementPattern,
        _ supportedEquipment: Set<StrengthEquipment>,
        unilateral: Bool = false,
        family progressionFamilyID: String
    ) -> StrengthExerciseDefinition {
        StrengthExerciseDefinition(
            id: id,
            displayName: displayName,
            primaryZone: primaryZone,
            secondaryZones: secondaryZones,
            movementPattern: movementPattern,
            supportedEquipment: supportedEquipment,
            unilateral: unilateral,
            progressionFamilyID: progressionFamilyID
        )
    }
}
