import Foundation

enum CoachAdjustmentPolicy {
    static let version = "coach-adjustment-v1"

    private static let blockingSafetyFlags: Set<CoachSafetyFlag> = [
        .pain,
        .illness,
        .unsafeLoadSpike,
        .consecutiveHighIntensity,
        .ownershipMismatch,
        .staleRevision
    ]

    static func classify(_ proposal: CoachProposal) -> CoachDecisionClassification {
        guard proposal.isValid else { return .blocked }

        if !proposal.safetyFlags.isDisjoint(with: blockingSafetyFlags) {
            return .blocked
        }

        if proposal.weeklyLoadDelta > 0 ||
            proposal.replacesKeyWorkout ||
            proposal.cascadingChangeCount > 1 {
            return .approvalRequired
        }

        return .automatic
    }

    static func confidence(for proposal: CoachProposal) -> Double {
        guard proposal.isValid else { return 0 }

        let uniqueMissingData = Set(proposal.missingData.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }).subtracting([""])
        let evidencePenalty = min(Double(uniqueMissingData.count) * 0.12, 0.57)
        return max(0.35, 0.92 - evidencePenalty)
    }
}
