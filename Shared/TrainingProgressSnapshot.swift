import Foundation

enum WidgetPrescriptionStatus: String, Codable, Equatable, Sendable {
    case scheduled
    case committed
    case partial
    case completed

    static func resolve(isCompleted: Bool, isPartial: Bool, isCommitted: Bool = false) -> Self {
        if isPartial { return .partial }
        if isCompleted { return .completed }
        return isCommitted ? .committed : .scheduled
    }

    var label: String {
        switch self {
        case .scheduled: return "Up next"
        case .committed: return "Committed"
        case .partial: return "Partial"
        case .completed: return "Completed"
        }
    }
}

struct WidgetPrescriptionSnapshot: Codable, Equatable, Sendable {
    static let cacheKey = "widget_prescription_snapshot_v1"

    let title: String
    let detail: String
    let status: WidgetPrescriptionStatus
    var prescriptionFingerprint: String? = nil

    static func cached(in defaults: UserDefaults?) -> Self? {
        guard let data = defaults?.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

enum PerformanceCoachIntentAction: String, Codable, Sendable {
    case commitRecommendation
    case reviewOptions
    case viewCommittedWorkout
}

struct PerformanceCoachIntentRequest: Codable, Equatable, Sendable {
    static let cacheKey = "performance_coach_intent_request_v1"
    static let maximumAge: TimeInterval = 10 * 60

    let athleteID: Int
    let action: PerformanceCoachIntentAction
    let prescriptionFingerprint: String?
    let createdAt: Date

    var isCurrent: Bool {
        Date().timeIntervalSince(createdAt) <= Self.maximumAge
    }

    func store(in defaults: UserDefaults?) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults?.set(data, forKey: Self.cacheKey)
    }

    static func cached(in defaults: UserDefaults?) -> Self? {
        guard let data = defaults?.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    static func clear(in defaults: UserDefaults?) {
        defaults?.removeObject(forKey: cacheKey)
    }
}

enum CoachWidgetDecisionState: String, Codable, Equatable, Sendable {
    case proposed
    case applied
    case rejected
    case superseded
    case undone
    case blocked
}

struct CoachWidgetSnapshot: Codable, Equatable, Sendable {
    static let cacheKey = "coach_widget_snapshot_v1"
    static let maximumAge: TimeInterval = 4 * 60 * 60

    let athleteID: Int
    let decisionID: UUID
    let state: CoachWidgetDecisionState
    let headline: String
    let shortReason: String
    let updatedAt: Date
    let undoAvailable: Bool
    let activeWorkoutID: String

    func isCurrent(at date: Date = Date()) -> Bool {
        date >= updatedAt && date.timeIntervalSince(updatedAt) <= Self.maximumAge
    }

    static func cached(in defaults: UserDefaults?, athleteID: Int) -> Self? {
        guard athleteID > 0,
              let data = defaults?.data(forKey: cacheKey),
              let snapshot = try? JSONDecoder().decode(Self.self, from: data),
              snapshot.athleteID == athleteID else { return nil }
        return snapshot
    }
}

enum CoachWidgetAction: String, Codable, Sendable {
    case review
    case accept
    case keepOriginal
    case undo
    case reevaluate
}

struct CoachWidgetActionRequest: Codable, Sendable {
    static let cacheKey = "coach_widget_action_request_v1"
    let athleteID: Int
    let decisionID: UUID?
    let action: CoachWidgetAction
    let selectedPath: String?
    let createdAt: Date

    func store(in defaults: UserDefaults?) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults?.set(data, forKey: Self.cacheKey)
    }
}

enum ProgressActivityKind: String, Codable, CaseIterable, Sendable {
    case run, walk, strength, bike, swim, hike, mobility, other

    init(_ value: String) {
        switch value.lowercased().filter({ $0.isLetter }) {
        case "run", "running", "trailrun", "trailrunning", "virtualrun", "treadmill", "treadmillrun", "jog", "jogging": self = .run
        case "walk", "walking", "virtualwalk": self = .walk
        case "strength", "strengthtraining", "weighttraining", "workout", "functionalstrengthtraining", "traditionalstrengthtraining", "crossfit": self = .strength
        case "ride", "bikeride", "bike", "cycling", "virtualride", "ebikeride", "mountainbikeride", "gravelride", "indoorcycling": self = .bike
        case "swim", "swimming": self = .swim
        case "hike", "hiking": self = .hike
        case "yoga", "pilates", "mobility", "stretching", "flexibility", "stretchmobility": self = .mobility
        default: self = .other
        }
    }

    var title: String { rawValue == "bike" ? "Bike" : rawValue.capitalized }
    var symbol: String {
        switch self {
        case .run: return "figure.run"
        case .walk: return "figure.walk"
        case .strength: return "dumbbell.fill"
        case .bike: return "bicycle"
        case .swim: return "figure.pool.swim"
        case .hike: return "figure.hiking"
        case .mobility: return "figure.mind.and.body"
        case .other: return "figure.mixed.cardio"
        }
    }
}

struct TrainingProgressActivity: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    let athleteID: Int
    let name: String
    let type: String
    let date: Date
    let meters: Double
    let seconds: Double
    let polyline: String
    var kind: ProgressActivityKind { ProgressActivityKind(type) }
}

struct TrainingProgressSnapshot: Codable, Equatable, Sendable {
    static let cacheKey = "training_progress_snapshot_v1"
    static let athleteKey = "training_progress_athlete_id"
    static let metersPerMile = 1609.344

    struct Totals: Codable, Equatable, Sendable {
        var runningMeters = 0.0
        var distanceMeters = 0.0
        var runs = 0
        var sessions = 0
        var seconds = 0.0
        var activeDays = 0
        static let zero = Self()
    }

    struct Segment: Codable, Equatable, Identifiable, Sendable {
        let kind: ProgressActivityKind
        let seconds: Double
        var id: String { kind.rawValue }
    }

    struct Day: Codable, Equatable, Identifiable, Sendable {
        let date: Date
        let segments: [Segment]
        var id: Date { date }
        var seconds: Double { segments.reduce(0) { $0 + $1.seconds } }
    }

    let athleteID: Int
    let weekStart: Date
    let monthStart: Date
    let yearStart: Date
    let timeZoneIdentifier: String
    let refreshedAt: Date
    let week: Totals
    let month: Totals
    let year: Totals
    let days: [Day]

    func isCurrent(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        timeZoneIdentifier == calendar.timeZone.identifier
            && weekStart == TrainingProgressPolicy.weekStart(for: date, calendar: calendar)
            && calendar.isDate(monthStart, equalTo: date, toGranularity: .month)
            && calendar.isDate(yearStart, equalTo: date, toGranularity: .year)
    }

    static func cached(in defaults: UserDefaults?, athleteID: Int) -> Self? {
        guard let data = defaults?.data(forKey: cacheKey),
              let snapshot = try? JSONDecoder().decode(Self.self, from: data),
              snapshot.athleteID == athleteID else { return nil }
        return snapshot
    }
}
