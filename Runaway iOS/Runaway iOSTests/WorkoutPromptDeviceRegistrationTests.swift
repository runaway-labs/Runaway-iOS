import XCTest
@testable import Runaway_iOS

final class WorkoutPromptDeviceRegistrationTests: XCTestCase {
    func testCurrentClientPublishesCoachCapability() throws {
        let registration = WorkoutPromptDeviceRegistration(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            athleteID: 42,
            token: "abc123",
            environment: "production"
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(registration)) as? [String: Any]
        )
        XCTAssertEqual(object["athlete_id"] as? Int, 42)
        XCTAssertEqual(object["coach_capability_enabled"] as? Bool, true)
    }
}
