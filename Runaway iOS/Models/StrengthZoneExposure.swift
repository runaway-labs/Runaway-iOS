import Foundation

struct StrengthZoneExposure: Equatable, Sendable {
    let zone: StrengthZone
    let effectiveWorkingSets: Double
    let lastTrainedAt: Date
    let sourceResultIDs: Set<UUID>
}

struct StrengthZoneHistorySnapshot: Equatable, Sendable {
    let generatedAt: Date
    let exposures: [StrengthZone: StrengthZoneExposure]
    let hasUnattributedStrengthWork: Bool
}

enum StrengthZoneHistoryContext: Equatable, Sendable {
    case trainedYesterday
    case daysAgo(Int)
    case lowVolume
    case recovered
    case noRecentData
}

enum StrengthZoneHistoryPresentation {
    static func context(
        for exposure: StrengthZoneExposure?,
        now: Date,
        calendar: Calendar = .current
    ) -> StrengthZoneHistoryContext {
        guard let exposure else { return .noRecentData }
        let trainedDay = calendar.startOfDay(for: exposure.lastTrainedAt)
        let today = calendar.startOfDay(for: now)
        guard let elapsed = calendar.dateComponents([.day], from: trainedDay, to: today).day,
              (0...42).contains(elapsed) else { return .noRecentData }
        if elapsed == 1 { return .trainedYesterday }
        if exposure.effectiveWorkingSets < 2 { return .lowVolume }
        if elapsed <= 4 { return .recovered }
        return .daysAgo(elapsed)
    }
}
