//
//  OnboardingModels.swift
//  Runaway iOS
//
//  Created by Claude on 1/12/26.
//

import Foundation
import SwiftUI

// MARK: - Onboarding State

struct OnboardingState: Codable, Sendable {
    let id: Int?
    let athleteId: Int
    var isCompleted: Bool
    var currentStep: Int
    var movementTestCadence: Double?
    var movementTestVariance: Double?
    var locationPermissionGranted: Bool
    var coachPersonality: CoachPersonality
    var experienceLevel: ExperienceLevel?
    var completedAt: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case athleteId = "athlete_id"
        case isCompleted = "is_completed"
        case currentStep = "current_step"
        case movementTestCadence = "movement_test_cadence"
        case movementTestVariance = "movement_test_variance"
        case locationPermissionGranted = "location_permission_granted"
        case coachPersonality = "coach_personality"
        case experienceLevel = "experience_level"
        case completedAt = "completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // Create new onboarding state
    init(athleteId: Int) {
        self.id = nil
        self.athleteId = athleteId
        self.isCompleted = false
        self.currentStep = 0
        self.movementTestCadence = nil
        self.movementTestVariance = nil
        self.locationPermissionGranted = false
        self.coachPersonality = .balanced
        self.experienceLevel = nil
        self.completedAt = nil
        self.createdAt = nil
        self.updatedAt = nil
    }

    // Full initializer for database responses
    init(id: Int?, athleteId: Int, isCompleted: Bool, currentStep: Int,
         movementTestCadence: Double?, movementTestVariance: Double?,
         locationPermissionGranted: Bool, coachPersonality: CoachPersonality,
         experienceLevel: ExperienceLevel?, completedAt: String?,
         createdAt: String?, updatedAt: String?) {
        self.id = id
        self.athleteId = athleteId
        self.isCompleted = isCompleted
        self.currentStep = currentStep
        self.movementTestCadence = movementTestCadence
        self.movementTestVariance = movementTestVariance
        self.locationPermissionGranted = locationPermissionGranted
        self.coachPersonality = coachPersonality
        self.experienceLevel = experienceLevel
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Onboarding Step

enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome = 0
    case profileSetup = 1
    case goalsSetup = 2
    case experienceAssessment = 3
    case movementTest = 4
    case runnerMindset = 5
    case locationPermission = 6
    case coachSelection = 7
    case completion = 8
    case activityMix = 9
    case trainingSchedule = 10

    static let allCases: [OnboardingStep] = [
        .welcome,
        .profileSetup,
        .goalsSetup,
        .activityMix,
        .trainingSchedule,
        .experienceAssessment,
        .movementTest,
        .locationPermission,
        .coachSelection,
        .completion,
    ]

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .profileSetup: return "About You"
        case .goalsSetup: return "Your Goals"
        case .activityMix: return "Training Mix"
        case .trainingSchedule: return "Your Week"
        case .experienceAssessment: return "Your Experience"
        case .movementTest: return "Movement Test"
        case .runnerMindset: return "Your Mindset"
        case .locationPermission: return "Location"
        case .coachSelection: return "Your Coach"
        case .completion: return "Ready!"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: return "Let's get you set up"
        case .profileSetup: return "Tell us your name"
        case .goalsSetup: return "Set your running targets"
        case .activityMix: return "Choose what belongs in your week"
        case .trainingSchedule: return "Fit training around real life"
        case .experienceAssessment: return "Tell us about your running"
        case .movementTest: return "Quick 30-second assessment"
        case .runnerMindset: return "What drives you to run"
        case .locationPermission: return "Track your runs"
        case .coachSelection: return "Choose your style"
        case .completion: return "You're all set"
        }
    }

    var icon: String {
        switch self {
        case .welcome: return "hand.wave.fill"
        case .profileSetup: return "person.fill"
        case .goalsSetup: return "target"
        case .activityMix: return "figure.mixed.cardio"
        case .trainingSchedule: return "calendar"
        case .experienceAssessment: return "figure.run"
        case .movementTest: return "waveform.path.ecg"
        case .runnerMindset: return "brain.head.profile"
        case .locationPermission: return "location.fill"
        case .coachSelection: return "person.fill.questionmark"
        case .completion: return "checkmark.circle.fill"
        }
    }

    var isSkippable: Bool {
        switch self {
        case .welcome, .profileSetup, .goalsSetup, .activityMix, .trainingSchedule, .completion: return false
        case .experienceAssessment, .movementTest, .runnerMindset, .locationPermission, .coachSelection: return true
        }
    }

    static var totalSteps: Int {
        allCases.count
    }

    var flowIndex: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    var next: OnboardingStep? {
        let nextIndex = flowIndex + 1
        guard Self.allCases.indices.contains(nextIndex) else { return nil }
        return Self.allCases[nextIndex]
    }

    var previous: OnboardingStep? {
        let previousIndex = flowIndex - 1
        guard Self.allCases.indices.contains(previousIndex) else { return nil }
        return Self.allCases[previousIndex]
    }

    static func resumeStep(
        persistedRawValue: Int,
        trainingDraftFlowVersion: Int?
    ) -> OnboardingStep? {
        guard let persisted = OnboardingStep(rawValue: persistedRawValue) else { return nil }
        if persisted == .runnerMindset { return .locationPermission }
        let legacyLaterSteps: Set<OnboardingStep> = [
            .experienceAssessment,
            .movementTest,
            .runnerMindset,
            .locationPermission,
            .coachSelection,
            .completion,
        ]
        if legacyLaterSteps.contains(persisted),
           (trainingDraftFlowVersion ?? 0) < OnboardingAnswers.currentFlowVersion {
            return .activityMix
        }
        return persisted
    }
}

// MARK: - Training Profile Answers

enum OnboardingPrimaryGoal: String, Codable, Sendable {
    case race
    case running
    case generalFitness

    var displayName: String {
        switch self {
        case .race: return "Train for a race"
        case .running: return "Run consistently"
        case .generalFitness: return "Build general fitness"
        }
    }

    var detail: String {
        switch self {
        case .race: return "Build toward a start line with running as the priority."
        case .running: return "Create a repeatable running routine and progress steadily."
        case .generalFitness: return "Balance movement for broad health and fitness."
        }
    }
}

struct OnboardingAnswers: Codable, Equatable, Sendable {
    static let currentFlowVersion = 1

    var primaryGoal: OnboardingPrimaryGoal
    var draft: TrainingProfile
    var flowVersion: Int

    init(
        primaryGoal: OnboardingPrimaryGoal,
        draft: TrainingProfile,
        flowVersion: Int = currentFlowVersion
    ) {
        self.primaryGoal = primaryGoal
        self.draft = draft
        self.flowVersion = flowVersion
    }

    private enum CodingKeys: String, CodingKey {
        case primaryGoal, draft, flowVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primaryGoal = try container.decode(OnboardingPrimaryGoal.self, forKey: .primaryGoal)
        draft = try container.decode(TrainingProfile.self, forKey: .draft)
        flowVersion = try container.decodeIfPresent(Int.self, forKey: .flowVersion) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(primaryGoal, forKey: .primaryGoal)
        try container.encode(draft, forKey: .draft)
        try container.encode(flowVersion, forKey: .flowVersion)
    }

    static func `default`(for goal: OnboardingPrimaryGoal) -> OnboardingAnswers {
        var profile = TrainingProfile.runningFirstDefault
        if goal == .generalFitness {
            profile.activities[0].sessionsPerWeek = 3
        }
        return OnboardingAnswers(primaryGoal: goal, draft: profile)
    }
}

typealias OnboardingTrainingAnswers = OnboardingAnswers

struct OnboardingTrainingDraftStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(for athleteId: Int) throws -> OnboardingAnswers? {
        guard let data = defaults.data(forKey: key(for: athleteId)) else { return nil }
        if let answers = try? JSONDecoder().decode(OnboardingAnswers.self, from: data) {
            return answers
        }
        let legacyProfile = try JSONDecoder().decode(TrainingProfile.self, from: data)
        return OnboardingAnswers(primaryGoal: .running, draft: legacyProfile)
    }

    func save(_ answers: OnboardingAnswers, for athleteId: Int) throws {
        defaults.set(try JSONEncoder().encode(answers), forKey: key(for: athleteId))
    }

    func clear(for athleteId: Int) {
        defaults.removeObject(forKey: key(for: athleteId))
    }

    private func key(for athleteId: Int) -> String {
        "onboarding.trainingProfileDraft.\(athleteId)"
    }
}

// MARK: - Coach Personality

enum CoachPersonality: String, Codable, CaseIterable, Sendable {
    case motivational = "motivational"
    case analytical = "analytical"
    case balanced = "balanced"

    var displayName: String {
        switch self {
        case .motivational: return "Motivational"
        case .analytical: return "Analytical"
        case .balanced: return "Balanced"
        }
    }

    var description: String {
        switch self {
        case .motivational:
            return "Focuses on encouragement, celebrates wins, and keeps you pumped up"
        case .analytical:
            return "Data-driven insights, detailed metrics, and performance analysis"
        case .balanced:
            return "A mix of motivation and analysis tailored to the moment"
        }
    }

    var icon: String {
        switch self {
        case .motivational: return "flame.fill"
        case .analytical: return "chart.line.uptrend.xyaxis"
        case .balanced: return "scale.3d"
        }
    }

    var color: Color {
        switch self {
        case .motivational: return .orange
        case .analytical: return .blue
        case .balanced: return .purple
        }
    }

    var sampleMessage: String {
        switch self {
        case .motivational:
            return "\"You're crushing it! That pace is fire! 🔥 Keep pushing!\""
        case .analytical:
            return "\"Your pace is 8:23/mi, 12% faster than your 30-day average. Heart rate zone 3.\""
        case .balanced:
            return "\"Great pace today! You're running 12% faster than usual. Keep it up!\""
        }
    }
}

// MARK: - Experience Level

enum ExperienceLevel: String, Codable, CaseIterable, Sendable {
    case beginner = "beginner"
    case intermediate = "intermediate"
    case advanced = "advanced"
    case skip = "skip"

    var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        case .skip: return "Skip"
        }
    }

    var description: String {
        switch self {
        case .beginner:
            return "New to running or getting back into it"
        case .intermediate:
            return "Run regularly, familiar with training concepts"
        case .advanced:
            return "Experienced runner, focused on performance"
        case .skip:
            return "I'll set this up later"
        }
    }

    var icon: String {
        switch self {
        case .beginner: return "leaf.fill"
        case .intermediate: return "figure.run"
        case .advanced: return "trophy.fill"
        case .skip: return "arrow.right.circle"
        }
    }

    var color: Color {
        switch self {
        case .beginner: return .green
        case .intermediate: return .blue
        case .advanced: return .orange
        case .skip: return .gray
        }
    }

    var weeklyMilesRange: String {
        switch self {
        case .beginner: return "0-10 miles/week"
        case .intermediate: return "10-30 miles/week"
        case .advanced: return "30+ miles/week"
        case .skip: return ""
        }
    }
}

// MARK: - Movement Test Result

struct MovementTestResult: Codable, Sendable {
    let averageCadence: Double  // Steps per minute
    let variance: Double        // Cadence consistency
    let testDuration: TimeInterval
    let sampleCount: Int

    var cadenceAssessment: CadenceAssessment {
        if averageCadence < 150 {
            return .low
        } else if averageCadence < 170 {
            return .moderate
        } else if averageCadence < 185 {
            return .good
        } else {
            return .excellent
        }
    }

    var consistencyAssessment: String {
        if variance < 5 {
            return "Very consistent"
        } else if variance < 10 {
            return "Consistent"
        } else if variance < 15 {
            return "Moderate variation"
        } else {
            return "Variable"
        }
    }
}

enum CadenceAssessment: String {
    case low = "Low"
    case moderate = "Moderate"
    case good = "Good"
    case excellent = "Excellent"

    var color: Color {
        switch self {
        case .low: return .orange
        case .moderate: return .yellow
        case .good: return .green
        case .excellent: return .blue
        }
    }

    var recommendation: String {
        switch self {
        case .low:
            return "Try taking quicker, shorter steps to improve efficiency"
        case .moderate:
            return "Your cadence is developing well, keep practicing"
        case .good:
            return "Great cadence! This helps reduce injury risk"
        case .excellent:
            return "Elite-level cadence! You're running efficiently"
        }
    }
}

// MARK: - Onboarding Progress

struct OnboardingProgress {
    let currentStep: OnboardingStep
    let totalSteps: Int

    var progress: Double {
        return Double(currentStep.flowIndex) / Double(totalSteps - 1)
    }

    var isComplete: Bool {
        return currentStep == .completion
    }

    var stepsRemaining: Int {
        return totalSteps - currentStep.flowIndex - 1
    }
}
