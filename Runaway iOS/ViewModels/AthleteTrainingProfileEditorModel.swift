import Combine
import Foundation

@MainActor
final class AthleteTrainingProfileEditorModel: ObservableObject {
    @Published var draft: AthleteTrainingProfile
    @Published private(set) var observations: [TrainingObservation] = []
    @Published private(set) var loaded = false
    @Published private(set) var isImporting = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published var receipt: String?

    let athleteID: Int
    private let store: AthleteTrainingProfileStore
    private let repository: ProtectedTrainingRepository
    private var importTask: Task<Void, Never>?
    private var sessionSubscription: AnyCancellable?

    init(athleteID: Int) {
        self.athleteID = athleteID
        draft = AthleteTrainingProfile(athleteID: athleteID)
        store = AthleteTrainingProfileStore()
        repository = ProtectedTrainingRepository(activeAthleteID: {
            UserSession.shared.isReady ? UserSession.shared.userId : nil
        })
        sessionSubscription = NotificationCenter.default.publisher(for: .trainingSessionInvalidated)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.invalidate() }
            }
    }

    func load() {
        guard !loaded else { return }
        do {
            let saved = try store.load(athleteID: athleteID)
            let evidence = try repository.currentObservations(athleteID: athleteID)
            var profile = saved ?? AthleteTrainingProfile(athleteID: athleteID)
            profile.migrateLegacyGoalsToOutcomes()
            profile.migrateStrengthRecommendations()
            for day in 1...7 where !profile.availability.contains(where: { $0.weekday == day }) {
                profile.availability.append(TrainingDayAvailability(weekday: day, availableMinutes: 0))
            }
            profile.availability.sort { $0.weekday < $1.weekday }
            draft = profile
            observations = evidence
            loaded = true
            errorMessage = nil
            Task { [weak self] in
                guard let self else { return }
                do {
                    if let reconciled = try await store.loadReconciled(athleteID: athleteID) {
                        draft = reconciled
                    }
                    if case .unsynced(let message) = store.syncState {
                        errorMessage = "Using your protected profile while cloud sync retries. \(message)"
                    }
                } catch is CancellationError {
                } catch {
                    errorMessage = "Could not refresh your training profile. Your protected copy is still available. \(error.localizedDescription)"
                }
            }
        } catch {
            errorMessage = "Could not open training data. Existing files were preserved. \(error.localizedDescription)"
        }
    }

    func save() {
        guard loaded, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        receipt = nil
        Task { [weak self] in
            guard let self else { return }
            defer { isSaving = false }
            do {
                draft = try await store.saveAndSync(draft, athleteID: athleteID)
                receipt = "Training profile saved securely and synced."
            } catch {
                errorMessage = "Your changes are protected on this phone but have not synced yet. \(error.localizedDescription)"
            }
        }
    }

    func setStrengthSuggestionsEnabled(_ enabled: Bool) {
        var preferences = draft.resolvedStrengthRecommendations
        preferences.suggestionsEnabled = enabled
        draft.strengthRecommendations = preferences
    }

    func setStrengthZone(_ zone: StrengthZone, available: Bool) {
        var preferences = draft.resolvedStrengthRecommendations
        if available {
            preferences.availableZones.insert(zone)
        } else {
            preferences.availableZones.remove(zone)
        }
        draft.strengthRecommendations = preferences
    }

    func importRuns(_ activities: [Activity]) {
        guard loaded, !isImporting else { return }
        isImporting = true
        errorMessage = nil
        receipt = nil
        importTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isImporting = false }
            do {
                let report = try await TrainingEvidenceImportService.importRuns(activities,
                    athleteID: athleteID, repository: repository)
                try Task.checkCancellation()
                observations = try repository.currentObservations(athleteID: athleteID)
                receipt = report.summary
            } catch is CancellationError {
                // The account lifecycle clears presentation; already written records stay with their owner.
            } catch {
                errorMessage = "Import stopped. Runs already saved are safe; retry will not duplicate them. \(error.localizedDescription)"
            }
        }
    }

    func sessionPreview() throws -> TrainingSessionPreviewSnapshot {
        guard loaded, !isImporting else { throw PreviewError.dataNotReady }
        guard let saved = try store.load(athleteID: athleteID) else { throw PreviewError.saveFirst }
        guard draft == saved else { throw PreviewError.saveFirst }
        let now = Date()
        let inputs = try TrainingDecisionInputBuilder.build(profile: saved,
            history: repository.observations(athleteID: athleteID), athleteID: athleteID,
            now: now, timeZone: .current, sessionResults: repository.sessionResults(athleteID: athleteID))
        return TrainingSessionPreviewSnapshot(generatedAt: now, fingerprint: inputs.fingerprint,
            policyVersion: GoalDrivenTrainingEngine.version, goals: saved.goals,
            observations: inputs.observations, sessions: GoalDrivenTrainingEngine.previews(for: inputs), completeStrengthSessions: CompleteStrengthSessionPolicy.previews(for: inputs), athleteID: athleteID,
            sessionResults: inputs.sessionResults, availability: saved.availability,
            protectedStorageRevision: try ProtectedTrainingSnapshotRevision.capture(athleteID: athleteID))
    }

    enum PreviewError: LocalizedError {
        case dataNotReady, saveFirst
        var errorDescription: String? {
            switch self {
            case .dataNotReady: return "Wait for your training data to finish opening or importing, then try again."
            case .saveFirst: return "Save your profile before previewing sessions. Your current edits have not been discarded."
            }
        }
    }

    func record(_ observation: TrainingObservation) throws {
        guard loaded else { throw ProtectedTrainingRepository.RepositoryError.ownershipMismatch }
        try repository.append(observation, athleteID: athleteID)
        observations = try repository.currentObservations(athleteID: athleteID)
        receipt = "Actual set recorded. This records performance, not an entire workout completion."
    }

    private func invalidate() {
        importTask?.cancel()
        importTask = nil
        draft = AthleteTrainingProfile(athleteID: athleteID)
        observations = []
        loaded = false
        isImporting = false
        isSaving = false
        errorMessage = nil
        receipt = nil
        store.clearSession()
    }
}
