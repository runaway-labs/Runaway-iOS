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

    private static func provider(for activity: Activity) -> String? {
        guard let source = activity.source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !source.isEmpty else { return nil }
        if source.contains("garmin") { return "garmin" }
        if source.contains("apple") || source.contains("healthkit") || source.contains("health_kit") {
            return "apple_health"
        }
        return source.replacingOccurrences(of: " ", with: "_")
    }

    private static func sourceRecordID(for activity: Activity) -> String {
        guard let provider = provider(for: activity) else { return "activity:\(activity.id)" }
        return "activity:\(provider):\(activity.id)"
    }

    private static func isProbableMirror(_ left: TrainingObservation, _ right: TrainingObservation) -> Bool {
        guard abs(left.measuredAt.timeIntervalSince(right.measuredAt)) <= 120,
              case let .run(leftDistance, leftDuration, _) = left.value,
              case let .run(rightDistance, rightDuration, _) = right.value else { return false }
        let durationTolerance = max(60, max(leftDuration, rightDuration) * 0.05)
        let distanceTolerance = max(100, max(leftDistance, rightDistance) * 0.05)
        return abs(leftDuration - rightDuration) <= durationTolerance &&
            abs(leftDistance - rightDistance) <= distanceTolerance
    }

    private static func authoritativeActivities(
        from activities: [Activity], athleteID: Int, now: Date
    ) -> [Activity] {
        let garmin = activities.compactMap { activity -> TrainingObservation? in
            guard provider(for: activity) == "garmin" else { return nil }
            return observation(for: activity, athleteID: athleteID, now: now)
        }

        return activities.filter { activity in
            guard provider(for: activity) == "apple_health",
                  let apple = observation(for: activity, athleteID: athleteID, now: now) else { return true }
            return !garmin.contains { isProbableMirror(apple, $0) }
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
            receivedAt: now, source: .importedActivity, sourceRecordID: sourceRecordID(for: activity),
            sessionID: nil, supersedesID: nil,
            value: .run(distanceMeters: distance, durationSeconds: elapsed, effort: nil))
    }

    static func importRuns(_ activities: [Activity], athleteID: Int,
                           repository: ProtectedTrainingRepository, now: Date = Date(),
                           eventSink: (@MainActor (CoachEvent) async -> Void)? = nil) async throws -> Report {
        let history = try repository.observations(athleteID: athleteID)
        var bySource = Dictionary(grouping: history.filter { $0.source == .importedActivity }, by: \.sourceRecordID)
        var report = Report()
        for activity in authoritativeActivities(from: activities, athleteID: athleteID, now: now) {
            try Task.checkCancellation()
            guard let candidate = observation(for: activity, athleteID: athleteID, now: now) else {
                report.excluded += 1
                continue
            }
            let legacySourceRecordID = "activity:\(activity.id)"
            if let revisions = bySource[candidate.sourceRecordID] ?? bySource[legacySourceRecordID] {
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
