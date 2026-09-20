import Foundation
import Testing
@testable import Runaway_iOS

@Suite(.serialized)
struct TodayRecommendationPolicyTests {
    private func earlierSessionResult(_ result: TrainingSessionResult, days: Int) -> TrainingSessionResult {
        let date = result.completedAt.addingTimeInterval(-Double(days) * 86_400)
        let old = result.reference
        let reference = TrainingSessionResult.Reference(athleteID: old.athleteID, goalID: old.goalID,
            goalTitle: old.goalTitle, fingerprint: old.fingerprint + "/earlier/\(days)",
            policyVersion: old.policyVersion, generatedAt: date, distanceUnit: old.distanceUnit,
            massUnit: old.massUnit, prescribedSeconds: old.prescribedSeconds, items: old.items)
        return TrainingSessionResult(id: UUID(), reference: reference, completedAt: date, recordedAt: date,
            elapsedSeconds: result.elapsedSeconds, perceivedEffort: result.perceivedEffort,
            bodyState: result.bodyState, entries: result.entries)
    }

    @Test func resultDrivenInputsChangeFingerprintAndRejectWrongOwner() throws {
        let result = sessionResultFixture()
        let profile = AthleteTrainingProfile(athleteID: 42)
        let now = result.recordedAt.addingTimeInterval(1)
        let zone = TimeZone(secondsFromGMT: 0)!
        let before = try TrainingDecisionInputBuilder.build(profile: profile, history: [], athleteID: 42, now: now, timeZone: zone)
        let after = try TrainingDecisionInputBuilder.build(profile: profile, history: [], athleteID: 42, now: now, timeZone: zone, sessionResults: [result])
        #expect(before.fingerprint != after.fingerprint)
        #expect(after.sessionResults.count == 1)
        #expect(throws: TrainingDecisionInputBuilder.InputError.ownershipMismatch) {
            try TrainingDecisionInputBuilder.build(profile: AthleteTrainingProfile(athleteID: 43), history: [], athleteID: 43,
                now: now, timeZone: zone, sessionResults: [result])
        }
    }

    @Test func resultDrivenInputsExcludeFutureResultsAndRejectDuplicates() throws {
        let result = sessionResultFixture()
        let profile = AthleteTrainingProfile(athleteID: 42)
        let now = result.recordedAt.addingTimeInterval(-1)
        let zone = TimeZone(secondsFromGMT: 0)!
        let inputs = try TrainingDecisionInputBuilder.build(profile: profile, history: [], athleteID: 42,
            now: now, timeZone: zone, sessionResults: [result])
        #expect(inputs.sessionResults.isEmpty)
        #expect(throws: TrainingDecisionInputBuilder.InputError.invalidHistory) {
            try TrainingDecisionInputBuilder.build(profile: profile, history: [], athleteID: 42,
                now: now, timeZone: zone, sessionResults: [result, result])
        }
    }

    @Test func progressionNeedsDistinctMatchingCompletedDays() {
        let result = sessionResultFixture()
        let old = earlierSessionResult(result, days: 3)
        let now = result.recordedAt.addingTimeInterval(1)
        #expect(TrainingProgressionService.assess(goalID: result.reference.goalID, athleteID: 42,
            results: [old, result], on: now).state == .reviewIncrease)
        #expect(TrainingProgressionService.assess(goalID: result.reference.goalID, athleteID: 42,
            results: [result], on: now).state == .repeatDose)
    }

    @Test func progressionDoesNotSkipLatestPartialOrDifficultResult() {
        var result = sessionResultFixture()
        let old = earlierSessionResult(result, days: 3)
        result.entries[0].repetitions = 4
        #expect(TrainingProgressionService.assess(goalID: result.reference.goalID, athleteID: 42,
            results: [old, result], on: result.recordedAt.addingTimeInterval(1)).state == .hold)
        result.entries[0].repetitions = 8
        result.perceivedEffort = 9
        #expect(TrainingProgressionService.assess(goalID: result.reference.goalID, athleteID: 42,
            results: [old, result], on: result.recordedAt.addingTimeInterval(1)).state == .reviewRecovery)
    }

    @Test func progressionDoesNotTreatChangedDoseAsRepeatedEvidence() {
        let result = sessionResultFixture()
        var old = earlierSessionResult(result, days: 3)
        old.entries[0].loadKilograms = 40
        #expect(TrainingProgressionService.assess(goalID: result.reference.goalID, athleteID: 42,
            results: [old, result], on: result.recordedAt.addingTimeInterval(1)).state == .repeatDose)
    }

    @Test func remainingWeekPreservesExplicitRestAndWorkoutDespiteAvailability() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 13))!
        let monday = calendar.date(byAdding: .day, value: 1, to: sunday)!
        let tuesday = calendar.date(byAdding: .day, value: 2, to: sunday)!
        let workouts = [
            DailyWorkout(id: "rest", date: monday, dayOfWeek: .monday, workoutType: .rest, title: "Rest",
                description: "", duration: nil, distance: nil, targetPace: nil, exercises: nil, isCompleted: false, completedActivityId: nil),
            DailyWorkout(id: "choice", date: tuesday, dayOfWeek: .tuesday, workoutType: .easyRun, title: "My run",
                description: "Chosen for today", duration: 30, distance: nil, targetPace: nil, exercises: nil, isCompleted: false, completedActivityId: nil)
        ]
        let review = RemainingWeekTrainingPolicy.review(workouts: workouts, results: [], availability: [], on: sunday, calendar: calendar)
        #expect(review.count == 6)
        #expect(review[0].state == .preserved)
        #expect(review[1].state == .preserved)
    }

    @Test func remainingWeekFlagsTimeConflictWithoutCountingMissedPlansAsRecovery() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 13))!
        let monday = calendar.date(byAdding: .day, value: 1, to: sunday)!
        let planned = DailyWorkout(id: "monday", date: monday, dayOfWeek: .monday, workoutType: .easyRun,
            title: "Easy run", description: "", duration: 45, distance: nil, targetPace: nil,
            exercises: nil, isCompleted: false, completedActivityId: nil)
        let review = RemainingWeekTrainingPolicy.review(workouts: [planned], results: [],
            availability: [.init(weekday: 2, availableMinutes: 30)], on: sunday, calendar: calendar)
        #expect(review[0].state == .timeConflict)
        #expect(review[0].title == "Easy run")
        #expect(review.allSatisfy { $0.date > sunday })
    }

    private func sessionResultFixture() -> TrainingSessionResult {
        let date = Date(timeIntervalSince1970: 1_789_200_000)
        let item = TrainingSessionResult.Item(id: "bench/1", title: "Bench press, set 1",
            kind: .strength, exerciseID: "barbell-bench-press", seconds: nil,
            repetitions: 6...8, convention: .total, loadKilograms: nil, assistanceKilograms: nil)
        let reference = TrainingSessionResult.Reference(athleteID: 42, goalID: UUID(),
            goalTitle: "Bench goal", fingerprint: "fixture", policyVersion: "test-v1",
            generatedAt: date, distanceUnit: .miles, massUnit: .pounds,
            prescribedSeconds: 900, items: [item])
        let actual = TrainingSessionResult.Entry(itemID: item.id, skipped: false,
            seconds: nil, repetitions: 8, loadKilograms: 45, assistanceKilograms: nil,
            repsInReserve: 3)
        return TrainingSessionResult(id: UUID(), reference: reference, completedAt: date,
            recordedAt: date, elapsedSeconds: 900, perceivedEffort: 5, bodyState: .good,
            entries: [actual])
    }

    @Test func sessionResultsRequireActualCalibrationLoadAndEffort() {
        var result = sessionResultFixture()
        #expect(result.isValid)
        result.entries[0].loadKilograms = nil
        #expect(!result.isValid)
        result.entries[0].loadKilograms = 45
        result.entries[0].repsInReserve = nil
        #expect(!result.isValid)
    }

    @Test func sessionResultsRejectDuplicatedAndMissingEntries() {
        var result = sessionResultFixture()
        result.entries.append(result.entries[0])
        #expect(!result.isValid)
        result.entries = []
        #expect(!result.isValid)
    }

    @Test func sessionResultsDoNotTreatSkippedSetsAsCompletedWork() {
        var result = sessionResultFixture()
        var second = result.reference.items[0]
        second.id = "bench/2"
        result.reference.items.append(second)
        result.entries.append(.init(itemID: "bench/2", skipped: true, seconds: nil,
            repetitions: nil, loadKilograms: nil, assistanceKilograms: nil, repsInReserve: nil))
        #expect(result.isValid)
        #expect(result.isPartial)
        result.entries[1].repetitions = 8
        #expect(!result.isValid)
    }

    @Test func sessionResultsRejectInvalidTimesAndGlobalEffort() {
        var result = sessionResultFixture()
        result.elapsedSeconds = .nan
        #expect(!result.isValid)
        result.elapsedSeconds = 900
        result.perceivedEffort = 0
        #expect(!result.isValid)
        result.perceivedEffort = 5
        result.completedAt = result.recordedAt.addingTimeInterval(1)
        #expect(!result.isValid)
    }

    @MainActor @Test func sessionResultsPersistAtomicallyAndRetriesDoNotDuplicate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ProtectedTrainingRepository(root: root, activeAthleteID: { 42 })
        let result = sessionResultFixture()
        #expect(try repository.appendSessionResult(result, athleteID: 42) == result)
        #expect(try repository.appendSessionResult(result, athleteID: 42) == result)
        #expect(try repository.sessionResults(athleteID: 42) == [result])
        var duplicate = result
        duplicate.id = UUID()
        #expect(throws: (any Error).self) { try repository.appendSessionResult(duplicate, athleteID: 42) }
        #expect(try repository.sessionResults(athleteID: 42).count == 1)
    }

    @MainActor @Test func sessionResultsRejectDifferentOwnerAndConflictingRetry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ProtectedTrainingRepository(root: root, activeAthleteID: { 42 })
        var result = sessionResultFixture()
        #expect(throws: (any Error).self) { try repository.appendSessionResult(result, athleteID: 43) }
        try repository.appendSessionResult(result, athleteID: 42)
        result.entries[0].repetitions = 7
        #expect(throws: (any Error).self) { try repository.appendSessionResult(result, athleteID: 42) }
        #expect(try repository.sessionResults(athleteID: 42).first?.entries[0].repetitions == 8)
    }

    @Test func runningPrescriptionKeepsWarmupAndCooldownInsideBudget() {
        guard case .session(let run) = RunningPrescriptionPolicy.make(
            recordedElapsedSeconds: 1_800, availableSeconds: 1_200
        ) else { Issue.record("Expected a time-bounded running prescription"); return }
        #expect(run.warmupSeconds == 300)
        #expect(run.runningSeconds == 600)
        #expect(run.cooldownSeconds == 300)
        #expect(run.totalSeconds == 1_200)
    }

    @Test func runningPrescriptionDoesNotExceedObservedDurationOrPreviewCap() {
        guard case .session(let short) = RunningPrescriptionPolicy.make(
            recordedElapsedSeconds: 475.9, availableSeconds: 3_600
        ), case .session(let long) = RunningPrescriptionPolicy.make(
            recordedElapsedSeconds: 7_200, availableSeconds: 3_600
        ) else { Issue.record("Expected duration-limited sessions"); return }
        #expect(short.runningSeconds == 475)
        #expect(short.totalSeconds == 1_075)
        #expect(long.runningSeconds == 1_200)
        #expect(long.totalSeconds == 1_800)
    }

    @Test func runningPrescriptionBlocksMissingAndInvalidEvidence() {
        let invalid: [Double?] = [nil, 0, -1, .nan, .infinity, 299.9]
        for elapsed in invalid {
            guard case .needsInput = RunningPrescriptionPolicy.make(
                recordedElapsedSeconds: elapsed, availableSeconds: 1_800
            ) else { Issue.record("Invalid evidence must not create a run"); continue }
        }
    }

    @Test func runningPrescriptionBlocksInsufficientTimeWithoutOverflow() {
        for budget in [Int.min, -1, 0, 899] {
            guard case .needsInput = RunningPrescriptionPolicy.make(
                recordedElapsedSeconds: 1_800, availableSeconds: budget
            ) else { Issue.record("Insufficient time must not remove warm-up or cooldown"); continue }
        }
        guard case .session(let minimum) = RunningPrescriptionPolicy.make(
            recordedElapsedSeconds: 300, availableSeconds: 900
        ) else { Issue.record("The minimum supported session should fit"); return }
        #expect(minimum.totalSeconds == 900)
    }

    @Test func runningPrescriptionWalkBreakReplacesWorkRatherThanAddingTime() {
        guard case .session(let run) = RunningPrescriptionPolicy.make(
            recordedElapsedSeconds: 1_800, availableSeconds: 1_800
        ) else { Issue.record("Expected running prescription"); return }
        let blocks = run.blocks(includingWalkBreak: true)
        #expect(blocks.map(\.phase) == [.warmup, .running, .recovery, .running, .cooldown])
        #expect(blocks.map(\.durationSeconds) == [300, 570, 60, 570, 300])
        #expect(blocks.reduce(0) { $0 + $1.durationSeconds } == 1_800)
        #expect(blocks.filter { $0.phase == .running }.reduce(0) { $0 + $1.durationSeconds } == 1_140)
    }

    @Test func runningPrescriptionOddDurationRetainsEverySecondWithRecovery() {
        guard case .session(let run) = RunningPrescriptionPolicy.make(
            recordedElapsedSeconds: 475.9, availableSeconds: 1_800
        ) else { Issue.record("Expected running prescription"); return }
        #expect(run.blocks(includingWalkBreak: true).map(\.durationSeconds) == [300, 207, 60, 208, 300])
        #expect(run.blocks(includingWalkBreak: false).map(\.durationSeconds) == [300, 475, 300])
        #expect(run.blocks(includingWalkBreak: false).map(\.phase) == [.warmup, .running, .cooldown])
    }

    @Test func runningPrescriptionMinimumRetainsPositiveWorkOnBothSidesOfBreak() {
        guard case .session(let run) = RunningPrescriptionPolicy.make(
            recordedElapsedSeconds: 300, availableSeconds: 900
        ) else { Issue.record("Expected minimum session"); return }
        #expect(run.blocks(includingWalkBreak: true).map(\.durationSeconds) == [300, 120, 60, 120, 300])
    }

    @Test func runningEvidenceDistanceUsesSavedGoalUnits() {
        #expect(abs(RunningPrescriptionPolicy.distanceValue(meters: 1_609.344, unit: .miles) - 1) < 0.000_001)
        #expect(RunningPrescriptionPolicy.distanceValue(meters: 5_000, unit: .kilometers) == 5)
        #expect(abs(RunningPrescriptionPolicy.distanceValue(meters: 5_000, unit: .miles) - 3.106_856) < 0.000_001)
    }

    @Test func completeStrengthSessionFitsThirtyMinutesWithoutDroppingPatterns() throws {
        let result = CompleteStrengthSessionPolicy.make(
            anchor: completeStrengthAnchor, equipment: .fullGym,
            availableSeconds: 1_800, evidence: [], now: testDate
        )
        guard case .session(let session) = result else {
            Issue.record("Expected a complete session"); return
        }
        #expect(session.blocks.count == 4)
        #expect(Set(session.blocks.map(\.pattern)).count == 4)
        #expect(session.blocks.first?.exerciseID == "barbell-bench-press")
        #expect(session.blocks.map(\.sets) == [2, 2, 2, 1])
        #expect(session.totalSeconds == 1_770)
        #expect(session.blocks.first?.resistance == .external(kilograms: 45.359237, convention: .total))
        #expect(session.blocks.dropFirst().allSatisfy { $0.requiresCalibration })
    }

    @Test func completeStrengthSessionRejectsInsufficientTimeAndEquipment() {
        let tooShort = CompleteStrengthSessionPolicy.make(
            anchor: completeStrengthAnchor, equipment: .fullGym,
            availableSeconds: 1_200, evidence: [], now: testDate
        )
        guard case .needsInput = tooShort else { Issue.record("Must not silently drop a movement"); return }
        let incompatible = CompleteStrengthSessionPolicy.make(
            anchor: completeStrengthAnchor, equipment: .bodyweight,
            availableSeconds: 3_600, evidence: [], now: testDate
        )
        guard case .needsInput = incompatible else { Issue.record("Must not invent a barbell"); return }
    }

    @Test func completeStrengthSessionUsesOnlyMatchingMeasuredComplementLoads() {
        let evidence = [CompleteStrengthSessionPolicy.Evidence(
            exerciseID: "dumbbell-row", loadKilograms: 12, convention: .perHand,
            repetitions: 8, repsInReserve: 3, measuredAt: testDate.addingTimeInterval(-86_400)
        )]
        let result = CompleteStrengthSessionPolicy.make(
            anchor: completeStrengthAnchor, equipment: .fullGym,
            availableSeconds: 2_400, evidence: evidence, now: testDate
        )
        guard case .session(let session) = result else { Issue.record("Expected session"); return }
        #expect(session.blocks[1].exerciseID == "dumbbell-row")
        #expect(session.blocks[1].resistance == .external(kilograms: 12, convention: .perHand))
        #expect(!session.blocks[1].requiresCalibration)
        #expect(session.blocks[2].requiresCalibration)
        #expect(session.blocks[3].requiresCalibration)
        #expect(session.totalSeconds == 1_920)
    }

    @Test func completeStrengthSessionDoesNotBorrowStaleOrWrongConventionLoads() {
        let evidence = [
            CompleteStrengthSessionPolicy.Evidence(exerciseID: "dumbbell-row", loadKilograms: 99, convention: .total, repetitions: 12, repsInReserve: 3, measuredAt: testDate.addingTimeInterval(-86_400)),
            CompleteStrengthSessionPolicy.Evidence(exerciseID: "dumbbell-row", loadKilograms: 10, convention: .perHand, repetitions: 12, repsInReserve: 3, measuredAt: testDate.addingTimeInterval(-40 * 86_400))
        ]
        let result = CompleteStrengthSessionPolicy.make(anchor: completeStrengthAnchor, equipment: .fullGym,
            availableSeconds: 2_400, evidence: evidence, now: testDate)
        guard case .session(let session) = result else { Issue.record("Expected session"); return }
        #expect(session.blocks[1].requiresCalibration)
    }

    @Test func completeStrengthSessionDoesNotReuseOlderEasySetAfterLatestHardSet() {
        let evidence = [
            CompleteStrengthSessionPolicy.Evidence(exerciseID: "dumbbell-row", loadKilograms: 12, convention: .perHand, repetitions: 8, repsInReserve: 3, measuredAt: testDate.addingTimeInterval(-2 * 86_400)),
            CompleteStrengthSessionPolicy.Evidence(exerciseID: "dumbbell-row", loadKilograms: 12, convention: .perHand, repetitions: 6, repsInReserve: 0, measuredAt: testDate.addingTimeInterval(-86_400))
        ]
        let result = CompleteStrengthSessionPolicy.make(anchor: completeStrengthAnchor, equipment: .fullGym,
            availableSeconds: 2_400, evidence: evidence, now: testDate)
        guard case .session(let session) = result else { Issue.record("Expected session"); return }
        #expect(session.blocks[1].requiresCalibration)
    }

    private var completeStrengthAnchor: GoalSessionPreview.Strength {
        .init(exerciseID: "barbell-bench-press", sets: 2, repetitions: 6...8,
              resistance: .external(kilograms: 45.359237, convention: .total),
              warmupSeconds: 300, setupSeconds: 120, secondsReservedPerSet: 60,
              restBetweenSetsSeconds: 90, cooldownSeconds: 180,
              effortInstruction: "Finish with 2-3 reps in reserve.")
    }

    @Test func shadowSelectionBalancesEqualPriorityDisciplines() {
        let history = [GoalDailyShadowPolicy.CompletedDay(discipline: .running, date: testDate.addingTimeInterval(-86_400))]
        let decision = GoalDailyShadowPolicy.select(
            candidates: shadowCandidates, history: history, on: testDate, readinessScore: 87
        )
        #expect(decision.selectedGoalID == shadowCandidates[1].goalID)
        #expect(decision.rankings.first?.discipline == .strength)
        #expect(decision.rankings.first?.shareDeficit == 0.5)
    }

    @Test func shadowSelectionDoesNotFavorRunningWhenStrengthWasCompleted() {
        let history = [GoalDailyShadowPolicy.CompletedDay(discipline: .strength, date: testDate.addingTimeInterval(-86_400))]
        let decision = GoalDailyShadowPolicy.select(
            candidates: shadowCandidates, history: history, on: testDate, readinessScore: 87
        )
        #expect(decision.selectedGoalID == shadowCandidates[0].goalID)
    }

    @Test func shadowSelectionCountsTrainingDaysNotIndividualStrengthSets() {
        let run = GoalDailyShadowPolicy.CompletedDay(discipline: .running, date: testDate.addingTimeInterval(-2 * 86_400))
        let set = GoalDailyShadowPolicy.CompletedDay(discipline: .strength, date: testDate.addingTimeInterval(-86_400))
        let decision = GoalDailyShadowPolicy.select(
            candidates: shadowCandidates, history: [run, set, set, set], on: testDate, readinessScore: 87
        )
        #expect(decision.rankings.map(\.completedDays) == [1, 1])
        #expect(decision.rankings.allSatisfy { $0.shareDeficit == 0 })
        #expect(decision.selectedGoalID == shadowCandidates[0].goalID)
    }

    @Test func shadowSelectionSurfacesExactTiesRatherThanPickingAlphabetically() {
        let decision = GoalDailyShadowPolicy.select(
            candidates: shadowCandidates.reversed(), history: [], on: testDate, readinessScore: 87
        )
        #expect(decision.selectedGoalID == nil)
        #expect(Set(decision.choiceGoalIDs) == Set(shadowCandidates.map(\.goalID)))
    }

    @Test func shadowSelectionBlocksMissingOrNonProceedReadiness() {
        let scores: [Int?] = [nil, -1, 35, 69, 101]
        for score in scores {
            let decision = GoalDailyShadowPolicy.select(
                candidates: shadowCandidates, history: [], on: testDate, readinessScore: score
            )
            #expect(decision.selectedGoalID == nil)
            #expect(decision.choiceGoalIDs.isEmpty)
            #expect(decision.blocker != nil)
        }
    }

    @Test func shadowSelectionPreservesExplicitChoiceAndDoesNotFillBlockedPrimaryWithSupport() {
        let preserved = GoalDailyShadowPolicy.select(
            candidates: shadowCandidates, history: [], on: testDate,
            readinessScore: nil, preserveUserChoice: true
        )
        #expect(preserved.preservesUserChoice)
        #expect(preserved.selectedGoalID == nil)
        let candidates = [
            GoalDailyShadowPolicy.Candidate(goalID: shadowCandidates[0].goalID, discipline: .running, isPrimary: true, blocker: "No recent run"),
            GoalDailyShadowPolicy.Candidate(goalID: shadowCandidates[1].goalID, discipline: .strength, isPrimary: false, blocker: nil)
        ]
        let blocked = GoalDailyShadowPolicy.select(candidates: candidates, history: [], on: testDate, readinessScore: 87)
        #expect(blocked.selectedGoalID == nil)
        #expect(blocked.blocker != nil)
    }

    @Test func shadowSelectionRejectsAnotherSessionTodayAndIgnoresFutureAndOldHistory() {
        let completed = GoalDailyShadowPolicy.CompletedDay(discipline: .running, date: testDate)
        let blocked = GoalDailyShadowPolicy.select(
            candidates: shadowCandidates, history: [completed], on: testDate, readinessScore: 87
        )
        #expect(blocked.blocker != nil)
        let outside = [
            GoalDailyShadowPolicy.CompletedDay(discipline: .running, date: testDate.addingTimeInterval(86_400)),
            GoalDailyShadowPolicy.CompletedDay(discipline: .strength, date: testDate.addingTimeInterval(-8 * 86_400))
        ]
        let decision = GoalDailyShadowPolicy.select(candidates: shadowCandidates, history: outside, on: testDate, readinessScore: 87)
        #expect(decision.choiceGoalIDs.count == 2)
        #expect(decision.rankings.allSatisfy { $0.completedDays == 0 })
    }

    private var shadowCandidates: [GoalDailyShadowPolicy.Candidate] {
        [
            .init(goalID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, discipline: .running, isPrimary: true, blocker: nil),
            .init(goalID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, discipline: .strength, isPrimary: true, blocker: nil)
        ]
    }

    @Test func unscheduledRecommendationDoesNotClaimAPlanExists() {
        let recommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: nil,
            profile: profile([(.running, .primary, 3)]),
            recentCompletedWorkouts: [], readinessScore: 87,
            schedulingContext: context(on: testDate)
        )
        #expect(recommendation.detail == "Your readiness supports training today.")
        #expect(recommendation.schedulingReason == .profileFrequency)
    }

    @Test func scheduledRecommendationKeepsPlanSpecificGuidance() {
        let planned = workout(type: .easyRun, date: testDate, title: "Scheduled easy run", isCompleted: false)
        let recommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: planned,
            profile: profile([(.running, .primary, 3)]),
            recentCompletedWorkouts: [], readinessScore: 87,
            schedulingContext: context(on: testDate)
        )
        #expect(recommendation.detail == "Your readiness supports the planned training.")
        #expect(recommendation.title == planned.title)
        #expect(recommendation.adjustment == .keepPlan)
    }

    @Test func explanationPreservesMissingReadinessWithoutInventingAScore() {
        let explanation = TodayRecommendationExplanation.evaluate(
            date: testDate, profile: profile([(.strength, .primary, 2)]),
            plannedWorkout: nil, planWorkouts: [], activities: [], readinessScore: nil
        )
        #expect(explanation.readinessScore == nil)
        #expect(explanation.recommendation.directive == .unknown)
        #expect(explanation.didRankAlternatives)
        #expect(explanation.evaluatedAt == testDate)
        #expect(explanation.completedWorkouts.isEmpty)
    }

    @Test func explanationSeparatesCompletedMissedAndFutureSessions() {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: testDate)!
        let earlier = calendar.date(byAdding: .day, value: -2, to: testDate)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: testDate)!
        let completed = workout(type: .easyRun, date: earlier, title: "Finished run")
        let missed = workout(type: .longRun, date: yesterday, title: "Missed run", isCompleted: false)
        let future = workout(type: .longRun, date: tomorrow, title: "Upcoming run", isCompleted: false)
        let explanation = TodayRecommendationExplanation.evaluate(
            date: testDate, profile: profile([(.running, .primary, 3), (.strength, .primary, 2)]),
            plannedWorkout: nil, planWorkouts: [completed, missed, future],
            activities: [], readinessScore: 82
        )
        #expect(explanation.completedWorkouts.map(\.id) == [completed.id])
        #expect(explanation.reservedFutureSessionCount == 1)
        #expect(explanation.nextPlannedWorkout == .longRun)
        #expect(explanation.readinessScore == 82)
        #expect(explanation.recommendation.workoutType != .fullBody)
    }

    @Test func explanationDoesNotClaimRankingWhenThePlanIsKept() {
        let planned = workout(type: .easyRun, date: testDate, title: "Planned easy run", isCompleted: false)
        let explanation = TodayRecommendationExplanation.evaluate(
            date: testDate, profile: profile([(.running, .primary, 3)]),
            plannedWorkout: planned, planWorkouts: [planned], activities: [], readinessScore: 82
        )
        #expect(!explanation.didRankAlternatives)
        #expect(explanation.recommendation.title == planned.title)
        #expect(explanation.recommendation.schedulingReason == .requiredPrimary)
        #expect(explanation.reservedFutureSessionCount == 0)
    }

    @Test func explanationKeepsLowReadinessAttachedToItsRecoveryDecision() {
        let explanation = TodayRecommendationExplanation.evaluate(
            date: testDate, profile: profile([(.running, .primary, 3), (.mobility, .supporting, 1)]),
            plannedWorkout: nil, planWorkouts: [], activities: [], readinessScore: 35
        )
        #expect(explanation.readinessScore == 35)
        #expect(explanation.recommendation.directive == .recover)
        #expect(explanation.recommendation.workoutType?.activity == .mobility)
        #expect(explanation.didRankAlternatives)
    }

    @Test func recordedSportWinsOverConflictingActivityNames() {
        let cases: [(String, String, WorkoutType)] = [
            ("Ride", "Run recovery ride", .cycling),
            ("Swim", "Long run recovery", .swimming),
            ("WeightTraining", "Run strength session", .strengthTraining),
            ("Walk", "Long run route preview", .walking),
            ("Hike", "Run trail scouting", .hiking),
            ("Yoga", "Run recovery flow", .yoga),
            ("Run", "Bike path workout", .easyRun)
        ]
        for (type, name, expected) in cases {
            let built = contextForRecordedActivity(type: type, name: name)
            #expect(built.recentCompletedWorkouts.count == 1)
            #expect(built.schedulingContext.previousWorkout == expected)
            #expect(built.schedulingContext.assignedWorkoutTypes == [expected])
        }
    }

    @Test func unknownActivityTypesDoNotInferWorkloadFromNames() {
        let types: [String?] = [nil, "", "Workout", "Crossfit", "Other", "RunAnalysis", "WalkingTourVideo"]
        for type in types {
            let built = contextForRecordedActivity(type: type, name: "Long run and weight training")
            #expect(built.recentCompletedWorkouts.isEmpty)
            #expect(built.schedulingContext.previousWorkout == nil)
            #expect(built.schedulingContext.assignedWorkoutTypes.isEmpty)
        }
    }

    @Test func supportedRecordedTypeAliasesDoNotNeedDescriptiveNames() {
        let cases: [(String, WorkoutType)] = [
            ("Run", .easyRun), ("Running", .easyRun), ("TrailRun", .easyRun),
            ("TrailRunning", .easyRun), ("VirtualRun", .easyRun),
            ("Treadmill", .easyRun), ("TreadmillRun", .easyRun), ("Jogging", .easyRun),
            ("Ride", .cycling), ("VirtualRide", .cycling), ("EBikeRide", .cycling),
            ("MountainBikeRide", .cycling), ("GravelRide", .cycling),
            ("Cycling", .cycling), ("IndoorCycling", .cycling),
            ("Swim", .swimming), ("Swimming", .swimming),
            ("Walk", .walking), ("Walking", .walking), ("Hike", .hiking),
            ("Hiking", .hiking), ("Yoga", .yoga), ("Mobility", .stretchMobility),
            ("Stretching", .stretchMobility), ("WeightTraining", .strengthTraining),
            ("StrengthTraining", .strengthTraining),
            ("FunctionalStrengthTraining", .strengthTraining),
            ("TraditionalStrengthTraining", .strengthTraining),
            ("  trail_running  ", .easyRun), ("weight-training", .strengthTraining)
        ]
        for (type, expected) in cases {
            let built = contextForRecordedActivity(type: type, name: "Morning session")
            #expect(built.recentCompletedWorkouts.first?.workoutType == expected)
        }
    }

    @Test func longRunNameRefinesOnlyConfirmedRunningActivity() {
        let built = contextForRecordedActivity(type: "Run", name: "Sunday Long Run")
        #expect(built.recentCompletedWorkouts.first?.workoutType == .longRun)
        #expect(built.schedulingContext.previousWorkout == .longRun)
    }

    private func contextForRecordedActivity(type: String?, name: String) -> TodayRecommendationContext {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: testDate)!
        let activity = Activity(
            id: 8_001, name: name, type: type, distance: 5_000,
            elapsed_time: 1_800, activity_date: yesterday.timeIntervalSince1970
        )
        return TodayRecommendationContextBuilder.build(
            date: testDate,
            profile: profile([(.running, .primary, 3), (.strength, .primary, 2)]),
            plannedWorkout: nil, planWorkouts: [], activities: [activity], readinessScore: 82
        )
    }

    @Test func missedLongRunDoesNotCreateRecoveryLoad() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: testDate)!
        let activeProfile = profile([(.running, .primary, 3), (.strength, .primary, 2)])
        let missed = workout(type: .longRun, date: yesterday, title: "Missed long run", isCompleted: false)
        let built = TodayRecommendationContextBuilder.build(
            date: testDate, profile: activeProfile, plannedWorkout: nil,
            planWorkouts: [missed], activities: [], readinessScore: 82
        )

        #expect(built.recentCompletedWorkouts.isEmpty)
        #expect(built.schedulingContext.previousWorkout == nil)
        #expect(built.schedulingContext.assignedWorkoutTypes.isEmpty)
        #expect(ComplementarySchedulingPolicy.evaluation(
            of: .fullBody, for: built.schedulingContext
        ).rejectionReason == nil)
        let recommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: nil, profile: activeProfile,
            recentCompletedWorkouts: built.recentCompletedWorkouts,
            readinessScore: 82, schedulingContext: built.schedulingContext
        )
        #expect(recommendation.schedulingReason != .preservesLegRecovery)
    }

    @Test func twoIdleDaysDoNotSatisfyTrainingFrequency() {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: testDate)!
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: testDate)!
        let activeProfile = profile([(.strength, .primary, 2)])
        let missed = [
            workout(type: .fullBody, date: twoDaysAgo, title: "Missed strength", isCompleted: false),
            workout(type: .upperBody, date: yesterday, title: "Missed strength", isCompleted: false)
        ]
        let built = TodayRecommendationContextBuilder.build(
            date: testDate, profile: activeProfile, plannedWorkout: nil,
            planWorkouts: missed, activities: [], readinessScore: 82
        )
        let recommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: nil, profile: activeProfile,
            recentCompletedWorkouts: built.recentCompletedWorkouts,
            readinessScore: 82, schedulingContext: built.schedulingContext
        )

        #expect(built.recentCompletedWorkouts.isEmpty)
        #expect(built.schedulingContext.assignedWorkoutTypes.isEmpty)
        #expect(recommendation.workoutType?.isStrength == true)
        #expect(recommendation.schedulingReason == .profileFrequency)
    }

    @Test func futureLongRunStillConstrainsStrengthWithoutBecomingCompletedLoad() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: testDate)!
        let planned = workout(type: .longRun, date: tomorrow, title: "Upcoming long run", isCompleted: false)
        let built = TodayRecommendationContextBuilder.build(
            date: testDate,
            profile: profile([(.running, .primary, 3), (.strength, .primary, 2)]),
            plannedWorkout: nil, planWorkouts: [planned], activities: [], readinessScore: 82
        )

        #expect(built.recentCompletedWorkouts.isEmpty)
        #expect(built.schedulingContext.previousWorkout == nil)
        #expect(built.schedulingContext.nextWorkout == .longRun)
        #expect(built.schedulingContext.assignedWorkoutTypes == [.longRun])
        #expect(ComplementarySchedulingPolicy.evaluation(
            of: .fullBody, for: built.schedulingContext
        ).rejectionReason == .lowerBodyRecoveryConflict)
    }

    @Test func completedLongRunStillCreatesRecoveryContext() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: testDate)!
        let completed = workout(type: .longRun, date: yesterday, title: "Completed long run")
        let built = TodayRecommendationContextBuilder.build(
            date: testDate,
            profile: profile([(.running, .primary, 3), (.strength, .primary, 2)]),
            plannedWorkout: nil, planWorkouts: [completed], activities: [], readinessScore: 82
        )

        #expect(built.recentCompletedWorkouts.count == 1)
        #expect(built.schedulingContext.previousWorkout == .longRun)
        #expect(built.schedulingContext.assignedWorkoutTypes == [.longRun])
        #expect(ComplementarySchedulingPolicy.evaluation(
            of: .fullBody, for: built.schedulingContext
        ).rejectionReason == .lowerBodyRecoveryConflict)
    }

    @Test func recommendationDoesNotUseUnsubstantiatedPreviousSchedulingSlot() {
        let activeProfile = profile([(.strength, .primary, 2)])
        let staleContext = SchedulingDayContext(
            date: testDate, weekday: DayOfWeek.from(date: testDate), profile: activeProfile,
            plannedOrFixedWorkout: nil, previousWorkout: .longRun, nextWorkout: nil,
            readiness: .normal, assignedWorkoutTypes: [], isCompletedProtected: false,
            isUnavailable: false, isTaperProtected: false
        )
        let recommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: nil, profile: activeProfile, recentCompletedWorkouts: [],
            readinessScore: 82, schedulingContext: staleContext
        )

        #expect(recommendation.workoutType?.isStrength == true)
        #expect(recommendation.schedulingReason == .profileFrequency)
    }

    @Test func poorReadinessRecommendsRecovery() {
        let recommendation = TodayRecommendationPolicy.recommendation(readinessScore: 29)

        #expect(recommendation.directive == .recover)
        #expect(recommendation.status == "Recovery")
        #expect(recommendation.title == "Recovery Day")
    }

    @Test func lowReadinessRecommendsRecovery() {
        let recommendation = TodayRecommendationPolicy.recommendation(readinessScore: 30)

        #expect(recommendation.directive == .recover)
    }

    @Test func moderateReadinessReducesIntensity() {
        let recommendation = TodayRecommendationPolicy.recommendation(readinessScore: 50)

        #expect(recommendation.directive == .reduceIntensity)
        #expect(recommendation.status == "Adjusted")
    }

    @Test func goodReadinessPreservesThePlan() {
        let recommendation = TodayRecommendationPolicy.recommendation(readinessScore: 70)

        #expect(recommendation.directive == .proceed)
    }

    @Test func missingReadinessDoesNotInventRecoveryAdvice() {
        let recommendation = TodayRecommendationPolicy.recommendation(readinessScore: nil)

        #expect(recommendation.directive == .unknown)
        #expect(recommendation.status == "Check In")
    }

    @Test func runningAndStrengthRecommendsUpperBodyAfterYesterdayLongRun() throws {
        let date = testDate
        let previous = workout(type: .longRun, date: date.addingTimeInterval(-86_400), title: "Long Run")
        let recommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: nil,
            profile: profile([(.running, .primary, 3), (.strength, .supporting, 2)]),
            recentCompletedWorkouts: [previous],
            readinessScore: 82,
            schedulingContext: context(on: date)
        )

        #expect(recommendation.workoutType == .upperBody)
        #expect(recommendation.title == "Upper Body")
        #expect(recommendation.reason == "Placed after yesterday's long run to preserve leg recovery.")
        #expect(recommendation.schedulingReason == .preservesLegRecovery)
    }

    @Test func runningOnlyFallbackExcludesUnselectedSupportingActivities() throws {
        let recommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: nil,
            profile: profile([(.running, .primary, 4)]),
            recentCompletedWorkouts: [],
            readinessScore: 78,
            schedulingContext: context(on: testDate)
        )
        let workoutType = try #require(recommendation.workoutType)

        #expect(workoutType.isRunning || workoutType == .rest)
        #expect(!workoutType.isStrength)
        #expect(workoutType != .cycling)
        #expect(workoutType != .swimming)
    }

    @Test func lowReadinessChoosesSelectedRecoveryWithoutHighOrLowerBodyLoad() throws {
        let recommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: workout(type: .tempoRun, date: testDate, title: "Tempo Run"),
            profile: profile([
                (.running, .primary, 3),
                (.strength, .supporting, 2),
                (.mobility, .supporting, 1)
            ]),
            recentCompletedWorkouts: [],
            readinessScore: 38,
            schedulingContext: context(on: testDate)
        )
        let workoutType = try #require(recommendation.workoutType)

        #expect(workoutType.activity == .mobility)
        #expect(workoutType.isRecoveryCompatible)
        #expect(!workoutType.isHighIntensity)
        #expect(!workoutType.isLowerBodyDemanding)
        #expect(recommendation.adjustment == .recoveryDay)
    }

    @Test func selectedPlannedWorkoutSurvivesProceedReadinessUnchanged() {
        let planned = workout(type: .tempoRun, date: testDate, title: "Threshold Progression")
        let recommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: planned,
            profile: profile([(.running, .primary, 4)]),
            recentCompletedWorkouts: [],
            readinessScore: 84,
            schedulingContext: context(on: testDate)
        )

        #expect(recommendation.directive == .proceed)
        #expect(recommendation.workoutType == planned.workoutType)
        #expect(recommendation.title == planned.title)
        #expect(recommendation.schedulingReason == .requiredPrimary)
        #expect(recommendation.reason == "Scheduled in your plan.")
        #expect(recommendation.adjustment == .keepPlan)
    }

    @Test func moderateReadinessReturnsEasierSelectedWorkoutInsteadOfPlannedType() throws {
        let planned = workout(type: .tempoRun, date: testDate, title: "Threshold Progression")
        let recommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: planned,
            profile: profile([(.running, .primary, 4)]),
            recentCompletedWorkouts: [],
            readinessScore: 58,
            schedulingContext: context(on: testDate)
        )
        let workoutType = try #require(recommendation.workoutType)

        #expect(recommendation.directive == .reduceIntensity)
        #expect(workoutType != planned.workoutType)
        #expect(workoutType.activity == .running)
        #expect(workoutType.loadClass < planned.workoutType.loadClass)
        #expect(recommendation.title == workoutType.displayName)
        #expect(recommendation.adjustment == .easierWorkout)
    }

    @Test func productionContextConvertsActualLongRunAndDeduplicatesSynchronizedPlanWorkout() throws {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: testDate)!
        let syncedPlanWorkout = workout(
            type: .easyRun,
            date: yesterday,
            title: "Planned Run",
            completedActivityId: 7_001
        )
        let activity = Activity(
            id: 7_001,
            name: "Sunday Long Run",
            type: "Run",
            distance: 18_000,
            elapsed_time: 6_000,
            activity_date: yesterday.addingTimeInterval(12 * 60 * 60).timeIntervalSince1970
        )

        let built = TodayRecommendationContextBuilder.build(
            date: testDate,
            profile: profile([(.running, .primary, 3), (.strength, .supporting, 2)]),
            plannedWorkout: nil,
            planWorkouts: [syncedPlanWorkout],
            activities: [activity],
            readinessScore: 80
        )
        let completed = try #require(built.recentCompletedWorkouts.first)

        #expect(built.recentCompletedWorkouts.count == 1)
        #expect(completed.workoutType == .longRun)
        #expect(completed.isCompleted)
        #expect(completed.completedActivityId == activity.id)
        #expect(built.schedulingContext.previousWorkout == .longRun)
        #expect(built.schedulingContext.assignedWorkoutTypes.filter { $0 == .longRun }.count == 1)
        #expect(built.schedulingContext.assignedWorkoutTypes.count == 1)
    }

    @Test func presentationUsesDisplayNameSemanticAccentAndPlannedReason() {
        let planned = workout(type: .tempoRun, date: testDate, title: "Threshold Progression")
        let plannedRecommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: planned,
            profile: profile([(.running, .primary, 4)]),
            recentCompletedWorkouts: [],
            readinessScore: 82,
            schedulingContext: context(on: testDate)
        )
        let plannedPresentation = TodayRecommendationPresentation(recommendation: plannedRecommendation)

        #expect(plannedPresentation.badgeText == WorkoutType.tempoRun.displayName)
        #expect(plannedPresentation.accent == .runningPrimary)
        #expect(plannedPresentation.reason == "Scheduled in your plan.")

        let aerobicRecommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: nil,
            profile: profile([(.cycling, .primary, 3)]),
            recentCompletedWorkouts: [],
            readinessScore: 82,
            schedulingContext: context(on: testDate)
        )
        let aerobicPresentation = TodayRecommendationPresentation(recommendation: aerobicRecommendation)
        #expect(aerobicPresentation.badgeText == WorkoutType.cycling.displayName)
        #expect(aerobicPresentation.accent == .aerobic)

        let recoveryRecommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: nil,
            profile: profile([(.mobility, .primary, 3)]),
            recentCompletedWorkouts: [],
            readinessScore: 35,
            schedulingContext: context(on: testDate)
        )
        let recoveryPresentation = TodayRecommendationPresentation(recommendation: recoveryRecommendation)
        #expect(!recoveryPresentation.badgeText.contains("_"))
        #expect(recoveryPresentation.accent == .recovery)
        #expect(recoveryPresentation.reason?.isEmpty == false)
    }

    @Test func unselectedPlannedSupportIsReplacedBySelectedAlternative() throws {
        let recommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: workout(type: .cycling, date: testDate, title: "Aerobic Ride"),
            profile: profile([(.running, .primary, 4)]),
            recentCompletedWorkouts: [],
            readinessScore: 80,
            schedulingContext: context(on: testDate)
        )
        let workoutType = try #require(recommendation.workoutType)

        #expect(workoutType.isRunning)
        #expect(workoutType != .cycling)
        #expect(recommendation.title == workoutType.displayName)
    }

    @Test func generatedRecommendationLabelsAreHumanReadable() throws {
        let recommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: nil,
            profile: profile([(.running, .primary, 4), (.strength, .supporting, 2)]),
            recentCompletedWorkouts: [],
            readinessScore: 80,
            schedulingContext: context(on: testDate)
        )
        let workoutType = try #require(recommendation.workoutType)

        #expect(recommendation.title == workoutType.displayName)
        #expect(recommendation.badgeTitle == workoutType.displayName)
        #expect(!recommendation.title.contains("_"))
        #expect(!recommendation.badgeTitle.contains("_"))
    }

    @Test func recoveryChoiceOnlyReplacesTargetDayAndRecalculatesMileage() throws {
        let fixture = makePlan()
        let result = try #require(TodayRecommendationPolicy.applying(
            .recoveryDay,
            to: fixture.plan,
            on: fixture.today,
            readinessScore: 42
        ))

        #expect(result.updatedWorkout.workoutType == WorkoutType.rest)
        #expect(result.updatedWorkout.distance == nil)
        #expect(result.plan.workouts[1].id == "tomorrow")
        #expect(result.plan.workouts[1].distance == 4)
        #expect(result.plan.totalMileage == 4)
        #expect(result.receiptDetail.contains("42"))
    }

    @Test func userSelectedRecoveryRemainsVisibleWhenReadinessImproves() throws {
        let fixture = makePlan()
        let result = try #require(TodayRecommendationPolicy.applying(
            .recoveryDay,
            to: fixture.plan,
            on: fixture.today,
            readinessScore: 42
        ))

        let recommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: result.updatedWorkout,
            profile: profile([(.running, .primary, 3), (.mobility, .supporting, 1)]),
            recentCompletedWorkouts: [],
            readinessScore: 73,
            schedulingContext: context(on: fixture.today)
        )

        #expect(recommendation.workoutType == .rest)
        #expect(recommendation.title == result.updatedWorkout.title)
        #expect(recommendation.status == "Your Choice")
        #expect(recommendation.adjustment == .keepPlan)
    }

    @Test func easierChoiceReducesDistanceAndRemovesIntensity() throws {
        let fixture = makePlan()
        let result = try #require(TodayRecommendationPolicy.applying(
            .easierWorkout,
            to: fixture.plan,
            on: fixture.today,
            readinessScore: 58
        ))

        #expect(result.updatedWorkout.workoutType == WorkoutType.recoveryRun)
        #expect(abs((result.updatedWorkout.distance ?? 0) - 3.9) < 0.001)
        #expect(result.updatedWorkout.duration == 34)
        #expect(result.updatedWorkout.targetPace == "Conversational effort")
        #expect(abs(result.plan.totalMileage - 7.9) < 0.001)
    }

    @Test func keepingPlanDoesNotCreateAnAdjustment() {
        let fixture = makePlan()
        let result = TodayRecommendationPolicy.applying(
            .keepPlan,
            to: fixture.plan,
            on: fixture.today,
            readinessScore: 40
        )

        #expect(result == nil)
    }

    @Test func moderateReadinessOffersProfileSelectedWorkoutAlternatives() {
        let alternatives = TodayRecommendationPolicy.workoutAlternatives(
            profile: profile([
                (.running, .primary, 3),
                (.strength, .supporting, 2),
                (.mobility, .optional, 1)
            ]),
            readinessScore: 58
        )

        #expect(alternatives.contains(.recoveryRun))
        #expect(alternatives.contains(.upperBody))
        #expect(!alternatives.contains {
            $0.isHighIntensity || ($0.isLowerBodyDemanding && !$0.isRecoveryCompatible)
        })
    }

    @Test func allSafeProfileActivitiesAppearAsWorkoutAlternatives() {
        let alternatives = TodayRecommendationPolicy.workoutAlternatives(
            profile: profile([
                (.running, .primary, 3),
                (.strength, .supporting, 2),
                (.walking, .supporting, 1),
                (.mobility, .supporting, 1)
            ]),
            readinessScore: 73
        )

        #expect(alternatives == [.easyRun, .stretchMobility, .upperBody, .walking])
    }

    @Test func normalPlannedWorkoutStillOffersTrainingChoice() {
        let plannedWorkout = makePlan().plan.workouts.first

        #expect(TodayRecommendationPolicy.canChooseTodaysTraining(
            plannedWorkout: plannedWorkout,
            hasCompletedActivity: false
        ))
        #expect(!TodayRecommendationPolicy.canChooseTodaysTraining(
            plannedWorkout: plannedWorkout,
            hasCompletedActivity: true
        ))
    }

    @Test func missingTrainingProfileBlocksWorkoutAlternatives() {
        #expect(TrainingChoiceAvailabilityPolicy.requiresProfileSetup(
            needsPersonalization: true
        ))
        #expect(!TrainingChoiceAvailabilityPolicy.requiresProfileSetup(
            needsPersonalization: false
        ))
    }

    @Test func chosenWorkoutCanReplaceAPlannedRestDay() throws {
        let fixture = makePlan()
        let original = fixture.plan.workouts[0]
        let rest = DailyWorkout(
            id: original.id,
            date: original.date,
            dayOfWeek: original.dayOfWeek,
            workoutType: .rest,
            title: "Rest Day",
            description: "Recover.",
            duration: nil,
            distance: nil,
            targetPace: nil,
            exercises: nil,
            isCompleted: false,
            completedActivityId: nil
        )
        var workouts = fixture.plan.workouts
        workouts[0] = rest
        let restPlan = WeeklyTrainingPlan(
            id: fixture.plan.id,
            athleteId: fixture.plan.athleteId,
            weekStartDate: fixture.plan.weekStartDate,
            weekEndDate: fixture.plan.weekEndDate,
            workouts: workouts,
            weekNumber: fixture.plan.weekNumber,
            totalMileage: workouts.filter { $0.workoutType.isRunning }.compactMap(\.distance).reduce(0, +),
            focusArea: fixture.plan.focusArea,
            notes: fixture.plan.notes,
            generatedAt: fixture.plan.generatedAt,
            goalId: fixture.plan.goalId
        )

        let result = try #require(TodayRecommendationPolicy.applying(
            .chosenWorkout(.upperBody),
            to: restPlan,
            on: fixture.today,
            readinessScore: 58
        ))

        #expect(result.updatedWorkout.workoutType == .upperBody)
        #expect(result.updatedWorkout.duration != nil)
        #expect(result.plan.workouts[1].id == restPlan.workouts[1].id)
    }

    @Test func chosenWorkoutCanFillAnEmptyPlanDay() throws {
        let fixture = makePlan()
        let emptyDate = Calendar.current.date(
            byAdding: .day,
            value: 2,
            to: fixture.today
        )!

        let result = try #require(TodayRecommendationPolicy.applying(
            .chosenWorkout(.upperBody),
            to: fixture.plan,
            on: emptyDate,
            readinessScore: 73
        ))

        #expect(result.plan.workouts.count == fixture.plan.workouts.count + 1)
        #expect(result.updatedWorkout.workoutType == .upperBody)
        #expect(Calendar.current.isDate(result.updatedWorkout.date, inSameDayAs: emptyDate))
    }

    @Test func adaptiveChoiceUsesRemainingWeekRegeneratorAndReportsFutureChanges() async throws {
        let fixture = makePlan()
        let local = try #require(TodayRecommendationPolicy.applying(
            .recoveryDay,
            to: fixture.plan,
            on: fixture.today,
            readinessScore: 42
        ))
        let originalTomorrow = local.plan.workouts[1]
        let revisedTomorrow = DailyWorkout(
            id: originalTomorrow.id,
            date: originalTomorrow.date,
            dayOfWeek: originalTomorrow.dayOfWeek,
            workoutType: .stretchMobility,
            title: "Mobility",
            description: "Rebalanced.",
            duration: 20,
            distance: nil,
            targetPace: nil,
            exercises: nil,
            isCompleted: false,
            completedActivityId: nil
        )
        var revisedWorkouts = local.plan.workouts
        revisedWorkouts[1] = revisedTomorrow
        let revisedPlan = WeeklyTrainingPlan(
            id: local.plan.id,
            athleteId: local.plan.athleteId,
            weekStartDate: local.plan.weekStartDate,
            weekEndDate: local.plan.weekEndDate,
            workouts: revisedWorkouts,
            weekNumber: local.plan.weekNumber,
            totalMileage: revisedWorkouts.filter { $0.workoutType.isRunning }.compactMap(\.distance).reduce(0, +),
            focusArea: local.plan.focusArea,
            notes: local.plan.notes,
            generatedAt: local.plan.generatedAt,
            goalId: local.plan.goalId
        )

        let adapted = try await TodayRecommendationPolicy.adaptingRemainingWeek(
            local,
            profile: profile([(.running, .primary, 4)]),
            on: fixture.today,
            regenerate: { input, _ in
                #expect(input.workouts[0].workoutType == .rest)
                return revisedPlan
            }
        )

        #expect(adapted.plan.workouts[1].workoutType == .stretchMobility)
        #expect(adapted.receiptDetail.contains("Rebalanced"))
    }

    @Test func genericRecordedRunCannotDowngradeLinkedPlannedLongRun() throws {
        let calendar = Calendar(identifier: .gregorian)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: testDate))
        let activeProfile = profile([
            (.running, .primary, 4),
            (.strength, .supporting, 2),
        ])
        let plannedLongRun = workout(
            type: .longRun,
            date: yesterday,
            title: "Planned Long Run",
            completedActivityId: 7001
        )
        let genericRecordedRun = Activity(
            id: 7001,
            name: "Morning Run",
            type: "Run",
            distance: 16_093.44,
            start_date: yesterday.timeIntervalSince1970,
            elapsed_time: 4_800,
            athlete_id: 1,
            activity_date: yesterday.timeIntervalSince1970
        )

        let context = TodayRecommendationContextBuilder.build(
            date: testDate,
            profile: activeProfile,
            plannedWorkout: nil,
            planWorkouts: [plannedLongRun],
            activities: [genericRecordedRun],
            readinessScore: 82,
            calendar: calendar
        )

        #expect(context.recentCompletedWorkouts.count == 1)
        #expect(context.recentCompletedWorkouts.first?.workoutType == .longRun)
        #expect(context.schedulingContext.previousWorkout == .longRun)
        #expect(context.schedulingContext.assignedWorkoutTypes.filter { $0 == .longRun }.count == 1)
        #expect(context.schedulingContext.assignedWorkoutTypes.count == 1)

        let recommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: nil,
            profile: activeProfile,
            recentCompletedWorkouts: context.recentCompletedWorkouts,
            readinessScore: 82,
            schedulingContext: context.schedulingContext
        )

        #expect(recommendation.workoutType == .upperBody)
        #expect(recommendation.schedulingReason == .preservesLegRecovery)
        #expect(recommendation.reason == "Placed after yesterday's long run to preserve leg recovery.")
    }

    @Test func explicitlyRecordedLongRunWinsEqualSpecificityPlannedQualityTypes() throws {
        let calendar = Calendar(identifier: .gregorian)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: testDate))
        let activeProfile = profile([(.running, .primary, 4)])

        for (index, plannedType) in [WorkoutType.tempoRun, .intervalRun, .hillRun].enumerated() {
            let activityID = 7_101 + index
            let plannedWorkout = workout(
                type: plannedType,
                date: yesterday,
                title: "Planned \(plannedType.displayName)",
                completedActivityId: activityID
            )
            let recordedLongRun = Activity(
                id: activityID,
                name: "Long Run",
                type: "Run",
                distance: 16_093.44,
                start_date: yesterday.timeIntervalSince1970,
                elapsed_time: 4_800,
                athlete_id: 1,
                activity_date: yesterday.timeIntervalSince1970
            )

            let context = TodayRecommendationContextBuilder.build(
                date: testDate,
                profile: activeProfile,
                plannedWorkout: nil,
                planWorkouts: [plannedWorkout],
                activities: [recordedLongRun],
                readinessScore: 82,
                calendar: calendar
            )

            #expect(context.recentCompletedWorkouts.count == 1)
            #expect(context.recentCompletedWorkouts.first?.workoutType == .longRun)
            #expect(context.schedulingContext.previousWorkout == .longRun)
            #expect(context.schedulingContext.assignedWorkoutTypes == [.longRun])
        }
    }

    @Test func genericRecordedRunNeverDowngradesSpecificPlannedRunTypes() throws {
        let calendar = Calendar(identifier: .gregorian)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: testDate))
        let activeProfile = profile([(.running, .primary, 4)])

        for (index, plannedType) in [WorkoutType.longRun, .tempoRun, .intervalRun, .hillRun].enumerated() {
            let activityID = 7_201 + index
            let plannedWorkout = workout(
                type: plannedType,
                date: yesterday,
                title: "Planned \(plannedType.displayName)",
                completedActivityId: activityID
            )
            let genericRecordedRun = Activity(
                id: activityID,
                name: "Morning Run",
                type: "Run",
                distance: 8_046.72,
                start_date: yesterday.timeIntervalSince1970,
                elapsed_time: 2_400,
                athlete_id: 1,
                activity_date: yesterday.timeIntervalSince1970
            )

            let context = TodayRecommendationContextBuilder.build(
                date: testDate,
                profile: activeProfile,
                plannedWorkout: nil,
                planWorkouts: [plannedWorkout],
                activities: [genericRecordedRun],
                readinessScore: 82,
                calendar: calendar
            )

            #expect(context.recentCompletedWorkouts.count == 1)
            #expect(context.recentCompletedWorkouts.first?.workoutType == plannedType)
            #expect(context.schedulingContext.previousWorkout == plannedType)
            #expect(context.schedulingContext.assignedWorkoutTypes == [plannedType])
        }
    }

    @Test @MainActor func adjustmentReceiptCanBeUndoneAndRestoredPlanReplacesCache() throws {
        let fixture = makePlan()
        let profile = profile([(.running, .primary, 4)])
        let manager = DataManager.shared
        let originalActive = manager.currentWeeklyPlan
        let restoreCache = snapshotStandardCache()
        defer {
            manager.currentWeeklyPlan = originalActive
            restoreCache()
        }
        manager.currentWeeklyPlan = fixture.plan
        let adjustment = try #require(TodayRecommendationPolicy.applying(
            .easierWorkout,
            to: fixture.plan,
            on: fixture.today,
            readinessScore: 58
        ))

        try manager.updateCurrentWeeklyPlan(adjustment.plan, profile: profile)
        #expect(manager.currentWeeklyPlan?.workouts.first?.workoutType == .recoveryRun)
        #expect(!adjustment.receiptTitle.isEmpty)
        #expect(!adjustment.receiptDetail.isEmpty)

        try manager.updateCurrentWeeklyPlan(fixture.plan, profile: profile)
        #expect(manager.currentWeeklyPlan?.id == fixture.plan.id)
        #expect(manager.currentWeeklyPlan?.workouts.map(\.id) == fixture.plan.workouts.map(\.id))
        #expect(manager.currentWeeklyPlan?.workouts.map(\.workoutType) == fixture.plan.workouts.map(\.workoutType))
        guard case let .valid(cached) = TrainingPlanService.cachedPlanStatus(for: profile) else {
            Issue.record("Expected Undo to restore the cached original plan")
            return
        }
        #expect(cached.id == fixture.plan.id)
        #expect(cached.workouts.map(\.id) == fixture.plan.workouts.map(\.id))
        #expect(cached.workouts.map(\.workoutType) == fixture.plan.workouts.map(\.workoutType))
    }

    @Test @MainActor func profilelessProductionUpdateRestoresActiveAndCachedPrescriptionOnUndo() throws {
        let fixture = makePlan()
        let activeProfile = profile([(.running, .primary, 4)])
        let manager = DataManager.shared
        let originalActive = manager.currentWeeklyPlan
        let restoreCache = snapshotStandardCache()
        let restoreProfile = snapshotStandardTrainingProfile()
        defer {
            manager.currentWeeklyPlan = originalActive
            restoreCache()
            restoreProfile()
        }

        try TrainingProfileStore().save(activeProfile)
        manager.currentWeeklyPlan = fixture.plan
        try manager.updateCurrentWeeklyPlan(fixture.plan)
        let adjustment = try #require(TodayRecommendationPolicy.applying(
            .easierWorkout,
            to: fixture.plan,
            on: fixture.today,
            readinessScore: 58
        ))

        try manager.updateCurrentWeeklyPlan(adjustment.plan)
        try manager.updateCurrentWeeklyPlan(fixture.plan)

        let restoredActive = try #require(manager.currentWeeklyPlan)
        #expect(restoredActive.id == fixture.plan.id)
        #expect(restoredActive.workouts.map(\.id) == fixture.plan.workouts.map(\.id))
        #expect(restoredActive.workouts.map(\.workoutType) == fixture.plan.workouts.map(\.workoutType))
        #expect(restoredActive.workouts.map(\.duration) == fixture.plan.workouts.map(\.duration))
        #expect(restoredActive.workouts.map(\.distance) == fixture.plan.workouts.map(\.distance))
        #expect(restoredActive.workouts.map(\.targetPace) == fixture.plan.workouts.map(\.targetPace))
        #expect(restoredActive.workouts.map(\.title) == fixture.plan.workouts.map(\.title))
        #expect(restoredActive.workouts.map(\.description) == fixture.plan.workouts.map(\.description))

        let storedProfile = TrainingProfileStore().profile
        #expect(storedProfile == activeProfile.validated(existingPlan: fixture.plan).profile)
        guard case let .valid(cached) = TrainingPlanService.cachedPlanStatus(for: storedProfile) else {
            Issue.record("Expected profile-less Undo to restore a cache-valid original plan")
            return
        }
        #expect(cached.id == fixture.plan.id)
        #expect(cached.workouts.map(\.id) == fixture.plan.workouts.map(\.id))
        #expect(cached.workouts.map(\.workoutType) == fixture.plan.workouts.map(\.workoutType))
        #expect(cached.workouts.map(\.duration) == fixture.plan.workouts.map(\.duration))
        #expect(cached.workouts.map(\.distance) == fixture.plan.workouts.map(\.distance))
        #expect(cached.workouts.map(\.targetPace) == fixture.plan.workouts.map(\.targetPace))
        #expect(cached.workouts.map(\.title) == fixture.plan.workouts.map(\.title))
        #expect(cached.workouts.map(\.description) == fixture.plan.workouts.map(\.description))
    }

    private var testDate: Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 8, day: 27))!
    }

    private func profile(
        _ preferences: [(TrainingActivity, TrainingActivityRole, Int)]
    ) -> TrainingProfile {
        TrainingProfile(
            schemaVersion: TrainingProfile.currentSchemaVersion,
            activities: preferences.map {
                TrainingActivityPreference(activity: $0.0, role: $0.1, sessionsPerWeek: $0.2)
            },
            trainingDaysPerWeek: 6,
            preferredLongRunWeekday: 1,
            unavailableWeekdays: [],
            strengthEquipment: .dumbbells,
            strengthExperience: .intermediate
        )
    }

    private func context(on date: Date) -> SchedulingDayContext {
        SchedulingDayContext(
            date: date,
            weekday: DayOfWeek.from(date: date),
            profile: .runningFirstDefault,
            plannedOrFixedWorkout: nil,
            previousWorkout: nil,
            nextWorkout: nil,
            readiness: .normal,
            assignedWorkoutTypes: [],
            isCompletedProtected: false,
            isUnavailable: false,
            isTaperProtected: false
        )
    }

    private func workout(
        type: WorkoutType,
        date: Date,
        title: String,
        completedActivityId: Int? = nil,
        isCompleted: Bool = true
    ) -> DailyWorkout {
        DailyWorkout(
            id: "\(type.rawValue)-\(date.timeIntervalSince1970)",
            date: date,
            dayOfWeek: DayOfWeek.from(date: date),
            workoutType: type,
            title: title,
            description: "Test workout",
            duration: 45,
            distance: type.isRunning ? 5 : nil,
            targetPace: type.isRunning ? "Conversational effort" : nil,
            exercises: nil,
            isCompleted: isCompleted,
            completedActivityId: completedActivityId
        )
    }

    private func snapshotStandardCache() -> () -> Void {
        let defaults = UserDefaults.standard
        let cachedPlan = defaults.object(forKey: TrainingPlanService.cacheKey)
        let expiration = defaults.object(forKey: TrainingPlanService.cacheExpirationKey)
        return {
            if let cachedPlan { defaults.set(cachedPlan, forKey: TrainingPlanService.cacheKey) }
            else { defaults.removeObject(forKey: TrainingPlanService.cacheKey) }
            if let expiration { defaults.set(expiration, forKey: TrainingPlanService.cacheExpirationKey) }
            else { defaults.removeObject(forKey: TrainingPlanService.cacheExpirationKey) }
        }
    }

    private func snapshotStandardTrainingProfile() -> () -> Void {
        let defaults = UserDefaults.standard
        let profile = defaults.object(forKey: "trainingProfile.v1")
        let personalized = defaults.object(forKey: "trainingProfile.personalized.v1")
        return {
            if let profile { defaults.set(profile, forKey: "trainingProfile.v1") }
            else { defaults.removeObject(forKey: "trainingProfile.v1") }
            if let personalized { defaults.set(personalized, forKey: "trainingProfile.personalized.v1") }
            else { defaults.removeObject(forKey: "trainingProfile.personalized.v1") }
        }
    }

    private func makePlan() -> (plan: WeeklyTrainingPlan, today: Date) {
        let calendar = Calendar(identifier: .gregorian)
        let currentDay = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: currentDay)
        let weekStart = calendar.date(byAdding: .day, value: -(weekday - 1), to: currentDay)!
        let today = calendar.date(byAdding: .day, value: 3, to: weekStart)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let workouts = [
            DailyWorkout(
                id: "today",
                date: today,
                dayOfWeek: DayOfWeek.from(date: today),
                workoutType: .tempoRun,
                title: "Tempo Run",
                description: "Planned quality session",
                duration: 45,
                distance: 6,
                targetPace: "8:00/mi",
                exercises: nil,
                isCompleted: false,
                completedActivityId: nil
            ),
            DailyWorkout(
                id: "tomorrow",
                date: tomorrow,
                dayOfWeek: DayOfWeek.from(date: tomorrow),
                workoutType: .easyRun,
                title: "Easy Run",
                description: "Easy miles",
                duration: 36,
                distance: 4,
                targetPace: "10:00/mi",
                exercises: nil,
                isCompleted: false,
                completedActivityId: nil
            )
        ]
        return (
            WeeklyTrainingPlan(
                id: "week",
                athleteId: 1,
                weekStartDate: weekStart,
                weekEndDate: calendar.date(byAdding: .day, value: 6, to: weekStart)!,
                workouts: workouts,
                weekNumber: 1,
                totalMileage: 10,
                focusArea: "Base",
                notes: nil,
                generatedAt: today,
                goalId: nil
            ),
            today
        )
    }
}

extension TodayRecommendationPolicyTests {
    @Test func numericProgressionRepeatsOneCompletedStrengthSession() {
        let result = sessionResultFixture()
        let proposal = SessionProgressionProposalPolicy.propose(goalID: result.reference.goalID, athleteID: 42, results: [result], on: result.recordedAt, availableSeconds: 1800)
        #expect(proposal.items.first?.repetitions == 8)
        #expect(proposal.items.first?.loadKilograms == 45)
        #expect(proposal.hasIncrease == false)
    }

    @Test func numericProgressionRequiresEquipmentIncrementAtRepCeiling() {
        let result = sessionResultFixture()
        let proposal = SessionProgressionProposalPolicy.propose(goalID: result.reference.goalID, athleteID: 42, results: [result, earlierSessionResult(result, days: 3)], on: result.recordedAt, availableSeconds: 1800)
        #expect(proposal.items.first?.loadKilograms == 45)
        #expect(proposal.needsEquipmentIncrement)
    }

    @Test func numericProgressionUsesExplicitIncrementAndResetsReps() {
        let result = sessionResultFixture()
        let proposal = SessionProgressionProposalPolicy.propose(goalID: result.reference.goalID, athleteID: 42, results: [result, earlierSessionResult(result, days: 3)], on: result.recordedAt, availableSeconds: 1800, incrementsKilograms: ["barbell-bench-press": 2])
        #expect(proposal.items.first?.loadKilograms == 47)
        #expect(proposal.items.first?.repetitions == 6)
        #expect(proposal.hasIncrease)
    }

    @Test func numericProgressionRejectsLargeOrInvalidIncrements() {
        let result = sessionResultFixture()
        for increment in [Double.nan, Double.infinity, -2, 0, 10] {
            let proposal = SessionProgressionProposalPolicy.propose(goalID: result.reference.goalID, athleteID: 42, results: [result, earlierSessionResult(result, days: 3)], on: result.recordedAt, availableSeconds: 1800, incrementsKilograms: ["barbell-bench-press": increment])
            #expect(proposal.items.first?.loadKilograms == 45)
            #expect(!proposal.hasIncrease)
        }
    }

    @Test func numericProgressionAddsRepOnlyAfterMatchingCompletedDays() {
        var result = sessionResultFixture()
        result.entries[0].repetitions = 6
        let proposal = SessionProgressionProposalPolicy.propose(goalID: result.reference.goalID, athleteID: 42, results: [result, earlierSessionResult(result, days: 3)], on: result.recordedAt, availableSeconds: 1800)
        #expect(proposal.items.first?.repetitions == 7)
        #expect(proposal.items.first?.loadKilograms == 45)
    }

    @Test func numericProgressionBlocksPartialHardStaleAndWrongOwner() {
        var result = sessionResultFixture()
        result.entries[0].repetitions = 4
        #expect(SessionProgressionProposalPolicy.propose(goalID: result.reference.goalID, athleteID: 42, results: [result], on: result.recordedAt, availableSeconds: 1800).items.isEmpty)
        result.entries[0].repetitions = 8
        result.perceivedEffort = 9
        #expect(SessionProgressionProposalPolicy.propose(goalID: result.reference.goalID, athleteID: 42, results: [result], on: result.recordedAt, availableSeconds: 1800).items.isEmpty)
        result.perceivedEffort = 5
        #expect(SessionProgressionProposalPolicy.propose(goalID: result.reference.goalID, athleteID: 42, results: [result], on: result.recordedAt.addingTimeInterval(40 * 86400), availableSeconds: 1800).items.isEmpty)
        #expect(SessionProgressionProposalPolicy.propose(goalID: result.reference.goalID, athleteID: 43, results: [result], on: result.recordedAt, availableSeconds: 1800).items.isEmpty)
    }

    @Test func numericProgressionRequiresFullTimeBudget() {
        let result = sessionResultFixture()
        #expect(SessionProgressionProposalPolicy.propose(goalID: result.reference.goalID, athleteID: 42, results: [result], on: result.recordedAt, availableSeconds: 899).items.isEmpty)
    }

    @Test func numericProgressionConvertsPoundsWithoutRelabeling() {
        #expect(abs(SessionProgressionProposalPolicy.kilograms(5, unit: .pounds) - 2.26796185) < 0.000001)
        #expect(abs(SessionProgressionProposalPolicy.displayMass(45, unit: .pounds) - 99.20801798) < 0.00001)
        #expect(SessionProgressionProposalPolicy.kilograms(5, unit: .kilograms) == 5)
    }

    @Test func numericRunningProposalRepeatsActualBlocksWithoutInventingPace() {
        let strength = sessionResultFixture()
        let item = TrainingSessionResult.Item(id: "run/0", title: "Easy run", kind: .running, exerciseID: nil, seconds: 1200, repetitions: nil, convention: nil, loadKilograms: nil, assistanceKilograms: nil)
        let reference = TrainingSessionResult.Reference(athleteID: 42, goalID: strength.reference.goalID, goalTitle: "Running", fingerprint: "run", policyVersion: "test", generatedAt: strength.recordedAt, distanceUnit: .miles, massUnit: .pounds, prescribedSeconds: 1200, items: [item])
        let entry = TrainingSessionResult.Entry(itemID: item.id, skipped: false, seconds: 1230, repetitions: nil, loadKilograms: nil, assistanceKilograms: nil, repsInReserve: nil)
        let result = TrainingSessionResult(id: UUID(), reference: reference, completedAt: strength.completedAt, recordedAt: strength.recordedAt, elapsedSeconds: 1230, perceivedEffort: 4, bodyState: .good, entries: [entry])
        let proposal = SessionProgressionProposalPolicy.propose(goalID: reference.goalID, athleteID: 42, results: [result], on: result.recordedAt, availableSeconds: 1800)
        #expect(proposal.items.first?.seconds == 1230)
        #expect(proposal.requiredSeconds == 1230)
        #expect(!proposal.hasIncrease)
    }
}

extension TodayRecommendationPolicyTests {
    private func acceptanceFixture() -> (WeeklyTrainingPlan, TrainingSessionResult, SessionProgressionProposalPolicy.Proposal, Date, Date) {
        let source = sessionResultFixture()
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 12))!
        let start = Calendar.current.startOfDay(for: now)
        let target = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start)!
        let workout = DailyWorkout(id: "monday", date: target, dayOfWeek: .from(date: target), workoutType: .easyRun, title: "Original run", description: "Planned", duration: 30, distance: 3, targetPace: nil, exercises: nil, isCompleted: false, completedActivityId: nil)
        let plan = WeeklyTrainingPlan(id: "acceptance", athleteId: 42, weekStartDate: start, weekEndDate: end, workouts: [workout], weekNumber: nil, totalMileage: 3, focusArea: nil, notes: nil, generatedAt: now, goalId: nil)
        let proposal = SessionProgressionProposalPolicy.propose(goalID: source.reference.goalID, athleteID: 42, results: [source], on: now, availableSeconds: 1800)
        return (plan, source, proposal, now, target)
    }

    @Test func acceptedPrescriptionRetainsExactDoseAndUnits() throws {
        let (plan, source, proposal, now, target) = acceptanceFixture()
        let updated = try AcceptedPrescriptionPlanPolicy.placing(proposal, source: source.reference, in: plan, on: target, now: now)
        let workout = try #require(updated.workouts.first)
        #expect(workout.acceptedPrescription?.items.first?.loadKilograms == 45)
        #expect(workout.acceptedPrescription?.massUnit == .pounds)
        #expect(workout.exercises?.first?.sets == 1)
        #expect(workout.distance == nil)
        #expect(updated.totalMileage == 0)
        let decoded = try JSONDecoder().decode(WeeklyTrainingPlan.self, from: JSONEncoder().encode(updated))
        #expect(decoded.workouts.first?.acceptedPrescription == workout.acceptedPrescription)
    }

    @Test func acceptedPrescriptionRejectsCompletedOrPastDay() throws {
        let (plan, source, proposal, now, target) = acceptanceFixture()
        #expect(throws: (any Error).self) {
            try AcceptedPrescriptionPlanPolicy.placing(proposal, source: source.reference, in: plan, on: now, now: now)
        }
        let original = plan.workouts[0]
        let completed = DailyWorkout(id: original.id, date: target, dayOfWeek: original.dayOfWeek, workoutType: original.workoutType, title: original.title, description: original.description, duration: original.duration, distance: original.distance, targetPace: nil, exercises: nil, isCompleted: true, completedActivityId: 12)
        let protected = AcceptedPrescriptionPlanPolicy.replacingWorkouts(in: plan, with: [completed], generatedAt: now)
        #expect(throws: (any Error).self) {
            try AcceptedPrescriptionPlanPolicy.placing(proposal, source: source.reference, in: protected, on: target, now: now)
        }
    }

    @Test func acceptedPrescriptionRejectsWrongOwnerAndEmptyProposal() {
        let (plan, source, _, now, target) = acceptanceFixture()
        let empty = SessionProgressionProposalPolicy.Proposal(reason: "No evidence")
        #expect(throws: (any Error).self) {
            try AcceptedPrescriptionPlanPolicy.placing(empty, source: source.reference, in: plan, on: target, now: now)
        }
        let other = WeeklyTrainingPlan(id: plan.id, athleteId: 43, weekStartDate: plan.weekStartDate, weekEndDate: plan.weekEndDate, workouts: plan.workouts, weekNumber: nil, totalMileage: 3, focusArea: nil, notes: nil, generatedAt: now, goalId: nil)
        let proposal = SessionProgressionProposalPolicy.propose(goalID: source.reference.goalID, athleteID: 42, results: [source], on: now, availableSeconds: 1800)
        #expect(throws: (any Error).self) {
            try AcceptedPrescriptionPlanPolicy.placing(proposal, source: source.reference, in: other, on: target, now: now)
        }
    }

    @Test func acceptedReceiptRejectsUndoAfterNewerEdit() throws {
        let (plan, source, proposal, now, target) = acceptanceFixture()
        let after = try AcceptedPrescriptionPlanPolicy.placing(proposal, source: source.reference, in: plan, on: target, now: now)
        let receipt = try AcceptedPrescriptionPlanReceipt(before: plan, after: after, acceptedAt: now)
        #expect(try receipt.restoredPlan(current: after, athleteID: 42).workouts.first?.title == "Original run")
        let changed = AcceptedPrescriptionPlanPolicy.replacingWorkouts(in: after, with: [], generatedAt: now)
        #expect(throws: (any Error).self) { try receipt.restoredPlan(current: changed, athleteID: 42) }
        #expect(throws: (any Error).self) { try receipt.restoredPlan(current: after, athleteID: 43) }
    }

    @Test func acceptedReceiptFingerprintSurvivesCacheDateEncoding() throws {
        let (plan, source, proposal, now, target) = acceptanceFixture()
        let after = try AcceptedPrescriptionPlanPolicy.placing(proposal, source: source.reference, in: plan, on: target, now: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let reloaded = try decoder.decode(WeeklyTrainingPlan.self, from: encoder.encode(after))
        #expect(try AcceptedPrescriptionPlanPolicy.fingerprint(after) == AcceptedPrescriptionPlanPolicy.fingerprint(reloaded))
    }

    @Test func acceptedRegenerationCannotDropExplicitChoice() throws {
        let (plan, source, proposal, now, target) = acceptanceFixture()
        let placed = try AcceptedPrescriptionPlanPolicy.placing(proposal, source: source.reference, in: plan, on: target, now: now)
        #expect(AcceptedPrescriptionPlanPolicy.isExplicitChoice(placed.workouts[0]))
        #expect(throws: (any Error).self) {
            try AcceptedPrescriptionPlanPolicy.validateRegenerated(before: placed, after: plan, targetDate: target, availability: [], now: now)
        }
    }
}

extension TodayRecommendationPolicyTests {
    @Test func acceptedStrengthUsesPrescriptionEffortRatherThanGenericZone() throws {
        let (plan, source, proposal, now, target) = acceptanceFixture()
        let placed = try AcceptedPrescriptionPlanPolicy.placing(proposal, source: source.reference, in: plan, on: target, now: now)
        let workout = try #require(placed.workouts.first)
        #expect(WorkoutEffortDisplayPolicy.zoneTarget(for: workout) == nil)
        #expect(WorkoutEffortDisplayPolicy.acceptedEffort(for: workout)?.title == "Prescribed reps and load")
    }

    @Test func acceptedRunningDoesNotAcquireAHeartRateZone() throws {
        let (plan, _, _, now, target) = acceptanceFixture()
        let item = TrainingSessionResult.Item(id: "run", title: "Easy running", kind: .running, exerciseID: nil, seconds: 1200, repetitions: nil, convention: nil, loadKilograms: nil, assistanceKilograms: nil)
        let reference = TrainingSessionResult.Reference(athleteID: plan.athleteId, goalID: UUID(), goalTitle: "Running goal", fingerprint: "effort-display", policyVersion: "test", generatedAt: now.addingTimeInterval(-86400), distanceUnit: .miles, massUnit: .pounds, prescribedSeconds: 1200, items: [item])
        let entry = TrainingSessionResult.Entry(itemID: item.id, skipped: false, seconds: 1200, repetitions: nil, loadKilograms: nil, assistanceKilograms: nil, repsInReserve: nil)
        let result = TrainingSessionResult(id: UUID(), reference: reference, completedAt: now.addingTimeInterval(-86400), recordedAt: now.addingTimeInterval(-86400), elapsedSeconds: 1200, perceivedEffort: 4, bodyState: .good, entries: [entry])
        let proposal = SessionProgressionProposalPolicy.propose(goalID: reference.goalID, athleteID: plan.athleteId, results: [result], on: now, availableSeconds: 1800)
        let placed = try AcceptedPrescriptionPlanPolicy.placing(proposal, source: reference, in: plan, on: target, now: now)
        let workout = try #require(placed.workouts.first)
        #expect(WorkoutEffortDisplayPolicy.zoneTarget(for: workout) == nil)
        #expect(WorkoutEffortDisplayPolicy.acceptedEffort(for: workout)?.title == "Conversational effort")
        #expect(workout.acceptedPrescription?.items.first?.seconds == 1200)
    }

    @Test func existingWorkoutZonePresentationIsUnchanged() {
        let (plan, _, _, _, _) = acceptanceFixture()
        let workout = plan.workouts[0]
        #expect(WorkoutEffortDisplayPolicy.zoneTarget(for: workout)?.label == NativeTrainingGuidancePolicy.zoneTarget(for: workout.workoutType)?.label)
        #expect(WorkoutEffortDisplayPolicy.acceptedEffort(for: workout) == nil)
    }

    @Test @MainActor func acceptanceLoadsOwnedCachedPlanWithoutOpeningPlanTab() async throws {
        let fixture = makePlan()
        let manager = DataManager.shared
        let previous = manager.currentWeeklyPlan
        let previousPending = manager.pendingNextWeekPlan
        let suite = "acceptance-cold-load-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { manager.currentWeeklyPlan = previous; manager.pendingNextWeekPlan = previousPending; defaults.removePersistentDomain(forName: suite) }
        let profile = TrainingProfile.runningFirstDefault
        try TrainingPlanService.cachePlan(fixture.plan, profile: profile, defaults: defaults)
        manager.currentWeeklyPlan = nil
        let loaded = await manager.loadPlanForPrescriptionAcceptance(athleteID: fixture.plan.athleteId, profile: profile, defaults: defaults, activeAthleteID: { fixture.plan.athleteId })
        #expect(loaded)
        #expect(manager.currentWeeklyPlan?.id == fixture.plan.id)
    }

    @Test @MainActor func acceptanceDoesNotLoadAnotherAccountsCache() async throws {
        let fixture = makePlan()
        let manager = DataManager.shared
        let previous = manager.currentWeeklyPlan
        let previousPending = manager.pendingNextWeekPlan
        let suite = "acceptance-other-owner-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { manager.currentWeeklyPlan = previous; manager.pendingNextWeekPlan = previousPending; defaults.removePersistentDomain(forName: suite) }
        let profile = TrainingProfile.runningFirstDefault
        try TrainingPlanService.cachePlan(fixture.plan, profile: profile, defaults: defaults)
        manager.currentWeeklyPlan = nil
        let other = fixture.plan.athleteId + 1
        let loaded = await manager.loadPlanForPrescriptionAcceptance(athleteID: other, profile: profile, defaults: defaults, activeAthleteID: { other })
        #expect(!loaded)
        #expect(manager.currentWeeklyPlan == nil)
    }

    @Test @MainActor func acceptancePromotesOwnedPendingPlanWhenItsWeekArrives() async throws {
        let fixture = makePlan()
        let manager = DataManager.shared
        let previous = manager.currentWeeklyPlan
        let previousPending = manager.pendingNextWeekPlan
        let suite = "acceptance-pending-load-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { manager.currentWeeklyPlan = previous; manager.pendingNextWeekPlan = previousPending; defaults.removePersistentDomain(forName: suite) }
        let profile = TrainingProfile.runningFirstDefault
        try TrainingPlanService.cachePendingNextWeekPlan(fixture.plan, profile: profile, defaults: defaults)
        manager.currentWeeklyPlan = nil
        let loaded = await manager.loadPlanForPrescriptionAcceptance(athleteID: fixture.plan.athleteId, profile: profile, defaults: defaults, activeAthleteID: { fixture.plan.athleteId })
        #expect(loaded)
        #expect(manager.currentWeeklyPlan?.id == fixture.plan.id)
        #expect(defaults.data(forKey: TrainingPlanService.pendingNextWeekCacheKey) == nil)
    }

    @Test @MainActor func acceptanceMissingCacheDoesNotGenerateAPlan() async throws {
        let manager = DataManager.shared
        let previous = manager.currentWeeklyPlan
        let suite = "acceptance-missing-load-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { manager.currentWeeklyPlan = previous; defaults.removePersistentDomain(forName: suite) }
        manager.currentWeeklyPlan = nil
        let loaded = await manager.loadPlanForPrescriptionAcceptance(athleteID: 42, profile: .runningFirstDefault, defaults: defaults, activeAthleteID: { 42 })
        #expect(!loaded)
        #expect(manager.currentWeeklyPlan == nil)
        #expect(defaults.data(forKey: TrainingPlanService.cacheKey) == nil)
    }
}

extension TodayRecommendationPolicyTests {
    @Test func acceptedCompletionUsesProposedDoseAndKeepsProgressionRange() throws {
        let (plan, source, initial, now, target) = acceptanceFixture()
        var proposal = initial
        proposal.items[0].repetitions = 6
        proposal.items[0].loadKilograms = 47
        let placed = try AcceptedPrescriptionPlanPolicy.placing(proposal, source: source.reference, in: plan, on: target, now: now)
        let workout = try #require(placed.workouts.first)
        let reference = try AcceptedPrescriptionCompletionPolicy.reference(for: workout, athleteID: 42)
        #expect(reference.items[0].prescribedRepetitions == 6)
        #expect(reference.items[0].repetitions == 6...8)
        #expect(reference.items[0].loadKilograms == 47)
        #expect(reference.massUnit == .pounds)
        #expect(reference.distanceUnit == .miles)
        #expect(reference.acceptedPrescriptionID == workout.acceptedPrescription?.id)
        #expect(reference.id != source.reference.id)
        #expect(try AcceptedPrescriptionCompletionPolicy.reference(for: workout, athleteID: 42) == reference)
        #expect(try JSONDecoder().decode(TrainingSessionResult.Reference.self, from: JSONEncoder().encode(reference)) == reference)
        #expect(AcceptedPrescriptionCompletionPolicy.effortLabel(for: workout) == "Prescribed")
        #expect(AcceptedPrescriptionCompletionPolicy.effortLabel(for: plan.workouts[0]) == nil)
    }

    @Test func acceptedCompletionPreservesFractionalRunningSeconds() throws {
        let (plan, source, _, now, target) = acceptanceFixture()
        let item = TrainingSessionResult.Item(id: "running/0", title: "Easy run", kind: .running,
            exerciseID: nil, seconds: 600, repetitions: nil, convention: nil,
            loadKilograms: nil, assistanceKilograms: nil)
        var oldReference = source.reference
        oldReference.items = [item]
        let entry = TrainingSessionResult.Entry(itemID: item.id, skipped: false, seconds: 610.5,
            repetitions: nil, loadKilograms: nil, assistanceKilograms: nil, repsInReserve: nil)
        let proposal = SessionProgressionProposalPolicy.Proposal(items: [.init(id: item.id, title: item.title,
            kind: .running, convention: nil, previous: entry, seconds: 610.5, repetitions: nil,
            loadKilograms: nil, assistanceKilograms: nil)], requiredSeconds: 900, evidenceIDs: [source.id], reason: "Repeat")
        let placed = try AcceptedPrescriptionPlanPolicy.placing(proposal, source: oldReference, in: plan, on: target, now: now)
        let workout = try #require(placed.workouts.first)
        let reference = try AcceptedPrescriptionCompletionPolicy.reference(for: workout, athleteID: 42)
        #expect(reference.items[0].durationSeconds == 610.5)
        #expect(reference.items[0].seconds == nil)
        #expect(AcceptedPrescriptionCompletionPolicy.effortLabel(for: workout) == "Conversational")
        var result = source
        result.reference = reference
        result.entries = [entry]
        result.completedAt = target.addingTimeInterval(3600)
        #expect(!result.isPartial)
        result.entries[0].seconds = 610
        #expect(result.isPartial)
    }

    @Test func acceptedCompletionRejectsWrongOwnerAndMalformedDose() throws {
        let (plan, source, initial, now, target) = acceptanceFixture()
        let placed = try AcceptedPrescriptionPlanPolicy.placing(initial, source: source.reference, in: plan, on: target, now: now)
        let workout = try #require(placed.workouts.first)
        #expect(throws: (any Error).self) { try AcceptedPrescriptionCompletionPolicy.reference(for: workout, athleteID: 43) }
        var invalid = initial
        invalid.items[0].repetitions = nil
        let malformed = try AcceptedPrescriptionPlanPolicy.placing(invalid, source: source.reference, in: plan, on: target, now: now)
        #expect(throws: (any Error).self) { try AcceptedPrescriptionCompletionPolicy.reference(for: malformed.workouts[0], athleteID: 42) }
    }

    @MainActor @Test func acceptedCompletionStoresExactRecordAndRejectsDuplicateAndStalePlan() throws {
        let (plan, source, proposal, now, target) = acceptanceFixture()
        let placed = try AcceptedPrescriptionPlanPolicy.placing(proposal, source: source.reference, in: plan, on: target, now: now)
        let workout = try #require(placed.workouts.first)
        let reference = try AcceptedPrescriptionCompletionPolicy.reference(for: workout, athleteID: 42)
        let completed = target.addingTimeInterval(3600)
        let result = TrainingSessionResult(id: UUID(), reference: reference, completedAt: completed,
            recordedAt: completed, elapsedSeconds: source.elapsedSeconds, perceivedEffort: 5,
            bodyState: .good, entries: source.entries)
        try AcceptedPrescriptionCompletionPolicy.validate(result, workout: workout, currentPlan: placed, athleteID: 42, now: completed)
        #expect(throws: (any Error).self) {
            try AcceptedPrescriptionCompletionPolicy.validate(result, workout: workout, currentPlan: plan, athleteID: 42, now: completed)
        }
        #expect(throws: (any Error).self) {
            try AcceptedPrescriptionCompletionPolicy.validate(result, workout: workout, currentPlan: placed, athleteID: 42, now: now)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ProtectedTrainingRepository(root: root, activeAthleteID: { 42 })
        try repository.appendSessionResult(source, athleteID: 42)
        try repository.appendSessionResult(result, athleteID: 42)
        #expect(try repository.sessionResults(athleteID: 42).contains(result))
        var duplicate = result
        duplicate.id = UUID()
        #expect(throws: (any Error).self) { try repository.appendSessionResult(duplicate, athleteID: 42) }
        #expect(try repository.sessionResults(athleteID: 42).count == 2)
    }

    @Test func acceptedCompletionUsesExactRepTargetForPartialWork() throws {
        let (plan, source, initial, now, target) = acceptanceFixture()
        var proposal = initial
        proposal.items[0].repetitions = 7
        let placed = try AcceptedPrescriptionPlanPolicy.placing(proposal, source: source.reference, in: plan, on: target, now: now)
        var result = source
        result.reference = try AcceptedPrescriptionCompletionPolicy.reference(for: placed.workouts[0], athleteID: 42)
        result.entries[0].repetitions = 6
        #expect(result.isPartial)
        result.entries[0].repetitions = 7
        #expect(!result.isPartial)
    }
}

extension TodayRecommendationPolicyTests {
    private func completionStatusFixture(partial: Bool = false) throws -> (WeeklyTrainingPlan, TrainingSessionResult) {
        let (plan, source, proposal, now, target) = acceptanceFixture()
        let placed = try AcceptedPrescriptionPlanPolicy.placing(proposal, source: source.reference, in: plan, on: target, now: now)
        let reference = try AcceptedPrescriptionCompletionPolicy.reference(for: placed.workouts[0], athleteID: 42)
        var entries = source.entries
        if partial { entries[0].repetitions = 1 }
        let completed = target.addingTimeInterval(3600)
        let result = TrainingSessionResult(id: UUID(), reference: reference, completedAt: completed,
            recordedAt: completed, elapsedSeconds: 900, perceivedEffort: 5, bodyState: .good, entries: entries)
        return (placed, result)
    }

    @Test func acceptedFullCompletionUpdatesPlanWithoutChangingPrescriptionOrMileage() throws {
        let (plan, result) = try completionStatusFixture()
        let updated = try #require(try AcceptedWorkoutCompletionProjection.applying([result], to: plan))
        #expect(updated.workouts[0].isCompleted)
        #expect(updated.workouts[0].acceptedCompletion?.resultID == result.id)
        #expect(updated.workouts[0].acceptedPrescription == plan.workouts[0].acceptedPrescription)
        #expect(updated.totalMileage == plan.totalMileage)
        #expect(updated.workouts[0].completedActivityId == nil)
        #expect(updated.mergedWithActivities([]).filter(\.isCompleted).count == 1)
        #expect(try AcceptedWorkoutCompletionProjection.applying([result], to: updated) == nil)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(WeeklyTrainingPlan.self, from: encoder.encode(updated))
        #expect(restored.workouts[0].acceptedCompletion == updated.workouts[0].acceptedCompletion)
    }

    @Test func acceptedPartialCompletionIsNotClaimedAsFullWorkout() throws {
        let (plan, result) = try completionStatusFixture(partial: true)
        let updated = try #require(try AcceptedWorkoutCompletionProjection.applying([result], to: plan))
        #expect(!updated.workouts[0].isCompleted)
        #expect(updated.workouts[0].acceptedCompletion?.status == "Partial session")
        let entry = try #require(updated.mergedWithActivities([]).first { $0.plannedWorkout?.acceptedCompletion != nil })
        #expect(entry.statusText == "Partial session")
        #expect(!entry.isCompleted)
        #expect(entry.displayDuration == 15)
    }

    @Test func completionProjectionRejectsWrongOwnerAndDuplicateRecords() throws {
        let (plan, result) = try completionStatusFixture()
        #expect(throws: (any Error).self) { try AcceptedWorkoutCompletionProjection.applying([result, result], to: plan) }
        let other = WeeklyTrainingPlan(id: plan.id, athleteId: 43, weekStartDate: plan.weekStartDate,
            weekEndDate: plan.weekEndDate, workouts: plan.workouts, weekNumber: nil, totalMileage: 0,
            focusArea: nil, notes: nil, generatedAt: plan.generatedAt, goalId: nil)
        #expect(throws: (any Error).self) { try AcceptedWorkoutCompletionProjection.applying([result], to: other) }
        #expect(try AcceptedWorkoutCompletionProjection.applying([], to: plan) == nil)
    }

    @Test func completionAndSyncedActivityDoNotCountTwiceInWeekOrContext() throws {
        let (plan, result) = try completionStatusFixture()
        let updated = try #require(try AcceptedWorkoutCompletionProjection.applying([result], to: plan))
        let activity = Activity(id: 80808, name: "Strength", type: "WeightTraining",
            distance: 0, start_date: result.completedAt.timeIntervalSince1970,
            elapsed_time: 900, athlete_id: 42, activity_date: result.completedAt.timeIntervalSince1970)
        #expect(updated.mergedWithActivities([activity]).filter(\.isCompleted).count == 1)
        let context = TodayRecommendationContextBuilder.build(date: result.completedAt.addingTimeInterval(86400),
            profile: .runningFirstDefault, plannedWorkout: nil, planWorkouts: updated.workouts,
            activities: [activity], readinessScore: 80)
        #expect(context.recentCompletedWorkouts.count == 1)
        #expect(updated.weekStats(with: [activity]).actualMiles == 0)
    }
}
