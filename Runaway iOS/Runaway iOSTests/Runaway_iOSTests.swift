//
//  Runaway_iOSTests.swift
//  Runaway iOSTests
//
//  Created by Jack Rudelic on 2/18/25.
//

import Foundation
import Testing
@testable import Runaway_iOS

struct Runaway_iOSTests {

    @Test func activityDatesUseCalendarDaysInsteadOfRollingTwentyFourHours() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Chicago"))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 3, hour: 13, minute: 18
        )))
        let priorCalendarDay = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 2, hour: 14, minute: 8
        )))

        #expect(
            ActivityDateLabel.text(
                for: priorCalendarDay,
                relativeTo: now,
                calendar: calendar
            ) == "Yesterday"
        )
    }

    @Test func activityMetricsUseOneExplicitDisplayUnit() {
        let meters = 3.0 / AppConstants.Conversion.metersToMiles
        let elapsedSeconds = 27.0 * 60.0

        #expect(UnitFormatter.formatDistance(meters, unit: .miles, decimals: 2) == "3.00mi")
        #expect(UnitFormatter.formatDistance(meters, unit: .kilometers, decimals: 2) == "4.83km")
        #expect(UnitFormatter.formatPace(secondsPerMeter: elapsedSeconds / meters, unit: .miles) == "9:00/mi")
        #expect(UnitFormatter.formatPace(secondsPerMeter: elapsedSeconds / meters, unit: .kilometers) == "5:36/km")
    }

    @Test func primaryTabsFollowTheRunnerJourney() {
        #expect(RunawayTab.allCases.map(\.title) == ["Today", "Activities", "Plan", "You"])
        #expect(RunawayTab.today.systemImage == "sun.max.fill")
        #expect(RunawayTab.plan.systemImage == "calendar.badge.clock")
    }

    @Test func athleteAccountRowsResolveToActions() {
        #expect(AthleteAccountItem.devicesAndSensors.action == .systemSettings)
        #expect(AthleteAccountItem.trainingPreferences.action == .trainingPreferences)
        #expect(AthleteAccountItem.notifications.action == .systemSettings)
    }

    @Test func manualRaceEditKeepsIdentityAndPrefillsDraft() throws {
        let race = AthleteRace(
            id: 42,
            athleteId: 7,
            runsignupRaceId: nil,
            eventId: 0,
            raceName: "Skippo",
            raceDate: "2026-11-02",
            city: nil,
            state: nil,
            countryCode: nil,
            logoUrl: nil,
            externalUrl: nil,
            distanceMiles: 19,
            source: "manual",
            syncedAt: nil
        )

        let edit = try #require(ManualRaceEdit(race: race))

        #expect(edit.raceID == 42)
        #expect(edit.draft.name == "Skippo")
        #expect(edit.draft.distanceMiles == 19)
        #expect(edit.draft.date == race.parsedDate)
    }

    @Test func importedRaceCannotBeEditedAsManualRace() {
        let race = AthleteRace(
            id: 42,
            athleteId: 7,
            runsignupRaceId: 99,
            eventId: 12,
            raceName: "Imported Race",
            raceDate: "2026-11-02",
            city: nil,
            state: nil,
            countryCode: nil,
            logoUrl: nil,
            externalUrl: nil,
            distanceMiles: 13.1,
            source: "runsignup",
            syncedAt: nil
        )

        #expect(ManualRaceEdit(race: race) == nil)
    }

    @Test func supportedDeepLinksResolveToConcreteRoutes() throws {
        let activityURL = try #require(URL(string: "runaway://open/activity?id=42"))
        let commitmentURL = try #require(URL(string: "runaway://open/commitment"))
        let goalsURL = try #require(URL(string: "runaway://open/goals"))

        #expect(AppRouter.deepLinkRoute(for: activityURL) == .activityDetail(42))
        #expect(AppRouter.deepLinkRoute(for: commitmentURL) == .commitmentSetup)
        #expect(AppRouter.deepLinkRoute(for: goalsURL) == .goalManagement)
    }

    @Test func runningClassifierRecognizesRunVariantsWithoutCountingOtherSports() {
        #expect(AppConstants.ActivityTypes.isRunning("Run"))
        #expect(AppConstants.ActivityTypes.isRunning("Trail Run"))
        #expect(AppConstants.ActivityTypes.isRunning("VirtualRun"))
        #expect(!AppConstants.ActivityTypes.isRunning("Walk"))
        #expect(!AppConstants.ActivityTypes.isRunning("Bike Ride"))
        #expect(!AppConstants.ActivityTypes.isRunning(nil))
    }

    @Test func weeklyStatsExcludeNonRunningActivities() {
        let now = Date().timeIntervalSince1970
        let activities = [
            Activity(
                id: 1,
                name: "Morning Run",
                type: "Run",
                distance: 1_609.34,
                start_date: now,
                elapsed_time: 600,
                activity_date: now
            ),
            Activity(
                id: 2,
                name: "Bike Ride",
                type: "Bike Ride",
                distance: 16_093.4,
                start_date: now,
                elapsed_time: 1_800,
                activity_date: now
            )
        ]

        let stats = WeeklyActivityStats(activities: activities)

        #expect(stats.activityCount == 1)
        #expect(abs(stats.totalMiles - 1) < 0.001)
        #expect(stats.totalSeconds == 600)
    }

    @Test func manualRaceDraftRequiresANameFutureDateAndDistance() {
        let futureDate = Date().addingTimeInterval(86_400)

        #expect(ManualRaceDraft(name: "City Half", distanceMiles: 13.1, date: futureDate).isValid)
        #expect(!ManualRaceDraft(name: "", distanceMiles: 13.1, date: futureDate).isValid)
        #expect(!ManualRaceDraft(name: "City Half", distanceMiles: 0, date: futureDate).isValid)
        #expect(!ManualRaceDraft(name: "City Half", distanceMiles: 13.1, date: Date.distantPast).isValid)
    }

    @Test func manualAthleteRaceDecodesWithoutRunSignupIdentifier() throws {
        let data = try #require(
            """
            {
              "id": 12,
              "athlete_id": 7,
              "runsignup_race_id": null,
              "event_id": 0,
              "race_name": "City Half",
              "race_date": "2026-10-18",
              "distance_miles": 13.1,
              "source": "manual"
            }
            """.data(using: .utf8)
        )

        let race = try JSONDecoder().decode(AthleteRace.self, from: data)

        #expect(race.runsignupRaceId == nil)
        #expect(race.distanceMiles == 13.1)
        #expect(race.source == "manual")
    }

    @Test func raceRetainsItsSavedDisplayUnitAndProvidesAnEquivalentDistance() throws {
        let data = try #require(
            """
            {
              "id": 12,
              "athlete_id": 7,
              "runsignup_race_id": null,
              "event_id": 0,
              "race_name": "Skippo",
              "race_date": "2026-11-02",
              "distance_miles": 11.8061,
              "distance_unit": "kilometers",
              "source": "manual"
            }
            """.data(using: .utf8)
        )

        let race = try JSONDecoder().decode(AthleteRace.self, from: data)

        #expect(race.resolvedDistanceUnit(fallback: .miles) == .kilometers)
        #expect(race.primaryDistanceLabel(fallback: .miles) == "19.0 km")
        #expect(race.convertedDistanceLabel(fallback: .miles) == "11.81 mi equivalent")
    }

    @Test func legacyRaceUsesTheCurrentPreferenceUntilItIsSavedAgain() throws {
        let data = try #require(
            """
            {
              "id": 12,
              "athlete_id": 7,
              "race_name": "Legacy Race",
              "race_date": "2026-11-02",
              "distance_miles": 6.21371,
              "source": "manual"
            }
            """.data(using: .utf8)
        )

        let race = try JSONDecoder().decode(AthleteRace.self, from: data)

        #expect(race.distanceUnit == nil)
        #expect(race.resolvedDistanceUnit(fallback: .kilometers) == .kilometers)
    }

    @Test func manualRaceDraftCarriesUnitSeparatelyFromNormalizedMiles() {
        let draft = ManualRaceDraft(
            name: "Metric Race",
            distanceMiles: 6.21371,
            distanceUnit: .kilometers,
            date: Date().addingTimeInterval(172_800)
        )

        #expect(draft.distanceMiles == 6.21371)
        #expect(draft.distanceUnit == .kilometers)
    }

    @Test func runningGoalsRetainTheirSavedUnitWhileLegacyGoalsRemainCompatible() throws {
        let metric = GoalSettings(
            weeklyGoalMiles: 18.6411,
            monthlyGoalMiles: 74.5645,
            distanceUnit: .kilometers
        )
        let encoded = try JSONEncoder().encode(metric)
        let decoded = try JSONDecoder().decode(GoalSettings.self, from: encoded)
        let legacyData = try #require(
            """
            {"weeklyGoalMiles":20,"monthlyGoalMiles":80,"showInWidget":true}
            """.data(using: .utf8)
        )
        let legacy = try JSONDecoder().decode(GoalSettings.self, from: legacyData)

        #expect(decoded.distanceUnit == .kilometers)
        #expect(legacy.distanceUnit == nil)
        #expect(legacy.resolvedDistanceUnit(fallback: .miles) == .miles)
    }

    @Test func readinessNormalizesOnlyAvailableFactors() {
        let weightedScore = (70.0 * 0.20) + (75.0 * 0.20)
        #expect(
            ReadinessService.normalizedScore(weightedScore: weightedScore, availableWeight: 0.40) == 73
        )
    }

    @Test func readinessScoreIsClamped() {
        #expect(ReadinessService.normalizedScore(weightedScore: 120, availableWeight: 1) == 100)
        #expect(ReadinessService.normalizedScore(weightedScore: -10, availableWeight: 1) == 0)
    }

    @Test func readinessIncludesWholeBodyTrainingAndExcludesUnknownActivities() {
        #expect(ReadinessService.isReadinessActivity(activityType: "Run"))
        #expect(ReadinessService.isReadinessActivity(activityType: "Ride"))
        #expect(ReadinessService.isReadinessActivity(activityType: "Weight Training"))
        #expect(ReadinessService.isReadinessActivity(activityType: "Swim"))
        #expect(ReadinessService.isReadinessActivity(activityType: "Hike"))
        #expect(ReadinessService.isReadinessActivity(activityType: "Walking"))
        #expect(ReadinessService.isReadinessActivity(activityType: "Mobility"))
        #expect(!ReadinessService.isReadinessActivity(activityType: "Meditation"))
        #expect(!ReadinessService.isReadinessActivity(activityType: nil))
    }

    @Test func becomingEngineMakesRecoveryTheSafeDefaultWhenReadinessIsLow() throws {
        let snapshot = BecomingEngine.simulate(
            readinessScore: 34,
            plannedTitle: "Threshold Intervals",
            plannedDemand: .high,
            alternativeTitles: ["Mobility", "Walking"],
            remainingSessionCount: 4
        )

        #expect(snapshot.recommendedChoice == .recover)
        #expect(snapshot.headline == "Protect tomorrow's capacity")
        #expect(snapshot.paths.count == 3)
        #expect(try #require(snapshot.paths.first(where: { $0.choice == .recover })).isRecommended)
    }

    @Test func becomingEnginePreservesThePlanWhenCapacitySupportsIt() throws {
        let snapshot = BecomingEngine.simulate(
            readinessScore: 82,
            plannedTitle: "Aerobic Progression",
            plannedDemand: .moderate,
            alternativeTitles: ["Upper Body", "Cycling"],
            remainingSessionCount: 3
        )

        #expect(snapshot.recommendedChoice == .planned)
        #expect(snapshot.headline == "Build from today's choice")
        let planned = try #require(snapshot.paths.first(where: { $0.choice == .planned }))
        #expect(planned.title == "Aerobic Progression")
        #expect(planned.weekEffect == "Keeps 3 future sessions on their current path.")
    }

    @Test func becomingEngineOffersAProfileAlternativeWithoutClaimingItIsEquivalent() throws {
        let snapshot = BecomingEngine.simulate(
            readinessScore: 61,
            plannedTitle: "Tempo Run",
            plannedDemand: .high,
            alternativeTitles: ["Upper Body", "Swimming"],
            remainingSessionCount: 5
        )

        #expect(snapshot.recommendedChoice == .easier)
        let alternate = try #require(snapshot.paths.first(where: { $0.choice == .alternate }))
        #expect(alternate.title == "Upper Body")
        #expect(alternate.weekEffect == "Rebalances 5 future sessions after you choose.")
    }

    @Test func raceDateRoundTripsWithoutChangingCalendarDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Chicago"))
        let date = try #require(RaceDateCodec.date(from: "2026-11-02", calendar: calendar))
        #expect(RaceDateCodec.string(from: date, calendar: calendar) == "2026-11-02")
    }

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}

extension Runaway_iOSTests {
    @Test func projectedKilometerIsNotAnObservedMileRecord() {
        #expect(!PersonalRecordEvidencePolicy.supports(targetMeters: 1609.34, timeSeconds: 483,
            kind: .run, flagged: false, activityMeters: 5000, activitySeconds: 1800,
            splits: [RecordedEffortSplit(distance: 1000, elapsed_time: 300)]))
    }

    @Test func recordEvidenceRequiresRunningAndExactContiguousDistance() {
        let splits = (0..<5).map { _ in RecordedEffortSplit(distance: 1000, elapsed_time: 300) }
        #expect(PersonalRecordEvidencePolicy.supports(targetMeters: 5000, timeSeconds: 1500,
            kind: .run, flagged: false, activityMeters: 8000, activitySeconds: 2500, splits: splits))
        #expect(!PersonalRecordEvidencePolicy.supports(targetMeters: 5000, timeSeconds: 1500,
            kind: .bike, flagged: false, activityMeters: 5000, activitySeconds: 1500, splits: splits))
        #expect(!PersonalRecordEvidencePolicy.supports(targetMeters: 21097.5, timeSeconds: 6300,
            kind: .run, flagged: false, activityMeters: 21000, activitySeconds: 6300,
            splits: (0..<21).map { _ in RecordedEffortSplit(distance: 1000, elapsed_time: 300) }))
        #expect(!PersonalRecordEvidencePolicy.supports(targetMeters: 5000, timeSeconds: 1500,
            kind: .run, flagged: true, activityMeters: 5000, activitySeconds: 1500, splits: splits))
    }

    @Test func invalidSplitCannotBeBridgedIntoARecord() {
        let splits = [RecordedEffortSplit(distance: 1000, elapsed_time: 300),
                      RecordedEffortSplit(distance: nil, elapsed_time: nil),
                      RecordedEffortSplit(distance: 1000, elapsed_time: 300)]
        #expect(!PersonalRecordEvidencePolicy.supports(targetMeters: 2000, timeSeconds: 600,
            kind: .run, flagged: false, activityMeters: 8000, activitySeconds: 3000, splits: splits))
    }
}
