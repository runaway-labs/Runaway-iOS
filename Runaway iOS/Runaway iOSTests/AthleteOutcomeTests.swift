import Foundation
import Testing
@testable import Runaway_iOS

@Suite("Athlete outcomes")
struct AthleteOutcomeTests {
    @Test("Strength zones keep stable persisted identifiers")
    func strengthZoneRawValuesAreStable() {
        #expect(StrengthZone.allCases.map(\.rawValue) == [
            "chest", "back", "shoulders", "arms", "legs", "core"
        ])
    }

    @Test("Strength recommendations default to every available zone")
    func strengthRecommendationDefaults() {
        let preferences = StrengthRecommendationPreferences.default

        #expect(preferences.suggestionsEnabled)
        #expect(preferences.availableZones == Set(StrengthZone.allCases))
    }

    @Test("Every strength zone may be unavailable without inventing a reason")
    func allStrengthZonesMayBeUnavailable() {
        let preferences = StrengthRecommendationPreferences(
            suggestionsEnabled: true,
            availableZones: []
        )

        #expect(preferences.availableZones.isEmpty)
    }

    @Test("Schema version two profiles migrate to safe strength defaults")
    func legacyProfileMigratesToSafeStrengthDefaults() throws {
        var legacy = AthleteTrainingProfile(athleteID: 42)
        legacy.schemaVersion = 2
        let encoded = try JSONEncoder().encode(legacy)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "strengthRecommendations")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        var decoded = try JSONDecoder().decode(AthleteTrainingProfile.self, from: legacyData)
        decoded.migrateStrengthRecommendations()

        #expect(decoded.schemaVersion == 3)
        #expect(decoded.resolvedStrengthRecommendations == .default)
    }

    @Test("Approved outcomes survive protected profile encoding")
    func outcomesRoundTrip() throws {
        var profile = AthleteTrainingProfile(athleteID: 42)
        profile.outcomes = [.marathonReady, .leanStrong, .durableCore]

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(AthleteTrainingProfile.self, from: data)

        #expect(decoded.outcomes == [.marathonReady, .leanStrong, .durableCore])
    }

    @Test("Marathon Ready is valid without a race date or lift benchmark")
    func ongoingMarathonReadinessNeedsNoEvent() {
        var profile = AthleteTrainingProfile(athleteID: 42)
        profile.outcomes = [.marathonReady]

        #expect(profile.outcomeValidationMessage == nil)
    }

    @Test("At least one durable outcome is required")
    func emptyOutcomesAreRejected() {
        var profile = AthleteTrainingProfile(athleteID: 42)
        profile.outcomes = []

        #expect(profile.outcomeValidationMessage == "Choose at least one training outcome.")
    }

    @Test("Legacy metric goals migrate to outcomes without losing benchmark evidence")
    func legacyGoalsMigrateWithoutDataLoss() {
        let running = AthleteTrainingGoal(
            title: "Build to 20 miles per week",
            metric: .weeklyRunningDistance,
            target: GoalMeasurement(distanceMeters: 32_186.88)
        )
        let strength = AthleteTrainingGoal(
            title: "Bench benchmark",
            metric: .strengthPerformance,
            baseline: GoalMeasurement(
                loadKilograms: 102.058,
                repetitions: 4,
                exerciseID: "bench_press",
                loadConvention: .total
            ),
            baselineMeasuredAt: Date(timeIntervalSince1970: 1_700_000_000),
            baselineSource: .userEntered,
            target: GoalMeasurement(
                loadKilograms: 102.058,
                repetitions: 8,
                exerciseID: "bench_press",
                loadConvention: .total
            )
        )
        var profile = AthleteTrainingProfile(athleteID: 42)
        profile.outcomes = nil
        profile.goals = [running, strength]

        profile.migrateLegacyGoalsToOutcomes()

        #expect(profile.outcomes == [.marathonReady, .leanStrong])
        #expect(profile.goals == [running, strength])
    }

    @Test("Outcome cards use athlete language instead of storage metrics")
    func outcomePresentationIsHumanReadable() {
        #expect(AthleteOutcome.marathonReady.title == "Marathon Ready")
        #expect(AthleteOutcome.leanStrong.title == "Lean + Strong")
        #expect(AthleteOutcome.durableCore.title == "Strong, Durable Core")
        #expect(AthleteOutcome.marathonReady.detail.contains("race date") == false)
        #expect(AthleteOutcome.leanStrong.detail.contains("bench") == false)
    }
}
