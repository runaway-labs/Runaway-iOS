import Foundation
import Combine
import WidgetKit
import Supabase

/// Loads a complete, narrow year-to-date projection rather than treating the
/// activity feed's latest 50 records as a complete history.
@MainActor
final class TrainingProgressStore: ObservableObject {
    static let shared = TrainingProgressStore()
    @Published private(set) var snapshot: TrainingProgressSnapshot?
    @Published private(set) var weekActivities: [TrainingProgressActivity] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    private var athleteID: Int?
    private var generation = 0
    private var work: Task<Void, Never>?
    private let defaults = UserDefaults(suiteName: AppConstants.AppGroup.identifier)

    func activate(athleteID id: Int) {
        guard athleteID != id else { return }
        work?.cancel()
        work = nil
        generation += 1
        athleteID = id
        weekActivities = []
        errorMessage = nil
        isRefreshing = false
        snapshot = TrainingProgressSnapshot.cached(in: defaults, athleteID: id)
        if snapshot?.isCurrent() != true { snapshot = nil }
        defaults?.set(id, forKey: TrainingProgressSnapshot.athleteKey)
        if snapshot == nil { defaults?.removeObject(forKey: TrainingProgressSnapshot.cacheKey) }
    }

    func reset() {
        work?.cancel()
        work = nil
        generation += 1
        athleteID = nil
        snapshot = nil
        weekActivities = []
        errorMessage = nil
        isRefreshing = false
        defaults?.removeObject(forKey: TrainingProgressSnapshot.cacheKey)
        // Zero explicitly marks a signed-out payload to the widget adapter.
        defaults?.set(0, forKey: TrainingProgressSnapshot.athleteKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func refresh(athleteID id: Int, force: Bool = false) async {
        activate(athleteID: id)
        if !force, let snapshot, snapshot.isCurrent(), !weekActivities.isEmpty,
           Date().timeIntervalSince(snapshot.refreshedAt) < 60 { return }
        if let work {
            await work.value
            guard force, athleteID == id else { return }
        }
        let token = generation
        isRefreshing = true
        errorMessage = nil
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let now = Date()
                let calendar = Calendar.current
                let yearStart = calendar.dateInterval(of: .year, for: now)!.start
                let from = min(yearStart, TrainingProgressPolicy.weekStart(for: now, calendar: calendar))
                let activities = try await Self.fetch(athleteID: id, from: from, through: now)
                try Task.checkCancellation()
                guard self.athleteID == id, self.generation == token else { return }
                let snapshot = TrainingProgressPolicy.snapshot(activities: activities, athleteID: id, at: now, calendar: calendar)
                self.weekActivities = TrainingProgressPolicy.unique(activities, athleteID: id, through: now)
                    .filter { $0.date >= snapshot.weekStart }.sorted { $0.date > $1.date }
                self.snapshot = snapshot
                WidgetSyncService.shared.updateProgressSnapshot(snapshot)
            } catch is CancellationError {
                // A superseded athlete's response must never be published.
            } catch {
                guard self.athleteID == id, self.generation == token else { return }
                self.errorMessage = "Couldn't refresh progress. Your last synced totals are kept."
            }
        }
        work = task
        await task.value
        if generation == token { work = nil; isRefreshing = false }
    }

    private static func fetch(athleteID: Int, from: Date, through now: Date) async throws -> [TrainingProgressActivity] {
        let formatter = ISO8601DateFormatter()
        let lower = formatter.string(from: from)
        let upper = formatter.string(from: now)
        var result: [TrainingProgressActivity] = []
        var offset = 0
        while true {
            try Task.checkCancellation()
            let rows: [TrainingProgressRemoteActivity] = try await supabase.from("activities")
                .select("id,athlete_id,name,activity_types(name),start_time,activity_date,distance,elapsed_time,flagged,map_summary_polyline")
                .eq("athlete_id", value: athleteID)
                .or("and(start_time.gte.\(lower),start_time.lte.\(upper)),and(start_time.is.null,activity_date.gte.\(lower),activity_date.lte.\(upper))")
                .order("id", ascending: true)
                .range(from: offset, to: offset + 499)
                .execute().value
            result.append(contentsOf: rows.compactMap(\.activity))
            if rows.count < 500 { break }
            offset += 500
        }
        return result
    }
}

struct TrainingProgressRemoteActivity: Decodable {
    struct ActivityType: Decodable { let name: String }
    let id: Int
    let athlete_id: Int
    let name: String?
    let activity_types: ActivityType?
    let start_time: Date?
    let activity_date: Date?
    let distance: Double?
    let elapsed_time: Double?
    let flagged: Bool?
    let map_summary_polyline: String?

    var activity: TrainingProgressActivity? {
        guard flagged != true, let date = start_time ?? activity_date else { return nil }
        return TrainingProgressActivity(id: id, athleteID: athlete_id, name: name ?? "Activity",
            type: activity_types?.name ?? "Other", date: date,
            meters: TrainingProgressPolicy.clean(distance ?? 0), seconds: TrainingProgressPolicy.clean(elapsed_time ?? 0),
            polyline: map_summary_polyline ?? "")
    }
}

extension TrainingProgressActivity {
    var localActivity: LocalActivity {
        LocalActivity(id: id, name: name, type: type, summary_polyline: polyline,
                      distance: meters, start_date: date, elapsed_time: seconds)
    }

    init?(_ activity: Activity, athleteID: Int) {
        guard activity.flagged != true,
              let timestamp = activity.activity_date ?? activity.start_date else { return nil }
        self.init(id: activity.id, athleteID: activity.athlete_id ?? athleteID,
                  name: activity.name ?? "Activity", type: activity.type ?? "Other",
                  date: Date(timeIntervalSince1970: timestamp),
                  meters: TrainingProgressPolicy.clean(activity.distance ?? 0),
                  seconds: TrainingProgressPolicy.clean(activity.elapsed_time ?? 0), polyline: activity.summary_polyline ?? "")
    }
}
