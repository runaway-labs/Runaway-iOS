import Foundation
import Supabase

@MainActor
protocol AthleteStateProviding {
    func latestState(athleteID: Int) async throws -> AthleteStateSnapshot?
    func latestPrescription(athleteID: Int, status: PrescriptionStatus) async throws -> TrainingPrescriptionRevision?
}

@MainActor
final class AthleteStateService: ObservableObject, AthleteStateProviding {
    typealias StateLoader = (Int) async throws -> AthleteStateSnapshot?
    typealias PrescriptionLoader = (Int, PrescriptionStatus) async throws -> TrainingPrescriptionRevision?

    @Published private(set) var snapshot: AthleteStateSnapshot?
    @Published private(set) var shadowPrescription: TrainingPrescriptionRevision?
    @Published private(set) var refreshError: Error?

    private let stateLoader: StateLoader
    private let prescriptionLoader: PrescriptionLoader
    private let cache: UserDefaults?

    init() {
        stateLoader = Self.loadLatestState
        prescriptionLoader = Self.loadLatestPrescription
        cache = .standard
    }

    init(stateLoader: @escaping StateLoader, prescriptionLoader: @escaping PrescriptionLoader) {
        self.stateLoader = stateLoader
        self.prescriptionLoader = prescriptionLoader
        cache = nil
    }

    func latestState(athleteID: Int) async throws -> AthleteStateSnapshot? {
        try await stateLoader(athleteID)
    }

    func latestPrescription(athleteID: Int, status: PrescriptionStatus) async throws -> TrainingPrescriptionRevision? {
        try await prescriptionLoader(athleteID, status)
    }

    func refresh(athleteID: Int) async throws {
        if snapshot == nil { snapshot = cachedSnapshot(athleteID: athleteID) }
        do {
            async let state = stateLoader(athleteID)
            async let prescription = prescriptionLoader(athleteID, .shadow)
            let (latestState, latestPrescription) = try await (state, prescription)
            if let latestState {
                snapshot = latestState
                cacheSnapshot(latestState, athleteID: athleteID)
            }
            if let latestPrescription { shadowPrescription = latestPrescription }
            refreshError = nil
        } catch {
            refreshError = error
            throw error
        }
    }

    private static func loadLatestState(_ athleteID: Int) async throws -> AthleteStateSnapshot? {
        let rows: [AthleteStateSnapshot] = try await supabase.from("athlete_daily_states")
            .select().eq("athlete_id", value: athleteID)
            .order("calculated_at", ascending: false).limit(1).execute().value
        return rows.first
    }

    private static func loadLatestPrescription(_ athleteID: Int, _ status: PrescriptionStatus) async throws -> TrainingPrescriptionRevision? {
        let rows: [TrainingPrescriptionRevision] = try await supabase.from("training_prescription_revisions")
            .select().eq("athlete_id", value: athleteID).eq("status", value: status.rawValue)
            .order("calculated_at", ascending: false).limit(1).execute().value
        return rows.first
    }

    private func cacheKey(_ athleteID: Int) -> String { "athleteStateSnapshot.v1.\(athleteID)" }

    private func cacheSnapshot(_ value: AthleteStateSnapshot, athleteID: Int) {
        guard let cache else { return }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(value) { cache.set(data, forKey: cacheKey(athleteID)) }
    }

    private func cachedSnapshot(athleteID: Int) -> AthleteStateSnapshot? {
        guard let data = cache?.data(forKey: cacheKey(athleteID)) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AthleteStateSnapshot.self, from: data)
    }
}
