import Foundation
import Testing
@testable import Runaway_iOS

@Suite("Strength zone recommendations")
struct StrengthZoneRecommendationPolicyTests {
    @Test("Disabled suggestions return no recommendation ranking")
    func suggestionsCanBeDisabled() {
        var context = makeContext()
        context.athleteProfile.strengthRecommendations = StrengthRecommendationPreferences(
            suggestionsEnabled: false, availableZones: Set(StrengthZone.allCases)
        )

        #expect(StrengthZoneRecommendationPolicy.recommendations(for: context).isEmpty)
    }

    @Test("Unavailable zones are never recommended")
    func exclusionsAreAuthoritative() {
        var context = makeContext()
        context.athleteProfile.strengthRecommendations = StrengthRecommendationPreferences(
            suggestionsEnabled: true, availableZones: [.chest, .back, .core]
        )

        let values = StrengthZoneRecommendationPolicy.recommendations(for: context)
        #expect(Set(values.map(\.zone)) == [.chest, .back, .core])
    }

    @Test("Durable core and lean strength goals shape coach picks")
    func goalsShapeRanking() {
        var context = makeContext()
        context.athleteProfile.outcomes = [.durableCore, .leanStrong]

        let values = StrengthZoneRecommendationPolicy.recommendations(for: context)

        #expect(values.first?.zone == .core)
        #expect(values.first?.reasons.contains(.goalSupport) == true)
        #expect(values.filter(\.isCoachPick).count == 2)
    }

    @Test("Recent attributable work is penalized without disabling the zone")
    func recentWorkPenalty() {
        var context = makeContext()
        context.history = snapshot(zone: .core, sets: 5, daysAgo: 1, now: context.date)

        let core = StrengthZoneRecommendationPolicy.recommendations(for: context)
            .first { $0.zone == .core }

        #expect(core?.reasons.contains(.recentlyTrained) == true)
        #expect(core?.isSelectable == true)
        #expect(core?.isCoachPick == false)
    }

    @Test("Missing history stays low-confidence instead of becoming extreme need")
    func insufficientHistoryIsControlled() {
        let values = StrengthZoneRecommendationPolicy.recommendations(for: makeContext())

        #expect(values.allSatisfy { $0.reasons.contains(.insufficientHistory) })
        #expect(values.allSatisfy { $0.context == .noRecentData })
        #expect(values.map(\.score).allSatisfy { $0 < 100 })
    }

    @Test("Upcoming long run deprioritizes but never disables legs")
    func upcomingLongRunDeprioritizesButDoesNotDisableLegs() {
        var context = makeContext()
        let tomorrow = context.calendar.date(byAdding: .day, value: 1, to: context.date)!
        context.weeklyPlan = makePlan(workouts: [DailyWorkout(
            id: "long-run", date: tomorrow, dayOfWeek: .from(date: tomorrow),
            workoutType: .longRun, title: "Long Run", description: "Aerobic long run",
            duration: 90, distance: 8, targetPace: "Easy", exercises: nil,
            isCompleted: false, completedActivityId: nil
        )], now: context.date, calendar: context.calendar)

        let legs = StrengthZoneRecommendationPolicy.recommendations(for: context)
            .first { $0.zone == .legs }

        #expect(legs != nil)
        #expect(legs?.reasons.contains(.protectUpcomingRun) == true)
        #expect(legs?.isSelectable == true)
    }

    @Test("Low attributable weekly volume is explained as a gap")
    func weeklyVolumeGapIsExplicit() {
        var context = makeContext()
        context.history = snapshot(zone: .chest, sets: 1, daysAgo: 3, now: context.date)

        let chest = StrengthZoneRecommendationPolicy.recommendations(for: context)
            .first { $0.zone == .chest }

        #expect(chest?.reasons.contains(.weeklyVolumeGap) == true)
        #expect(chest?.explanation.isEmpty == false)
    }

    private func makeContext() -> StrengthZoneRecommendationContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var athlete = AthleteTrainingProfile(athleteID: 42)
        athlete.outcomes = [.durableCore, .leanStrong]
        athlete.strengthRecommendations = .default
        return StrengthZoneRecommendationContext(
            athleteProfile: athlete,
            trainingProfile: .runningFirstDefault,
            weeklyPlan: makePlan(workouts: [], now: date, calendar: calendar),
            history: StrengthZoneHistorySnapshot(
                generatedAt: date, exposures: [:], hasUnattributedStrengthWork: false
            ),
            date: date,
            calendar: calendar
        )
    }

    private func snapshot(zone: StrengthZone, sets: Double, daysAgo: Int, now: Date) -> StrengthZoneHistorySnapshot {
        let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: -daysAgo, to: now)!
        return StrengthZoneHistorySnapshot(
            generatedAt: now,
            exposures: [zone: StrengthZoneExposure(
                zone: zone, effectiveWorkingSets: sets, lastTrainedAt: date, sourceResultIDs: [UUID()]
            )],
            hasUnattributedStrengthWork: false
        )
    }

    private func makePlan(workouts: [DailyWorkout], now: Date, calendar: Calendar) -> WeeklyTrainingPlan {
        let start = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        return WeeklyTrainingPlan(
            id: "recommendation-policy-week", athleteId: 42, weekStartDate: start,
            weekEndDate: calendar.date(byAdding: .day, value: 6, to: start)!,
            workouts: workouts, weekNumber: 1, totalMileage: 0,
            focusArea: "Balanced", notes: nil, generatedAt: now, goalId: nil
        )
    }
}
