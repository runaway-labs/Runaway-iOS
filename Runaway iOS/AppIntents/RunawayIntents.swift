//
//  RunawayIntents.swift
//  Runaway iOS
//
//  App Intents for Siri and Shortcuts
//

import AppIntents
import Foundation

// MARK: - Check Training Phase

struct CheckTrainingPhaseIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Training Phase"
    static var description = IntentDescription("See your current training phase and locally generated guidance.")

    func perform() async throws -> some ReturnsValue<String> & ProvidesDialog {
        let defaults = UserDefaults(suiteName: "group.com.jackrudelic.runawayios")
        let phase = defaults?.string(forKey: "current_training_phase") ?? "Training steady"
        let message = defaults?.string(forKey: "becoming_headline") ?? "Keep the week moving."
        let response = "\(phase). \(message)"
        return .result(value: response, dialog: IntentDialog(stringLiteral: response))
    }
}

// MARK: - Daily Brief

struct GetDailyBriefIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Daily Brief"
    static var description = IntentDescription("Get your Runaway daily training brief.")
    static var openAppWhenRun = true

    func perform() async throws -> some OpensIntent {
        return .result()
    }
}

// MARK: - Race Countdown

struct CheckRaceCountdownIntent: AppIntent {
    static var title: LocalizedStringResource = "Race Countdown"
    static var description = IntentDescription("Check how many days until your next race.")

    func perform() async throws -> some ReturnsValue<Int> & ProvidesDialog {
        let defaults = UserDefaults(suiteName: "group.com.jackrudelic.runawayios")
        let days = defaults?.integer(forKey: "days_until_race") ?? 0
        let raceName = defaults?.string(forKey: "next_race_name") ?? "your race"

        if days > 0 {
            let response = "\(days) days until \(raceName)."
            return .result(value: days, dialog: IntentDialog(stringLiteral: response))
        } else {
            let response = "No upcoming race set. Add a goal in Runaway."
            return .result(value: 0, dialog: IntentDialog(stringLiteral: response))
        }
    }
}
