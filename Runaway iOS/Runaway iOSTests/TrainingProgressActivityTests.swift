import XCTest
@testable import Runaway_iOS

final class TrainingProgressActivityTests: XCTestCase {
    func testMissingSportMirrorCountsOnceThroughActivityConversion() throws {
        let time = Date(timeIntervalSince1970: 1_790_701_968)
        let garmin = Activity(id: -1, name: "Kirkwood Running", distance: 7702.45,
            elapsed_time: 3137, athlete_id: 7, activity_date: time.timeIntervalSince1970, source: "garmin")
        let strava = Activity(id: 1, type: "Run", distance: 7702.50,
            elapsed_time: 3137, athlete_id: 7, activity_date: time.timeIntervalSince1970, source: "strava")
        let projection = try [XCTUnwrap(TrainingProgressActivity(garmin, athleteID: 7)),
                              XCTUnwrap(TrainingProgressActivity(strava, athleteID: 7))]
        XCTAssertTrue(projection[0].type.isEmpty)
        XCTAssertEqual(projection[0].source, "garmin")
        let unique = TrainingProgressPolicy.unique(projection, athleteID: 7, through: time.addingTimeInterval(3600))
        XCTAssertEqual(unique.count, 1)
        XCTAssertEqual(unique.first?.kind, .run)
        XCTAssertEqual(unique.first?.meters, 7702.50)
    }

    func testConversionKeepsCanonicalDateAndExcludesFlaggedActivity() throws {
        let activity = Activity(id: 1, start_date: 1_000, elapsed_time: 600,
            athlete_id: 7, activity_date: 2_000, source: "strava")
        XCTAssertEqual(try XCTUnwrap(TrainingProgressActivity(activity, athleteID: 7)).date,
                       Date(timeIntervalSince1970: 2_000))
        XCTAssertNil(TrainingProgressActivity(Activity(id: 2, activity_date: 2_000, flagged: true), athleteID: 7))
    }
}
