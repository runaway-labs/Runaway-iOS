import XCTest
@testable import Runaway_iOS

@MainActor
final class CoachNotificationTests: XCTestCase {
    func testOpaqueScheduledWakeCreatesOwnedEvent() throws {
        let eventID = UUID()
        let receivedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let payload: [AnyHashable: Any] = [
            "coach_event_id": eventID.uuidString,
            "athlete_id": "42",
        ]

        let event = try XCTUnwrap(CoachEvent.remoteScheduledCheckIn(
            from: payload,
            authenticatedAthleteID: 42,
            receivedAt: receivedAt
        ))

        XCTAssertEqual(event.id, eventID)
        XCTAssertEqual(event.athleteID, 42)
        XCTAssertEqual(event.kind, .scheduledCheckIn)
        XCTAssertEqual(event.source, .schedule)
        XCTAssertEqual(event.sourceRecordID, "schedule-\(eventID.uuidString)")
        XCTAssertEqual(event.payload, .none)
        XCTAssertNil(CoachEvent.remoteScheduledCheckIn(
            from: payload,
            authenticatedAthleteID: 7,
            receivedAt: receivedAt
        ))
    }

    func testScheduledRecommendationCopyUsesWorkoutAppropriateDose() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let walking = DailyWorkout(
            id: "walk", date: date, dayOfWeek: .sunday, workoutType: .walking,
            title: "Walking", description: "Easy movement", duration: 40,
            distance: nil, targetPace: "9:22/mi", exercises: nil,
            isCompleted: false, completedActivityId: nil
        )
        let running = DailyWorkout(
            id: "run", date: date, dayOfWeek: .sunday, workoutType: .easyRun,
            title: "Easy Run", description: "Aerobic work", duration: 35,
            distance: 3.5, targetPace: "9:22/mi", exercises: nil,
            isCompleted: false, completedActivityId: nil
        )

        let walkingCopy = ScheduledCoachNotificationCopy(workout: walking)
        let runningCopy = ScheduledCoachNotificationCopy(workout: running)

        XCTAssertEqual(walkingCopy.title, "Up next: Walking")
        XCTAssertTrue(walkingCopy.body.contains("40 min"))
        XCTAssertFalse(walkingCopy.body.contains("/mi"))
        XCTAssertTrue(runningCopy.body.contains("9:22/mi"))
    }

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
