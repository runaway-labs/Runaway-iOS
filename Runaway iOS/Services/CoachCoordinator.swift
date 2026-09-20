import Foundation

struct CoachContext {
    let athleteID: Int
    let activePlan: WeeklyTrainingPlan
    let candidatePlan: WeeklyTrainingPlan
    var planRevision: String
    let reasonCodes: [CoachReasonCode]
    let safetyFlags: Set<CoachSafetyFlag>
    let missingData: [String]
}

struct CoachProcessingResult {
    let event: CoachEvent
    let decision: CoachDecision?
    let activePlan: WeeklyTrainingPlan
}

@MainActor
final class CoachCoordinator {
    private let ledger: CoachDecisionLedger

    init(ledger: CoachDecisionLedger) {
        self.ledger = ledger
    }

    func process(_ event: CoachEvent, context: CoachContext) async throws -> CoachProcessingResult {
        let stored = try ledger.append(event)
        guard context.athleteID == stored.athleteID,
              context.activePlan.athleteId == stored.athleteID,
              context.candidatePlan.athleteId == stored.athleteID else {
            throw ProtectedTrainingRepository.RepositoryError.ownershipMismatch
        }
        if let existing = try ledger.decision(forEvent: stored.id) {
            try ledger.markProcessed([stored.id])
            return CoachProcessingResult(
                event: stored,
                decision: existing,
                activePlan: existing.state == .applied ? context.candidatePlan : context.activePlan
            )
        }
        let currentRevision = try CoachDecisionLedger.fingerprint(of: context.activePlan)
        guard currentRevision == context.planRevision else {
            throw ProtectedTrainingRepository.RepositoryError.staleCoachDecision
        }
        let comparison = try CoachPlanComparator.compare(
            before: context.activePlan,
            after: context.candidatePlan
        )
        guard !comparison.changes.isEmpty else {
            try ledger.markProcessed([stored.id])
            return CoachProcessingResult(event: stored, decision: nil, activePlan: context.activePlan)
        }
        let candidateRevision = try CoachDecisionLedger.fingerprint(of: context.candidatePlan)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let proposal = CoachProposal(
            athleteID: context.athleteID,
            eventIDs: [stored.id],
            beforeRevision: currentRevision,
            afterRevision: candidateRevision,
            changes: comparison.changes,
            weeklyLoadDelta: comparison.weeklyLoadDelta,
            replacesKeyWorkout: comparison.replacesKeyWorkout,
            cascadingChangeCount: comparison.changes.count,
            safetyFlags: context.safetyFlags,
            missingData: context.missingData,
            createdAt: stored.receivedAt,
            previousPlanData: try encoder.encode(context.activePlan),
            proposedPlanData: try encoder.encode(context.candidatePlan)
        )
        let classification = CoachAdjustmentPolicy.classify(proposal)
        let state: CoachDecisionState = switch classification {
        case .automatic: .applied
        case .approvalRequired: .proposed
        case .blocked: .blocked
        }
        let decision = CoachDecision(
            athleteID: context.athleteID,
            eventIDs: [stored.id],
            beforeRevision: currentRevision,
            afterRevision: candidateRevision,
            changes: comparison.changes,
            reasonCodes: context.reasonCodes,
            classification: classification,
            state: state,
            confidence: CoachAdjustmentPolicy.confidence(for: proposal),
            missingData: context.missingData,
            policyVersion: CoachAdjustmentPolicy.version,
            createdAt: stored.receivedAt,
            appliedAt: state == .applied ? Date() : nil,
            previousPlanData: proposal.previousPlanData,
            appliedPlanFingerprint: state == .applied ? candidateRevision : nil
        )
        try ledger.appendDecision(decision)
        try ledger.markProcessed([stored.id])
        return CoachProcessingResult(
            event: stored,
            decision: decision,
            activePlan: state == .applied ? context.candidatePlan : context.activePlan
        )
    }
}
