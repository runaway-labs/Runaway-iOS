import XCTest
@testable import Runaway_iOS

final class GoalDrivenTrainingEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_100_000)
    private let utc = TimeZone(secondsFromGMT: 0)!

    private func profile(minutes: Int = 30) -> AthleteTrainingProfile {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        var value = AthleteTrainingProfile(athleteID: 1)
        value.goals = [
            AthleteTrainingGoal(title: "Run consistently", metric: .weeklyRunningDistance,
                target: GoalMeasurement(distanceMeters: 20000)),
            AthleteTrainingGoal(title: "Build bench strength", metric: .strengthPerformance,
                target: GoalMeasurement(loadKilograms: 100, repetitions: 8,
                    exerciseID: "barbell-bench-press", loadConvention: .total))
        ]
        value.availability = [.init(weekday: calendar.component(.weekday, from: now), availableMinutes: minutes)]
        value.equipment = [.fullGym]
        return value
    }

    private func record(_ value: TrainingObservationValue, daysAgo: Double = 3,
                        athleteID: Int = 1, id: UUID = UUID(), parent: UUID? = nil) -> TrainingObservation {
        TrainingObservation(id: id, athleteID: athleteID, measuredAt: now.addingTimeInterval(-daysAgo * 86400),
            receivedAt: now.addingTimeInterval(-60), source: .userEntered, sourceRecordID: id.uuidString,
            sessionID: nil, supersedesID: parent, value: value)
    }

    private func runningObservation(daysAgo: Double = 3) -> TrainingObservation {
        record(.run(distanceMeters: 5000, durationSeconds: 1800, effort: nil), daysAgo: daysAgo)
    }

    private func set(convention: LoadConvention = .total,
                     effort: TrainingEffortObservation? = .init(scale: .repetitionsInReserve, value: 3)) -> TrainingObservation {
        record(.strengthSet(exerciseID: "barbell-bench-press", equipmentID: nil, repetitions: 8,
            externalLoadKilograms: 45, assistanceKilograms: nil, convention: convention, effort: effort))
    }

    private func inputs(_ value: AthleteTrainingProfile, _ history: [TrainingObservation] = []) throws -> TrainingDecisionInputs {
        try TrainingDecisionInputBuilder.build(profile: value, history: history, athleteID: 1, now: now, timeZone: utc)
    }

    func testTwoIdleDaysPreserveBothEqualGoalsAndProduceSpecificPreviews() throws {
        let evidence = [runningObservation(), set()]
        let results = GoalDrivenTrainingEngine.previews(for: try inputs(profile(), evidence))
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.priority == .equalPrimary })
        let running = try XCTUnwrap(results.first { $0.discipline == .running })
        guard case .running(let session) = running.outcome else { return XCTFail("Expected timed running, not a generic fallback") }
        XCTAssertEqual(session.warmupSeconds, 300)
        XCTAssertEqual(session.runningSeconds, 1200)
        XCTAssertEqual(session.cooldownSeconds, 300)
        XCTAssertEqual(session.totalSeconds, 1800)
        let strength = try XCTUnwrap(results.first { $0.discipline == .strength })
        guard case .strength(let lifting) = strength.outcome else { return XCTFail("Expected a goal-specific strength block") }
        XCTAssertEqual(lifting.exerciseID, "barbell-bench-press")
        XCTAssertEqual(lifting.sets, 2)
        XCTAssertEqual(lifting.repetitions, 6...8)
        XCTAssertEqual(lifting.resistance, .external(kilograms: 45, convention: .total))
        XCTAssertEqual(lifting.totalSeconds, 810)
        XCTAssertEqual(Set(results.flatMap(\.evidenceIDs)), Set(evidence.map(\.id)))
    }

    func testUnknownAbilityNeverUsesTargetAsObservedLoadOrRunningHistory() throws {
        let results = GoalDrivenTrainingEngine.previews(for: try inputs(profile()))
        let running = try XCTUnwrap(results.first { $0.discipline == .running })
        guard case .needsInput = running.outcome else { return XCTFail("Unknown running capacity needs specific input") }
        let strength = try XCTUnwrap(results.first { $0.discipline == .strength })
        guard case .strength(let session) = strength.outcome else { return XCTFail("External load can use calibration") }
        XCTAssertEqual(session.resistance, .chooseComfortableLoad(.total))
        XCTAssertTrue(strength.evidenceIDs.isEmpty)
    }

    func testUnknownEffortAndDifferentConventionCannotSupplyWorkingWeight() throws {
        for evidence in [set(effort: nil), set(effort: .init(scale: .setRPE, value: 8)), set(convention: .perHand)] {
            let results = GoalDrivenTrainingEngine.previews(for: try inputs(profile(), [evidence]))
            let strength = try XCTUnwrap(results.first { $0.discipline == .strength })
            guard case .strength(let session) = strength.outcome else { return XCTFail("Expected calibration") }
            XCTAssertEqual(session.resistance, .chooseComfortableLoad(.total))
            XCTAssertTrue(strength.evidenceIDs.isEmpty)
        }
    }

    func testTimeBudgetIncludesWarmupRestAndCooldown() throws {
        let results = GoalDrivenTrainingEngine.previews(for: try inputs(profile(minutes: 10), [runningObservation(), set()]))
        XCTAssertEqual(results.count, 2)
        for result in results {
            guard case .needsInput = result.outcome else { return XCTFail("Do not drop preparation or rest to fit an impossible budget") }
        }
        let fitting = GoalDrivenTrainingEngine.previews(for: try inputs(profile(minutes: 15), [runningObservation(), set()]))
        for result in fitting {
            switch result.outcome {
            case .running(let session): XCTAssertLessThanOrEqual(session.totalSeconds, 900)
            case .strength(let session): XCTAssertLessThanOrEqual(session.totalSeconds, 900)
            case .needsInput: XCTFail("Both example blocks fit this budget")
            }
        }
    }

    func testMissingAvailabilityDiffersFromExplicitUnavailableDay() throws {
        var missing = profile()
        missing.availability = []
        XCTAssertNil(try inputs(missing).today)
        let absent = GoalDrivenTrainingEngine.previews(for: try inputs(missing))
        let unavailable = GoalDrivenTrainingEngine.previews(for: try inputs(profile(minutes: 0)))
        XCTAssertNotEqual(absent.first?.reasons, unavailable.first?.reasons)
    }

    func testActualTrainingTodayBlocksUnaccountedExtraSessionButBodyWeightDoesNot() throws {
        for actual in [runningObservation(daysAgo: 0), record(.strengthSet(exerciseID: "pull-up", equipmentID: nil,
            repetitions: 3, externalLoadKilograms: nil, assistanceKilograms: nil, convention: .bodyweight, effort: nil), daysAgo: 0)] {
            let results = GoalDrivenTrainingEngine.previews(for: try inputs(profile(), [actual]))
            for result in results {
                guard case .needsInput = result.outcome else { return XCTFail("Additional session needs remaining-time accounting") }
            }
        }
        let results = GoalDrivenTrainingEngine.previews(for: try inputs(profile(), [runningObservation(), record(.bodyWeight(kilograms: 80), daysAgo: 0)]))
        let running = try XCTUnwrap(results.first { $0.discipline == .running })
        guard case .running = running.outcome else { return XCTFail("Body measurements are not completed training") }
    }

    func testLimitationsAndIncompatibleEquipmentBlockPrescriptions() throws {
        var restricted = profile()
        restricted.reportedLimitations = "Avoid overhead movement"
        for result in GoalDrivenTrainingEngine.previews(for: try inputs(restricted, [runningObservation(), set()])) {
            guard case .needsInput = result.outcome else { return XCTFail("Do not interpret free-text restrictions as clearance") }
        }
        var noGym = profile()
        noGym.equipment = [.bodyweight]
        let strength = try XCTUnwrap(GoalDrivenTrainingEngine.previews(for: try inputs(noGym, [set()])).first { $0.discipline == .strength })
        guard case .needsInput = strength.outcome else { return XCTFail("Barbell requires compatible equipment") }
    }

    func testCorrectionHistorySuppliesOnlyLatestEvidenceAndRejectsBranches() throws {
        let first = runningObservation()
        let revised = record(.run(distanceMeters: 4500, durationSeconds: 1500, effort: nil), parent: first.id)
        XCTAssertEqual(try inputs(profile(), [revised, first]).observations, [revised])
        let branch = record(.run(distanceMeters: 4600, durationSeconds: 1600, effort: nil), parent: first.id)
        XCTAssertThrowsError(try inputs(profile(), [first, revised, branch]))
        XCTAssertThrowsError(try inputs(profile(), [revised]))
    }

    func testMixedAccountsRejectedAndFutureEvidenceExcluded() throws {
        XCTAssertThrowsError(try inputs(profile(), [record(.bodyWeight(kilograms: 80), athleteID: 2)]))
        let valid = runningObservation()
        let future = record(.run(distanceMeters: 6000, durationSeconds: 2100, effort: nil), daysAgo: -1, parent: valid.id)
        XCTAssertEqual(try inputs(profile(), [valid, future]).observations, [valid])
    }

    func testFingerprintIgnoresDisplayUnitsLabelsSaveRevisionAndArrayOrdering() throws {
        let original = profile()
        let history = [runningObservation(), set()]
        var displayEdit = original
        displayEdit.revision = UUID()
        displayEdit.updatedAt = now
        displayEdit.goals.reverse()
        for index in displayEdit.goals.indices {
            displayEdit.goals[index].title = "A different display name"
            displayEdit.goals[index].enteredDistanceUnit = .kilometers
            displayEdit.goals[index].enteredLoadUnit = .kilograms
        }
        XCTAssertEqual(try inputs(original, history).fingerprint, try inputs(displayEdit, history.reversed()).fingerprint)
        displayEdit.availability[0].availableMinutes = 45
        XCTAssertNotEqual(try inputs(original, history).fingerprint, try inputs(displayEdit, history).fingerprint)
    }

    func testOldEvidenceAndGoalBaselineAreNotRecentCompletedWorkouts() throws {
        var value = profile()
        value.goals[0].baseline = GoalMeasurement(distanceMeters: 15000)
        value.goals[0].baselineSource = .userEntered
        value.goals[0].baselineMeasuredAt = now.addingTimeInterval(-86400)
        let built = try inputs(value, [runningObservation(daysAgo: 29)])
        XCTAssertEqual(built.observations.count, 1, "Keep older evidence in history even when not used by the policy")
        let running = try XCTUnwrap(GoalDrivenTrainingEngine.previews(for: built).first { $0.discipline == .running })
        guard case .needsInput = running.outcome else { return XCTFail("Neither targets nor stale evidence prove current capacity") }
    }
}
