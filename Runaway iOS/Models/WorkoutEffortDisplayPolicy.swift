import Foundation

/// Display the accepted dose without adding physiological targets it never prescribed.
enum WorkoutEffortDisplayPolicy {
    struct Effort: Equatable {
        let title: String
        let detail: String
    }

    static func zoneTarget(for workout: DailyWorkout) -> TrainingZoneTarget? {
        guard workout.acceptedPrescription == nil else { return nil }
        return NativeTrainingGuidancePolicy.zoneTarget(for: workout.workoutType)
    }

    static func acceptedEffort(for workout: DailyWorkout) -> Effort? {
        guard let prescription = workout.acceptedPrescription else { return nil }
        if prescription.items.contains(where: { $0.kind == .running }) {
            return Effort(title: "Conversational effort",
                          detail: "Follow the accepted running and recovery blocks. This prescription does not specify a heart-rate zone or calibrated pace; slow down or walk as needed.")
        }
        return Effort(title: "Prescribed reps and load",
                      detail: "Follow the accepted sets, reps and load guidance. A heart-rate zone is not a target for this strength prescription.")
    }
}
