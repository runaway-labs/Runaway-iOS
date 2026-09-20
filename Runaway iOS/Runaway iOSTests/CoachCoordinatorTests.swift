import XCTest
@testable import Runaway_iOS

@MainActor
final class CoachCoordinatorTests: XCTestCase {
    func testNoOpIsSilentAndMarksEventProcessed() async throws {
        try await withSystem { coordinator, ledger in
            let active = plan(duration: 40)
            let event = self.event()
            let result = try await coordinator.process(event, context: try self.context(active: active, candidate: active))
            XCTAssertNil(result.decision)
            XCTAssertEqual(result.activePlan.workouts.first?.duration, 40)
            XCTAssertTrue(try ledger.pendingEvents().isEmpty)
        }
    }

    func testReductionAppliesWhileIncreaseWaitsForApproval() async throws {
        try await withSystem { coordinator, _ in
            let active = plan(duration: 40)
            let reduction = try await coordinator.process(
                self.event(sourceID: "reduce"),
                context: try self.context(active: active, candidate: self.plan(duration: 25))
            )
            XCTAssertEqual(reduction.decision?.classification, .automatic)
            XCTAssertEqual(reduction.decision?.state, .applied)
            XCTAssertEqual(reduction.activePlan.workouts.first?.duration, 25)

            let increase = try await coordinator.process(
                self.event(sourceID: "increase"),
                context: try self.context(active: active, candidate: self.plan(duration: 60))
            )
            XCTAssertEqual(increase.decision?.classification, .approvalRequired)
            XCTAssertEqual(increase.decision?.state, .proposed)
            XCTAssertEqual(increase.activePlan.workouts.first?.duration, 40)
        }
    }

    func testSafetyFlagBlocksAndStaleRevisionIsRejected() async throws {
        try await withSystem { coordinator, _ in
            let active = plan(duration: 40)
            let blocked = try await coordinator.process(
                self.event(sourceID: "pain"),
                context: try self.context(active: active, candidate: self.plan(duration: 25), flags: [.pain])
            )
            XCTAssertEqual(blocked.decision?.state, .blocked)
            XCTAssertEqual(blocked.activePlan.workouts.first?.duration, 40)

            var stale = try self.context(active: active, candidate: self.plan(duration: 25))
            stale.planRevision = "stale"
            await XCTAssertThrowsErrorAsync {
                _ = try await coordinator.process(self.event(sourceID: "stale"), context: stale)
            }
        }
    }

    private func withSystem(_ body: (CoachCoordinator, CoachDecisionLedger) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = ProtectedTrainingRepository(root: root, activeAthleteID: { 1 })
        let ledger = CoachDecisionLedger(repository: repo, athleteID: 1)
        try await body(CoachCoordinator(ledger: ledger), ledger)
    }

    private func context(active: WeeklyTrainingPlan, candidate: WeeklyTrainingPlan,
                         flags: Set<CoachSafetyFlag> = []) throws -> CoachContext {
        CoachContext(athleteID: 1, activePlan: active, candidatePlan: candidate,
                     planRevision: try CoachDecisionLedger.fingerprint(of: active),
                     reasonCodes: [.athleteRequested], safetyFlags: flags, missingData: [])
    }

    private func event(sourceID: String = "event") -> CoachEvent {
        let date = Date(timeIntervalSince1970: 100)
        return CoachEvent(athleteID: 1, kind: .reevaluationRequested, source: .app,
                          occurredAt: date, receivedAt: date, sourceRecordID: sourceID,
                          payload: .reevaluationRequested(reason: "test"))
    }

    private func plan(duration: Int) -> WeeklyTrainingPlan {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        return WeeklyTrainingPlan(id: "plan", athleteId: 1, weekStartDate: date,
            weekEndDate: date.addingTimeInterval(6 * 86_400),
            workouts: [DailyWorkout(id: "day", date: date, dayOfWeek: .sunday,
                workoutType: .easyRun, title: "Easy run", description: "Test", duration: duration,
                distance: Double(duration) / 10, targetPace: nil, exercises: nil,
                isCompleted: false, completedActivityId: nil)], weekNumber: 1,
            totalMileage: Double(duration) / 10, focusArea: nil, notes: nil,
            generatedAt: date, goalId: nil)
    }
}

private extension XCTestCase {
    func XCTAssertThrowsErrorAsync(_ expression: () async throws -> Void) async {
        do { try await expression(); XCTFail("Expected error") } catch { }
    }
}
