//
//  Runaway_iOSUITests.swift
//  Runaway iOSUITests
//
//  Created by Jack Rudelic on 2/18/25.
//

import XCTest

final class Runaway_iOSUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testStrengthZoneWorkoutCanBeBuiltAndCommitted() throws {
        let app = XCUIApplication()
        app.launchEnvironment["RUNAWAY_UI_TEST_SCENARIO"] = "strength-zone-workout"
        app.launch()

        let change = app.buttons["Change"]
        XCTAssertTrue(change.waitForExistence(timeout: 10))
        change.tap()

        let chooseSomethingElse = app.buttons["Choose something else"]
        if chooseSomethingElse.waitForExistence(timeout: 3) {
            chooseSomethingElse.tap()
        }
        let strength = app.buttons["todayChoice.strength"]
        XCTAssertTrue(strength.waitForExistence(timeout: 5))
        strength.tap()

        let back = app.buttons["Back"]
        let core = app.buttons["Core"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(core.exists)
        back.tap()
        core.tap()
        app.buttons["Build workout"].tap()

        XCTAssertTrue(app.staticTexts["Back + Core"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'sets'")).count, 0)
        app.buttons["Use this workout"].tap()

        let commit = app.buttons["Commit"]
        if commit.waitForExistence(timeout: 3) { commit.tap() }
        app.buttons["Plan"].tap()
        XCTAssertTrue(app.staticTexts["Back + Core"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testStrengthRecommendationSettingsPersistAcrossPresentation() throws {
        let app = XCUIApplication()
        app.launchEnvironment["RUNAWAY_UI_TEST_SCENARIO"] = "strength-zone-settings"
        app.launch()

        app.buttons["You"].tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        app.buttons["Strength recommendations"].tap()

        let suggestions = app.switches["Zone suggestions"]
        let legs = app.switches["Legs"]
        XCTAssertTrue(suggestions.waitForExistence(timeout: 5))
        XCTAssertTrue(legs.exists)
        let originalSuggestions = suggestions.value as? String
        let originalLegs = legs.value as? String
        suggestions.tap()
        legs.tap()
        app.buttons["Save"].tap()

        app.buttons["Strength recommendations"].tap()
        XCTAssertNotEqual(app.switches["Zone suggestions"].value as? String, originalSuggestions)
        XCTAssertNotEqual(app.switches["Legs"].value as? String, originalLegs)
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
