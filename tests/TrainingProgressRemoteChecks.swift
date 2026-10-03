import Foundation

@main
struct TrainingProgressRemoteChecks {
    static func main() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let canonical = ISO8601DateFormatter().date(from: "2026-09-28T18:46:08Z")!
        func remote(_ overrides: [String: Any] = [:]) throws -> TrainingProgressRemoteActivity {
            var json: [String: Any] = ["id": -1, "athlete_id": 7, "name": "Kirkwood Running",
                "activity_types": NSNull(), "source": "garmin", "start_time": "2026-09-28T13:46:08Z",
                "activity_date": "2026-09-28T18:46:08Z", "distance": 7702.45, "elapsed_time": 3137,
                "flagged": false, "map_summary_polyline": ""]
            json.merge(overrides) { _, new in new }
            return try decoder.decode(TrainingProgressRemoteActivity.self, from: JSONSerialization.data(withJSONObject: json))
        }
        var count = 0
        func check(_ condition: Bool, _ name: String) {
            guard condition else { fatalError("FAIL: \(name)") }
            count += 1
            print("PASS: \(name)")
        }
        let missingType = try remote().activity!
        check(missingType.date == canonical, "Canonical activity_date wins over provider-local start_time")
        check(missingType.type.isEmpty && missingType.kind == .other, "Missing sport stays unknown, without guessing from the activity title")
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(missingType)) as! [String: Any]
        check(encoded["source"] as? String == "garmin", "Provider provenance survives the remote projection and Codable boundary")
        check(try remote(["activity_types": ["name": "Run"]]).activity?.kind == .run, "Joined sport classification is retained")
        check(try remote(["activity_date": NSNull(), "start_time": "2026-09-28T18:46:08Z"]).activity?.date == canonical, "Missing canonical date falls back to start_time")
        check(try remote(["activity_date": NSNull(), "start_time": NSNull()]).activity == nil, "Missing both dates excludes the row")
        check(try remote(["flagged": true]).activity == nil, "Flagged rows remain excluded")
        check(try remote(["distance": NSNull()]).activity?.meters == 0, "Zero-distance strength remains a valid time contribution")
        let typed = try remote(["id": 1, "source": "strava", "activity_types": ["name": "Run"]]).activity!
        let unique = TrainingProgressPolicy.unique([missingType, typed], athleteID: 7, through: canonical.addingTimeInterval(3600))
        check(unique.count == 1 && unique.first?.kind == .run, "Remote decoding feeds canonical identity and sport into real deduplication")
        print("\(count) remote progress checks passed")
    }
}
