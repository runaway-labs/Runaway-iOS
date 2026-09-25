import Foundation

struct WorkoutCommitment: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case recommendation
        case alternative
        case custom
    }

    let committedAt: Date
    let source: Source
    let prescriptionFingerprint: String
    let originalWorkoutID: String
}

enum WorkoutPrescriptionFingerprint {
    private struct Prescription: Encodable {
        let id: String
        let date: Date
        let dayOfWeek: DayOfWeek
        let workoutType: WorkoutType
        let title: String
        let description: String
        let duration: Int?
        let distance: Double?
        let targetPace: String?
        let exercises: [Exercise]?
        let acceptedPrescription: AcceptedTrainingPrescription?
        let strengthPrescription: StrengthPrescriptionMetadata?
    }

    static func make(_ workout: DailyWorkout) throws -> String {
        try AcceptedPrescriptionPlanPolicy.fingerprint(
            Prescription(
                id: workout.id,
                date: workout.date,
                dayOfWeek: workout.dayOfWeek,
                workoutType: workout.workoutType,
                title: workout.title,
                description: workout.description,
                duration: workout.duration,
                distance: workout.distance,
                targetPace: workout.displayTargetPace,
                exercises: workout.exercises,
                acceptedPrescription: workout.acceptedPrescription,
                strengthPrescription: workout.strengthPrescription
            )
        )
    }
}
