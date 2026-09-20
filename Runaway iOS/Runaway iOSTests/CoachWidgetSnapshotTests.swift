import XCTest
@testable import Runaway_iOS

final class CoachWidgetSnapshotTests: XCTestCase {
    func testPendingProposalKeepsOriginalWorkoutAndRequestsReview() {
        let decision = makeDecision(state: .proposed)

        let snapshot = CoachWidgetSnapshot.make(
            decision: decision,
            originalActiveWorkoutID: "original-workout",
            proposedActiveWorkoutID: "replacement-workout",
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(snapshot.activeWorkoutID, "original-workout")
        XCTAssertEqual(snapshot.headline, "Review change")
        XCTAssertFalse(snapshot.undoAvailable)
    }

    func testAppliedDecisionShowsAcceptedWorkoutAndUndo() {
        let decision = makeDecision(state: .applied)

        let snapshot = CoachWidgetSnapshot.make(
            decision: decision,
            originalActiveWorkoutID: "original-workout",
            proposedActiveWorkoutID: "replacement-workout",
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(snapshot.activeWorkoutID, "replacement-workout")
        XCTAssertEqual(snapshot.headline, "Week updated")
        XCTAssertTrue(snapshot.undoAvailable)
    }

    func testStaleSnapshotIsNotCurrent() {
        let snapshot = CoachWidgetSnapshot.make(
            decision: makeDecision(state: .applied),
            originalActiveWorkoutID: "original",
            proposedActiveWorkoutID: "replacement",
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertFalse(snapshot.isCurrent(at: Date(timeIntervalSince1970: 100 + CoachWidgetSnapshot.maximumAge + 1)))
    }

    func testCompletedPrescriptionRemainsCompletedBesideCoachState() {
        let prescription = WidgetPrescriptionSnapshot(title: "Tempo Run", detail: "40 min", status: .resolve(isCompleted: true, isPartial: false))
        let coach = CoachWidgetSnapshot.make(
            decision: makeDecision(state: .applied),
            originalActiveWorkoutID: "tempo",
            proposedActiveWorkoutID: "tempo",
            now: Date()
        )

        XCTAssertEqual(prescription.status, .completed)
        XCTAssertEqual(coach.state, .applied)
    }

    func testCacheNeverCrossesAthletes() throws {
        let suite = "CoachWidgetSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let snapshot = CoachWidgetSnapshot.make(
            decision: makeDecision(state: .applied, athleteID: 11),
            originalActiveWorkoutID: "original",
            proposedActiveWorkoutID: "replacement",
            now: Date()
        )
        defaults.set(try JSONEncoder().encode(snapshot), forKey: CoachWidgetSnapshot.cacheKey)

        XCTAssertNotNil(CoachWidgetSnapshot.cached(in: defaults, athleteID: 11))
        XCTAssertNil(CoachWidgetSnapshot.cached(in: defaults, athleteID: 12))
    }

    private func makeDecision(state: CoachDecisionState, athleteID: Int = 7) -> CoachDecision {
        CoachDecision(
            athleteID: athleteID,
            eventIDs: [UUID()],
            beforeRevision: "before",
            afterRevision: "after",
            changes: [CoachChange(
                kind: .replaced,
                workoutID: "original-workout",
                before: "Tempo Run - 40 minutes",
                after: "Easy Run - 30 minutes",
                weeklyLoadDelta: -10,
                isKeyWorkout: true
            )],
            reasonCodes: [.recoveryDeclined],
            classification: state == .proposed ? .approvalRequired : .automatic,
            state: state,
            confidence: 0.9,
            missingData: [],
            policyVersion: "1",
            createdAt: Date()
        )
    }
}
