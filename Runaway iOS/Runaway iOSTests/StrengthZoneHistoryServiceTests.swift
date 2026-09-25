import Foundation
import Testing
@testable import Runaway_iOS

@Suite("Strength zone history")
struct StrengthZoneHistoryServiceTests {
    @Test("A completed catalog set credits primary and secondary zones")
    func completedSetAttribution() throws {
        let result = makeResult(exerciseID: "push_up", prescribed: 10, completed: 10)
        let snapshot = StrengthZoneHistoryService.snapshot(
            workouts: [], observations: [], sessionResults: [result], unattributedStrengthDates: []
        )

        #expect(snapshot.exposures[.chest]?.effectiveWorkingSets == 1)
        #expect(snapshot.exposures[.arms]?.effectiveWorkingSets == 0.5)
        #expect(snapshot.exposures[.chest]?.sourceResultIDs == [result.id])
    }

    @Test("Skipped and materially incomplete sets do not create exposure")
    func skippedAndInsufficientEntriesEarnNoCredit() {
        let skipped = makeResult(exerciseID: "push_up", prescribed: 10, completed: nil)
        let insufficient = makeResult(exerciseID: "push_up", prescribed: 10, completed: 4)

        let snapshot = StrengthZoneHistoryService.snapshot(
            workouts: [], observations: [], sessionResults: [skipped, insufficient],
            unattributedStrengthDates: []
        )

        #expect(snapshot.exposures.isEmpty)
    }

    @Test("Partial completed repetitions scale set credit")
    func partialCompletionScalesCredit() {
        let result = makeResult(exerciseID: "push_up", prescribed: 10, completed: 6)
        let snapshot = StrengthZoneHistoryService.snapshot(
            workouts: [], observations: [], sessionResults: [result], unattributedStrengthDates: []
        )

        #expect(snapshot.exposures[.chest]?.effectiveWorkingSets == 0.6)
        #expect(snapshot.exposures[.arms]?.effectiveWorkingSets == 0.3)
    }

    @Test("Duplicate result and prescription identifiers count once")
    func duplicateResultsAreDeduplicated() {
        let prescriptionID = UUID()
        let first = makeResult(exerciseID: "push_up", prescribed: 10, completed: 10,
                               acceptedPrescriptionID: prescriptionID)
        var exactDuplicate = first
        exactDuplicate.completedAt = first.completedAt.addingTimeInterval(60)
        let samePrescription = makeResult(exerciseID: "push_up", prescribed: 10, completed: 10,
                                          acceptedPrescriptionID: prescriptionID)

        let snapshot = StrengthZoneHistoryService.snapshot(
            workouts: [], observations: [],
            sessionResults: [first, exactDuplicate, samePrescription], unattributedStrengthDates: []
        )

        #expect(snapshot.exposures[.chest]?.effectiveWorkingSets == 1)
        #expect(snapshot.exposures[.chest]?.sourceResultIDs == [first.id])
    }

    @Test("Stable set observations count but unknown exercise IDs do not")
    func observationAttributionRequiresCatalogIdentity() {
        let known = makeObservation(exerciseID: "dead_bug", sourceRecordID: "known")
        let unknown = makeObservation(exerciseID: "generic_strength", sourceRecordID: "unknown")

        let snapshot = StrengthZoneHistoryService.snapshot(
            workouts: [], observations: [known, unknown], sessionResults: [],
            unattributedStrengthDates: []
        )

        #expect(snapshot.exposures[.core]?.effectiveWorkingSets == 1)
        #expect(snapshot.exposures.count == 1)
    }

    @Test("Duration-only external strength never invents zone exposure")
    func durationOnlyExternalStrengthDoesNotCreateZoneExposure() {
        let snapshot = StrengthZoneHistoryService.snapshot(
            workouts: [], observations: [], sessionResults: [],
            unattributedStrengthDates: [Date(timeIntervalSince1970: 1_800_000_000)]
        )

        #expect(snapshot.exposures.isEmpty)
        #expect(snapshot.hasUnattributedStrengthWork)
    }

    @Test("Each exposure retains the zone represented by its dictionary key")
    func exposureZoneIdentityIsStableWhenTotalsMatch() {
        var result = makeResult(exerciseID: "dead_bug", prescribed: 10, completed: 10)
        let legsItem = TrainingSessionResult.Item(
            id: "set-2", title: "Bodyweight Squat", kind: .strength,
            exerciseID: "bodyweight_squat", seconds: nil, repetitions: 10...10,
            convention: .bodyweight, loadKilograms: nil, assistanceKilograms: nil,
            prescribedRepetitions: 10
        )
        result.reference.items.append(legsItem)
        result.entries.append(TrainingSessionResult.Entry(
            itemID: legsItem.id, skipped: false, seconds: nil, repetitions: 10,
            loadKilograms: nil, assistanceKilograms: nil, repsInReserve: 2
        ))

        let snapshot = StrengthZoneHistoryService.snapshot(
            workouts: [], observations: [], sessionResults: [result], unattributedStrengthDates: []
        )

        #expect(snapshot.exposures[.core]?.zone == .core)
        #expect(snapshot.exposures[.legs]?.zone == .legs)
    }

    @Test("History labels stay concise and stop implying stale precision")
    func controlledContextLabels() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(StrengthZoneHistoryPresentation.context(
            for: exposure(at: calendar.date(byAdding: .day, value: -1, to: now)!, sets: 4),
            now: now, calendar: calendar
        ) == .trainedYesterday)
        #expect(StrengthZoneHistoryPresentation.context(
            for: exposure(at: calendar.date(byAdding: .day, value: -8, to: now)!, sets: 4),
            now: now, calendar: calendar
        ) == .daysAgo(8))
        #expect(StrengthZoneHistoryPresentation.context(
            for: exposure(at: calendar.date(byAdding: .day, value: -3, to: now)!, sets: 1),
            now: now, calendar: calendar
        ) == .lowVolume)
        #expect(StrengthZoneHistoryPresentation.context(
            for: exposure(at: calendar.date(byAdding: .day, value: -43, to: now)!, sets: 4),
            now: now, calendar: calendar
        ) == .noRecentData)
        #expect(StrengthZoneHistoryPresentation.context(for: nil, now: now, calendar: calendar) == .noRecentData)
    }

    private func makeResult(
        exerciseID: String,
        prescribed: Int,
        completed: Int?,
        acceptedPrescriptionID: UUID? = UUID()
    ) -> TrainingSessionResult {
        let generatedAt = Date(timeIntervalSince1970: 1_799_999_000)
        let completedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let item = TrainingSessionResult.Item(
            id: "set-1", title: exerciseID, kind: .strength, exerciseID: exerciseID,
            seconds: nil, repetitions: prescribed...prescribed, convention: .bodyweight,
            loadKilograms: nil, assistanceKilograms: nil, prescribedRepetitions: prescribed
        )
        let reference = TrainingSessionResult.Reference(
            athleteID: 42, goalID: UUID(), goalTitle: "Strength", fingerprint: UUID().uuidString,
            policyVersion: "test", generatedAt: generatedAt, distanceUnit: .miles,
            massUnit: .pounds, prescribedSeconds: 600, items: [item],
            acceptedPrescriptionID: acceptedPrescriptionID
        )
        return TrainingSessionResult(
            id: UUID(), reference: reference, completedAt: completedAt, recordedAt: completedAt,
            elapsedSeconds: 600, perceivedEffort: 7, bodyState: .good,
            entries: [TrainingSessionResult.Entry(
                itemID: item.id, skipped: completed == nil, seconds: nil, repetitions: completed,
                loadKilograms: nil, assistanceKilograms: nil,
                repsInReserve: completed == nil ? nil : 2
            )]
        )
    }

    private func makeObservation(exerciseID: String, sourceRecordID: String) -> TrainingObservation {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        return TrainingObservation(
            id: UUID(), athleteID: 42, measuredAt: date, receivedAt: date,
            source: .importedActivity, sourceRecordID: sourceRecordID, sessionID: nil,
            supersedesID: nil,
            value: .strengthSet(
                exerciseID: exerciseID, equipmentID: nil, repetitions: 10,
                externalLoadKilograms: nil, assistanceKilograms: nil,
                convention: .bodyweight, effort: nil
            )
        )
    }

    private func exposure(at date: Date, sets: Double) -> StrengthZoneExposure {
        StrengthZoneExposure(zone: .chest, effectiveWorkingSets: sets,
                             lastTrainedAt: date, sourceResultIDs: [])
    }
}
