import Foundation

/// Imports completed API records, never planned workouts or inferred performance.
/// Changed source records require review rather than silently replacing a correction.
@MainActor
enum TrainingEvidenceImportService {
    struct Report {
        var imported = 0
        var unchanged = 0
        var excluded = 0
        var needsReview = 0

        var summary: String {
            "\(imported) runs added; \(unchanged) already recorded; \(excluded) excluded; \(needsReview) changed records need review."
        }
    }

    static func observation(for activity: Activity, athleteID: Int, now: Date) -> TrainingObservation? {
        // A title containing "run" is not proof that an activity is a run.
        let type = (activity.type ?? "").lowercased().filter { $0.isLetter }
        let runTypes: Set<String> = ["run", "running", "trailrun", "trailrunning", "virtualrun", "treadmill", "treadmillrun", "jog", "jogging"]
        guard activity.athlete_id == athleteID, activity.id > 0,
              runTypes.contains(type), activity.flagged != true,
              let distance = activity.distance, distance.isFinite, distance > 0,
              let elapsed = activity.elapsed_time, elapsed.isFinite, elapsed > 0,
              let timestamp = activity.activity_date ?? activity.start_date,
              timestamp.isFinite, timestamp > 0 else { return nil }
        let measuredAt = Date(timeIntervalSince1970: timestamp)
        guard measuredAt.addingTimeInterval(elapsed) <= now else { return nil }
        return TrainingObservation(id: UUID(), athleteID: athleteID, measuredAt: measuredAt,
            receivedAt: now, source: .importedActivity, sourceRecordID: "activity:\(activity.id)",
            sessionID: nil, supersedesID: nil,
            value: .run(distanceMeters: distance, durationSeconds: elapsed, effort: nil))
    }

    static func importRuns(_ activities: [Activity], athleteID: Int,
                           repository: ProtectedTrainingRepository, now: Date = Date(),
                           eventSink: (@MainActor (CoachEvent) async -> Void)? = nil) async throws -> Report {
        let history = try repository.observations(athleteID: athleteID)
        var bySource = Dictionary(grouping: history.filter { $0.source == .importedActivity }, by: \.sourceRecordID)
        var report = Report()
        for activity in activities {
            try Task.checkCancellation()
            guard let candidate = observation(for: activity, athleteID: athleteID, now: now) else {
                report.excluded += 1
                continue
            }
            if let revisions = bySource[candidate.sourceRecordID] {
                if revisions.contains(where: {
                    $0.value == candidate.value && $0.measuredAt == candidate.measuredAt && $0.sessionID == nil
                }) {
                    report.unchanged += 1
                } else {
                    report.needsReview += 1
                }
                continue
            }
            // Repository rechecks account ownership at each write, including after yielding.
            try repository.append(candidate, athleteID: athleteID)
            bySource[candidate.sourceRecordID] = [candidate]
            report.imported += 1
            let event = CoachEvent(
                athleteID: athleteID, kind: .workoutImported, source: .app,
                occurredAt: candidate.measuredAt, receivedAt: candidate.receivedAt,
                sourceRecordID: candidate.sourceRecordID,
                payload: .workoutImported(activityID: activity.id)
            )
            if let eventSink {
                await eventSink(event)
            } else {
                let ledger = CoachDecisionLedger(repository: repository, athleteID: athleteID)
                try ledger.append(event)
            }
            await Task.yield()
        }
        return report
    }
}
