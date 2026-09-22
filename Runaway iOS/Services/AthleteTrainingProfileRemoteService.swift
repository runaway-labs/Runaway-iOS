import Foundation

struct ProfileSyncReceipt: Codable, Equatable {
    let changed: Bool
    let revision: UUID
    let inputFingerprint: String
    let updatedAt: Date
}

struct ProfileSyncRequest: Codable {
    let action: String
    let athleteID: Int
    let profile: AthleteTrainingProfile?
}

struct ProfileSyncResponse: Codable {
    let profile: AthleteTrainingProfile?
    let receipt: ProfileSyncReceipt?
}

@MainActor
protocol AthleteTrainingProfileRemotePersisting {
    func save(_ profile: AthleteTrainingProfile, activeAthleteID: Int) async throws -> ProfileSyncReceipt
    func fetch(activeAthleteID: Int) async throws -> AthleteTrainingProfile?
}

@MainActor
final class AthleteTrainingProfileRemoteService: AthleteTrainingProfileRemotePersisting {
    typealias Transport = (ProfileSyncRequest) async throws -> ProfileSyncResponse
    private let transport: Transport

    init(client: AuthenticatedEdgeFunctionClient = .live) {
        transport = { request in
            try await client.invoke("athlete-training-profile", body: request)
        }
    }

    init(transport: @escaping Transport) { self.transport = transport }

    func save(_ profile: AthleteTrainingProfile, activeAthleteID: Int) async throws -> ProfileSyncReceipt {
        guard profile.athleteID == activeAthleteID else { throw RemoteError.ownershipMismatch }
        let response = try await transport(ProfileSyncRequest(action: "save", athleteID: activeAthleteID, profile: profile))
        guard let receipt = response.receipt else { throw RemoteError.invalidResponse }
        return receipt
    }

    func fetch(activeAthleteID: Int) async throws -> AthleteTrainingProfile? {
        try await fetch(activeAthleteID: activeAthleteID, localProfile: nil)
    }

    func fetch(activeAthleteID: Int, localProfile: AthleteTrainingProfile?) async throws -> AthleteTrainingProfile? {
        let response = try await transport(ProfileSyncRequest(action: "fetch", athleteID: activeAthleteID, profile: nil))
        guard let remote = response.profile else { return localProfile }
        guard remote.athleteID == activeAthleteID else { throw RemoteError.ownershipMismatch }
        guard let localProfile else { return remote }
        return remote.updatedAt > localProfile.updatedAt ? remote : localProfile
    }

    enum RemoteError: LocalizedError {
        case ownershipMismatch, invalidResponse
        var errorDescription: String? {
            switch self {
            case .ownershipMismatch: return "The profile does not belong to the signed-in athlete."
            case .invalidResponse: return "The server did not confirm the profile sync."
            }
        }
    }
}
