//
//  GarminService.swift
//  Runaway iOS
//
//  Service for Garmin Connect integration
//

import Foundation
import Combine

@MainActor
class GarminService: ObservableObject {
    static let shared = GarminService()

    // MARK: - Published Properties
    @Published var isConnected: Bool = false
    @Published var isConnecting: Bool = false
    @Published var connectionError: String?
    @Published var lastSyncDate: Date?

    // MARK: - Private Properties
    private let supabaseURL = "https://nkxvjcdxiyjbndjvfmqy.supabase.co"
    private let edgeClient: AuthenticatedEdgeFunctionClient

    // MARK: - Initialization
    init(edgeClient: AuthenticatedEdgeFunctionClient = .live, checksConnectionOnInit: Bool = true) {
        self.edgeClient = edgeClient
        // Check connection status on init
        if checksConnectionOnInit {
            Task {
                await checkConnectionStatus()
            }
        }
    }

    // MARK: - Public Methods

    /// Check if user has connected Garmin
    func checkConnectionStatus() async {
        do {
            let session = try await supabase.auth.session
            let authUserId = session.user.id.uuidString

            // Check athletes table for garmin_connected flag
            let response: [GarminConnectionStatus] = try await supabase
                .from("athletes")
                .select("garmin_connected, garmin_connected_at")
                .eq("auth_user_id", value: authUserId)
                .execute()
                .value

            if let athlete = response.first {
                isConnected = athlete.garmin_connected ?? false
                if let connectedAt = athlete.garmin_connected_at {
                    lastSyncDate = ISO8601DateFormatter().date(from: connectedAt)
                }
            }
        } catch {
            #if DEBUG
            print("❌ GarminService: Failed to check connection status: \(error)")
            #endif
        }
    }

    /// Get the Garmin OAuth authorization URL
    func getGarminConnectURL(authUserId _: String) async -> URL? {
        isConnecting = true
        connectionError = nil

        defer { isConnecting = false }

        do {
            // Call our edge function to initiate OAuth
            let response: OAuthInitiationResponse = try await edgeClient.invoke(
                "garmin-auth",
                body: OAuthInitiationRequest()
            )

            guard response.success,
                  let url = response.authorizationURL else {
                connectionError = response.error ?? "Failed to get authorization URL"
                return nil
            }

            #if DEBUG
            print("✅ GarminService: Got authorization URL")
            #endif

            return url

        } catch {
            #if DEBUG
            print("❌ GarminService: Failed to initiate OAuth: \(error)")
            #endif
            connectionError = error.localizedDescription
            return nil
        }
    }

    /// Disconnect from Garmin
    func disconnectGarmin(authUserId: String) async throws {
        // Update athletes table to clear Garmin connection
        let updates = GarminDisconnectUpdate(
            garmin_connected: false,
            garmin_access_token: nil,
            garmin_token_secret: nil,
            garmin_connected_at: nil
        )

        try await supabase
            .from("athletes")
            .update(updates)
            .eq("auth_user_id", value: authUserId)
            .execute()

        isConnected = false
        lastSyncDate = nil

        #if DEBUG
        print("✅ GarminService: Disconnected from Garmin")
        #endif
    }

    /// Handle OAuth callback (called when app receives deep link)
    func handleOAuthCallback(success: Bool) {
        if success {
            isConnected = true
            lastSyncDate = Date()
            connectionError = nil

            #if DEBUG
            print("✅ GarminService: OAuth callback successful")
            #endif
        } else {
            connectionError = "Authorization was denied or failed"

            #if DEBUG
            print("❌ GarminService: OAuth callback failed")
            #endif
        }
    }
}

// MARK: - Helper Models
private struct GarminConnectionStatus: Decodable {
    let garmin_connected: Bool?
    let garmin_connected_at: String?
}

private struct GarminDisconnectUpdate: Encodable {
    let garmin_connected: Bool
    let garmin_access_token: String?
    let garmin_token_secret: String?
    let garmin_connected_at: String?
}

private struct GarminHealthRefreshRequest: Encodable {}

private struct GarminHealthRefreshResponse: Decodable {
    let success: Bool
}

extension GarminService {
    func refreshHealthHistory() async {
        do {
            let _: GarminHealthRefreshResponse = try await edgeClient.invoke(
                "garmin-stats",
                body: GarminHealthRefreshRequest()
            )
        } catch {
            // Refresh is opportunistic. Existing HealthKit and cached Garmin data remain available.
            print("Garmin health refresh deferred: \(error.localizedDescription)")
        }
    }
}
