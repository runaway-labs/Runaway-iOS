import Foundation

enum CoachDecisionClassification: String, Codable, Sendable {
    case automatic, approvalRequired, blocked
}

enum CoachDecisionState: String, Codable, Sendable {
    case proposed, applied, rejected, superseded, undone, blocked

    func canTransition(to next: Self) -> Bool {
        switch (self, next) {
        case (.proposed, .applied), (.proposed, .rejected), (.proposed, .superseded),
             (.applied, .undone), (.applied, .superseded): true
        default: false
        }
    }
}

enum CoachSafetyFlag: String, Codable, Hashable, Sendable {
    case pain, illness, unsafeLoadSpike, consecutiveHighIntensity
    case ownershipMismatch, staleRevision
}

enum CoachReasonCode: String, Codable, Sendable {
    case workoutImported, workoutMissed, completionChanged, recoveryDeclined
    case recoveryImproved, weatherChanged, availabilityChanged, athleteRequested
    case unsafeChange, stalePlan
}

struct CoachChange: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case moved, reduced, replaced, restored, weatherAdjusted, exerciseSubstituted
    }

    let id: UUID
    let kind: Kind
    let workoutID: String
    let before: String?
    let after: String
    let weeklyLoadDelta: Double
    let isKeyWorkout: Bool

    init(id: UUID = UUID(), kind: Kind, workoutID: String, before: String?, after: String,
         weeklyLoadDelta: Double, isKeyWorkout: Bool) {
        self.id = id
        self.kind = kind
        self.workoutID = workoutID
        self.before = before
        self.after = after
        self.weeklyLoadDelta = weeklyLoadDelta
        self.isKeyWorkout = isKeyWorkout
    }

    var isValid: Bool {
        !workoutID.isEmpty && !after.isEmpty && weeklyLoadDelta.isFinite
    }
}

struct CoachProposal: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let athleteID: Int
    let eventIDs: [UUID]
    let beforeRevision: String
    let afterRevision: String
    let changes: [CoachChange]
    let weeklyLoadDelta: Double
    let replacesKeyWorkout: Bool
    let cascadingChangeCount: Int
    let safetyFlags: Set<CoachSafetyFlag>
    let missingData: [String]
    let createdAt: Date
    var previousPlanData: Data?
    var proposedPlanData: Data?

    init(id: UUID = UUID(), athleteID: Int, eventIDs: [UUID], beforeRevision: String,
         afterRevision: String, changes: [CoachChange], weeklyLoadDelta: Double,
         replacesKeyWorkout: Bool, cascadingChangeCount: Int,
         safetyFlags: Set<CoachSafetyFlag>, missingData: [String], createdAt: Date,
         previousPlanData: Data? = nil, proposedPlanData: Data? = nil) {
        self.id = id
        self.athleteID = athleteID
        self.eventIDs = eventIDs
        self.beforeRevision = beforeRevision
        self.afterRevision = afterRevision
        self.changes = changes
        self.weeklyLoadDelta = weeklyLoadDelta
        self.replacesKeyWorkout = replacesKeyWorkout
        self.cascadingChangeCount = cascadingChangeCount
        self.safetyFlags = safetyFlags
        self.missingData = missingData
        self.createdAt = createdAt
        self.previousPlanData = previousPlanData
        self.proposedPlanData = proposedPlanData
    }

    var isStale: Bool { safetyFlags.contains(.staleRevision) }
    var createsUnsafeIntensitySpacing: Bool { safetyFlags.contains(.consecutiveHighIntensity) }

    var isValid: Bool {
        athleteID > 0 && !eventIDs.isEmpty && !beforeRevision.isEmpty &&
            !afterRevision.isEmpty && !changes.isEmpty && changes.allSatisfy(\.isValid) &&
            weeklyLoadDelta.isFinite && cascadingChangeCount >= 0 &&
            createdAt.timeIntervalSince1970.isFinite
    }
}

struct CoachDecision: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let athleteID: Int
    let eventIDs: [UUID]
    let beforeRevision: String
    let afterRevision: String
    let changes: [CoachChange]
    let reasonCodes: [CoachReasonCode]
    let classification: CoachDecisionClassification
    let state: CoachDecisionState
    let confidence: Double
    let missingData: [String]
    let policyVersion: String
    let createdAt: Date
    let appliedAt: Date?
    let previousPlanData: Data?
    let appliedPlanFingerprint: String?

    init(id: UUID = UUID(), athleteID: Int, eventIDs: [UUID], beforeRevision: String,
         afterRevision: String, changes: [CoachChange], reasonCodes: [CoachReasonCode],
         classification: CoachDecisionClassification, state: CoachDecisionState,
         confidence: Double, missingData: [String], policyVersion: String,
         createdAt: Date, appliedAt: Date? = nil, previousPlanData: Data? = nil,
         appliedPlanFingerprint: String? = nil) {
        self.id = id
        self.athleteID = athleteID
        self.eventIDs = eventIDs
        self.beforeRevision = beforeRevision
        self.afterRevision = afterRevision
        self.changes = changes
        self.reasonCodes = reasonCodes
        self.classification = classification
        self.state = state
        self.confidence = confidence
        self.missingData = missingData
        self.policyVersion = policyVersion
        self.createdAt = createdAt
        self.appliedAt = appliedAt
        self.previousPlanData = previousPlanData
        self.appliedPlanFingerprint = appliedPlanFingerprint
    }

    var isValid: Bool {
        athleteID > 0 && !eventIDs.isEmpty && !beforeRevision.isEmpty &&
            !afterRevision.isEmpty && !changes.isEmpty && changes.allSatisfy(\.isValid) &&
            confidence.isFinite && (0...1).contains(confidence) && !policyVersion.isEmpty &&
            createdAt.timeIntervalSince1970.isFinite &&
            (appliedAt?.timeIntervalSince1970.isFinite ?? true)
    }
}
