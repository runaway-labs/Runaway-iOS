import Foundation

enum StrengthZoneRecommendationReason: String, Codable, Hashable, Sendable {
    case goalSupport
    case weeklyVolumeGap
    case wellRecovered
    case protectUpcomingRun
    case recentlyTrained
    case insufficientHistory
}

struct StrengthZoneRecommendation: Identifiable, Equatable, Sendable {
    let zone: StrengthZone
    let score: Double
    let reasons: [StrengthZoneRecommendationReason]
    let context: StrengthZoneHistoryContext
    let isSelectable: Bool
    var isCoachPick: Bool
    let explanation: String

    var id: StrengthZone { zone }
}

struct StrengthZoneRecommendationContext: Sendable {
    var athleteProfile: AthleteTrainingProfile
    var trainingProfile: TrainingProfile
    var weeklyPlan: WeeklyTrainingPlan
    var history: StrengthZoneHistorySnapshot
    var date: Date
    var calendar: Calendar
}
