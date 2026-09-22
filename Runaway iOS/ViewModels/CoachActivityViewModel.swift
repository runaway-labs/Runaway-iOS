import Foundation
import Observation

enum CoachDecisionAction: Equatable {
    case accept, keepOriginal, undo
}

@MainActor
@Observable
final class CoachActivityViewModel {
    private let ledger: CoachDecisionLedger
    private let currentPlan: () -> WeeklyTrainingPlan?
    private let activate: (WeeklyTrainingPlan, String) throws -> Void

    private(set) var pending: [CoachDecision] = []
    private(set) var history: [CoachDecision] = []
    private(set) var recommendations: [CoachRecommendationJournalEntry] = []
    private(set) var errorMessage: String?

    init(ledger: CoachDecisionLedger, currentPlan: @escaping () -> WeeklyTrainingPlan?,
         activate: @escaping (WeeklyTrainingPlan, String) throws -> Void) {
        self.ledger = ledger
        self.currentPlan = currentPlan
        self.activate = activate
    }

    func load(athleteID: Int) throws {
        let owned = try ledger.decisions().filter { $0.athleteID == athleteID }
        pending = owned.filter { $0.state == .proposed }.sorted { $0.createdAt > $1.createdAt }
        history = owned.filter { $0.state != .proposed }.sorted { $0.createdAt > $1.createdAt }
        recommendations = try ledger.recommendations()
            .filter { $0.athleteID == athleteID }
            .sorted { $0.deliveredAt > $1.deliveredAt }
    }

    func openRecommendation(_ id: UUID, athleteID: Int) throws {
        try ledger.markRecommendationOpened(id)
        try load(athleteID: athleteID)
    }

    func availableActions(for decision: CoachDecision) -> [CoachDecisionAction] {
        switch decision.state {
        case .proposed: [.accept, .keepOriginal]
        case .applied: [.undo]
        case .rejected, .superseded, .undone, .blocked: []
        }
    }

    func accept(_ decisionID: UUID) throws {
        do {
            guard let original = try ledger.decisions().first(where: { $0.id == decisionID }),
                  original.state == .proposed,
                  let data = original.proposedPlanData,
                  let active = currentPlan(),
                  try CoachDecisionLedger.fingerprint(of: active) == original.beforeRevision else {
                throw ProtectedTrainingRepository.RepositoryError.staleCoachDecision
            }
            let proposed = try JSONDecoder().decode(WeeklyTrainingPlan.self, from: data)
            guard proposed.athleteId == original.athleteID else {
                throw ProtectedTrainingRepository.RepositoryError.ownershipMismatch
            }
            let applied = transition(
                original, to: .applied, appliedAt: Date(),
                fingerprint: try CoachDecisionLedger.fingerprint(of: proposed)
            )
            try ledger.replaceDecision(applied, expected: original)
            try activate(proposed, original.beforeRevision)
            try load(athleteID: original.athleteID)
            errorMessage = nil
        } catch {
            errorMessage = "Your plan changed since this recommendation. Review the current week before applying it."
            throw error
        }
    }

    func keepOriginal(_ decisionID: UUID) throws {
        guard let original = try ledger.decisions().first(where: { $0.id == decisionID }),
              original.state == .proposed else { return }
        _ = try ledger.replaceDecision(transition(original, to: .rejected), expected: original)
        try load(athleteID: original.athleteID)
    }

    func undo(_ decisionID: UUID) throws -> WeeklyTrainingPlan {
        guard let plan = currentPlan() else {
            throw ProtectedTrainingRepository.RepositoryError.staleUndo
        }
        let result = try ledger.undo(decisionID: decisionID, currentPlan: plan)
        try activate(result.restoredPlan, try CoachDecisionLedger.fingerprint(of: plan))
        try load(athleteID: result.reversal.athleteID)
        return result.restoredPlan
    }

    private func transition(_ original: CoachDecision, to state: CoachDecisionState,
                            appliedAt: Date? = nil, fingerprint: String? = nil) -> CoachDecision {
        CoachDecision(id: original.id, athleteID: original.athleteID, eventIDs: original.eventIDs,
            beforeRevision: original.beforeRevision, afterRevision: original.afterRevision,
            changes: original.changes, reasonCodes: original.reasonCodes,
            classification: original.classification, state: state, confidence: original.confidence,
            missingData: original.missingData, policyVersion: original.policyVersion,
            createdAt: original.createdAt, appliedAt: appliedAt,
            previousPlanData: original.previousPlanData, proposedPlanData: original.proposedPlanData,
            appliedPlanFingerprint: fingerprint)
    }
}
