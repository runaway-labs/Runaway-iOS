import SwiftUI
import Foundation
import Supabase
import WidgetKit
import Observation

/// Unified user session manager combining authentication and profile management
@MainActor
@Observable
public final class UserSession {
    // MARK: - Observable Properties

    /// Authentication state
    public var isAuthenticated = false

    /// Checking authentication state (for initial load)
    public var isCheckingAuth = true

    /// Supabase authentication user
    public var currentUser: Supabase.User?

    /// User profile from custom User model
    public var profileUser: User?

    /// Onboarding completion state
    public var hasCompletedOnboarding = true

    /// Loading onboarding state
    public var isCheckingOnboarding = false

    /// A user-safe error when authenticated account setup could not finish.
    public private(set) var setupError: String?

    /// Flag to prevent re-checking onboarding after user completes it in this session
    private var onboardingCompletedInSession = false

    /// Stored athlete ID from ensureAthleteExists (used before profile is loaded)
    private var storedAthleteId: Int?

    // MARK: - Singleton

    public static let shared = UserSession(startAutomatically: true)

    // MARK: - Computed Properties

    /// Convenience accessor for user ID from profile or stored athlete ID
    public var userId: Int? {
        return profileUser?.userId ?? storedAthleteId
    }

    /// User's email from authentication
    public var email: String? {
        return currentUser?.email
    }

    /// Authentication alone is not enough to enter the app's data surfaces.
    public var isReady: Bool {
        isAuthenticated && userId != nil && setupError == nil
    }

    // MARK: - Initialization

    init(startAutomatically: Bool) {
        #if DEBUG
        print("UserSession initialized")
        #endif
        if startAutomatically {
            Task {
                await checkAuthState()
                await listenForAuthChanges()
            }
        }
    }

    // MARK: - Authentication State Management

    private func checkAuthState() async {
        do {
            let session = try await supabase.auth.session
            #if DEBUG
            print("✅ Found existing session for user: \(session.user.email ?? "unknown")")
            #endif
            await updateAuthState(with: session.user)
        } catch {
            #if DEBUG
            print("⚠️ No existing session found: \(error.localizedDescription)")
            #endif
            await MainActor.run {
                self.isAuthenticated = false
            }
        }

        // Mark auth check as complete
        await MainActor.run {
            self.isCheckingAuth = false
        }
    }

    private func listenForAuthChanges() async {
        for await (event, session) in supabase.auth.authStateChanges {
            await handleAuthStateChange(event: event, session: session)
        }
    }

    private func handleAuthStateChange(event: AuthChangeEvent, session: Session?) async {
        switch event {
        case .signedIn:
            if let user = session?.user {
                await updateAuthState(with: user)
            }
        case .signedOut:
            await clearSession()
            // Refresh widgets after sign out
            WidgetSyncService.refreshForAuthUpdate()
        case .tokenRefreshed:
            if let user = session?.user {
                await updateAuthState(with: user)
            }
        default:
            break
        }
    }

    private func updateAuthState(with user: Supabase.User) async {
        if currentUser?.id != user.id {
            NotificationCenter.default.post(name: .trainingSessionInvalidated, object: nil)
            profileUser = nil
            storedAthleteId = nil
        }
        #if DEBUG
        print("🔐 UserSession: Updating auth state for user \(user.email ?? "unknown")")
        #endif

        await MainActor.run {
            self.currentUser = user
            self.isAuthenticated = true
            self.setupError = nil
            self.storedAthleteId = nil
            self.isCheckingOnboarding = true // Start checking onboarding
        }

        #if DEBUG
        print("🔐 UserSession: isAuthenticated=true, isCheckingOnboarding=true")
        #endif

        // Refresh widgets after authentication state update
        WidgetSyncService.refreshForAuthUpdate()

        await prepareAthleteSession(for: user)

        #if DEBUG
        print("🔐 UserSession: Final state - hasCompletedOnboarding=\(hasCompletedOnboarding), isCheckingOnboarding=\(isCheckingOnboarding)")
        #endif
    }

    private func prepareAthleteSession(for user: Supabase.User) async {
        do {
            let athleteId = try await AthleteService.ensureAthleteExists(
                authId: user.id,
                email: user.email
            )
            #if DEBUG
            print("✅ UserSession: Athlete record confirmed with ID \(athleteId)")
            #endif
            completeAthleteSetup(with: .success(athleteId))
            PushNotificationService.shared.resumeRegistration()
            writeWidgetConfiguration(athleteId: athleteId)
            await checkOnboardingStatusForAthlete(athleteId: athleteId)
        } catch {
            #if DEBUG
            print("⚠️ UserSession: Failed to ensure athlete exists: \(error)")
            #endif
            completeAthleteSetup(with: .failure(error))
        }
    }

    func completeAthleteSetup(with result: Result<Int, Error>) {
        switch result {
        case .success(let athleteId) where athleteId > 0:
            storedAthleteId = athleteId
            setupError = nil
        case .success, .failure:
            storedAthleteId = nil
            hasCompletedOnboarding = false
            isCheckingOnboarding = false
            setupError = "We couldn't finish setting up your account. Please try again."
        }
    }

    public func retrySetup() async {
        guard let currentUser else { return }
        setupError = nil
        isCheckingOnboarding = true
        await prepareAthleteSession(for: currentUser)
    }

    /// Check onboarding status for a specific athlete ID
    private func checkOnboardingStatusForAthlete(athleteId: Int) async {
        #if DEBUG
        print("🔍 UserSession: Checking onboarding status for athlete \(athleteId)")
        #endif

        // Skip if user just completed onboarding in this session
        if onboardingCompletedInSession {
            #if DEBUG
            print("✅ UserSession: Skipping onboarding check - completed in this session")
            #endif
            await MainActor.run {
                self.hasCompletedOnboarding = true
                self.isCheckingOnboarding = false
            }
            return
        }

        do {
            let isCompleted = try await OnboardingService.checkOnboardingStatus(athleteId: athleteId)
            #if DEBUG
            print("✅ UserSession: OnboardingService returned isCompleted=\(isCompleted)")
            #endif
            await MainActor.run {
                self.hasCompletedOnboarding = isCompleted
                self.isCheckingOnboarding = false
                self.hasCheckedOnboarding = true
                if isCompleted {
                    self.onboardingCompletedInSession = true
                }
            }
            #if DEBUG
            print("✅ UserSession: Set hasCompletedOnboarding=\(isCompleted)")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ UserSession: Failed to check onboarding status: \(error)")
            print("⚠️ UserSession: Defaulting to hasCompletedOnboarding=false (show onboarding)")
            #endif
            await MainActor.run {
                // Default to NOT completed for new users - show onboarding
                self.hasCompletedOnboarding = false
                self.isCheckingOnboarding = false
            }
        }
    }

    // MARK: - Onboarding State Management

    /// Track if we've already checked onboarding status
    private var hasCheckedOnboarding = false

    /// Check if the current user has completed onboarding (called from setProfile)
    private func checkOnboardingStatus() async {
        // Skip if user just completed onboarding in this session
        if onboardingCompletedInSession {
            #if DEBUG
            print("✅ UserSession: Skipping onboarding check - completed in this session")
            #endif
            return
        }

        // Skip if we've already checked (prevents repeated checks from setProfile calls)
        if hasCheckedOnboarding {
            #if DEBUG
            print("✅ UserSession: Skipping onboarding check - already checked")
            #endif
            return
        }

        guard let athleteId = userId else {
            // No athlete ID yet - default to showing onboarding for new users
            #if DEBUG
            print("⚠️ UserSession: No athlete ID for onboarding check, defaulting to not completed")
            #endif
            await MainActor.run {
                self.hasCompletedOnboarding = false
            }
            return
        }

        await checkOnboardingStatusForAthlete(athleteId: athleteId)
    }

    /// Mark onboarding as completed (call after user finishes onboarding flow)
    public func markOnboardingCompleted() {
        self.onboardingCompletedInSession = true
        self.hasCompletedOnboarding = true
        self.isCheckingOnboarding = false
    }

    /// Refresh onboarding status (call when profile is set)
    public func refreshOnboardingStatus() async {
        await checkOnboardingStatus()
    }

    // MARK: - Profile Management

    /// Set the user profile
    public func setProfile(_ user: User) {
        self.profileUser = user

        // Check onboarding status now that we have the athlete ID
        Task {
            await checkOnboardingStatus()
        }
    }

    // MARK: - Widget Credential Sharing

    /// Share non-secret configuration with the widget. User access tokens are
    /// deliberately not persisted in App Group UserDefaults.
    private func writeWidgetConfiguration(athleteId: Int) {
        guard let defaults = UserDefaults(suiteName: AppConstants.AppGroup.identifier) else { return }
        defaults.set(athleteId, forKey: AppConstants.WidgetKeys.athleteId)
        if let url = SupabaseConfiguration.supabaseURL {
            defaults.set(url, forKey: AppConstants.WidgetKeys.supabaseURL)
        }
        if let key = SupabaseConfiguration.supabaseKey {
            defaults.set(key, forKey: AppConstants.WidgetKeys.supabaseKey)
        }
    }

    /// Clear both auth and profile data
    private func clearSession() async {
        NotificationCenter.default.post(name: .trainingSessionInvalidated, object: nil)
        await MainActor.run {
            self.currentUser = nil
            self.isAuthenticated = false
            self.profileUser = nil
            self.storedAthleteId = nil // Clear stored athlete ID
            self.setupError = nil
            self.hasCompletedOnboarding = true // Reset to default
            self.isCheckingOnboarding = false
            self.hasCheckedOnboarding = false // Reset so next login checks fresh
            self.onboardingCompletedInSession = false
        }
    }

    // MARK: - Authentication Methods

    func signUp(email: String, password: String) async throws {
        _ = try await supabase.auth.signUp(
            email: email,
            password: password
        )
        // Auth state will be updated automatically via listener
    }

    func signIn(email: String, password: String) async throws {
        _ = try await supabase.auth.signIn(
            email: email,
            password: password
        )
        // Auth state will be updated automatically via listener
    }

    func signOut() async throws {
        try await PushNotificationService.shared.unregisterCurrentDevice()
        do {
            try await supabase.auth.signOut()
        } catch {
            PushNotificationService.shared.resumeRegistration()
            throw error
        }
        await clearSession()
    }

    /// Sign in with Apple using ID token
    func signInWithApple(idToken: String, nonce: String) async throws {
        _ = try await supabase.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: idToken,
                nonce: nonce
            )
        )
        // Auth state will be updated automatically via listener
    }

    /// Resend verification email
    func resendVerificationEmail(email: String) async throws {
        try await supabase.auth.resend(email: email, type: .signup)
    }
}
