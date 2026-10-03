import Foundation

@main
struct TrainingProgressMirrorChecks {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let formatter = ISO8601DateFormatter()
        let now = formatter.date(from: "2026-10-02T22:00:00Z")!
        func row(_ id: Int, _ source: String?, _ type: String, _ time: String,
                 _ seconds: Double, _ meters: Double) throws -> TrainingProgressActivity {
            var json: [String: Any] = ["id": id, "athleteID": 7, "name": type, "type": type,
                "date": formatter.date(from: time)!.timeIntervalSinceReferenceDate,
                "seconds": seconds, "meters": meters, "polyline": ""]
            if let source { json["source"] = source }
            return try JSONDecoder().decode(TrainingProgressActivity.self, from: JSONSerialization.data(withJSONObject: json))
        }
        // Garmin lacks activity_types; Strava supplies the sport. Both describe
        // the same session using activity_date, despite different database IDs.
        let monday = "2026-09-28T18:46:08Z"
        let tuesday = "2026-09-29T18:25:18Z"
        let thursday = "2026-10-01T20:29:06Z"
        let friday = "2026-10-02T14:33:07Z"
        let week = try [row(-1, "garmin", "", monday, 3137, 7702.45), row(1, "strava", "Run", monday, 3137, 7702.50),
            row(-2, "garmin", "", tuesday, 4454, 0), row(2, "strava", "WeightTraining", tuesday, 4454, 0),
            row(-3, "garmin", "", thursday, 1830, 3758.21), row(3, "strava", "Run", thursday, 1834, 3758.20),
            row(-4, "garmin", "", friday, 4246, 4436.48), row(4, "strava", "Walk", friday, 4246, 4436.50)]
        var count = 0
        func check(_ condition: Bool, _ name: String) {
            guard condition else { fatalError("FAIL: \(name)") }
            count += 1
            print("PASS: \(name)")
        }
        func snapshot(_ rows: [TrainingProgressActivity]) -> TrainingProgressSnapshot {
            TrainingProgressPolicy.snapshot(activities: rows, athleteID: 7, at: now, calendar: calendar)
        }
        let result = snapshot(week)
        check(result.week.sessions == 4 && result.week.seconds == 13671, "Garmin/Strava mirrored sessions count once, including zero-distance strength")
        check(result.days.flatMap(\.segments).allSatisfy { $0.kind != .other }, "Missing Garmin sport does not add gray Other copies")
        check(result.week.runs == 2 && abs(result.week.runningMeters - 11460.70) < 0.00001, "Typed mirror retains running distance and run count")
        check(result.week.activeDays == 4 && result.month.seconds == 6080 && result.year.seconds == 13671, "All periods share the same deduplicated sessions")
        check(snapshot(Array(week.reversed())) == result, "Provider selection is independent of fetch order")
        let run = try row(10, "garmin", "Run", monday, 3137, 7702.45)
        let mirror = try row(11, "strava", "Run", monday, 3137, 7702.50)
        check(snapshot([run, mirror]).week.runningMeters == 7702.45, "Garmin wins when both copies have a known matching sport")
        check(snapshot([mirror, try row(12, "strava", "Run", monday, 3137, 7702.50)]).week.sessions == 2, "Different records from the same provider are not inferred duplicates")
        check(snapshot([run, try row(13, "strava", "Walk", monday, 3137, 7702.45)]).week.sessions == 2, "Conflicting known sports remain separate")
        check(snapshot([run, try row(14, nil, "Run", monday, 3137, 7702.45)]).week.sessions == 2, "Missing provenance never suppresses a session")
        check(snapshot([run, try row(15, "strava", "Run", "2026-09-28T19:46:08Z", 3137, 7702.45)]).week.sessions == 2, "Two real workouts on the same day remain separate")
        check(snapshot([run, try row(16, "strava", "Run", monday, 3600, 7702.45)]).week.sessions == 2, "Duration mismatch is not merged")
        check(snapshot([run, try row(17, "strava", "Run", monday, 3137, 9000)]).week.sessions == 2, "Distance mismatch is not merged")
        check(snapshot([run, mirror, try row(18, "strava", "Run", monday, 3137, 7702.50)]).week.sessions == 3, "Ambiguous cross-provider candidates remain separate")
        check(snapshot([run, run]).week.sessions == 1, "Repeated database ID still counts once")
        check(snapshot([try row(19, "garmin", "Other", monday, 3137, 7702.45), mirror]).week.sessions == 2, "Explicit Other sport is not treated as a missing type")
        let suite = "runaway.progress-mirror.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode(result), forKey: "training_progress_snapshot_v1")
        check(TrainingProgressSnapshot.cached(in: defaults, athleteID: 7) == nil, "Pre-fix aggregate cache is discarded instead of showing doubled totals")
        defaults.set(try JSONEncoder().encode(result), forKey: TrainingProgressSnapshot.cacheKey)
        check(TrainingProgressSnapshot.cached(in: defaults, athleteID: 7) == result, "Corrected aggregate cache remains readable")
        print("\(count) progress mirror checks passed")
    }
}
