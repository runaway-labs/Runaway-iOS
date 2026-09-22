import XCTest
@testable import Runaway_iOS

@MainActor
final class ProtectedTrainingRepositoryTests: XCTestCase {
    private func observation(id: UUID = UUID(), sourceID: String = "run-1", duration: Double = 300,
                             previous: UUID? = nil, athleteID: Int = 1) -> TrainingObservation {
        TrainingObservation(id: id, athleteID: athleteID,
            measuredAt: Date(timeIntervalSince1970: 1_700_000_000),
            receivedAt: Date(timeIntervalSince1970: 1_700_000_001),
            source: .importedActivity, sourceRecordID: sourceID, sessionID: nil,
            supersedesID: previous, value: .run(distanceMeters: 1000, durationSeconds: duration, effort: nil))
    }

    private func withRepository(_ body: (ProtectedTrainingRepository, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(ProtectedTrainingRepository(root: root, activeAthleteID: { 1 }), root)
    }

    private func sessionResult(id: UUID = UUID(), effort: Int = 4) -> TrainingSessionResult {
        let generated = Date(timeIntervalSince1970: 1_700_000_000)
        let item = TrainingSessionResult.Item(
            id: "run", title: "Easy running", kind: .running, exerciseID: nil,
            seconds: 1_200, repetitions: nil, convention: nil,
            loadKilograms: nil, assistanceKilograms: nil
        )
        let reference = TrainingSessionResult.Reference(
            athleteID: 1, goalID: UUID(), goalTitle: "Run consistently",
            fingerprint: "result-edit-fixture", policyVersion: "test", generatedAt: generated,
            distanceUnit: .miles, massUnit: .pounds, prescribedSeconds: 1_200, items: [item]
        )
        return TrainingSessionResult(
            id: id, reference: reference, completedAt: generated.addingTimeInterval(1_800),
            recordedAt: generated.addingTimeInterval(3_600), elapsedSeconds: 1_200,
            perceivedEffort: effort, bodyState: .good,
            entries: [.init(itemID: item.id, skipped: false, seconds: 1_200,
                            repetitions: nil, loadKilograms: nil,
                            assistanceKilograms: nil, repsInReserve: nil)]
        )
    }

    func testSessionResultEditRequiresExactOriginalAndKeepsOneRecord() throws {
        try withRepository { repo, _ in
            let original = sessionResult()
            try repo.appendSessionResult(original, athleteID: 1)
            var edited = original
            edited.perceivedEffort = 5

            try repo.replaceSessionResult(edited, replacing: original, athleteID: 1)

            XCTAssertEqual(try repo.sessionResults(athleteID: 1), [edited])
            var staleEdit = original
            staleEdit.elapsedSeconds = 1_300
            XCTAssertThrowsError(try repo.replaceSessionResult(staleEdit, replacing: original, athleteID: 1))
            XCTAssertEqual(try repo.sessionResults(athleteID: 1), [edited])
        }
    }

    func testLinkingImportedRunToSessionPreservesAuditTrailAndDeduplicatesDecisionInput() throws {
        try withRepository { repo, _ in
            let result = sessionResult()
            let imported = observation()
            try repo.appendSessionResult(result, athleteID: 1)
            try repo.append(imported, athleteID: 1)

            let linked = try repo.linkObservation(
                imported.id, toSessionResult: result.id, athleteID: 1,
                now: result.recordedAt.addingTimeInterval(60)
            )
            let history = try repo.observations(athleteID: 1)
            let inputs = try TrainingDecisionInputBuilder.build(
                profile: AthleteTrainingProfile(athleteID: 1), history: history,
                athleteID: 1, now: result.recordedAt.addingTimeInterval(120),
                timeZone: TimeZone(secondsFromGMT: 0)!, sessionResults: [result]
            )

            XCTAssertEqual(history.count, 2)
            XCTAssertEqual(linked.supersedesID, imported.id)
            XCTAssertEqual(linked.sessionID, result.id)
            XCTAssertTrue(inputs.observations.isEmpty)
            XCTAssertEqual(inputs.sessionResults, [result])
        }
    }

    func testSuccessiveCorrectionsPreserveHistoryAndExposeOnlyLatest() throws {
        try withRepository { repo, _ in
            let first = observation()
            let second = observation(duration: 310, previous: first.id)
            let third = observation(duration: 320, previous: second.id)
            let fourth = observation(duration: 330, previous: third.id)
            for item in [first, second, third, fourth] { try repo.append(item, athleteID: 1) }
            XCTAssertEqual(try repo.observations(athleteID: 1).count, 4)
            XCTAssertEqual(try repo.currentObservations(athleteID: 1), [fourth])
        }
    }

    func testBranchingAndMissingCorrectionsRejected() throws {
        try withRepository { repo, _ in
            let first = observation()
            try repo.append(first, athleteID: 1)
            try repo.append(observation(duration: 310, previous: first.id), athleteID: 1)
            XCTAssertThrowsError(try repo.append(observation(duration: 320, previous: first.id), athleteID: 1))
            XCTAssertThrowsError(try repo.append(observation(previous: UUID()), athleteID: 1))
            XCTAssertEqual(try repo.observations(athleteID: 1).count, 2)
        }
    }

    func testCorrectionCannotReuseUnrelatedSourceIdentity() throws {
        try withRepository { repo, _ in
            let first = observation()
            let other = observation(sourceID: "run-2")
            try repo.append(first, athleteID: 1)
            try repo.append(other, athleteID: 1)
            XCTAssertThrowsError(try repo.append(observation(sourceID: "run-2", duration: 320, previous: first.id), athleteID: 1))
            XCTAssertEqual(try repo.currentObservations(athleteID: 1).count, 2)
        }
    }

    func testDuplicateImportsAndRetriesDoNotCreateRecordsOrUndoCorrections() throws {
        // Corrections must work on either side of the original in the UUID sort.
        for correctionSortsFirst in [true, false] {
        try withRepository { repo, _ in
            let lowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
            let highID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
            let first = observation(id: correctionSortsFirst ? highID : lowID)
            try repo.append(first, athleteID: 1)
            XCTAssertEqual(try repo.append(first, athleteID: 1), first)
            XCTAssertEqual(try repo.append(observation(), athleteID: 1), first)
            let correction = observation(id: correctionSortsFirst ? lowID : highID,
                                         duration: 310, previous: first.id)
            try repo.append(correction, athleteID: 1)
            XCTAssertEqual(try repo.append(observation(), athleteID: 1), first)
            XCTAssertEqual(try repo.append(correction, athleteID: 1), correction)
            XCTAssertEqual(try repo.append(observation(duration: 310), athleteID: 1), correction)
            XCTAssertThrowsError(try repo.append(observation(duration: 320), athleteID: 1))
            XCTAssertEqual(try repo.currentObservations(athleteID: 1), [correction])
            XCTAssertEqual(try repo.observations(athleteID: 1).count, 2)
        }
        }
    }

    func testMutatingAnExistingRecordRequiresExplicitCorrection() throws {
        try withRepository { repo, _ in
            let first = observation()
            try repo.append(first, athleteID: 1)
            XCTAssertThrowsError(try repo.append(observation(id: first.id, duration: 320), athleteID: 1))
            XCTAssertThrowsError(try repo.append(observation(duration: 320), athleteID: 1))
            XCTAssertEqual(try repo.currentObservations(athleteID: 1), [first])
        }
    }

    func testCrossAccountOperationsAreRejected() throws {
        try withRepository { repo, _ in
            XCTAssertThrowsError(try repo.saveProfile(AthleteTrainingProfile(athleteID: 2), athleteID: 1))
            XCTAssertThrowsError(try repo.loadProfile(athleteID: 2))
            XCTAssertThrowsError(try repo.append(observation(athleteID: 2), athleteID: 1))
            XCTAssertThrowsError(try repo.observations(athleteID: 2))
            XCTAssertTrue(try repo.observations(athleteID: 1).isEmpty)
        }
    }

    func testProfileAndHistorySurviveRepositoryRecreation() throws {
        try withRepository { repo, root in
            let profile = AthleteTrainingProfile(athleteID: 1)
            let first = observation()
            try repo.saveProfile(profile, athleteID: 1)
            try repo.append(first, athleteID: 1)
            let reopened = ProtectedTrainingRepository(root: root, activeAthleteID: { 1 })
            XCTAssertEqual(try reopened.loadProfile(athleteID: 1), profile)
            XCTAssertEqual(try reopened.observations(athleteID: 1), [first])
        }
    }

    func testInvalidSavePreservesExistingProfile() throws {
        try withRepository { repo, _ in
            let profile = AthleteTrainingProfile(athleteID: 1)
            try repo.saveProfile(profile, athleteID: 1)
            var invalid = profile
            invalid.availability = [TrainingDayAvailability(weekday: 8, availableMinutes: 30)]
            XCTAssertThrowsError(try repo.saveProfile(invalid, athleteID: 1))
            XCTAssertEqual(try repo.loadProfile(athleteID: 1), profile)
        }
    }

    func testCorruptProfileRemainsOnDiskAndIsNotTreatedAsMissing() throws {
        try withRepository { repo, root in
            try repo.saveProfile(AthleteTrainingProfile(athleteID: 1), athleteID: 1)
            let url = root.appendingPathComponent("1/profile.json")
            let corrupt = Data("not-json".utf8)
            try corrupt.write(to: url)
            XCTAssertThrowsError(try repo.loadProfile(athleteID: 1))
            XCTAssertEqual(try Data(contentsOf: url), corrupt)
        }
    }

    func testAccountChangeHidesCachedProfileAndSessionEventClearsIt() throws {
        try withRepository { _, root in
            var account: Int? = 1
            let store = AthleteTrainingProfileStore(root: root, activeAthleteID: { account })
            try store.save(AthleteTrainingProfile(athleteID: 1), athleteID: 1)
            XCTAssertNotNil(store.profile)
            account = 2
            XCTAssertNil(store.profile)
            NotificationCenter.default.post(name: .trainingSessionInvalidated, object: nil)
            XCTAssertNil(store.profile)
            XCTAssertNil(store.accountID)
            XCTAssertNil(try store.load(athleteID: 2))
            account = nil
            XCTAssertThrowsError(try store.load(athleteID: 1))
        }
    }

    func testLegacyImportRequiresConfirmationAndDoesNotOverwriteProtectedProfile() throws {
        try withRepository { _, root in
            let name = "training-repository-test.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let key = "athleteTrainingProfile.v2.1"
            defaults.set(try JSONEncoder().encode(AthleteTrainingProfile(athleteID: 1)), forKey: key)
            let store = AthleteTrainingProfileStore(defaults: defaults, root: root, activeAthleteID: { 1 })
            XCTAssertThrowsError(try store.importLegacyProfile(athleteID: 1, confirmed: false))
            XCTAssertNotNil(defaults.data(forKey: key))
            try store.importLegacyProfile(athleteID: 1, confirmed: true)
            XCTAssertNil(defaults.data(forKey: key))
            XCTAssertEqual(store.profile?.athleteID, 1)
            XCTAssertThrowsError(try store.importLegacyProfile(athleteID: 1, confirmed: true))
        }
    }

    func testEffortScalesAndAssistedBodyweightStayExplicit() {
        XCTAssertTrue(TrainingEffortObservation(scale: .repetitionsInReserve, value: 0).isValid)
        XCTAssertFalse(TrainingEffortObservation(scale: .setRPE, value: 0).isValid)
        XCTAssertFalse(TrainingEffortObservation(scale: .sessionRPE, value: .nan).isValid)
        XCTAssertTrue(TrainingObservationValue.strengthSet(exerciseID: "pull-up", equipmentID: "assist-1",
            repetitions: 6, externalLoadKilograms: nil, assistanceKilograms: 15,
            convention: .bodyweight, effort: nil).isValid)
        XCTAssertFalse(TrainingObservationValue.strengthSet(exerciseID: "press", equipmentID: nil,
            repetitions: 6, externalLoadKilograms: 30, assistanceKilograms: nil,
            convention: .machine, effort: nil).isValid)
    }

    func testCompleteFileProtectionOnPhysicalDevice() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Data Protection enforcement requires a physical iPhone; simulator checks cannot prove locked-device protection.")
        #else
        try withRepository { repo, root in
            try repo.saveProfile(AthleteTrainingProfile(athleteID: 1), athleteID: 1)
            let first = observation()
            try repo.append(first, athleteID: 1)
            for path in ["1/profile.json", "1/observations/\(first.id.uuidString).json"] {
                let attributes = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(path).path)
                XCTAssertEqual(attributes[.protectionKey] as? String, FileProtectionType.complete.rawValue)
            }
        }
        #endif
    }
}

// Integration coverage uses decoded API fixtures and real temporary protected files.
extension ProtectedTrainingRepositoryTests {
    private var evidenceNow: Date { Date(timeIntervalSince1970: 1_700_100_000) }

    private func importedActivity(_ overrides: [String: Any] = [:]) throws -> Activity {
        var json: [String: Any] = [
            "id": 42, "athlete_id": 1, "type": "Run", "name": "Morning run",
            "activity_date": "2023-11-14T22:13:20Z", "distance": 5000.0,
            "elapsed_time": 1800.0, "moving_time": 1500
        ]
        json.merge(overrides) { _, new in new }
        return try JSONDecoder().decode(Activity.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testManualSetSeparatesPerformanceAndSubmissionTimeAcrossRetries() throws {
        try withRepository { repo, _ in
            var draft = ManualStrengthEvidenceDraft()
            let performed = evidenceNow.addingTimeInterval(-86_400)
            let value = TrainingObservationValue.strengthSet(exerciseID: "barbell-bench-press",
                equipmentID: nil, repetitions: 8, externalLoadKilograms: 60,
                assistanceKilograms: nil, convention: .total, effort: nil)
            let first = try draft.observation(athleteID: 1, measuredAt: performed, value: value, now: evidenceNow)
            XCTAssertEqual(first.measuredAt, performed)
            XCTAssertEqual(first.receivedAt, evidenceNow)
            XCTAssertNotEqual(first.receivedAt, first.measuredAt)
            try repo.append(first, athleteID: 1)
            let retry = try draft.observation(athleteID: 1, measuredAt: performed, value: value,
                                              now: evidenceNow.addingTimeInterval(60))
            XCTAssertEqual(retry, first)
            try repo.append(retry, athleteID: 1)
            XCTAssertEqual(try repo.currentObservations(athleteID: 1), [first])
        }
    }

    func testInvalidManualSetDoesNotCaptureSubmissionTime() throws {
        var draft = ManualStrengthEvidenceDraft()
        XCTAssertThrowsError(try draft.observation(athleteID: 1, measuredAt: evidenceNow,
            value: .run(distanceMeters: 1000, durationSeconds: 300, effort: nil), now: evidenceNow))
        XCTAssertNil(draft.receivedAt)
        let set = TrainingObservationValue.strengthSet(exerciseID: "pull-up", equipmentID: nil,
            repetitions: 5, externalLoadKilograms: nil, assistanceKilograms: nil, convention: .bodyweight, effort: nil)
        XCTAssertThrowsError(try draft.observation(athleteID: 1, measuredAt: evidenceNow.addingTimeInterval(60),
                                                  value: set, now: evidenceNow))
        XCTAssertNil(draft.receivedAt)
    }

    func testRunImportPreservesActualElapsedTimeAndUnknownEffort() throws {
        let record = try XCTUnwrap(TrainingEvidenceImportService.observation(
            for: importedActivity(), athleteID: 1, now: evidenceNow))
        XCTAssertEqual(record.measuredAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(record.receivedAt, evidenceNow)
        XCTAssertEqual(record.sourceRecordID, "activity:42")
        XCTAssertEqual(record.value, .run(distanceMeters: 5000, durationSeconds: 1800, effort: nil))
        XCTAssertNil(record.sessionID)
    }

    func testImportDoesNotInferRunningFromTitlesOrAcceptUnownedActivities() throws {
        for fields: [String: Any] in [
            ["type": "Walk", "name": "Recovery run"],
            ["type": "Ride", "name": "Run commute"],
            ["type": NSNull(), "name": "Morning run"],
            ["athlete_id": 2], ["athlete_id": NSNull()], ["flagged": true]
        ] {
            XCTAssertNil(TrainingEvidenceImportService.observation(
                for: try importedActivity(fields), athleteID: 1, now: evidenceNow), "\(fields)")
        }
    }

    func testImportExcludesIncompleteMissingAndNonpositiveMeasurements() throws {
        for fields: [String: Any] in [
            ["distance": 0], ["distance": -1], ["distance": NSNull()],
            ["elapsed_time": 0], ["elapsed_time": NSNull()],
            ["activity_date": NSNull()], ["activity_date": "2099-01-01T00:00:00Z"],
            ["elapsed_time": 200_000]
        ] {
            XCTAssertNil(TrainingEvidenceImportService.observation(
                for: try importedActivity(fields), athleteID: 1, now: evidenceNow), "\(fields)")
        }
    }

    func testRunImportIsIdempotentAndLeavesProfileTargetsUntouched() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = ProtectedTrainingRepository(root: root, activeAthleteID: { 1 })
        let profile = AthleteTrainingProfile(athleteID: 1)
        try repo.saveProfile(profile, athleteID: 1)
        let activity = try importedActivity()
        let first = try await TrainingEvidenceImportService.importRuns([activity, activity], athleteID: 1,
                                                                      repository: repo, now: evidenceNow)
        XCTAssertEqual(first.imported, 1)
        XCTAssertEqual(first.unchanged, 1)
        let retry = try await TrainingEvidenceImportService.importRuns([activity], athleteID: 1,
            repository: repo, now: evidenceNow.addingTimeInterval(60))
        XCTAssertEqual(retry.imported, 0)
        XCTAssertEqual(retry.unchanged, 1)
        XCTAssertEqual(try repo.observations(athleteID: 1).count, 1)
        XCTAssertEqual(try repo.loadProfile(athleteID: 1), profile)
    }

    func testGarminRunPreventsCompetingAppleHealthMirrorObservation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = ProtectedTrainingRepository(root: root, activeAthleteID: { 1 })
        let garmin = try importedActivity(["id": 420, "source": "garmin"])
        let appleMirror = try importedActivity([
            "id": 421,
            "source": "apple_health",
            "activity_date": "2023-11-14T22:14:20Z",
            "distance": 4_950.0,
            "elapsed_time": 1_830.0
        ])

        let result = try await TrainingEvidenceImportService.importRuns(
            [appleMirror, garmin], athleteID: 1, repository: repo, now: evidenceNow)

        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(try repo.currentObservations(athleteID: 1).count, 1)
        XCTAssertEqual(try repo.currentObservations(athleteID: 1).first?.sourceRecordID, "activity:garmin:420")
    }

    func testReimportPreservesCorrectionAndReportsChangedSourceForReview() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = ProtectedTrainingRepository(root: root, activeAthleteID: { 1 })
        let activity = try importedActivity()
        _ = try await TrainingEvidenceImportService.importRuns([activity], athleteID: 1, repository: repo, now: evidenceNow)
        let original = try XCTUnwrap(repo.observations(athleteID: 1).first)
        let corrected = TrainingObservation(id: UUID(), athleteID: 1, measuredAt: original.measuredAt,
            receivedAt: evidenceNow, source: original.source, sourceRecordID: original.sourceRecordID,
            sessionID: nil, supersedesID: original.id,
            value: .run(distanceMeters: 5000, durationSeconds: 1850, effort: nil))
        try repo.append(corrected, athleteID: 1)
        let result = try await TrainingEvidenceImportService.importRuns(
            [activity, importedActivity(["elapsed_time": 1900])], athleteID: 1, repository: repo, now: evidenceNow)
        XCTAssertEqual(result.unchanged, 1)
        XCTAssertEqual(result.needsReview, 1)
        XCTAssertEqual(result.imported, 0)
        XCTAssertEqual(try repo.currentObservations(athleteID: 1), [corrected])
        XCTAssertEqual(try repo.observations(athleteID: 1).count, 2)
    }

    func testImportRejectsInactiveAccountWithoutWritingEvidence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var active: Int? = 2
        let repo = ProtectedTrainingRepository(root: root, activeAthleteID: { active })
        do {
            _ = try await TrainingEvidenceImportService.importRuns([importedActivity()], athleteID: 1,
                                                                   repository: repo, now: evidenceNow)
            XCTFail("An inactive account must not import evidence")
        } catch ProtectedTrainingRepository.RepositoryError.ownershipMismatch {
            // Expected ownership rejection, not an arbitrary decoding or I/O failure.
        }
        active = 1
        XCTAssertTrue(try repo.observations(athleteID: 1).isEmpty)
    }
}
