import Foundation

/// App-process serialized, local-only storage. Atomicity is per record, not across
/// an entire profile/history update. Locked-file errors propagate to the caller.
@MainActor
final class ProtectedTrainingRepository {
    private let root: URL
    private let activeAthleteID: @MainActor () -> Int?
    private let files: FileManager

    init(root: URL? = nil, files: FileManager = .default,
         activeAthleteID: @escaping @MainActor () -> Int?) {
        self.files = files
        self.root = root ?? files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProtectedTraining", isDirectory: true)
        self.activeAthleteID = activeAthleteID
    }

    func loadProfile(athleteID: Int) throws -> AthleteTrainingProfile? {
        try requireOwner(athleteID)
        let url = directory(athleteID).appendingPathComponent("profile.json")
        guard files.fileExists(atPath: url.path) else { return nil }
        let profile = try JSONDecoder().decode(AthleteTrainingProfile.self, from: Data(contentsOf: url))
        guard profile.athleteID == athleteID else { throw RepositoryError.ownershipMismatch }
        guard profile.validationIssues().isEmpty else { throw RepositoryError.invalidRecord }
        return profile
    }

    func saveProfile(_ profile: AthleteTrainingProfile, athleteID: Int) throws {
        try requireOwner(athleteID)
        guard profile.athleteID == athleteID else { throw RepositoryError.ownershipMismatch }
        guard profile.validationIssues().isEmpty else { throw RepositoryError.invalidRecord }
        try write(profile, to: directory(athleteID).appendingPathComponent("profile.json"))
    }

    func observations(athleteID: Int) throws -> [TrainingObservation] {
        try requireOwner(athleteID)
        let folder = directory(athleteID).appendingPathComponent("observations", isDirectory: true)
        guard files.fileExists(atPath: folder.path) else { return [] }
        let urls = try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return try urls.map { url in
            let observation = try JSONDecoder().decode(TrainingObservation.self, from: Data(contentsOf: url))
            guard observation.athleteID == athleteID else { throw RepositoryError.ownershipMismatch }
            guard observation.isValid else { throw RepositoryError.invalidRecord }
            return observation
        }.sorted {
            if $0.measuredAt != $1.measuredAt { return $0.measuredAt < $1.measuredAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func currentObservations(athleteID: Int) throws -> [TrainingObservation] {
        let history = try observations(athleteID: athleteID)
        let superseded = Set(history.compactMap(\.supersedesID))
        return history.filter { !superseded.contains($0.id) }
    }

    /// Retries are idempotent; changes to imported evidence require a correction.
    @discardableResult
    func append(_ observation: TrainingObservation, athleteID: Int) throws -> TrainingObservation {
        try requireOwner(athleteID)
        guard observation.athleteID == athleteID else { throw RepositoryError.ownershipMismatch }
        guard observation.isValid else { throw RepositoryError.invalidRecord }
        let history = try observations(athleteID: athleteID)
        if let existing = history.first(where: { $0.id == observation.id }) {
            guard existing == observation else { throw RepositoryError.conflictingObservation }
            return existing
        }
        if let previousID = observation.supersedesID {
            guard let previous = history.first(where: { $0.id == previousID }),
                  previous.value.measurementIdentity == observation.value.measurementIdentity,
                  !history.contains(where: { $0.supersedesID == previousID }) else {
                throw RepositoryError.invalidCorrection
            }
            // Earlier revisions of this same source record are legitimate ancestors,
            // not duplicate imports. Reject a collision with any other chain.
            var ancestors: Set<UUID> = [previousID]
            var cursor = previous
            while let parentID = cursor.supersedesID {
                guard ancestors.insert(parentID).inserted,
                      let parent = history.first(where: { $0.id == parentID }) else {
                    throw RepositoryError.invalidCorrection
                }
                cursor = parent
            }
            if history.contains(where: {
                $0.source == observation.source && $0.sourceRecordID == observation.sourceRecordID
                    && !ancestors.contains($0.id)
            }) { throw RepositoryError.conflictingObservation }
        } else {
            let sourceHistory = history.filter {
                $0.source == observation.source && $0.sourceRecordID == observation.sourceRecordID
            }
            if !sourceHistory.isEmpty {
                // A replay may match an older revision. Do not let history order
                // turn that retry into a conflict or restore superseded evidence.
                guard let existing = sourceHistory.first(where: {
                    $0.value == observation.value && $0.measuredAt == observation.measuredAt
                        && $0.sessionID == observation.sessionID
                }) else { throw RepositoryError.conflictingObservation }
                return existing
            }
        }
        let url = directory(athleteID).appendingPathComponent("observations", isDirectory: true)
            .appendingPathComponent(observation.id.uuidString + ".json")
        try write(observation, to: url)
        return observation
    }

    func sessionResults(athleteID: Int) throws -> [TrainingSessionResult] {
        try requireOwner(athleteID)
        let folder = directory(athleteID).appendingPathComponent("session-results", isDirectory: true)
        guard files.fileExists(atPath: folder.path) else { return [] }
        let urls = try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        let results = try urls.map { url in
            let result = try JSONDecoder().decode(TrainingSessionResult.self, from: Data(contentsOf: url))
            guard result.reference.athleteID == athleteID else { throw RepositoryError.ownershipMismatch }
            guard result.isValid, url.deletingPathExtension().lastPathComponent == result.id.uuidString else {
                throw RepositoryError.invalidRecord
            }
            return result
        }
        guard Set(results.map(\.id)).count == results.count,
              Set(results.map { $0.reference.id }).count == results.count else { throw RepositoryError.invalidRecord }
        return results.sorted {
            if $0.completedAt != $1.completedAt { return $0.completedAt > $1.completedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    /// One atomic envelope contains the reference and all actual entries.
    /// It deliberately does not also append observations, which could duplicate imports.
    @discardableResult
    func appendSessionResult(_ result: TrainingSessionResult, athleteID: Int) throws -> TrainingSessionResult {
        try requireOwner(athleteID)
        guard result.reference.athleteID == athleteID else { throw RepositoryError.ownershipMismatch }
        guard result.isValid else { throw RepositoryError.invalidRecord }
        let history = try sessionResults(athleteID: athleteID)
        if let existing = history.first(where: { $0.id == result.id }) {
            guard existing == result else { throw RepositoryError.conflictingSessionResult }
            return existing
        }
        guard !history.contains(where: { $0.reference.id == result.reference.id }) else {
            throw RepositoryError.duplicateSessionReference
        }
        try write(result, to: directory(athleteID).appendingPathComponent("session-results", isDirectory: true)
            .appendingPathComponent(result.id.uuidString + ".json"))
        return result
    }

    /// Replaces one local result only when the caller still holds the exact stored value.
    /// The prescription reference and stable identity cannot be changed by an edit.
    @discardableResult
    func replaceSessionResult(
        _ result: TrainingSessionResult,
        replacing original: TrainingSessionResult,
        athleteID: Int
    ) throws -> TrainingSessionResult {
        try requireOwner(athleteID)
        guard original.reference.athleteID == athleteID,
              result.reference.athleteID == athleteID,
              result.id == original.id,
              result.reference == original.reference,
              result.isValid else { throw RepositoryError.invalidRecord }
        let history = try sessionResults(athleteID: athleteID)
        guard history.first(where: { $0.id == original.id }) == original else {
            throw RepositoryError.conflictingSessionResult
        }
        try write(result, to: directory(athleteID).appendingPathComponent("session-results", isDirectory: true)
            .appendingPathComponent(result.id.uuidString + ".json"))
        return result
    }

    /// Links imported run evidence to its richer completed-session result by
    /// appending a correction. The original import remains available for audit.
    @discardableResult
    func linkObservation(
        _ observationID: UUID,
        toSessionResult resultID: UUID,
        athleteID: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> TrainingObservation {
        try requireOwner(athleteID)
        guard now.timeIntervalSince1970.isFinite,
              let result = try sessionResults(athleteID: athleteID).first(where: { $0.id == resultID }),
              result.reference.items.contains(where: { $0.kind == .running }),
              let observation = try currentObservations(athleteID: athleteID).first(where: { $0.id == observationID }),
              observation.source == .importedActivity,
              case .run = observation.value,
              calendar.isDate(observation.measuredAt, inSameDayAs: result.completedAt),
              now >= observation.receivedAt else { throw RepositoryError.invalidCorrection }
        if observation.sessionID == resultID { return observation }
        guard observation.sessionID == nil else { throw RepositoryError.invalidCorrection }
        let linked = TrainingObservation(
            id: UUID(), athleteID: athleteID, measuredAt: observation.measuredAt,
            receivedAt: now, source: observation.source,
            sourceRecordID: observation.sourceRecordID, sessionID: resultID,
            supersedesID: observation.id, value: observation.value
        )
        return try append(linked, athleteID: athleteID)
    }

    func coachEventRecords(athleteID: Int) throws -> [ProtectedCoachEventRecord] {
        try requireOwner(athleteID)
        let folder = directory(athleteID).appendingPathComponent("coach-events", isDirectory: true)
        guard files.fileExists(atPath: folder.path) else { return [] }
        return try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { url in
                let record = try JSONDecoder().decode(
                    ProtectedCoachEventRecord.self,
                    from: Data(contentsOf: url)
                )
                guard record.event.athleteID == athleteID,
                      record.event.isValid,
                      url.deletingPathExtension().lastPathComponent == record.event.id.uuidString else {
                    throw RepositoryError.invalidRecord
                }
                return record
            }
            .sorted {
                if $0.event.occurredAt != $1.event.occurredAt {
                    return $0.event.occurredAt < $1.event.occurredAt
                }
                return $0.event.id.uuidString < $1.event.id.uuidString
            }
    }

    func saveCoachEventRecord(_ record: ProtectedCoachEventRecord, athleteID: Int) throws {
        try requireOwner(athleteID)
        guard record.event.athleteID == athleteID, record.event.isValid else {
            throw RepositoryError.ownershipMismatch
        }
        try write(
            record,
            to: directory(athleteID).appendingPathComponent("coach-events", isDirectory: true)
                .appendingPathComponent(record.event.id.uuidString + ".json")
        )
    }

    func coachRecommendationEntries(athleteID: Int) throws -> [CoachRecommendationJournalEntry] {
        try requireOwner(athleteID)
        let folder = directory(athleteID).appendingPathComponent("coach-recommendations", isDirectory: true)
        guard files.fileExists(atPath: folder.path) else { return [] }
        return try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { url in
                let entry = try JSONDecoder().decode(
                    CoachRecommendationJournalEntry.self,
                    from: Data(contentsOf: url)
                )
                guard entry.athleteID == athleteID, entry.isValid,
                      url.deletingPathExtension().lastPathComponent == entry.id.uuidString else {
                    throw RepositoryError.invalidRecord
                }
                return entry
            }
            .sorted { $0.deliveredAt < $1.deliveredAt }
    }

    func saveCoachRecommendationEntry(_ entry: CoachRecommendationJournalEntry, athleteID: Int) throws {
        try requireOwner(athleteID)
        guard entry.athleteID == athleteID, entry.isValid else {
            throw RepositoryError.ownershipMismatch
        }
        try write(
            entry,
            to: directory(athleteID).appendingPathComponent("coach-recommendations", isDirectory: true)
                .appendingPathComponent(entry.id.uuidString + ".json")
        )
    }

    func coachDecisions(athleteID: Int) throws -> [CoachDecision] {
        try requireOwner(athleteID)
        let folder = directory(athleteID).appendingPathComponent("coach-decisions", isDirectory: true)
        guard files.fileExists(atPath: folder.path) else { return [] }
        return try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { url in
                let decision = try JSONDecoder().decode(CoachDecision.self, from: Data(contentsOf: url))
                guard decision.athleteID == athleteID,
                      decision.isValid,
                      url.deletingPathExtension().lastPathComponent == decision.id.uuidString else {
                    throw RepositoryError.invalidRecord
                }
                return decision
            }
            .sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    func saveCoachDecision(_ decision: CoachDecision, athleteID: Int) throws {
        try requireOwner(athleteID)
        guard decision.athleteID == athleteID, decision.isValid else {
            throw RepositoryError.ownershipMismatch
        }
        try write(
            decision,
            to: directory(athleteID).appendingPathComponent("coach-decisions", isDirectory: true)
                .appendingPathComponent(decision.id.uuidString + ".json")
        )
    }

    private func directory(_ athleteID: Int) -> URL {
        root.appendingPathComponent(String(athleteID), isDirectory: true)
    }

    private func requireOwner(_ athleteID: Int) throws {
        guard athleteID > 0, activeAthleteID() == athleteID else { throw RepositoryError.ownershipMismatch }
    }

    private func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(value)
        #if os(iOS)
        let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
        #else
        let attributes: [FileAttributeKey: Any] = [:]
        #endif
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: attributes)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    enum RepositoryError: LocalizedError {
        case ownershipMismatch, invalidRecord, conflictingObservation, invalidCorrection
        case conflictingSessionResult, duplicateSessionReference
        case conflictingCoachEvent, conflictingCoachDecision, staleCoachDecision, staleUndo
        var errorDescription: String? {
            switch self {
            case .ownershipMismatch: return "Sign in to the account that owns this training data."
            case .invalidRecord: return "This training record is invalid. Existing data has been preserved."
            case .conflictingObservation: return "This observation already exists with different information. Save an explicit correction."
            case .invalidCorrection: return "This correction no longer matches the current observation. Reload before trying again."
            case .conflictingSessionResult: return "This session is already saved with different values. Its original record has been preserved."
            case .duplicateSessionReference: return "A completed-session record already exists for this goal preview. Open completed session records to review it; it has not been counted twice."
            case .conflictingCoachEvent: return "This coach event already exists with different evidence. The original event was preserved."
            case .conflictingCoachDecision: return "This coach decision already exists with different details. The original decision was preserved."
            case .staleCoachDecision: return "This coach decision changed before it could be saved. Reload the current decision and try again."
            case .staleUndo: return "The training plan changed after this decision. Undo was stopped to preserve the newer plan."
            }
        }
    }
}
