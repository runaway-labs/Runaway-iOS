import Foundation

struct AthleteBiometric: Codable, Identifiable {
    let id: UUID?
    let athleteId: Int
    let entryDate: String // YYYY-MM-DD
    let hrvMs: Double?
    let rhrBpm: Int?
    let sleepScore: Int?
    let readinessScore: Int?
    let recoveryPhase: String?
    let stressLevel: Double?
    let rawSource: String?
    let hrvBaselineMs: Double?
    let rhrBaselineBpm: Double?
    let sleepMinutes: Int?
    let deepSleepMinutes: Int?
    let remSleepMinutes: Int?
    let coreSleepMinutes: Int?
    let awakeMinutes: Int?
    let sleepStartAt: Date?
    let sleepEndAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case athleteId = "athlete_id"
        case entryDate = "entry_date"
        case hrvMs = "hrv_ms"
        case rhrBpm = "rhr_bpm"
        case sleepScore = "sleep_score"
        case readinessScore = "readiness_score"
        case recoveryPhase = "recovery_phase"
        case stressLevel = "stress_level"
        case rawSource = "raw_source"
        case hrvBaselineMs = "hrv_baseline_ms"
        case rhrBaselineBpm = "rhr_baseline_bpm"
        case sleepMinutes = "sleep_minutes"
        case deepSleepMinutes = "deep_sleep_minutes"
        case remSleepMinutes = "rem_sleep_minutes"
        case coreSleepMinutes = "core_sleep_minutes"
        case awakeMinutes = "awake_minutes"
        case sleepStartAt = "sleep_start_at"
        case sleepEndAt = "sleep_end_at"
    }
}
