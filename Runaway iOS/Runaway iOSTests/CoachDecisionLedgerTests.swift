import XCTest
@testable import Runaway_iOS

@MainActor
final class CoachDecisionLedgerTests: XCTestCase {
    func testEventRetriesAreIdempotentAndConflictsAreRejected() throws {
        try withLedger { ledger, _, _ in
            let original = event()
            XCTAssertEqual(try ledger.append(original), original)
            XCTAssertEqual(try ledger.append(original), original)

            let conflict = event(id: original.id, payload: .reevaluationRequested(reason: "different"))
            XCTAssertThrowsError(try ledger.append(conflict))
            XCTAssertEqual(try ledger.pendingEvents(), [original])
        }
    }

    func testProcessedEventsLeavePendingQueueWithoutDeletingHistory() throws {
        try withLedger { ledger, _, _ in
            let first = event(occurredAt: Date(timeIntervalSince1970: 100))
            let second = event(occurredAt: Date(timeIntervalSince1970: 200))
            try ledger.append(first)
            try ledger.append(second)

            try ledger.markProcessed([first.id])

            XCTAssertEqual(try ledger.pendingEvents(), [second])
            XCTAssertEqual(try ledger.events(), [first, second])
        }
    }

    func testOwnershipAndAthleteSwitchingIsolateEveryOperation() throws {
        try withLedger { ledger, _, setActiveAthlete in
            XCTAssertThrowsError(try ledger.append(event(athleteID: 2)))
            setActiveAthlete(2)
            XCTAssertThrowsError(try ledger.pendingEvents())
            XCTAssertThrowsError(try ledger.appendDecision(decision()))
        }
    }

    func testDecisionHistoryIsAppendOnlyAndCompareAndSwapRejectsStaleWriter() throws {
        try withLedger { ledger, _, _ in
            let original = decision(state: .proposed)
            XCTAssertEqual(try ledger.appendDecision(original), original)
            XCTAssertEqual(try ledger.appendDecision(original), original)

            let conflicting = decision(id: original.id, state: .rejected)
            XCTAssertThrowsError(try ledger.appendDecision(conflicting))

            let applied = transitioned(original, to: .applied, appliedAt: Date(timeIntervalSince1970: 400))
            XCTAssertEqual(try ledger.replaceDecision(applied, expected: original), applied)
            XCTAssertThrowsError(try ledger.replaceDecision(conflicting, expected: original))
            XCTAssertEqual(try ledger.decisions(), [applied])
        }
    }

    func testUndoAppendsReversalAndRestoresPreviousPlan() throws {
        try withLedger { ledger, _, _ in
            let previous = plan(id: "before", title: "Easy run")
            let applied = plan(id: "after", title: "Recovery run")
            let previousData = try Self.encoder.encode(previous)
            let record = decision(
                state: .applied,
                appliedAt: Date(timeIntervalSince1970: 400),
                previousPlanData: previousData,
                appliedPlanFingerprint: try CoachDecisionLedger.fingerprint(of: applied)
            )
            try ledger.appendDecision(record)

            let result = try ledger.undo(decisionID: record.id, currentPlan: applied)

            XCTAssertEqual(result.restoredPlan.id, previous.id)
            XCTAssertEqual(result.restoredPlan.workouts.first?.title, "Easy run")
            XCTAssertEqual(result.reversal.state, .undone)
            XCTAssertNotEqual(result.reversal.id, record.id)
            XCTAssertEqual(try ledger.decisions().count, 2)
            XCTAssertEqual(try ledger.decisions().first, record)
        }
    }

    func testUndoRejectsStaleCurrentPlanAndPreservesHistory() throws {
        try withLedger { ledger, _, _ in
            let previous = plan(id: "before", title: "Easy run")
            let applied = plan(id: "after", title: "Recovery run")
            let record = decision(
                state: .applied,
                appliedAt: Date(timeIntervalSince1970: 400),
                previousPlanData: try Self.encoder.encode(previous),
                appliedPlanFingerprint: try CoachDecisionLedger.fingerprint(of: applied)
            )
            try ledger.appendDecision(record)

            XCTAssertThrowsError(try ledger.undo(
                decisionID: record.id,
                currentPlan: plan(id: "newer", title: "Intervals")
            ))
            XCTAssertEqual(try ledger.decisions(), [record])
        }
    }

    private func withLedger(
        _ body: (CoachDecisionLedger, URL, (Int?) -> Void) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var activeAthlete: Int? = 1
        let repository = ProtectedTrainingRepository(root: root, activeAthleteID: { activeAthlete })
        let ledger = CoachDecisionLedger(repository: repository, athleteID: 1)
        try body(ledger, root, { activeAthlete = $0 })
    }

    private func event(
        id: UUID = UUID(),
        athleteID: Int = 1,
        occurredAt: Date = Date(timeIntervalSince1970: 100),
        payload: CoachEvent.Payload = .reevaluationRequested(reason: "test")
    ) -> CoachEvent {
        CoachEvent(
            id: id,
            athleteID: athleteID,
            kind: .reevaluationRequested,
            source: .app,
            occurredAt: occurredAt,
            receivedAt: occurredAt.addingTimeInterval(1),
            sourceRecordID: "event-\(id.uuidString)",
            payload: payload
        )
    }

    private func decision(
        id: UUID = UUID(),
        state: CoachDecisionState = .proposed,
        appliedAt: Date? = nil,
        previousPlanData: Data? = nil,
        appliedPlanFingerprint: String? = nil
    ) -> CoachDecision {
        CoachDecision(
            id: id,
            athleteID: 1,
            eventIDs: [UUID()],
            beforeRevision: "revision-1",
            afterRevision: "revision-2",
            changes: [CoachChange(
                kind: .reduced,
                workoutID: "monday",
                before: "Easy run, 30 minutes",
                after: "Recovery run, 20 minutes",
                weeklyLoadDelta: -10,
                isKeyWorkout: false
            )],
            reasonCodes: [.recoveryDeclined],
            classification: .automatic,
            state: state,
            confidence: 0.9,
            missingData: [],
            policyVersion: CoachAdjustmentPolicy.version,
            createdAt: Date(timeIntervalSince1970: 300),
            appliedAt: appliedAt,
            previousPlanData: previousPlanData,
            appliedPlanFingerprint: appliedPlanFingerprint
        )
    }

    private func transitioned(
        _ original: CoachDecision,
        to state: CoachDecisionState,
        appliedAt: Date? = nil
    ) -> CoachDecision {
        CoachDecision(
            id: original.id,
            athleteID: original.athleteID,
            eventIDs: original.eventIDs,
            beforeRevision: original.beforeRevision,
            afterRevision: original.afterRevision,
            changes: original.changes,
            reasonCodes: original.reasonCodes,
            classification: original.classification,
            state: state,
            confidence: original.confidence,
            missingData: original.missingData,
            policyVersion: original.policyVersion,
            createdAt: original.createdAt,
            appliedAt: appliedAt,
            previousPlanData: original.previousPlanData,
            appliedPlanFingerprint: original.appliedPlanFingerprint
        )
    }

    private func plan(id: String, title: String) -> WeeklyTrainingPlan {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return WeeklyTrainingPlan(
            id: id,
            athleteId: 1,
            weekStartDate: start,
            weekEndDate: start.addingTimeInterval(6 * 86_400),
            workouts: [DailyWorkout(
                id: "monday",
                date: start.addingTimeInterval(86_400),
                dayOfWeek: .monday,
                workoutType: title == "Intervals" ? .intervalRun : .easyRun,
                title: title,
                description: "Test prescription",
                duration: 30,
                distance: 3,
                targetPace: nil,
                exercises: nil,
                isCompleted: false,
                completedActivityId: nil
            )],
            weekNumber: 1,
            totalMileage: 3,
            focusArea: "Consistency",
            notes: nil,
            generatedAt: start,
            goalId: 10
        )
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()
}
