import Foundation
import Supabase
import HealthKit

actor BiometricService {
    static let shared = BiometricService()

    private let reader = HealthKitDataReader()
    private let defaults = UserDefaults.standard
    private let initialBackfillVersion = 2
    private var isSyncing = false

    func recentBiometrics(athleteID: Int, limit: Int = 30) async throws -> [AthleteBiometric] {
        try await supabase.from("athlete_biometrics").select().eq("athlete_id", value: athleteID)
            .order("entry_date", ascending: false).limit(max(1, min(limit, 90))).execute().value
    }

    func syncHealthData() async {
        guard !isSyncing else { return }
        guard let athleteId = await UserSession.shared.userId else { return }

        isSyncing = true
        defer { isSyncing = false }

        let backfillKey = "biometricHistoryBackfill.v\(initialBackfillVersion).\(athleteId)"
        let completedInitialBackfill = defaults.bool(forKey: backfillKey)
        let calendar = Calendar.current
        let dates = BiometricSyncPlan.dates(
            endingOn: Date(),
            completedInitialBackfill: completedInitialBackfill,
            calendar: calendar
        )

        do {
            for date in dates {
                async let sleepTask = fetchSleep(on: date)
                async let hrvTask = fetchHRV(on: date)
                async let restingHRTask = fetchRestingHeartRate(on: date)
                let (sleep, hrv, restingHR) = await (sleepTask, hrvTask, restingHRTask)

                let dailyHRV = hrv?.samples.first(where: { calendar.isDate($0.date, inSameDayAs: date) })?.value
                let dailyRestingHR = restingHR?.samples.first(where: { calendar.isDate($0.date, inSameDayAs: date) })?.value

                guard sleep != nil || dailyHRV != nil || dailyRestingHR != nil else { continue }

                let readiness = calculateReadiness(
                    hrvScore: scoreHRV(dailyHRV, baseline: hrv?.averageHRV),
                    sleepScore: sleep?.qualityScore,
                    restingHRScore: scoreRestingHR(dailyRestingHR, baseline: restingHR?.averageRestingHR)
                )

                var payload: [String: AnyEncodable] = [
                    "athlete_id": AnyEncodable(athleteId),
                    "entry_date": AnyEncodable(ISO8601DateFormatter.justDate.string(from: date)),
                    "readiness_score": AnyEncodable(readiness.score),
                    "recovery_phase": AnyEncodable(readiness.phase),
                    "raw_source": AnyEncodable("apple_health")
                ]

                if let dailyHRV { payload["hrv_ms"] = AnyEncodable(dailyHRV) }
                if let baseline = hrv?.averageHRV { payload["hrv_baseline_ms"] = AnyEncodable(baseline) }
                if let dailyRestingHR { payload["rhr_bpm"] = AnyEncodable(Int(dailyRestingHR.rounded())) }
                if let baseline = restingHR?.averageRestingHR { payload["rhr_baseline_bpm"] = AnyEncodable(baseline) }

                if let sleep {
                    payload["sleep_score"] = AnyEncodable(sleep.qualityScore)
                    payload["sleep_minutes"] = AnyEncodable(Int(sleep.totalSleepMinutesRaw.rounded()))
                    payload["deep_sleep_minutes"] = AnyEncodable(Int(sleep.deepSleepMinutes.rounded()))
                    payload["rem_sleep_minutes"] = AnyEncodable(Int(sleep.remSleepMinutes.rounded()))
                    payload["core_sleep_minutes"] = AnyEncodable(Int(sleep.coreSleepMinutes.rounded()))
                    payload["awake_minutes"] = AnyEncodable(Int(sleep.awakeMinutes.rounded()))
                    if let start = sleep.sleepStartTime {
                        payload["sleep_start_at"] = AnyEncodable(ISO8601DateFormatter().string(from: start))
                    }
                    if let end = sleep.sleepEndTime {
                        payload["sleep_end_at"] = AnyEncodable(ISO8601DateFormatter().string(from: end))
                    }
                }

                try await supabase
                    .from("athlete_biometrics")
                    .upsert(payload, onConflict: "athlete_id, entry_date")
                    .execute()
            }

            defaults.set(true, forKey: backfillKey)

            #if DEBUG
            print("BiometricService: synced \(dates.count)-day collection window")
            #endif
        } catch {
            #if DEBUG
            print("BiometricService: sync failed: \(error)")
            #endif
        }
    }

    private func fetchSleep(on date: Date) async -> HealthKitDataReader.SleepAnalysis? {
        try? await reader.fetchSleepAnalysis(for: date)
    }

    private func fetchHRV(on date: Date) async -> HealthKitDataReader.HRVData? {
        try? await reader.fetchHRVData(for: date, days: 28)
    }

    private func fetchRestingHeartRate(on date: Date) async -> HealthKitDataReader.RestingHRData? {
        try? await reader.fetchRestingHeartRate(for: date, days: 28)
    }

    private func scoreHRV(_ value: Double?, baseline: Double?) -> Int? {
        guard let value, let baseline, baseline > 0 else { return nil }
        let rawScore = ((value / baseline) - 0.7) / 0.4 * 100
        return Int(min(max(rawScore, 0), 100))
    }

    private func scoreRestingHR(_ value: Double?, baseline: Double?) -> Int? {
        guard let value, let baseline, baseline > 0 else { return nil }
        return Int(min(max(70 - ((value - baseline) * 6), 0), 100))
    }

    private func calculateReadiness(
        hrvScore: Int?,
        sleepScore: Int?,
        restingHRScore: Int?
    ) -> (score: Int, phase: String) {
        let factors: [(score: Int?, weight: Double)] = [
            (hrvScore, 0.4),
            (sleepScore, 0.4),
            (restingHRScore, 0.2)
        ]
        let available = factors.compactMap { factor -> (Int, Double)? in
            guard let score = factor.score else { return nil }
            return (score, factor.weight)
        }
        let totalWeight = available.reduce(0) { $0 + $1.1 }
        let weightedScore = available.reduce(0) { $0 + (Double($1.0) * $1.1) }
        let score = totalWeight > 0 ? Int((weightedScore / totalWeight).rounded()) : 70

        let phase: String
        if score > 85 { phase = "peaking" }
        else if score < 45 { phase = "overreaching" }
        else if score < 60 { phase = "strained" }
        else { phase = "productive" }

        return (score, phase)
    }
}

enum BiometricSyncPlan {
    static func dates(
        endingOn date: Date,
        completedInitialBackfill: Bool,
        calendar: Calendar
    ) -> [Date] {
        let dayCount = completedInitialBackfill ? 3 : 30
        let end = calendar.startOfDay(for: date)
        return (0..<dayCount).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: end)
        }
    }
}

extension ISO8601DateFormatter {
    static let justDate: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}
