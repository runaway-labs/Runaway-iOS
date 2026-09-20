import XCTest
@testable import Runaway_iOS

@MainActor
final class UserSessionTests: XCTestCase {
    func testAthleteSetupFailureLeavesSessionUnreadyAndSurfacesError() {
        let session = UserSession(startAutomatically: false)
        session.isAuthenticated = true

        session.completeAthleteSetup(with: .failure(TestFailure.setup))

        XCTAssertFalse(session.isReady)
        XCTAssertNil(session.userId)
        XCTAssertNotNil(session.setupError)
        XCTAssertFalse(session.isCheckingOnboarding)
    }

    func testAthleteSetupSuccessMakesAuthenticatedSessionReady() {
        let session = UserSession(startAutomatically: false)
        session.isAuthenticated = true

        session.completeAthleteSetup(with: .success(73))

        XCTAssertTrue(session.isReady)
        XCTAssertEqual(session.userId, 73)
        XCTAssertNil(session.setupError)
    }
}

private enum TestFailure: Error {
    case setup
}

@MainActor
final class PushNotificationTests: XCTestCase {
    func testWorkoutNotificationWaitsForItsAccountAndDoesNotRouteAsAnActivity() {
        var athlete: Int?
        let service = PushNotificationService(athleteID: { athlete }, upload: { _, _ in })
        let id = UUID()
        service.receiveNotification(["workout_delivery_id": id.uuidString, "athlete_id": "73"])
        XCTAssertNil(service.takePendingWorkoutRoute())
        athlete = 73
        XCTAssertEqual(service.takePendingWorkoutRoute()?.id, id)
        XCTAssertNil(service.takePendingWorkoutRoute())
        XCTAssertNil(service.takePendingActivityID())
    }

    func testWorkoutNotificationCannotOpenAnotherAthletesRecommendation() {
        let service = PushNotificationService(athleteID: { 91 }, upload: { _, _ in })
        service.receiveNotification(["workout_delivery_id": UUID().uuidString, "athlete_id": "73"])
        XCTAssertNil(service.takePendingWorkoutRoute())
        XCTAssertNil(WorkoutPromptRoute(userInfo: ["workout_delivery_id": "invalid", "athlete_id": "73"]))
    }

    func testWorkoutNotificationsDefaultOffWithPrivateLockScreenText() {
        let settings = WorkoutPromptSettings(athlete_id: 73)
        XCTAssertFalse(settings.enabled)
        XCTAssertFalse(settings.show_workout_name)
        XCTAssertEqual(settings.hour, 7)
        XCTAssertEqual(settings.weekdays, [1, 2, 3, 4, 5, 6, 7])
    }
    func testTokenReceivedBeforeLoginIsSavedWhenAccountBecomesReady() async {
        var athleteID: Int?
        var saved: [Int] = []
        let service = PushNotificationService(athleteID: { athleteID }, upload: { _, id in
            saved.append(id)
        }, pause: { _ in })
        service.receiveToken("device-token")
        await service.synchronize()
        XCTAssertTrue(saved.isEmpty)
        athleteID = 73
        await service.synchronize()
        XCTAssertEqual(saved, [73])
        XCTAssertEqual(service.registrationStatus, .registered)
    }

    func testFailedUploadRetriesAndCanRecoverOnLaterForeground() async {
        var shouldFail = true
        var attempts = 0
        let service = PushNotificationService(athleteID: { 73 }, upload: { _, _ in
            attempts += 1
            if shouldFail { throw TestFailure.setup }
        }, pause: { _ in })
        service.receiveToken("device-token")
        await service.synchronize()
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(service.registrationStatus, .failed)
        shouldFail = false
        await service.synchronize()
        XCTAssertEqual(attempts, 4)
        XCTAssertEqual(service.registrationStatus, .registered)
    }

    func testRetryStopsWhenAccountChanges() async {
        var athleteID: Int? = 73
        var attempts = 0
        let service = PushNotificationService(athleteID: { athleteID }, upload: { _, _ in
            attempts += 1
            throw TestFailure.setup
        }, pause: { _ in athleteID = 91 })
        service.receiveToken("device-token")
        await service.synchronize()
        XCTAssertEqual(attempts, 1)
        XCTAssertNotEqual(service.registrationStatus, .registered)
    }

    func testNotificationWaitsForLoginAndIsConsumedOnlyOnce() {
        var athleteID: Int?
        let service = PushNotificationService(athleteID: { athleteID }, upload: { _, _ in }, pause: { _ in })
        service.receiveNotification(["activity_id": "20103650593"])
        XCTAssertNil(service.takePendingActivityID())
        athleteID = 73
        XCTAssertEqual(service.takePendingActivityID(), 20103650593)
        XCTAssertNil(service.takePendingActivityID())
    }

    func testInvalidNotificationCannotReplacePendingActivity() {
        let service = PushNotificationService(athleteID: { 73 }, upload: { _, _ in }, pause: { _ in })
        service.receiveNotification(["activity_id": 42])
        service.receiveNotification(["activity_id": "-1"])
        service.receiveNotification(["activity_id": "invalid"])
        XCTAssertEqual(service.takePendingActivityID(), 42)
    }
}
