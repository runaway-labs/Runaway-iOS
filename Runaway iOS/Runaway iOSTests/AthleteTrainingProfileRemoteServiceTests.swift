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

    func testReconciledLoadAcceptsANewerRemoteProfile() async throws {
        let athleteID = 1
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let remoteProfile = profile(
            athleteID: athleteID,
            updatedAt: Date(timeIntervalSinceNow: 3_600)
        )
        let remote = RemoteStub(fetched: remoteProfile)
        let store = AthleteTrainingProfileStore(
            root: root,
            activeAthleteID: { athleteID },
            remote: remote
        )

        let resolved = try await store.loadReconciled(athleteID: athleteID)

        XCTAssertEqual(resolved, remoteProfile)
        XCTAssertEqual(store.profile, remoteProfile)
        XCTAssertEqual(store.syncState, .saved)
    }

    func testFailedRemoteSaveRemainsVisibleAndKeepsProtectedLocalProfile() async throws {
        let athleteID = 1
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let remote = RemoteStub(saveError: TestError.offline)
        let store = AthleteTrainingProfileStore(
            root: root,
            activeAthleteID: { athleteID },
            remote: remote
        )
        var draft = profile(athleteID: athleteID)
        draft.outcomes = [.marathonReady, .leanStrong]

        await XCTAssertThrowsErrorAsync {
            _ = try await store.saveAndSync(draft, athleteID: athleteID)
        }

        XCTAssertNotNil(store.profile)
        guard case .unsynced = store.syncState else {
            return XCTFail("Expected the failed remote save to remain visibly unsynced")
        }
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

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AthleteTrainingProfileRemoteServiceTests-\(UUID().uuidString)")
    }

    private enum TestError: Error { case offline }

    private final class RemoteStub: AthleteTrainingProfileRemotePersisting {
        let fetched: AthleteTrainingProfile?
        let saveError: Error?

        init(fetched: AthleteTrainingProfile? = nil, saveError: Error? = nil) {
            self.fetched = fetched
            self.saveError = saveError
        }

        func save(_ profile: AthleteTrainingProfile, activeAthleteID: Int) async throws -> ProfileSyncReceipt {
            if let saveError { throw saveError }
            return ProfileSyncReceipt(
                changed: true,
                revision: profile.revision,
                inputFingerprint: "test",
                updatedAt: profile.updatedAt
            )
        }

        func fetch(activeAthleteID: Int) async throws -> AthleteTrainingProfile? { fetched }
    }
}

private extension XCTestCase {
    func XCTAssertThrowsErrorAsync(_ expression: () async throws -> Void) async {
        do { try await expression(); XCTFail("Expected error") } catch { }
    }
}
