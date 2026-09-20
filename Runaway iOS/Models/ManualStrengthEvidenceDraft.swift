import Foundation

/// Holds submission identity across retries without confusing performance time
/// with the time the athlete first submitted that performance.
struct ManualStrengthEvidenceDraft {
    let id = UUID()
    private(set) var receivedAt: Date?

    mutating func observation(athleteID: Int, measuredAt: Date,
                             value: TrainingObservationValue, now: Date = Date()) throws -> TrainingObservation {
        guard case .strengthSet = value, value.isValid, athleteID > 0,
              now.timeIntervalSince1970.isFinite,
              measuredAt.timeIntervalSince1970.isFinite, measuredAt <= now else {
            throw ProtectedTrainingRepository.RepositoryError.invalidRecord
        }
        let timestamp = receivedAt ?? now
        let record = TrainingObservation(id: id, athleteID: athleteID, measuredAt: measuredAt,
            receivedAt: timestamp, source: .userEntered, sourceRecordID: "manual-set:\(id.uuidString)",
            sessionID: nil, supersedesID: nil, value: value)
        receivedAt = timestamp
        return record
    }
}
