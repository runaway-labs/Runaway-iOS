import XCTest
@testable import Runaway_iOS

@MainActor
final class CoachEventServiceTests: XCTestCase {
    func testPendingEventsProcessChronologicallyAndRetriesStayProcessed() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = ProtectedTrainingRepository(root: root, activeAthleteID: { 1 })
        let ledger = CoachDecisionLedger(repository: repo, athleteID: 1)
        let later = event(sourceID: "later", time: 200)
        let earlier = event(sourceID: "earlier", time: 100)
        try ledger.append(later)
        try ledger.append(earlier)
        var processed: [String] = []
        let plan = self.plan()
        let service = CoachEventService(ledger: ledger, coordinator: CoachCoordinator(ledger: ledger),
            context: { event in
                processed.append(event.sourceRecordID)
                return CoachContext(athleteID: 1, activePlan: plan, candidatePlan: plan,
                    planRevision: try CoachDecisionLedger.fingerprint(of: plan),
                    reasonCodes: [], safetyFlags: [], missingData: [])
            }, activate: { _, _ in XCTFail("No-op must not activate a plan") })

        try await service.processPending(athleteID: 1)
        try await service.processPending(athleteID: 1)

        XCTAssertEqual(processed, ["earlier", "later"])
        XCTAssertTrue(try ledger.pendingEvents().isEmpty)
    }

    private func event(sourceID: String, time: TimeInterval) -> CoachEvent {
        let date = Date(timeIntervalSince1970: time)
        return CoachEvent(athleteID: 1, kind: .scheduledCheckIn, source: .schedule,
                          occurredAt: date, receivedAt: date, sourceRecordID: sourceID, payload: .none)
    }

    private func plan() -> WeeklyTrainingPlan {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        return WeeklyTrainingPlan(id: "plan", athleteId: 1, weekStartDate: date,
            weekEndDate: date.addingTimeInterval(6 * 86_400), workouts: [], weekNumber: 1,
            totalMileage: 0, focusArea: nil, notes: nil, generatedAt: date, goalId: nil)
    }
}
