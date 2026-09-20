import Foundation

enum TrainingEffortScale: String, Codable {
    case sessionRPE, setRPE, repetitionsInReserve
}

struct TrainingEffortObservation: Codable, Equatable {
    let scale: TrainingEffortScale
    let value: Double

    var isValid: Bool {
        guard value.isFinite else { return false }
        switch scale {
        case .sessionRPE, .setRPE: return (1...10).contains(value)
        case .repetitionsInReserve: return value >= 0
        }
    }
}

enum TrainingObservationValue: Codable, Equatable {
    case run(distanceMeters: Double, durationSeconds: Double, effort: TrainingEffortObservation?)
    case strengthSet(exerciseID: String, equipmentID: String?, repetitions: Int,
                     externalLoadKilograms: Double?, assistanceKilograms: Double?,
                     convention: LoadConvention, effort: TrainingEffortObservation?)
    case bodyWeight(kilograms: Double)
    case height(centimeters: Double)

    var isValid: Bool {
        func positive(_ value: Double) -> Bool { value.isFinite && value > 0 }
        switch self {
        case .run(let distance, let duration, let effort):
            return positive(distance) && positive(duration) && (effort?.isValid ?? true)
        case .strengthSet(let exercise, let equipment, let reps, let load, let assistance, let convention, let effort):
            guard !exercise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  reps > 0, effort?.isValid ?? true,
                  load.map(positive) ?? true, assistance.map(positive) ?? true else { return false }
            if let equipment, equipment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            if load != nil && assistance != nil { return false }
            switch convention {
            case .bodyweight: return load == nil
            case .machine: return equipment != nil && load != nil && assistance == nil
            case .perHand, .total: return load != nil && assistance == nil
            }
        case .bodyWeight(let value), .height(let value): return positive(value)
        }
    }

    var measurementIdentity: String {
        switch self {
        case .run: return "run"
        case .strengthSet(let exercise, let equipment, _, _, _, let convention, _):
            return "strength:\(exercise):\(equipment ?? "none"):\(convention.rawValue)"
        case .bodyWeight: return "weight"
        case .height: return "height"
        }
    }
}

/// An observation is evidence, not a goal or a prescribed workout.
/// Set-level imports need a distinct sourceRecordID for each set.
struct TrainingObservation: Codable, Equatable, Identifiable {
    let id: UUID
    let athleteID: Int
    let measuredAt: Date
    let receivedAt: Date
    let source: TrainingEvidenceSource
    let sourceRecordID: String
    let sessionID: UUID?
    let supersedesID: UUID?
    let value: TrainingObservationValue

    var isValid: Bool {
        athleteID > 0 && measuredAt.timeIntervalSince1970.isFinite
            && receivedAt.timeIntervalSince1970.isFinite
            && !sourceRecordID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && supersedesID != id && value.isValid
    }
}
