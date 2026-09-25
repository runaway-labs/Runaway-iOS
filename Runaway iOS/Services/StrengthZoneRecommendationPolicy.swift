import Foundation

enum StrengthZoneRecommendationPolicy {
    static let version = "strength-zone-recommendation-v1"

    private enum Weight {
        static let base = 10.0
        static let primaryGoal = 30.0
        static let secondaryGoal = 12.0
        static let weeklyGap = 16.0
        static let recovered = 8.0
        static let unknownHistory = 2.0
        static let recentlyTrained = -40.0
        static let protectRun = -25.0
    }

    static func recommendations(
        for context: StrengthZoneRecommendationContext
    ) -> [StrengthZoneRecommendation] {
        let preferences = context.athleteProfile.resolvedStrengthRecommendations
        guard preferences.suggestionsEnabled else { return [] }

        let available = Set(preferences.availableZones)
        let protectedLegs = hasNearbyDemandingRun(in: context)

        var ranked = StrengthZone.allCases.compactMap { zone -> StrengthZoneRecommendation? in
            guard available.contains(zone) else { return nil }

            let historyContext = StrengthZoneHistoryPresentation.context(
                for: context.history.exposures[zone],
                now: context.date,
                calendar: context.calendar
            )
            var score = Weight.base
            var reasons: [StrengthZoneRecommendationReason] = []

            applyGoalSupport(
                for: zone,
                outcomes: context.athleteProfile.outcomes,
                score: &score,
                reasons: &reasons
            )

            switch historyContext {
            case .trainedYesterday:
                score += Weight.recentlyTrained
                reasons.append(.recentlyTrained)
            case .daysAgo(let days):
                if days >= 5 {
                    score += Weight.recovered
                    reasons.append(.wellRecovered)
                }
                if days >= 7 {
                    score += Weight.weeklyGap
                    reasons.append(.weeklyVolumeGap)
                }
            case .lowVolume:
                score += Weight.weeklyGap
                reasons.append(.weeklyVolumeGap)
            case .recovered:
                score += Weight.recovered
                reasons.append(.wellRecovered)
            case .noRecentData:
                score += Weight.unknownHistory
                score += Weight.weeklyGap
                reasons.append(.insufficientHistory)
                reasons.append(.weeklyVolumeGap)
            }

            if zone == .legs, protectedLegs {
                score += Weight.protectRun
                reasons.append(.protectUpcomingRun)
            }

            let uniqueReasons = reasons.removingDuplicates()
            return StrengthZoneRecommendation(
                zone: zone,
                score: score,
                reasons: uniqueReasons,
                context: historyContext,
                isSelectable: true,
                isCoachPick: false,
                explanation: explanation(for: zone, reasons: uniqueReasons)
            )
        }

        let zoneOrder = Dictionary(uniqueKeysWithValues: StrengthZone.allCases.enumerated().map { ($1, $0) })
        ranked.sort {
            if $0.score == $1.score {
                return zoneOrder[$0.zone, default: 0] < zoneOrder[$1.zone, default: 0]
            }
            return $0.score > $1.score
        }

        var picksRemaining = 2
        for index in ranked.indices where picksRemaining > 0 {
            guard !ranked[index].reasons.contains(.recentlyTrained) else { continue }
            ranked[index].isCoachPick = true
            picksRemaining -= 1
        }

        return ranked
    }

    private static func applyGoalSupport(
        for zone: StrengthZone,
        outcomes: [AthleteOutcome]?,
        score: inout Double,
        reasons: inout [StrengthZoneRecommendationReason]
    ) {
        var contribution = 0.0

        let outcomes = Set(outcomes ?? AthleteOutcome.defaults)

        if outcomes.contains(.durableCore), zone == .core {
            contribution += Weight.primaryGoal
        }

        if outcomes.contains(.leanStrong) {
            contribution += zone == .core ? Weight.secondaryGoal * 0.75 : Weight.secondaryGoal
        }

        if outcomes.contains(.marathonReady), zone == .core || zone == .legs {
            contribution += Weight.secondaryGoal * 0.5
        }

        guard contribution > 0 else { return }
        score += contribution
        reasons.append(.goalSupport)
    }

    private static func hasNearbyDemandingRun(
        in context: StrengthZoneRecommendationContext
    ) -> Bool {
        let demandingTypes: Set<WorkoutType> = [.longRun, .tempoRun, .intervalRun, .hillRun]

        return context.weeklyPlan.workouts.contains { workout in
            guard demandingTypes.contains(workout.workoutType) else { return false }
            let distance = abs(context.calendar.dateComponents([.day], from: context.date, to: workout.date).day ?? 99)
            return distance <= 1
        }
    }

    private static func explanation(
        for zone: StrengthZone,
        reasons: [StrengthZoneRecommendationReason]
    ) -> String {
        let phrases = reasons.prefix(2).map { reason in
            switch reason {
            case .goalSupport:
                return "supports your goals"
            case .weeklyVolumeGap:
                return "needs attention this week"
            case .wellRecovered:
                return "looks ready for productive work"
            case .protectUpcomingRun:
                return "keeps your nearby run protected"
            case .recentlyTrained:
                return "was trained recently"
            case .insufficientHistory:
                return "has limited recent history"
            }
        }

        guard let first = phrases.first else {
            return "Available for today's strength session."
        }

        let body = ([first] + phrases.dropFirst()).joined(separator: " and ")
        return "\(zone.rawValue.capitalized) \(body)."
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
