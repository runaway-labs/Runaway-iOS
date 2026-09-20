import Foundation
import Observation
import OSLog
import Supabase
import UIKit
import UserNotifications

struct CoachNotificationRoute: Equatable, Identifiable {
    enum Category: String { case automatic, approval }
    let decisionID: UUID
    let athleteID: Int
    let expectedRevision: String
    let category: Category
    var id: UUID { decisionID }

    init?(userInfo: [AnyHashable: Any]) {
        guard let rawID = userInfo["coach_decision_id"] as? String,
              let decisionID = UUID(uuidString: rawID),
              let expectedRevision = userInfo["expected_revision"] as? String,
              !expectedRevision.isEmpty,
              let categoryRaw = userInfo["coach_category"] as? String,
              let category = Category(rawValue: categoryRaw) else { return nil }
        let athleteID = (userInfo["athlete_id"] as? Int)
            ?? (userInfo["athlete_id"] as? String).flatMap(Int.init)
        guard let athleteID, athleteID > 0 else { return nil }
        self.decisionID = decisionID
        self.athleteID = athleteID
        self.expectedRevision = expectedRevision
        self.category = category
    }
}

struct CoachNotificationCommand: Equatable {
    let route: CoachNotificationRoute
    let actionIdentifier: String
}

@MainActor
@Observable
final class PushNotificationService {
    enum RegistrationStatus: Equatable {
        case waiting, registering, registered, failed
    }

    static let shared = PushNotificationService(
        athleteID: { UserSession.shared.userId },
        upload: { token, athleteID in
            // A zero-row RLS update must not be mistaken for successful registration.
            struct SavedAthlete: Decodable { let id: Int }
            let _: SavedAthlete = try await supabase.from("athletes")
                .update(["apns_token": token])
                .eq("id", value: athleteID)
                .select("id").single().execute().value
            try await WorkoutPromptService.shared.register(token: token, athleteID: athleteID)
        }
    )

    private(set) var registrationStatus: RegistrationStatus = .waiting
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var pendingActivityID: Int?
    private(set) var pendingWorkoutRoute: WorkoutPromptRoute?
    private(set) var pendingCoachRoute: CoachNotificationRoute?
    private(set) var coachCommandRevision = 0
    @ObservationIgnored private var pendingCoachCommands: [CoachNotificationCommand] = []
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var registrationTask: Task<Void, Never>?
    @ObservationIgnored private var isSynchronizing = false
    @ObservationIgnored private var isSigningOut = false
    @ObservationIgnored private let athleteID: () -> Int?
    @ObservationIgnored private let upload: (String, Int) async throws -> Void
    @ObservationIgnored private let pause: (Int) async throws -> Void
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Runaway", category: "PushNotifications")

    init(
        athleteID: @escaping () -> Int?,
        upload: @escaping (String, Int) async throws -> Void,
        pause: @escaping (Int) async throws -> Void = { attempt in
            try await Task.sleep(for: .seconds(attempt == 0 ? 1 : 3))
        }
    ) {
        self.athleteID = athleteID
        self.upload = upload
        self.pause = pause
    }

    var settingsSummary: String {
        if authorizationStatus == .denied { return "Notifications off in iPhone Settings" }
        if authorizationStatus == .notDetermined { return "Choose whether to allow notifications" }
        switch registrationStatus {
        case .registered: return "Device registered - manage notification permissions"
        case .registering: return "Connecting this device for notifications"
        case .failed: return "Connection failed - retrying when you reopen the app"
        case .waiting: return "Waiting to register this device"
        }
    }

    func activate() async {
        let center = UNUserNotificationCenter.current()
        registerCoachCategories(center: center)
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            do { _ = try await center.requestAuthorization(options: [.alert, .badge, .sound]) }
            catch { logger.error("Notification permission request failed: \(error.localizedDescription, privacy: .public)") }
            settings = await center.notificationSettings()
        }
        authorizationStatus = settings.authorizationStatus
        UIApplication.shared.registerForRemoteNotifications()
        scheduleSynchronization()
    }

    func receiveToken(_ token: String) {
        guard !token.isEmpty else { return }
        self.token = token
    }

    func registrationFailed(_ error: Error) {
        registrationStatus = .failed
        logger.error("APNs device registration failed: \(error.localizedDescription, privacy: .public)")
    }

    func scheduleSynchronization() {
        guard registrationTask == nil, !isSigningOut else { return }
        registrationTask = Task {
            let startingToken = token
            let startingAthlete = athleteID()
            await synchronize()
            registrationTask = nil
            if !isSigningOut, startingToken != token || startingAthlete != athleteID() {
                scheduleSynchronization()
            }
        }
    }

    func synchronize() async {
        guard !isSigningOut, !isSynchronizing else { return }
        guard let token, let id = athleteID() else {
            registrationStatus = .waiting
            return
        }
        isSynchronizing = true
        defer { isSynchronizing = false }
        registrationStatus = .registering
        for attempt in 0..<3 {
            guard !Task.isCancelled, !isSigningOut, self.token == token, athleteID() == id else {
                registrationStatus = .waiting
                return
            }
            do {
                try await upload(token, id)
                guard self.token == token, athleteID() == id, !isSigningOut else {
                    registrationStatus = .waiting
                    return
                }
                registrationStatus = .registered
                logger.info("Push device registration saved")
                return
            } catch {
                registrationStatus = .failed
                logger.error("Push token save failed: \(error.localizedDescription, privacy: .public)")
                guard attempt < 2 else { return }
                do { try await pause(attempt) } catch { return }
            }
        }
    }

    func receiveNotification(_ userInfo: [AnyHashable: Any]) {
        if let route = CoachNotificationRoute(userInfo: userInfo) {
            pendingCoachRoute = route
            pendingWorkoutRoute = nil
            pendingActivityID = nil
            return
        }
        if let route = WorkoutPromptRoute(userInfo: userInfo) {
            pendingWorkoutRoute = route
            pendingActivityID = nil
            return
        }
        let id: Int?
        if let string = userInfo["activity_id"] as? String { id = Int(string) }
        else { id = userInfo["activity_id"] as? Int }
        guard let id, id > 0 else { return }
        pendingActivityID = id
        pendingWorkoutRoute = nil
    }

    func takePendingCoachRoute() -> CoachNotificationRoute? {
        guard let athlete = athleteID(), let route = pendingCoachRoute else { return nil }
        pendingCoachRoute = nil
        return route.athleteID == athlete ? route : nil
    }

    func enqueueCoachAction(_ userInfo: [AnyHashable: Any], actionIdentifier: String) {
        guard let route = CoachNotificationRoute(userInfo: userInfo) else { return }
        let command = CoachNotificationCommand(route: route, actionIdentifier: actionIdentifier)
        guard !pendingCoachCommands.contains(command) else { return }
        pendingCoachCommands.append(command)
        coachCommandRevision &+= 1
    }

    func takePendingCoachCommands() -> [CoachNotificationCommand] {
        guard let athlete = athleteID() else { return [] }
        let owned = pendingCoachCommands.filter { $0.route.athleteID == athlete }
        pendingCoachCommands.removeAll { $0.route.athleteID == athlete }
        return owned
    }

    private func registerCoachCategories(center: UNUserNotificationCenter) {
        let review = UNNotificationAction(identifier: "RUNAWAY_COACH_REVIEW", title: "Review")
        let undo = UNNotificationAction(identifier: "RUNAWAY_COACH_UNDO", title: "Undo")
        let accept = UNNotificationAction(identifier: "RUNAWAY_COACH_ACCEPT", title: "Accept")
        let keep = UNNotificationAction(identifier: "RUNAWAY_COACH_KEEP", title: "Keep Original")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "RUNAWAY_COACH_AUTOMATIC", actions: [review, undo], intentIdentifiers: []),
            UNNotificationCategory(identifier: "RUNAWAY_COACH_APPROVAL", actions: [review, accept, keep], intentIdentifiers: [])
        ])
    }

    func takePendingWorkoutRoute() -> WorkoutPromptRoute? {
        guard let athlete = athleteID() else { return nil }
        defer { pendingWorkoutRoute = nil }
        guard pendingWorkoutRoute?.athleteID == athlete else { return nil }
        return pendingWorkoutRoute
    }

    func takePendingActivityID() -> Int? {
        guard athleteID() != nil else { return nil }
        defer { pendingActivityID = nil }
        return pendingActivityID
    }

    func unregisterCurrentDevice() async throws {
        isSigningOut = true
        registrationTask?.cancel()
        await registrationTask?.value
        do {
            if let token, let id = athleteID() {
                try await WorkoutPromptService.shared.unregister(token: token, athleteID: id)
                // Do not clear a token subsequently registered by another device.
                try await supabase.from("athletes")
                    .update(["apns_token": Optional<String>.none])
                    .eq("id", value: id).eq("apns_token", value: token).execute()
            }
            pendingActivityID = nil
            pendingWorkoutRoute = nil
            pendingCoachRoute = nil
            pendingCoachCommands = []
            WorkoutPromptService.shared.reset()
            registrationStatus = .waiting
        } catch {
            isSigningOut = false
            throw error
        }
    }

    func resumeRegistration() {
        isSigningOut = false
        scheduleSynchronization()
    }
}
