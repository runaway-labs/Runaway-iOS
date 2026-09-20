import XCTest
@testable import Runaway_iOS

final class CoachDomainTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)

    func testDuplicateSourceEventsHaveTheSameIdentity() {
        let first = CoachEvent(athleteID: 42, kind: .workoutImported,
            source: .healthKit, occurredAt: instant, receivedAt: instant,
            sourceRecordID: "health-123", payload: .workoutImported(activityID: 99))
        let retry = CoachEvent(athleteID: 42, kind: .workoutImported,
            source: .healthKit, occurredAt: instant, receivedAt: instant.addingTimeInterval(5),
            sourceRecordID: "health-123", payload: .workoutImported(activityID: 99))

        XCTAssertEqual(first.deduplicationKey, retry.deduplicationKey)
    }

    func testEventValidationRejectsInvalidOwnerAndDates() {
        let invalidOwner = CoachEvent(athleteID: 0, kind: .appForegrounded,
            source: .app, occurredAt: instant, receivedAt: instant,
            sourceRecordID: "foreground-1", payload: .none)
        let receivedTooEarly = CoachEvent(athleteID: 42, kind: .appForegrounded,
            source: .app, occurredAt: instant, receivedAt: instant.addingTimeInterval(-1),
            sourceRecordID: "foreground-2", payload: .none)

        XCTAssertFalse(invalidOwner.isValid)
        XCTAssertFalse(receivedTooEarly.isValid)
    }

    func testEventRoundTripsWithoutChangingAuthoritativePayload() throws {
        let event = CoachEvent(athleteID: 42, kind: .weatherChanged,
            source: .weather, occurredAt: instant, receivedAt: instant,
            sourceRecordID: "weather-2026-09-20", payload: .weatherChanged(conditionKey: "heat", severity: 0.7))

        let decoded = try JSONDecoder().decode(CoachEvent.self, from: JSONEncoder().encode(event))

        XCTAssertEqual(decoded, event)
    }

    func testProposalRequiresEvidenceRevisionsAndChanges() {
        let invalid = CoachProposal(athleteID: 42, eventIDs: [], beforeRevision: "",
            afterRevision: "", changes: [], weeklyLoadDelta: 0,
            replacesKeyWorkout: false, cascadingChangeCount: 0,
            safetyFlags: [], missingData: [], createdAt: instant)

        XCTAssertFalse(invalid.isValid)
    }

    func testDecisionStateTransitionsAreAppendOnly() {
        XCTAssertTrue(CoachDecisionState.proposed.canTransition(to: .applied))
        XCTAssertTrue(CoachDecisionState.applied.canTransition(to: .undone))
        XCTAssertFalse(CoachDecisionState.applied.canTransition(to: .proposed))
        XCTAssertFalse(CoachDecisionState.rejected.canTransition(to: .applied))
    }

    func testDecisionRoundTripPreservesReversalData() throws {
        let change = CoachChange(kind: .reduced, workoutID: "run-1",
            before: "45 min", after: "35 min", weeklyLoadDelta: -10, isKeyWorkout: false)
        let decision = CoachDecision(athleteID: 42, eventIDs: [UUID()],
            beforeRevision: "before", afterRevision: "after", changes: [change],
            reasonCodes: [.recoveryDeclined], classification: .automatic, state: .applied,
            confidence: 0.8, missingData: [], policyVersion: "coach-v1",
            createdAt: instant, appliedAt: instant, previousPlanData: Data("prior".utf8),
            appliedPlanFingerprint: "after")

        let decoded = try JSONDecoder().decode(CoachDecision.self, from: JSONEncoder().encode(decision))

        XCTAssertEqual(decoded, decision)
        XCTAssertTrue(decoded.isValid)
    }
}
