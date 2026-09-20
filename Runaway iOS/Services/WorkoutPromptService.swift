import Foundation
import Observation
import Supabase

@MainActor @Observable
final class WorkoutPromptService {
    static let shared = WorkoutPromptService()
    private(set) var settings: WorkoutPromptSettings?
    private(set) var accountID: Int?
    private(set) var syncRevision = 0
    private(set) var syncError: String?
    private(set) var lastPublishedAt: Date?

    func requestSync() { syncRevision += 1 }

    func load(athleteID: Int) async throws {
        if accountID != athleteID { reset(); accountID = athleteID }
        let rows: [WorkoutPromptSettings] = try await supabase.from("workout_prompt_settings")
            .select().eq("athlete_id", value: athleteID).limit(1).execute().value
        guard UserSession.shared.userId == athleteID else { return }
        settings = rows.first ?? WorkoutPromptSettings(athlete_id: athleteID)
    }

    func save(_ draft: WorkoutPromptSettings) async throws {
        var draft = draft
        guard UserSession.shared.userId == draft.athlete_id, draft.scheduleValidationMessage == nil,
              TimeZone(identifier: draft.timezone) != nil else { throw PromptError.invalidSettings }
        draft.schedules = draft.effectiveSchedules.map { entry in
            var entry = entry
            entry.weekdays = Array(Set(entry.weekdays)).sorted()
            return entry
        }
        if let first = draft.schedules?.first {
            draft.hour = first.hour; draft.minute = first.minute; draft.weekdays = first.weekdays
        }
        try await supabase.from("workout_prompt_settings").upsert(draft).execute()
        guard UserSession.shared.userId == draft.athlete_id else { return }
        settings = draft
        requestSync()
        if draft.enabled { await PushNotificationService.shared.activate() }
    }

    func publish(_ publication: WorkoutPromptPublication) async {
        do {
            guard UserSession.shared.userId == publication.p_athlete else { return }
            if accountID != publication.p_athlete || settings == nil { try await load(athleteID: publication.p_athlete) }
            guard settings?.enabled == true, UserSession.shared.userId == publication.p_athlete, !Task.isCancelled else { return }
            try await supabase.rpc("publish_workout_prompts", params: publication).execute()
            guard UserSession.shared.userId == publication.p_athlete else { return }
            syncError = nil
            lastPublishedAt = Date()
        } catch {
            guard UserSession.shared.userId == publication.p_athlete else { return }
            syncError = "Recommendations haven't synced. Reopen the app to retry; notifications will ask for a fresh check-in until a current recommendation is available."
        }
    }

    func register(token: String, athleteID: Int) async throws {
        struct Device: Encodable { let id: UUID; let athlete_id: Int; let token: String; let environment: String }
        let key = "workout-prompt-installation.\(athleteID)"
        let id = UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:)) ?? UUID()
        UserDefaults.standard.set(id.uuidString, forKey: key)
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        try await supabase.from("workout_prompt_devices")
            .upsert(Device(id: id, athlete_id: athleteID, token: token, environment: environment)).execute()
    }

    func unregister(token: String, athleteID: Int) async throws {
        try await supabase.from("workout_prompt_devices").delete()
            .eq("athlete_id", value: athleteID).eq("token", value: token).execute()
    }

    func delivery(_ id: UUID) async throws -> WorkoutPromptDelivery? {
        struct Parameters: Encodable { let p_delivery: UUID }
        return try await supabase.rpc("read_workout_prompt_delivery", params: Parameters(p_delivery: id)).execute().value
    }

    func reset() {
        settings = nil; accountID = nil; syncError = nil; lastPublishedAt = nil
    }

    enum PromptError: LocalizedError {
        case invalidSettings
        var errorDescription: String? { "Choose valid, non-overlapping notification times, at least one day for each, and a valid time zone." }
    }
}
