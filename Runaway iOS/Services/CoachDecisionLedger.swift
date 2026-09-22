import CryptoKit
import Foundation

struct ProtectedCoachEventRecord: Codable, Equatable, Sendable {
    let event: CoachEvent
    var processedAt: Date?
}

struct CoachRecommendationJournalEntry: Codable, Identifiable {
    let id: UUID
    let athleteID: Int
    let workout: DailyWorkout
    let whyToday: String
    let recommendationOnly: Bool
    let deliveredAt: Date
    var openedAt: Date?

    var isValid: Bool {
        athleteID > 0 && !whyToday.isEmpty && deliveredAt.timeIntervalSince1970.isFinite &&
            (openedAt?.timeIntervalSince1970.isFinite ?? true)
    }
}

struct CoachUndoResult: Sendable {
    let restoredPlan: WeeklyTrainingPlan
    let reversal: CoachDecision
}

@MainActor
final class CoachDecisionLedger {
    private let repository: ProtectedTrainingRepository
    private let athleteID: Int

    init(repository: ProtectedTrainingRepository, athleteID: Int) {
        self.repository = repository
        self.athleteID = athleteID
    }

    @discardableResult
    func append(_ event: CoachEvent) throws -> CoachEvent {
        guard event.athleteID == athleteID else {
            throw ProtectedTrainingRepository.RepositoryError.ownershipMismatch
        }
        guard event.isValid else {
            throw ProtectedTrainingRepository.RepositoryError.invalidRecord
        }
        let records = try repository.coachEventRecords(athleteID: athleteID)
        if let existing = records.first(where: {
            $0.event.id == event.id || $0.event.deduplicationKey == event.deduplicationKey
        }) {
            guard existing.event == event else {
                throw ProtectedTrainingRepository.RepositoryError.conflictingCoachEvent
            }
            return existing.event
        }
        try repository.saveCoachEventRecord(
            ProtectedCoachEventRecord(event: event, processedAt: nil),
            athleteID: athleteID
        )
        return event
    }

    func events() throws -> [CoachEvent] {
        try repository.coachEventRecords(athleteID: athleteID).map(\.event)
    }

    func recommendations() throws -> [CoachRecommendationJournalEntry] {
        try repository.coachRecommendationEntries(athleteID: athleteID)
    }

    func saveRecommendation(_ entry: CoachRecommendationJournalEntry) throws {
        guard entry.athleteID == athleteID else {
            throw ProtectedTrainingRepository.RepositoryError.ownershipMismatch
        }
        try repository.saveCoachRecommendationEntry(entry, athleteID: athleteID)
    }

    func markRecommendationOpened(_ id: UUID, at date: Date = Date()) throws {
        guard var entry = try recommendations().first(where: { $0.id == id }) else { return }
        guard entry.openedAt == nil else { return }
        entry.openedAt = date
        try saveRecommendation(entry)
    }

    func pendingEvents() throws -> [CoachEvent] {
        try repository.coachEventRecords(athleteID: athleteID)
            .filter { $0.processedAt == nil }
            .map(\.event)
    }

    func markProcessed(_ eventIDs: [UUID], at date: Date = Date()) throws {
        guard date.timeIntervalSince1970.isFinite else {
            throw ProtectedTrainingRepository.RepositoryError.invalidRecord
        }
        let requested = Set(eventIDs)
        let records = try repository.coachEventRecords(athleteID: athleteID)
        guard requested.isSubset(of: Set(records.map { $0.event.id })) else {
            throw ProtectedTrainingRepository.RepositoryError.invalidRecord
        }
        for var record in records where requested.contains(record.event.id) && record.processedAt == nil {
            record.processedAt = date
            try repository.saveCoachEventRecord(record, athleteID: athleteID)
        }
    }

    @discardableResult
    func appendDecision(_ decision: CoachDecision) throws -> CoachDecision {
        guard decision.athleteID == athleteID else {
            throw ProtectedTrainingRepository.RepositoryError.ownershipMismatch
        }
        guard decision.isValid else {
            throw ProtectedTrainingRepository.RepositoryError.invalidRecord
        }
        if let existing = try repository.coachDecisions(athleteID: athleteID)
            .first(where: { $0.id == decision.id }) {
            guard existing == decision else {
                throw ProtectedTrainingRepository.RepositoryError.conflictingCoachDecision
            }
            return existing
        }
        try repository.saveCoachDecision(decision, athleteID: athleteID)
        return decision
    }

    func decisions() throws -> [CoachDecision] {
        try repository.coachDecisions(athleteID: athleteID)
    }

    func decision(forEvent eventID: UUID) throws -> CoachDecision? {
        try decisions().last { $0.eventIDs.contains(eventID) }
    }

    @discardableResult
    func replaceDecision(_ updated: CoachDecision, expected original: CoachDecision) throws -> CoachDecision {
        guard updated.id == original.id,
              updated.athleteID == athleteID,
              original.athleteID == athleteID,
              original.state.canTransition(to: updated.state),
              updated.eventIDs == original.eventIDs,
              updated.beforeRevision == original.beforeRevision,
              updated.afterRevision == original.afterRevision,
              updated.changes == original.changes,
              updated.reasonCodes == original.reasonCodes,
              updated.classification == original.classification,
              updated.confidence == original.confidence,
              updated.missingData == original.missingData,
              updated.policyVersion == original.policyVersion,
              updated.createdAt == original.createdAt,
              updated.previousPlanData == original.previousPlanData,
              updated.proposedPlanData == original.proposedPlanData,
              (updated.state == .applied
                ? updated.appliedPlanFingerprint?.isEmpty == false
                : updated.appliedPlanFingerprint == original.appliedPlanFingerprint),
              updated.isValid else {
            throw ProtectedTrainingRepository.RepositoryError.invalidRecord
        }
        let stored = try repository.coachDecisions(athleteID: athleteID)
            .first(where: { $0.id == original.id })
        guard stored == original else {
            throw ProtectedTrainingRepository.RepositoryError.staleCoachDecision
        }
        try repository.saveCoachDecision(updated, athleteID: athleteID)
        return updated
    }

    func undo(decisionID: UUID, currentPlan: WeeklyTrainingPlan) throws -> CoachUndoResult {
        let history = try decisions()
        let currentFingerprint = try Self.fingerprint(of: currentPlan)
        guard let original = history.first(where: { $0.id == decisionID }),
              original.state == .applied,
              currentPlan.athleteId == athleteID,
              let expectedFingerprint = original.appliedPlanFingerprint,
              expectedFingerprint == currentFingerprint,
              let previousPlanData = original.previousPlanData else {
            throw ProtectedTrainingRepository.RepositoryError.staleUndo
        }
        guard !history.contains(where: {
            $0.id != original.id && $0.state == .undone && $0.eventIDs == original.eventIDs
        }) else {
            throw ProtectedTrainingRepository.RepositoryError.staleUndo
        }
        let restoredPlan = try JSONDecoder().decode(WeeklyTrainingPlan.self, from: previousPlanData)
        guard restoredPlan.athleteId == athleteID else {
            throw ProtectedTrainingRepository.RepositoryError.ownershipMismatch
        }
        let now = Date()
        let reversedChanges = original.changes.reversed().map { change in
            CoachChange(
                kind: .restored,
                workoutID: change.workoutID,
                before: change.after,
                after: change.before ?? change.after,
                weeklyLoadDelta: -change.weeklyLoadDelta,
                isKeyWorkout: change.isKeyWorkout
            )
        }
        let reversal = CoachDecision(
            athleteID: athleteID,
            eventIDs: original.eventIDs,
            beforeRevision: original.afterRevision,
            afterRevision: original.beforeRevision,
            changes: reversedChanges,
            reasonCodes: [.athleteRequested],
            classification: .automatic,
            state: .undone,
            confidence: original.confidence,
            missingData: original.missingData,
            policyVersion: original.policyVersion,
            createdAt: now,
            appliedAt: now,
            previousPlanData: try Self.encoder.encode(currentPlan),
            proposedPlanData: previousPlanData,
            appliedPlanFingerprint: try Self.fingerprint(of: restoredPlan)
        )
        try appendDecision(reversal)
        return CoachUndoResult(restoredPlan: restoredPlan, reversal: reversal)
    }

    nonisolated static func fingerprint(of plan: WeeklyTrainingPlan) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let digest = SHA256.hash(data: try encoder.encode(plan))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()
}
