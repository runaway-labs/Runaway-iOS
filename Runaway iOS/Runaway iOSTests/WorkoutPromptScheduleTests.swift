import XCTest
@testable import Runaway_iOS

final class WorkoutPromptScheduleTests: XCTestCase {
    func testLegacySettingsDecodeAndPreserveExistingTime() throws {
        let json = #"{"athlete_id":73,"enabled":true,"hour":18,"minute":35,"weekdays":[2,4],"timezone":"America/Chicago","show_workout_name":false}"#
        let settings = try JSONDecoder().decode(WorkoutPromptSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.effectiveSchedules.count, 1)
        XCTAssertEqual(settings.effectiveSchedules[0].hour, 18)
        XCTAssertEqual(settings.effectiveSchedules[0].minute, 35)
        XCTAssertEqual(settings.effectiveSchedules[0].weekdays, [2, 4])
        XCTAssertEqual(settings.effectiveSchedules[0].id, settings.effectiveSchedules[0].id)
        XCTAssertNil(settings.scheduleValidationMessage)
    }

    func testMultipleTimesRoundTripWithIndependentDays() throws {
        var settings = WorkoutPromptSettings(athlete_id: 73)
        settings.schedules = [WorkoutPromptSchedule(hour: 7, minute: 15, weekdays: [2, 4]),
                              WorkoutPromptSchedule(hour: 18, minute: 30, weekdays: [3, 5])]
        XCTAssertNil(settings.scheduleValidationMessage)
        let decoded = try JSONDecoder().decode(WorkoutPromptSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
    }

    func testOverlappingDayAndTimeRejected() {
        var settings = WorkoutPromptSettings(athlete_id: 73)
        settings.schedules = [WorkoutPromptSchedule(hour: 7, weekdays: [2, 4]),
                              WorkoutPromptSchedule(hour: 7, weekdays: [4, 6])]
        XCTAssertNotNil(settings.scheduleValidationMessage)
    }

    func testSameTimeOnDifferentDaysAllowed() {
        var settings = WorkoutPromptSettings(athlete_id: 73)
        settings.schedules = [WorkoutPromptSchedule(hour: 7, weekdays: [2]),
                              WorkoutPromptSchedule(hour: 7, weekdays: [3])]
        XCTAssertNil(settings.scheduleValidationMessage)
    }

    func testInvalidTimeDaysAndEmptySchedulesRejected() {
        var settings = WorkoutPromptSettings(athlete_id: 73)
        for schedule in [WorkoutPromptSchedule(hour: 24), WorkoutPromptSchedule(minute: 60),
                         WorkoutPromptSchedule(weekdays: []), WorkoutPromptSchedule(weekdays: [0, 8])] {
            settings.schedules = [schedule]
            XCTAssertNotNil(settings.scheduleValidationMessage)
        }
        settings.schedules = []
        XCTAssertNotNil(settings.scheduleValidationMessage)
    }

    func testTwelveTimeLimitAndDuplicateIdentifiers() {
        var settings = WorkoutPromptSettings(athlete_id: 73)
        settings.schedules = (0..<12).map { WorkoutPromptSchedule(hour: $0) }
        XCTAssertNil(settings.scheduleValidationMessage)
        settings.schedules?.append(WorkoutPromptSchedule(hour: 12))
        XCTAssertNotNil(settings.scheduleValidationMessage)
        let id = UUID()
        settings.schedules = [WorkoutPromptSchedule(id: id, hour: 7), WorkoutPromptSchedule(id: id, hour: 18)]
        XCTAssertNotNil(settings.scheduleValidationMessage)
    }

    func testTimePickerWritesWallClockHourAndMinute() throws {
        var schedule = WorkoutPromptSchedule()
        schedule.time = try XCTUnwrap(Calendar.current.date(bySettingHour: 18, minute: 45, second: 0, of: Date()))
        XCTAssertEqual(schedule.hour, 18)
        XCTAssertEqual(schedule.minute, 45)
        XCTAssertEqual(Calendar.current.component(.hour, from: schedule.time), 18)
    }

    func testRemovingAnEntryPreservesOtherEntries() {
        var settings = WorkoutPromptSettings(athlete_id: 73)
        let morning = WorkoutPromptSchedule(hour: 7)
        let evening = WorkoutPromptSchedule(hour: 18)
        settings.schedules = [morning, evening]
        settings.schedules?.removeAll { $0.id == morning.id }
        XCTAssertEqual(settings.effectiveSchedules, [evening])
        XCTAssertNil(settings.scheduleValidationMessage)
    }
}
