import Combine
import Foundation

extension Notification.Name {
    static let trainingSessionInvalidated = Notification.Name("Runaway.trainingSessionInvalidated")
}

@MainActor
protocol AthleteTrainingProfilePersisting {
    func load(athleteID: Int) throws -> AthleteTrainingProfile?
    func save(_ profile: AthleteTrainingProfile, athleteID: Int) throws
    func clearSession()
}

/// Local-only profile facade. Sensitive records live in protected files, not preferences.
@MainActor
final class AthleteTrainingProfileStore: ObservableObject, AthleteTrainingProfilePersisting {
    @Published private var storedProfile: AthleteTrainingProfile?
    @Published private(set) var accountID: Int?

    var profile: AthleteTrainingProfile? {
        guard let accountID, activeAthleteID() == accountID else { return nil }
        return storedProfile
    }

    private let repository: ProtectedTrainingRepository
    private let legacyDefaults: UserDefaults
    private let activeAthleteID: @MainActor () -> Int?
    private var sessionSubscription: AnyCancellable?

    init(defaults: UserDefaults = .standard, root: URL? = nil,
         activeAthleteID: @escaping @MainActor () -> Int? = {
             UserSession.shared.isReady ? UserSession.shared.userId : nil
         }) {
        self.legacyDefaults = defaults
        self.activeAthleteID = activeAthleteID
        self.repository = ProtectedTrainingRepository(root: root, activeAthleteID: activeAthleteID)
        // UserSession emits synchronously from the main actor before replacing identity.
        sessionSubscription = NotificationCenter.default.publisher(for: .trainingSessionInvalidated)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.clearSession() }
            }
    }

    func load(athleteID: Int) throws -> AthleteTrainingProfile? {
        try requireOwner(athleteID)
        storedProfile = nil
        accountID = athleteID
        let loaded = try repository.loadProfile(athleteID: athleteID)
        storedProfile = loaded
        return loaded
    }

    func save(_ profile: AthleteTrainingProfile, athleteID: Int) throws {
        try requireOwner(athleteID)
        guard profile.athleteID == athleteID else { throw StoreError.ownershipMismatch }
        let issues = profile.validationIssues()
        guard issues.isEmpty else { throw StoreError.invalidProfile(issues) }
        var saved = profile
        saved.revision = UUID()
        saved.updatedAt = Date()
        try repository.saveProfile(saved, athleteID: athleteID)
        accountID = athleteID
        storedProfile = saved
    }

    /// Explicit, owner-checked migration of this feature's previous v2 preference blob.
    /// Unowned trainingProfile.v1 preferences are deliberately not imported here.
    func importLegacyProfile(athleteID: Int, confirmed: Bool) throws {
        try requireOwner(athleteID)
        guard confirmed else { throw StoreError.confirmationRequired }
        guard try repository.loadProfile(athleteID: athleteID) == nil else { throw StoreError.profileAlreadyExists }
        let key = "athleteTrainingProfile.v2.\(athleteID)"
        guard let data = legacyDefaults.data(forKey: key) else { return }
        let decoded: AthleteTrainingProfile
        do { decoded = try JSONDecoder().decode(AthleteTrainingProfile.self, from: data) }
        catch { throw StoreError.unreadableProfile }
        try save(decoded, athleteID: athleteID)
        legacyDefaults.removeObject(forKey: key)
    }

    func clearSession() {
        storedProfile = nil
        accountID = nil
    }

    private func requireOwner(_ athleteID: Int) throws {
        guard athleteID > 0, activeAthleteID() == athleteID else {
            clearSession()
            throw StoreError.ownershipMismatch
        }
        if accountID != athleteID { clearSession() }
    }

    enum StoreError: LocalizedError {
        case ownershipMismatch, unreadableProfile, confirmationRequired, profileAlreadyExists
        case invalidProfile([TrainingProfileIssue])

        var errorDescription: String? {
            switch self {
            case .ownershipMismatch: return "Sign in to the account that owns this training profile."
            case .unreadableProfile: return "This training profile could not be read. Its saved data has been preserved."
            case .confirmationRequired: return "Confirm that you want to import the existing profile for this account."
            case .profileAlreadyExists: return "A protected profile already exists. Import will not overwrite it."
            case .invalidProfile(let issues): return issues.map(\.message).joined(separator: "\n")
            }
        }
    }
}
