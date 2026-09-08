import Foundation
import Supabase

// Read-only saved-record presentation. Legacy estimates are retained in the
// database for a reviewed repair; they do not become achievement badges.
class PersonalBestService {
    static let shared = PersonalBestService()
    private init() {}

    func fetchPRs(athleteId: Int) async throws -> [PersonalBest] {
        try await supabase.from("athlete_personal_bests").select()
            .eq("athlete_id", value: athleteId).order("distance_label").execute().value
    }

    func fetchSupportedPRs(athleteId: Int) async throws -> [SupportedPersonalBest] {
        let records = try await fetchPRs(athleteId: athleteId)
        let ids = Array(Set(records.compactMap(\.activityId)))
        guard !ids.isEmpty else { return [] }
        let rows: [EvidenceRow] = try await supabase.from("activities")
            .select("id,athlete_id,name,activity_types(name),start_time,activity_date,distance,elapsed_time,flagged,splits,map_summary_polyline")
            .eq("athlete_id", value: athleteId).in("id", values: ids).execute().value
        let sources = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return records.compactMap { record in
            guard record.athleteId == athleteId,
                  let id = record.activityId, let source = sources[id],
                  source.athlete_id == athleteId,
                  let date = source.start_time ?? source.activity_date,
                  abs(record.achievedAt.timeIntervalSince(date)) < 2,
                  let target = PRDistance.allCases.first(where: { $0.label == record.distanceLabel }),
                  abs(record.distanceMeters - target.nominalMeters) < 1,
                  PersonalRecordEvidencePolicy.supports(targetMeters: target.nominalMeters,
                      timeSeconds: record.timeSeconds, kind: ProgressActivityKind(source.activity_types?.name ?? ""),
                      flagged: source.flagged == true, activityMeters: source.distance ?? 0,
                      activitySeconds: source.elapsed_time ?? 0, splits: source.splits ?? []) else { return nil }
            let activity = LocalActivity(id: id, name: source.name ?? "Run", type: source.activity_types?.name ?? "Run",
                summary_polyline: source.map_summary_polyline ?? "", distance: source.distance ?? 0,
                start_date: date, elapsed_time: source.elapsed_time ?? 0)
            return SupportedPersonalBest(record: record, activity: activity)
        }
    }

    /// Compatibility for older callers. Opening a screen must not rewrite
    /// production bests with broad distance bins or projected split paces.
    func recomputeAndSave(athleteId: Int) async throws -> [PersonalBest] {
        try await fetchSupportedPRs(athleteId: athleteId).map(\.record)
    }

    private struct EvidenceRow: Decodable {
        let id: Int
        let athlete_id: Int
        let name: String?
        let activity_types: TrainingProgressRemoteActivity.ActivityType?
        let start_time: Date?
        let activity_date: Date?
        let distance: Double?
        let elapsed_time: Double?
        let flagged: Bool?
        let splits: [RecordedEffortSplit]?
        let map_summary_polyline: String?
    }
}

struct PersonalBestCandidate {
    let distanceLabel: String
    let distanceMeters: Double
    let timeSeconds: Int
    let activityId: Int?
    let achievedAt: Date
}

struct PersonalBestUpsertPayload: Encodable {
    let athlete_id: Int
    let distance_label: String
    let distance_meters: Double
    let time_seconds: Int
    let activity_id: Int?
    let achieved_at: Date
    let updated_at: Date

    init(candidate: PersonalBestCandidate, athleteId: Int, updatedAt: Date = Date()) {
        self.athlete_id = athleteId
        self.distance_label = candidate.distanceLabel
        self.distance_meters = candidate.distanceMeters
        self.time_seconds = candidate.timeSeconds
        self.activity_id = candidate.activityId
        self.achieved_at = candidate.achievedAt
        self.updated_at = updatedAt
    }
}

private enum PersonalBestServiceError: Error {
    case missingServerGeneratedRecord
}
