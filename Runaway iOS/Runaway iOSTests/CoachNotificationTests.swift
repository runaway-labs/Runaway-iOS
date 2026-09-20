import XCTest
@testable import Runaway_iOS

@MainActor
final class CoachNotificationTests: XCTestCase {
    func testMalformedDecisionIdentifierIsIgnored() {
        let service = PushNotificationService(athleteID: { 1 }, upload: { _, _ in })
        service.receiveNotification(["coach_decision_id": "not-a-uuid", "athlete_id": 1])
        XCTAssertNil(service.takePendingCoachRoute())
    }

    func testNotificationWaitsForLoginAndRejectsForeignAthlete() {
        var athlete: Int?
        let service = PushNotificationService(athleteID: { athlete }, upload: { _, _ in })
        let id = UUID()
        service.receiveNotification(["coach_decision_id": id.uuidString, "athlete_id": 1,
                                     "coach_category": "approval", "expected_revision": "rev"])
        XCTAssertNil(service.takePendingCoachRoute())
        athlete = 1
        XCTAssertEqual(service.takePendingCoachRoute()?.decisionID, id)

        service.receiveNotification(["coach_decision_id": UUID().uuidString, "athlete_id": 2,
                                     "coach_category": "automatic", "expected_revision": "rev"])
        XCTAssertNil(service.takePendingCoachRoute())
    }

    func testDuplicateNotificationActionsEnqueueOneCommand() {
        let service = PushNotificationService(athleteID: { 1 }, upload: { _, _ in })
        let payload: [AnyHashable: Any] = ["coach_decision_id": UUID().uuidString,
            "athlete_id": 1, "coach_category": "approval", "expected_revision": "rev"]
        service.enqueueCoachAction(payload, actionIdentifier: "RUNAWAY_COACH_ACCEPT")
        service.enqueueCoachAction(payload, actionIdentifier: "RUNAWAY_COACH_ACCEPT")
        XCTAssertEqual(service.takePendingCoachCommands().count, 1)
    }
}
