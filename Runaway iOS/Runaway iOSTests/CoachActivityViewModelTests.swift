import XCTest
@testable import Runaway_iOS

@MainActor
final class CoachActivityViewModelTests: XCTestCase {
    func testPendingDecisionsLeadAndExposeTrustActions() throws {
        try withSystem { ledger, plan in
            let applied = decision(state: .applied, createdAt: Date(timeIntervalSince1970: 100))
            let pending = decision(state: .proposed, createdAt: Date(timeIntervalSince1970: 200),
                                   proposedPlanData: try Self.encoder.encode(Self.plan(duration: 30)))
            try ledger.appendDecision(applied)
            try ledger.appendDecision(pending)
            let model = CoachActivityViewModel(ledger: ledger, currentPlan: { plan }, activate: { _, _ in })

            try model.load(athleteID: 1)

            XCTAssertEqual(model.pending.map(\.id), [pending.id])
            XCTAssertEqual(model.history.map(\.id), [applied.id])
            XCTAssertEqual(model.availableActions(for: pending), [.accept, .keepOriginal])
        }
    }

    func testApprovalActivatesProposedPlanAndStaleApprovalExplainsFailure() throws {
        try withSystem { ledger, original in
            let proposed = plan(duration: 25)
            let pending = decision(
                state: .proposed,
                createdAt: Date(timeIntervalSince1970: 200),
                beforeRevision: try CoachDecisionLedger.fingerprint(of: original),
                proposedPlanData: try Self.encoder.encode(proposed)
            )
            try ledger.appendDecision(pending)
            var active = original
            let model = CoachActivityViewModel(ledger: ledger, currentPlan: { active }, activate: { plan, _ in active = plan })
            try model.load(athleteID: 1)

            try model.accept(pending.id)
            XCTAssertEqual(active.workouts.first?.duration, 25)
            XCTAssertEqual(try ledger.decisions().first?.state, .applied)

            let stale = decision(state: .proposed, createdAt: Date(timeIntervalSince1970: 300),
                                 beforeRevision: "older", proposedPlanData: try Self.encoder.encode(proposed))
            try ledger.appendDecision(stale)
            XCTAssertThrowsError(try model.accept(stale.id))
            XCTAssertNotNil(model.errorMessage)
        }
    }

    private func withSystem(_ body: (CoachDecisionLedger, WeeklyTrainingPlan) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ProtectedTrainingRepository(root: root, activeAthleteID: { 1 })
        try body(CoachDecisionLedger(repository: repository, athleteID: 1), plan(duration: 40))
    }

    private func decision(state: CoachDecisionState, createdAt: Date,
                          beforeRevision: String = "before", proposedPlanData: Data? = nil) -> CoachDecision {
        CoachDecision(athleteID: 1, eventIDs: [UUID()], beforeRevision: beforeRevision,
            afterRevision: "after", changes: [CoachChange(kind: .reduced, workoutID: "day",
                before: "40 minutes", after: "25 minutes", weeklyLoadDelta: -15, isKeyWorkout: false)],
            reasonCodes: [.recoveryDeclined], classification: state == .proposed ? .approvalRequired : .automatic,
            state: state, confidence: 0.88, missingData: [], policyVersion: CoachAdjustmentPolicy.version,
            createdAt: createdAt, appliedAt: state == .applied ? createdAt : nil,
            previousPlanData: nil, proposedPlanData: proposedPlanData,
            appliedPlanFingerprint: state == .applied ? "after" : nil)
    }

    private static func plan(duration: Int) -> WeeklyTrainingPlan {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        return WeeklyTrainingPlan(id: "plan", athleteId: 1, weekStartDate: date,
            weekEndDate: date.addingTimeInterval(6 * 86_400), workouts: [DailyWorkout(id: "day",
                date: date, dayOfWeek: .sunday, workoutType: .easyRun, title: "Easy run",
                description: "Test", duration: duration, distance: Double(duration) / 10,
                targetPace: nil, exercises: nil, isCompleted: false, completedActivityId: nil)],
            weekNumber: 1, totalMileage: Double(duration) / 10, focusArea: nil, notes: nil,
            generatedAt: date, goalId: nil)
    }

    private func plan(duration: Int) -> WeeklyTrainingPlan { Self.plan(duration: duration) }
    private static let encoder: JSONEncoder = { let value = JSONEncoder(); value.outputFormatting = .sortedKeys; return value }()
}
