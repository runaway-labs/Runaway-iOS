import Foundation

struct RecordedEffortSplit: Codable, Sendable {
    let distance: Double?
    let elapsed_time: Double?
}

/// A pace projection is never evidence of having covered the target distance.
/// Whole sessions and contiguous recorded splits must cover the actual target.
enum PersonalRecordEvidencePolicy {
    static func supports(targetMeters: Double, timeSeconds: Int, kind: ProgressActivityKind,
                         flagged: Bool, activityMeters: Double, activitySeconds: Double,
                         splits: [RecordedEffortSplit]) -> Bool {
        guard kind == .run, !flagged, targetMeters.isFinite, targetMeters > 0, timeSeconds > 0 else { return false }
        let tolerance = 1.0 // Rounding of recorded GPS distances, never a broad race-distance bin.
        if abs(activityMeters - targetMeters) <= tolerance,
           abs(activitySeconds - Double(timeSeconds)) < 0.5 { return true }
        for start in splits.indices {
            var meters = 0.0
            var seconds = 0.0
            for split in splits[start...] {
                guard let distance = split.distance, let time = split.elapsed_time,
                      distance.isFinite, time.isFinite, distance > 0, time > 0 else { break }
                meters += distance
                seconds += time
                if abs(meters - targetMeters) <= tolerance, abs(seconds - Double(timeSeconds)) < 0.5 { return true }
                if meters > targetMeters + tolerance { break }
            }
        }
        return false
    }
}

struct SupportedPersonalBest: Identifiable {
    let record: PersonalBest
    let activity: LocalActivity
    var id: Int { record.id }
}
