import Foundation

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
