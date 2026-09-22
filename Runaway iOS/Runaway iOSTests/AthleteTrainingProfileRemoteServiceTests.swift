import XCTest
@testable import Runaway_iOS

@MainActor
final class AthleteTrainingProfileRemoteServiceTests: XCTestCase {
    func testProfileSyncRejectsMismatchedAthleteOwnership() async {
        var requests = 0
        let remote = AthleteTrainingProfileRemoteService(transport: { _ in
            requests += 1
            return ProfileSyncResponse(profile: nil, receipt: nil)
        })

        await XCTAssertThrowsErrorAsync {
            _ = try await remote.save(self.profile(athleteID: 2), activeAthleteID: 1)
        }
        XCTAssertEqual(requests, 0)
    }

    func testFetchNeverReplacesANewerLocalProfile() async throws {
        let older = profile(athleteID: 1, updatedAt: Date(timeIntervalSince1970: 100))
        let remote = AthleteTrainingProfileRemoteService(transport: { _ in
            ProfileSyncResponse(profile: older, receipt: nil)
        })
        let newer = profile(athleteID: 1, updatedAt: Date(timeIntervalSince1970: 200))

        let resolved = try await remote.fetch(activeAthleteID: 1, localProfile: newer)

        XCTAssertEqual(resolved, newer)
    }

    private func profile(athleteID: Int, updatedAt: Date = Date()) -> AthleteTrainingProfile {
        AthleteTrainingProfile(
            athleteID: athleteID,
            revision: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            updatedAt: updatedAt,
            goals: [AthleteTrainingGoal(
                title: "Run consistently", metric: .weeklyRunningDuration,
                target: GoalMeasurement(durationSeconds: 10_800)
            )],
            availability: [TrainingDayAvailability(weekday: 2, availableMinutes: 60)]
        )
    }
}

private extension XCTestCase {
    func XCTAssertThrowsErrorAsync(_ expression: () async throws -> Void) async {
        do { try await expression(); XCTFail("Expected error") } catch { }
    }
}
