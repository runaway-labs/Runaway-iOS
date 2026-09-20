import XCTest
@testable import Runaway_iOS

final class CoachAdjustmentPolicyTests: XCTestCase {
    func testReductionAndSingleMoveAreAutomatic() {
        let reduction = proposal(
            changes: [change(kind: .reduced, loadDelta: -8)],
            weeklyLoadDelta: -8
        )
        let move = proposal(changes: [change(kind: .moved)])

        XCTAssertEqual(CoachAdjustmentPolicy.classify(reduction), .automatic)
        XCTAssertEqual(CoachAdjustmentPolicy.classify(move), .automatic)
    }

    func testLoadIncreaseKeyReplacementAndCascadeRequireApproval() {
        XCTAssertEqual(
            CoachAdjustmentPolicy.classify(proposal(weeklyLoadDelta: 1)),
            .approvalRequired
        )
        XCTAssertEqual(
            CoachAdjustmentPolicy.classify(proposal(replacesKeyWorkout: true)),
            .approvalRequired
        )
        XCTAssertEqual(
            CoachAdjustmentPolicy.classify(proposal(cascadingChangeCount: 2)),
            .approvalRequired
        )
    }

    func testPainUnsafeSpacingAndStaleRevisionAreBlocked() {
        XCTAssertEqual(
            CoachAdjustmentPolicy.classify(proposal(safetyFlags: [.pain])),
            .blocked
        )
        XCTAssertEqual(
            CoachAdjustmentPolicy.classify(proposal(safetyFlags: [.consecutiveHighIntensity])),
            .blocked
        )
        XCTAssertEqual(
            CoachAdjustmentPolicy.classify(proposal(safetyFlags: [.staleRevision])),
            .blocked
        )
    }

    func testMissingContextLowersConfidenceWithoutBlockingSafeChange() {
        let complete = proposal()
        let incomplete = proposal(missingData: ["readiness", "weather"])

        XCTAssertEqual(CoachAdjustmentPolicy.classify(incomplete), .automatic)
        XCTAssertLessThan(
            CoachAdjustmentPolicy.confidence(for: incomplete),
            CoachAdjustmentPolicy.confidence(for: complete)
        )
    }

    private func proposal(
        beforeRevision: String = "revision-4",
        afterRevision: String = "revision-5",
        changes: [CoachChange] = [change(kind: .moved)],
        weeklyLoadDelta: Double = 0,
        replacesKeyWorkout: Bool = false,
        cascadingChangeCount: Int = 1,
        safetyFlags: Set<CoachSafetyFlag> = [],
        missingData: [String] = []
    ) -> CoachProposal {
        CoachProposal(
            athleteID: 42,
            eventIDs: [UUID()],
            beforeRevision: beforeRevision,
            afterRevision: afterRevision,
            changes: changes,
            weeklyLoadDelta: weeklyLoadDelta,
            replacesKeyWorkout: replacesKeyWorkout,
            cascadingChangeCount: cascadingChangeCount,
            safetyFlags: safetyFlags,
            missingData: missingData,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private static func change(
        kind: CoachChange.Kind,
        loadDelta: Double = 0
    ) -> CoachChange {
        CoachChange(
            kind: kind,
            workoutID: "workout-1",
            before: "before",
            after: "after",
            weeklyLoadDelta: loadDelta,
            isKeyWorkout: false
        )
    }

    private func change(
        kind: CoachChange.Kind,
        loadDelta: Double = 0
    ) -> CoachChange {
        Self.change(kind: kind, loadDelta: loadDelta)
    }
}
