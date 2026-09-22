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

    func perform() async throws -> some ReturnsValue<String> & ProvidesDialog {
        let defaults = UserDefaults(suiteName: "group.com.jackrudelic.runawayios")
        let athleteID = defaults?.integer(forKey: TrainingProgressSnapshot.athleteKey) ?? 0
        let coach = CoachWidgetSnapshot.cached(in: defaults, athleteID: athleteID)
        let prescription = WidgetPrescriptionSnapshot.cached(in: defaults)
        let response: String
        if let coach, coach.isCurrent() {
            response = "\(coach.headline). \(coach.shortReason)."
        } else if let prescription {
            response = "\(prescription.status.label): \(prescription.title), \(prescription.detail)."
        } else {
            response = defaults?.string(forKey: "becoming_headline") ?? "Open Runaway for today's grounded training brief."
        }
        return .result(value: response, dialog: IntentDialog(stringLiteral: response))
    }
}

struct ReevaluateTrainingIntent: AppIntent {
    static var title: LocalizedStringResource = "Reevaluate Today's Training"
    static var description = IntentDescription("Ask Runaway to reevaluate today's prescription from current training data.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.com.jackrudelic.runawayios")
        CoachWidgetActionRequest(
            athleteID: defaults?.integer(forKey: TrainingProgressSnapshot.athleteKey) ?? 0,
            decisionID: nil,
            action: .reevaluate,
            selectedPath: nil,
            createdAt: Date()
        ).store(in: defaults)
        return .result()
    }
}

// MARK: - Performance Coach

struct CommitWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Commit to Today's Workout"
    static var description = IntentDescription("Commit to the exact workout currently published by Runaway.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let defaults = UserDefaults(suiteName: "group.com.jackrudelic.runawayios")
        guard let prescription = WidgetPrescriptionSnapshot.cached(in: defaults),
              let fingerprint = prescription.prescriptionFingerprint else {
            return .result(dialog: "Open Runaway to review today's current workout.")
        }
        if prescription.status == .committed {
            return .result(dialog: "You're already committed to \(prescription.title).")
        }
        PerformanceCoachIntentRequest(
            athleteID: defaults?.integer(forKey: TrainingProgressSnapshot.athleteKey) ?? 0,
            action: .commitRecommendation,
            prescriptionFingerprint: fingerprint,
            createdAt: Date()
        ).store(in: defaults)
        return .result(dialog: "Runaway will verify and commit \(prescription.title).")
    }
}

struct ReviewWorkoutOptionsIntent: AppIntent {
    static var title: LocalizedStringResource = "Review Workout Options"
    static var description = IntentDescription("Review complete alternatives and their effect on your training week.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.com.jackrudelic.runawayios")
        PerformanceCoachIntentRequest(
            athleteID: defaults?.integer(forKey: TrainingProgressSnapshot.athleteKey) ?? 0,
            action: .reviewOptions,
            prescriptionFingerprint: WidgetPrescriptionSnapshot.cached(in: defaults)?.prescriptionFingerprint,
            createdAt: Date()
        ).store(in: defaults)
        return .result()
    }
}

struct ViewCommittedWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "View Committed Workout"
    static var description = IntentDescription("Open the exact workout you committed to today.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.com.jackrudelic.runawayios")
        PerformanceCoachIntentRequest(
            athleteID: defaults?.integer(forKey: TrainingProgressSnapshot.athleteKey) ?? 0,
            action: .viewCommittedWorkout,
            prescriptionFingerprint: WidgetPrescriptionSnapshot.cached(in: defaults)?.prescriptionFingerprint,
            createdAt: Date()
        ).store(in: defaults)
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
