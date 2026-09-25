import Foundation

struct StrengthWorkoutGenerationRequest: Sendable {
    let selectedZones: Set<StrengthZone>
    let availableZones: Set<StrengthZone>
    let durationMinutes: Int
    let equipment: StrengthEquipment
    let experience: TrainingExperience
    let outcomes: [AthleteOutcome]
    let history: StrengthZoneHistorySnapshot
    let upcomingWorkouts: [DailyWorkout]
}

struct StrengthPrescriptionMetadata: Codable, Equatable, Sendable {
    let policyVersion: String
    let focusZones: Set<StrengthZone>
    let supportingZones: Set<StrengthZone>
    let exerciseIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case policyVersion
        case focusZones
        case supportingZones
        case exerciseIDs
    }

    init(
        policyVersion: String,
        focusZones: Set<StrengthZone>,
        supportingZones: Set<StrengthZone>,
        exerciseIDs: [String]
    ) {
        self.policyVersion = policyVersion
        self.focusZones = focusZones
        self.supportingZones = supportingZones
        self.exerciseIDs = exerciseIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        policyVersion = try container.decode(String.self, forKey: .policyVersion)
        focusZones = Set(try container.decode([StrengthZone].self, forKey: .focusZones))
        supportingZones = Set(try container.decode([StrengthZone].self, forKey: .supportingZones))
        exerciseIDs = try container.decode([String].self, forKey: .exerciseIDs)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(policyVersion, forKey: .policyVersion)
        try container.encode(Self.ordered(focusZones), forKey: .focusZones)
        try container.encode(Self.ordered(supportingZones), forKey: .supportingZones)
        try container.encode(exerciseIDs, forKey: .exerciseIDs)
    }

    private static func ordered(_ zones: Set<StrengthZone>) -> [StrengthZone] {
        StrengthZone.allCases.filter(zones.contains)
    }
}

struct GeneratedStrengthExercise: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let primaryZone: StrengthZone
    let secondaryZones: Set<StrengthZone>
    let sets: Int
    let repetitions: String
    let loadGuidance: String
    let targetRIR: Int
    let restSeconds: Int
    let isSupporting: Bool

    var planExercise: Exercise {
        Exercise(
            id: id,
            name: name,
            sets: sets,
            reps: repetitions,
            weight: loadGuidance,
            notes: "Stop with \(targetRIR) reps in reserve. Rest \(restSeconds) sec."
        )
    }
}

struct GeneratedStrengthWorkout: Equatable, Sendable {
    let exercises: [GeneratedStrengthExercise]
    let estimatedDurationMinutes: Int
    let metadata: StrengthPrescriptionMetadata
    let explanation: String

    var planExercises: [Exercise] { exercises.map(\.planExercise) }
}

enum StrengthWorkoutGenerationError: Error, Equatable {
    case noFocusZones
    case unavailableZone(StrengthZone)
    case noCompatibleExercise(StrengthZone)
    case insufficientDuration(minimumMinutes: Int, requestedMinutes: Int)
}
