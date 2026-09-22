//
//  CoachSettings.swift
//  Runaway iOS
//
//  Created by Claude on 12/23/25.
//

import Foundation
import Combine

// MARK: - Coach Settings

/// User-configurable settings for audio coaching during runs
struct CoachSettings: Codable {

    // MARK: - Master Toggle

    /// Whether audio coaching is enabled
    /// NOTE: Disabled by default until background audio mode is re-enabled
    var isEnabled: Bool = false

    // MARK: - Split Announcements

    /// Announce completed miles/kilometers
    var announceSplits: Bool = true

    /// Level of detail in split announcements
    var splitDetail: SplitDetail = .detailed

    /// Distance unit for splits
    var distanceUnit: DistanceUnit = .miles

    // MARK: - Pace Coaching

    /// Alert when pace drifts from target/average
    var paceAlerts: Bool = true

    /// Threshold for pace drift alerts (0.10 = 10%)
    var paceDriftThreshold: Double = 0.10

    /// Target pace in seconds per mile (nil = use average)
    var targetPace: TimeInterval? = nil

    // MARK: - Zone Coaching (Phase 2)

    /// Alert on heart rate zone transitions
    var zoneAlerts: Bool = true

    /// Which zones trigger alerts (4, 5 = high intensity)
    var alertOnZones: Set<Int> = [4, 5]

    /// Warn after extended time in high zones
    var zoneDurationWarnings: Bool = true

    /// Zone 4 warning threshold in seconds
    var zone4WarningTime: TimeInterval = 480 // 8 minutes

    /// Zone 5 warning threshold in seconds
    var zone5WarningTime: TimeInterval = 180 // 3 minutes

    // MARK: - Check-ins

    /// Enable periodic "How are you feeling?" prompts
    var enableCheckIns: Bool = true

    /// Interval between check-ins in seconds
    var checkInInterval: TimeInterval = 300 // 5 minutes

    /// Use smart timing (avoid interrupting hard efforts)
    var smartCheckInTiming: Bool = true

    // MARK: - Hydration

    /// Enable hydration reminders
    var hydrationReminders: Bool = false

    /// Hydration reminder interval in seconds
    var hydrationInterval: TimeInterval = 900 // 15 minutes

    /// Start hydration reminders after this duration
    var hydrationStartAfter: TimeInterval = 1200 // 20 minutes

    // MARK: - Heart Rate Settings

    /// User's maximum heart rate (nil = estimate from age)
    var maxHeartRate: Int? = nil

    /// User's resting heart rate (optional, for Karvonen formula)
    var restingHeartRate: Int? = nil

    // MARK: - Identity Voice Cues

    /// Retained as a decoding-compatible no-op after Running Mindset was retired.
    var enableIdentityVoiceCues: Bool {
        get { false }
        set { }
    }

    // MARK: - Voice Settings

    /// Speech rate (0.0 - 1.0, default 0.5)
    var speechRate: Float = 0.50

    /// Voice volume (0.0 - 1.0, default 0.8 - doesn't blast over music)
    var volume: Float = 0.8

    /// Voice identifier (nil = system default)
    var voiceIdentifier: String? = nil

    /// Duck other audio instead of pausing
    var duckOtherAudio: Bool = true

    /// Duck music volume during prompts
    var duckMusicDuringPrompts: Bool = true

    // MARK: - Voice Input

    /// Enable voice responses to prompts
    var enableVoiceInput: Bool = true

    /// Enable shake gesture to activate voice input
    var enableShakeToSpeak: Bool = true

    /// Auto-listen after check-in prompts (e.g., "How are you feeling?")
    var autoListenAfterCheckIn: Bool = true

    /// Timeout for voice input in seconds
    var voiceInputTimeout: TimeInterval = 5.0
}

// MARK: - Supporting Types

enum SplitDetail: String, Codable, CaseIterable {
    case off = "off"
    case basic = "basic"           // "Mile 3. 8:42"
    case detailed = "detailed"     // "Mile 3 complete. 8:42 pace, 10 seconds faster. Heart rate 156."

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .basic: return "Basic"
        case .detailed: return "Detailed"
        }
    }
}

enum DistanceUnit: String, Codable, CaseIterable, Sendable {
    case miles = "miles"
    case kilometers = "kilometers"

    var displayName: String {
        switch self {
        case .miles: return "Miles"
        case .kilometers: return "Kilometers"
        }
    }

    var metersPerUnit: Double {
        switch self {
        case .miles: return 1609.34
        case .kilometers: return 1000.0
        }
    }

    var abbreviation: String {
        switch self {
        case .miles: return "mi"
        case .kilometers: return "km"
        }
    }
}

// MARK: - Settings Storage

final class CoachSettingsStore: ObservableObject {

    static let shared = CoachSettingsStore()

    private let userDefaults: UserDefaults
    private let settingsKey = "coach_settings"

    private init() {
        // Use app group for widget access if needed
        self.userDefaults = UserDefaults(suiteName: "group.com.jackrudelic.runawayios") ?? .standard
        // Load initial settings
        if let data = userDefaults.data(forKey: settingsKey),
           let loaded = try? JSONDecoder().decode(CoachSettings.self, from: data) {
            self._settings = Published(initialValue: loaded)
        } else {
            self._settings = Published(initialValue: CoachSettings())
        }
    }

    /// Current settings (published for SwiftUI observation)
    @Published var settings: CoachSettings {
        didSet {
            saveSettings()
        }
    }

    private func loadSettings() -> CoachSettings {
        guard let data = userDefaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(CoachSettings.self, from: data) else {
            return CoachSettings()
        }
        return settings
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            userDefaults.set(data, forKey: settingsKey)
        }
    }

    /// Reset to defaults
    func resetToDefaults() {
        settings = CoachSettings()
    }
}
