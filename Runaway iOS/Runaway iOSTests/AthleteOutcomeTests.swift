import Foundation
import Testing
@testable import Runaway_iOS

@Suite("Athlete outcomes")
struct AthleteOutcomeTests {
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
}
