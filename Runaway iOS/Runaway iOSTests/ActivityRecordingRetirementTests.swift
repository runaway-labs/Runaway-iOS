import XCTest
@testable import Runaway_iOS

final class ActivityRecordingRetirementTests: XCTestCase {
    func testImportedActivityDeepLinkStillResolvesToActivityDetail() throws {
        let url = try XCTUnwrap(URL(string: "runaway://open/activity?id=42"))

        XCTAssertEqual(AppRouter.deepLinkRoute(for: url), .activityDetail(42))
    }

    func testImportedActivityListDeepLinkStillResolvesToHistory() throws {
        let url = try XCTUnwrap(URL(string: "runaway://open/activity"))

        XCTAssertEqual(AppRouter.deepLinkRoute(for: url), .activityList)
    }
}
