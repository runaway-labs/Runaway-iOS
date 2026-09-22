//
//  Runaway_iOSApp.swift
//  Runaway iOS
//

import SwiftUI
import SwiftData
import Foundation
import AppIntents
import HealthKit

@main
struct Runaway_iOSApp: App {
    @State private var isPresentingPasswordRecovery = false
    @State private var userSession = UserSession.shared
    @State private var realtimeService = RealtimeService.shared
    @State private var dataManager = DataManager.shared
    @StateObject private var stravaService = StravaService()
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var syncEngine = SyncEngine.shared
    @StateObject private var trainingProfileStore = TrainingProfileStore.shared
    @StateObject private var celebrationService = CelebrationService.shared
    @State private var router = AppRouter()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        Self.configureAppearance(isDark: ThemeManager.shared.isDarkMode)
    }

    static func configureAppearance(isDark: Bool) {
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()

        // Always use dark nav bar (Copilot-style: dark regardless of system mode)
        navAppearance.backgroundColor = UIColor(AppTheme.Colors.DarkMode.background)
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]

        navAppearance.buttonAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(AppTheme.Colors.accent)
        ]

        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().tintColor = UIColor(AppTheme.Colors.accent)

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()

        let selectedColor = UIColor(AppTheme.Colors.warmAmber)
        // Always dark tab bar (Copilot-style)
        tabBarAppearance.backgroundColor = UIColor(AppTheme.Colors.DarkMode.background)
        let normalColor = UIColor(AppTheme.Colors.DarkMode.textTertiary)

        tabBarAppearance.stackedLayoutAppearance.normal.iconColor = normalColor
        tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
        tabBarAppearance.stackedLayoutAppearance.selected.iconColor = selectedColor
        tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]
        tabBarAppearance.inlineLayoutAppearance.normal.iconColor = normalColor
        tabBarAppearance.inlineLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
        tabBarAppearance.inlineLayoutAppearance.selected.iconColor = selectedColor
        tabBarAppearance.inlineLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]

        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        UITabBar.appearance().tintColor = selectedColor
        UITabBar.appearance().unselectedItemTintColor = normalColor
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(themeManager.isDarkMode ? .dark : .light)
                .environment(userSession)
                .environment(realtimeService)
                .environment(dataManager)
                .environmentObject(themeManager)
                .environmentObject(syncEngine)
                .environmentObject(trainingProfileStore)
                .environment(router)
                .modelContainer(PersistenceController.shared.container)
                .celebrationOverlay(
                    isPresented: $celebrationService.isShowingCelebration,
                    intensity: celebrationService.currentIntensity,
                    message: "Workout complete. You moved the plan forward."
                )
                .onChange(of: themeManager.currentTheme) { _, newTheme in
                    Self.configureAppearance(isDark: newTheme == .dark)
                }
                .onAppear {
                    LocationManager.shared.requestLocationPermission()
                    requestPendingWidgetCommitmentDrain()
                }
                .onChange(of: userSession.isReady) { previousReady, newReady in
                    if WidgetPendingActionDrainCoordinator.shouldDrain(
                        previousReady: previousReady,
                        newReady: newReady
                    ) {
                        requestPendingWidgetCommitmentDrain()
                    }
                    if newReady {
                        Task { await GarminService.shared.refreshHealthHistory() }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    handleAppBecameActive()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    handleAppEnteredBackground()
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                    router.handleDeepLink(url)
                }
                .fullScreenCover(isPresented: $isPresentingPasswordRecovery) {
                    ResetPasswordView {
                        isPresentingPasswordRecovery = false
                    }
                }
        }
    }

    // MARK: - Deep Link Handling

    private func handleDeepLink(_ url: URL) {
        // Supabase auth callback
        if url.scheme == "runaway" && url.host == "auth" {
            let isPasswordRecovery = PasswordRecoveryLink.shouldPresentReset(
                for: url,
                hasPendingRequest: PasswordRecoveryRequest.hasRecentRequest()
            )
            Task {
                do {
                    _ = try await supabase.auth.session(from: url)
                    await MainActor.run {
                        if isPasswordRecovery {
                            PasswordRecoveryRequest.clear()
                            isPresentingPasswordRecovery = true
                        } else {
                            NotificationCenter.default.post(name: NSNotification.Name("EmailVerificationCompleted"), object: nil)
                        }
                    }
                } catch {
                    await MainActor.run {
                        if isPasswordRecovery {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("PasswordRecoveryFailed"),
                                object: nil,
                                userInfo: ["error": error.localizedDescription]
                            )
                        } else {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("EmailVerificationFailed"),
                                object: nil,
                                userInfo: ["error": error.localizedDescription]
                            )
                        }
                    }
                }
            }
            return
        }

        // Strava OAuth callback
        if url.scheme == "runaway" && url.host == "strava-connected" {
            Task { await stravaService.handleStravaCallback(url: url) }
        }

        // Garmin OAuth callback
        if url.scheme == "runaway" && url.host == "garmin-connected" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let success = components?.queryItems?.first(where: { $0.name == "success" })?.value == "true"
            Task { await MainActor.run { GarminService.shared.handleOAuthCallback(success: success) } }
        }
    }

    // MARK: - App Lifecycle

    private func handleAppBecameActive() {
        Task { await CommitmentManager.shared.refresh() }
        if userSession.isReady {
            Task { await GarminService.shared.refreshHealthHistory() }
        }
        requestPendingWidgetCommitmentDrain()
        realtimeService.startRealtimeSubscription()
        realtimeService.resumeFromBackground()
        syncEngine.startBackgroundSync()
        Task { await syncEngine.syncPendingChanges() }
        LocationManager.shared.requestLocationPermission()
        AnalyticsService.shared.resumeFromBackground()

        if HealthKitManager.shared.isHealthKitAvailable {
            Task {
                _ = await HealthKitManager.shared.requestAuthorization()
                await BiometricService.shared.syncHealthData()
            }
        }

        Task {
            if let athleteId = UserSession.shared.userId {
                await RestDayService.shared.runDetectionIfNeeded(athleteId: athleteId)
            }
        }

        AnalyticsService.shared.startSession()
        AnalyticsService.shared.track(.appOpened, category: .engagement)
    }

    private func handleAppEnteredBackground() {
        LocationManager.shared.stopLocationUpdates()
        realtimeService.pauseForBackground()
        syncEngine.stopBackgroundSync()
        AnalyticsService.shared.pauseForBackground()
        AnalyticsService.shared.track(.appBackgrounded, category: .engagement)
        AnalyticsService.shared.endSession()
    }

    @MainActor
    private func requestPendingWidgetCommitmentDrain() {
        WidgetPendingActionDrainCoordinator.shared.requestDrain {
            await applyPendingWidgetCommitment()
            applyPendingPerformanceCoachIntent()
        }
    }

    @MainActor
    private func applyPendingPerformanceCoachIntent() {
        guard userSession.isReady,
              let athleteID = userSession.userId,
              let defaults = UserDefaults(suiteName: AppConstants.AppGroup.identifier),
              let request = PerformanceCoachIntentRequest.cached(in: defaults) else { return }
        guard request.isCurrent, request.athleteID == athleteID else {
            PerformanceCoachIntentRequest.clear(in: defaults)
            return
        }

        switch request.action {
        case .commitRecommendation:
            guard let fingerprint = request.prescriptionFingerprint else {
                PerformanceCoachIntentRequest.clear(in: defaults)
                router.navigate(to: .commitmentSetup)
                return
            }
            do {
                try dataManager.commitPublishedRecommendation(prescriptionFingerprint: fingerprint)
                PerformanceCoachIntentRequest.clear(in: defaults)
            } catch {
                PerformanceCoachIntentRequest.clear(in: defaults)
                router.navigate(to: .commitmentSetup)
            }
        case .reviewOptions, .viewCommittedWorkout:
            PerformanceCoachIntentRequest.clear(in: defaults)
            router.navigate(to: .commitmentSetup)
        }
    }

    @MainActor
    private func applyPendingWidgetCommitment() async {
        guard userSession.isReady,
              let defaults = UserDefaults(suiteName: AppConstants.AppGroup.identifier),
              let athleteId = userSession.userId else { return }

        guard let pendingStore = try? PendingWidgetCommitmentStore(
                  defaults: defaults,
                  role: .appDrain
              ),
              let pendingActions = try? pendingStore.pendingActions() else { return }

        for pendingAction in pendingActions {
            guard let activityType = CommitmentActivityType(rawValue: pendingAction.activityType) else {
                continue
            }

            let manager = CommitmentManager.shared
            let loadResult = await manager.loadTodaysCommitment(for: athleteId)
            let decision = WidgetCommitmentPendingDecision.decide(from: loadResult)
            guard decision != .retainPending else { return }

            do {
                if decision == .create {
                    try await manager.createCommitment(activityType)
                } else {
                    try await manager.updateCommitment(to: activityType)
                }
                _ = try pendingStore.deleteExact(pendingAction)
            } catch {
                // Retain this exact file and all remaining actions for retry.
                return
            }
        }
    }
}
