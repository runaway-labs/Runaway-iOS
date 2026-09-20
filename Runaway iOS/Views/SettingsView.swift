//
//  SettingsView.swift
//  Runaway iOS
//
//  Created by Jack Rudelic on 6/27/25.
//

import SwiftUI
import AuthenticationServices

// MARK: - Garmin Auth Presentation Context
class GarminAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GarminAuthPresentationContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            preconditionFailure("Garmin authentication requires an active window scene")
        }
        return scene.windows.first ?? ASPresentationAnchor(windowScene: scene)
    }
}

struct SettingsView: View {
    @Environment(UserSession.self) var userSession
    @Environment(DataManager.self) var dataManager
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var stravaService = StravaService()
    @StateObject private var garminService = GarminService()
    @ObservedObject private var unitPreferences = UnitPreferences.shared
    @State private var showingStravaSheet = false
    @State private var showingGarminSheet = false
    @State private var showingDisconnectAlert = false
    @State private var showingGarminDisconnectAlert = false
    @State private var showingDeleteAccountAlert = false
    @State private var isDeletingAccount = false
    @State private var stravaError: String?
    @State private var garminError: String?
    @State private var deleteAccountError: String?
    @State private var showingGoalSettings = false
    @State private var showingWorkoutNotifications = false
    @State private var showingAthleteTrainingProfile = false

    private var colors: (background: Color, cardBg: Color, textPrimary: Color, textSecondary: Color) {
        if themeManager.isDarkMode {
            return (
                AppTheme.Colors.DarkMode.background,
                AppTheme.Colors.DarkMode.cardBackground,
                AppTheme.Colors.DarkMode.textPrimary,
                AppTheme.Colors.DarkMode.textSecondary
            )
        } else {
            return (
                AppTheme.Colors.LightMode.background,
                AppTheme.Colors.LightMode.cardBackground,
                AppTheme.Colors.LightMode.textPrimary,
                AppTheme.Colors.LightMode.textSecondary
            )
        }
    }

    var body: some View {
        ZStack {
            colors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {
                    profileSection
                    appSettingsSection
                    goalsSection
                    integrationsSection
                    supportSection
                    #if DEBUG
                    debugSection
                    #endif
                    accountSection
                    appInfoSection
                }
                .padding(AppTheme.Spacing.md)
            }
        }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(themeManager.isDarkMode ? .dark : .light, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .sheet(isPresented: $showingStravaSheet) {
                StravaConnectSheet(stravaService: stravaService)
            }
            .sheet(isPresented: $showingGarminSheet) {
                GarminConnectSheet(garminService: garminService)
            }
            .sheet(isPresented: $showingGoalSettings) {
                GoalSettingsView()
            }
            .sheet(isPresented: $showingWorkoutNotifications) {
                if let athleteID = userSession.userId { WorkoutPromptSettingsView(athleteID: athleteID) }
            }
            .sheet(isPresented: $showingAthleteTrainingProfile) {
                if let athleteID = userSession.userId {
                    AthleteTrainingProfileView(athleteID: athleteID)
                }
            }
            .alert("Disconnect from Strava", isPresented: $showingDisconnectAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Disconnect", role: .destructive) {
                    Task {
                        await disconnectFromStrava()
                    }
                }
            } message: {
                Text("Are you sure you want to disconnect from Strava? Your activities will no longer sync automatically.")
            }
            .alert("Disconnect from Garmin", isPresented: $showingGarminDisconnectAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Disconnect", role: .destructive) {
                    Task {
                        await disconnectFromGarmin()
                    }
                }
            } message: {
                Text("Are you sure you want to disconnect from Garmin Connect?")
            }
            .task {
                await stravaService.checkConnectionStatus()
            }
            .onChange(of: dataManager.athlete) { _, _ in
                Task {
                    await stravaService.checkConnectionStatus()
                }
            }
    }

    // MARK: - View Components

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("Profile")
                .font(AppTheme.Typography.headline)
                .foregroundColor(colors.textPrimary)

            NavigationLink(destination: AccountInformationView()) {
                SettingsRow(
                    icon: "person.circle.fill",
                    title: "Account Information",
                    subtitle: "Manage your profile details",
                    color: AppTheme.Colors.accent
                ) {
                    // Navigation handled by NavigationLink
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var appSettingsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("App Settings")
                .font(AppTheme.Typography.headline)
                .foregroundColor(colors.textPrimary)

            // Theme Toggle
            ThemeToggleRow(themeManager: themeManager, colors: colors)

            // Unit Toggle
            UnitToggleRow(unitPreferences: unitPreferences, colors: colors)

            SettingsRow(
                icon: "bell",
                title: "Notifications",
                subtitle: PushNotificationService.shared.settingsSummary,
                color: AppTheme.Colors.accent
            ) {
                showingWorkoutNotifications = true
            }

            NavigationLink(value: AppRouter.Route.coachActivity) {
                SettingsRow(icon: "list.bullet.clipboard", title: "Coach Activity",
                    subtitle: "Review plan changes, approvals, and Undo history",
                    color: AppTheme.Colors.warmAmber) { }
            }.buttonStyle(.plain)

            SettingsRow(
                icon: "location",
                title: "Location Services",
                subtitle: "Privacy and location settings",
                color: AppTheme.Colors.warning
            ) {
                // Open iOS settings for location
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }

            AudioCoachingRow(colors: colors)

            if let athleteId = dataManager.athlete?.id {
                NavigationLink(destination: RestDayHistoryView(athleteId: athleteId)) {
                    SettingsRow(
                        icon: "moon.zzz.fill",
                        title: "Rest Days",
                        subtitle: "View rest day history and recovery status",
                        color: .blue
                    ) {
                        // Navigation handled by NavigationLink
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // MARK: - Goals Section

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("Goals")
                .font(AppTheme.Typography.headline)
                .foregroundColor(colors.textPrimary)

            SettingsRow(
                icon: "figure.strengthtraining.traditional",
                title: "Goals & Current Ability",
                subtitle: "Measurable targets, actual performance, and availability",
                color: AppTheme.Colors.teal
            ) {
                showingAthleteTrainingProfile = true
            }

            SettingsRow(
                icon: "target",
                title: "Running Goals",
                subtitle: "Weekly: \(Int(GoalSettingsStore.shared.weeklyGoal)) mi • Monthly: \(Int(GoalSettingsStore.shared.monthlyGoal)) mi",
                color: AppTheme.Colors.success
            ) {
                showingGoalSettings = true
            }
        }
    }

    private var integrationsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("Integrations")
                .font(AppTheme.Typography.headline)
                .foregroundColor(colors.textPrimary)

            StravaIntegrationRow(
                stravaService: stravaService,
                onConnect: { showingStravaSheet = true },
                onDisconnect: { showingDisconnectAlert = true },
                onSync: {
                    Task {
                        guard let userId = dataManager.athlete?.id else {
                            stravaError = "No Strava athlete ID found"
                            return
                        }
                        do {
                            _ = try await stravaService.syncStravaData(userId: String(userId), syncType: .incremental)
                            stravaError = nil
                        } catch {
                            stravaError = error.localizedDescription
                        }
                    }
                }
            )

            if let error = stravaError {
                Text(error)
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.error)
                    .padding(.horizontal, AppTheme.Spacing.md)
            }

            GarminIntegrationRow(
                garminService: garminService,
                onConnect: { showingGarminSheet = true },
                onDisconnect: { showingGarminDisconnectAlert = true }
            )

            if let error = garminError {
                Text(error)
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.error)
                    .padding(.horizontal, AppTheme.Spacing.md)
            }
        }
    }

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("Support")
                .font(AppTheme.Typography.headline)
                .foregroundColor(colors.textPrimary)

            SettingsRow(
                icon: "envelope.fill",
                title: "Contact Support",
                subtitle: "Get in touch with our team",
                color: AppTheme.Colors.accent
            ) {
                // Open email compose
                if let url = URL(string: "mailto:jack@runawayendurance.com?subject=Runaway%20iOS%20Support") {
                    UIApplication.shared.open(url)
                }
            }

            SettingsRow(
                icon: "doc.text.fill",
                title: "Privacy Policy",
                subtitle: "View our privacy policy",
                color: AppTheme.Colors.teal
            ) {
                if let url = URL(string: "https://runawayendurance.com/privacy") {
                    UIApplication.shared.open(url)
                }
            }

            SettingsRow(
                icon: "doc.plaintext.fill",
                title: "Terms of Service",
                subtitle: "View our terms of service",
                color: AppTheme.Colors.deepPurple
            ) {
                if let url = URL(string: "https://runawayendurance.com/terms") {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    @ViewBuilder
    private var debugSection: some View {
        #if DEBUG
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("Debug")
                .font(AppTheme.Typography.headline)
                .foregroundColor(colors.textPrimary)

            NavigationLink(destination: DebugMenuView()) {
                SettingsRow(
                    icon: "wrench.and.screwdriver",
                    title: "Background Task Monitor",
                    subtitle: "Monitor realtime connections and background tasks",
                    color: .purple
                ) {
                    // Navigation handled by NavigationLink
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        #endif
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("Account")
                .font(AppTheme.Typography.headline)
                .foregroundColor(colors.textPrimary)

            SettingsRow(
                icon: "rectangle.portrait.and.arrow.right",
                title: "Sign Out",
                subtitle: "Sign out of your account",
                color: AppTheme.Colors.error,
                isDestructive: true
            ) {
                Task {
                    try? await userSession.signOut()
                    dismiss()
                }
            }

            SettingsRow(
                icon: "trash",
                title: "Delete Account",
                subtitle: "Permanently delete your account and all data",
                color: AppTheme.Colors.error,
                isDestructive: true
            ) {
                showingDeleteAccountAlert = true
            }

            if let error = deleteAccountError {
                Text(error)
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.error)
                    .padding(.horizontal)
            }
        }
        .alert("Delete Account", isPresented: $showingDeleteAccountAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await deleteAccount()
                }
            }
        } message: {
            Text("Are you sure you want to permanently delete your account? This action cannot be undone. All your activities, training plans, and data will be permanently removed.")
        }
    }

    private var appInfoSection: some View {
        let textTertiary = AppTheme.Colors.adaptiveTextTertiary
        return VStack(spacing: AppTheme.Spacing.sm) {
            Text("Runaway")
                .font(AppTheme.Typography.caption)
                .foregroundColor(textTertiary)

            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(AppTheme.Typography.caption)
                .foregroundColor(textTertiary)
        }
        .padding(.top, AppTheme.Spacing.xl)
    }

    // MARK: - Helper Methods

    private func disconnectFromStrava() async {
        guard let authUserId = await getCurrentAuthUserId() else {
            stravaError = "Unable to get user ID"
            return
        }

        do {
            try await stravaService.disconnectStrava(authUserId: authUserId)
            stravaError = nil
        } catch {
            stravaError = error.localizedDescription
        }
    }

    private func disconnectFromGarmin() async {
        guard let authUserId = await getCurrentAuthUserId() else {
            garminError = "Unable to get user ID"
            return
        }

        do {
            try await garminService.disconnectGarmin(authUserId: authUserId)
            garminError = nil
        } catch {
            garminError = error.localizedDescription
        }
    }

    private func getCurrentAuthUserId() async -> String? {
        do {
            let session = try await supabase.auth.session
            return session.user.id.uuidString
        } catch {
            return nil
        }
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        deleteAccountError = nil

        do {
            // Get current session for auth
            let session = try await supabase.auth.session
            let accessToken = session.accessToken

            // Call the delete-account edge function
            guard let url = URL(string: "\(SupabaseConfiguration.supabaseURL ?? "")/functions/v1/delete-account") else {
                deleteAccountError = "Invalid URL"
                isDeletingAccount = false
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            if let apiKey = SupabaseConfiguration.supabaseKey {
                request.setValue(apiKey, forHTTPHeaderField: "apikey")
            }
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let body: [String: Any] = [
                "user_id": session.user.id.uuidString
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                deleteAccountError = "Invalid response"
                isDeletingAccount = false
                return
            }

            if httpResponse.statusCode == 200 {
                // Sign out after successful deletion
                try? await userSession.signOut()
                dismiss()
            } else {
                // Try to parse error message
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    deleteAccountError = message
                } else {
                    deleteAccountError = "Failed to delete account (status: \(httpResponse.statusCode))"
                }
            }
        } catch {
            deleteAccountError = error.localizedDescription
        }

        isDeletingAccount = false
    }
}

// MARK: - Settings Row
struct SettingsRow: View {
    @ObservedObject private var themeManager = ThemeManager.shared

    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    var isDestructive: Bool = false
    let action: () -> Void

    private var textPrimary: Color {
        AppTheme.Colors.adaptiveTextPrimary
    }

    private var textSecondary: Color {
        AppTheme.Colors.adaptiveTextSecondary
    }

    private var textTertiary: Color {
        AppTheme.Colors.adaptiveTextTertiary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.md) {
                // Icon
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 40, height: 40)

                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(color)
                }

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTheme.Typography.body.weight(.medium))
                        .foregroundColor(isDestructive ? AppTheme.Colors.error : textPrimary)

                    Text(subtitle)
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(textSecondary)
                }

                Spacer()

                // Chevron
                if !isDestructive {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(textTertiary)
                }
            }
            .padding(AppTheme.Spacing.md)
            .contentShape(Rectangle()) // Make entire row tappable
        }
        .buttonStyle(PlainButtonStyle())
        .surfaceCard()
    }
}

// MARK: - Strava Connect Sheet
struct StravaConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject var stravaService: StravaService
    @State private var isLoading = false

    private var background: Color {
        AppTheme.Colors.adaptiveBackground
    }

    private var textPrimary: Color {
        AppTheme.Colors.adaptiveTextPrimary
    }

    private var textSecondary: Color {
        AppTheme.Colors.adaptiveTextSecondary
    }

    var body: some View {
        NavigationView {
            ZStack {
                background.ignoresSafeArea()

                VStack(spacing: AppTheme.Spacing.xl) {
                    // Strava Logo/Icon
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.2))
                            .frame(width: 100, height: 100)

                        Image(systemName: "bolt.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                    }
                    .padding(.top, AppTheme.Spacing.xl)

                    // Title and Description
                    VStack(spacing: AppTheme.Spacing.md) {
                        Text("Connect to Strava")
                            .font(AppTheme.Typography.title)
                            .foregroundColor(textPrimary)

                        Text("Sync your Strava activities automatically. You can disconnect at any time.")
                            .font(AppTheme.Typography.body)
                            .foregroundColor(textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppTheme.Spacing.lg)
                    }

                    // Benefits List
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        BenefitRow(icon: "arrow.triangle.2.circlepath", text: "Automatic activity sync")
                        BenefitRow(icon: "chart.line.uptrend.xyaxis", text: "Enhanced analytics")
                        BenefitRow(icon: "lock.shield", text: "Secure OAuth connection")
                    }
                    .padding(.horizontal, AppTheme.Spacing.xl)

                    Spacer()

                    // Connect Button
                    Button(action: {
                        Task {
                            await connectToStrava()
                        }
                    }) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "bolt.fill")
                                Text("Connect with Strava")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(AppTheme.Spacing.md)
                    }
                    .disabled(isLoading)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.bottom, AppTheme.Spacing.lg)
                }
            }
            .navigationTitle("Strava Integration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.Colors.accent)
                }
            }
        }
    }

    private func connectToStrava() async {
        isLoading = true
        defer { isLoading = false }

        guard let authUserId = await getCurrentAuthUserId() else {
            #if DEBUG
            print("❌ Unable to get auth user ID for Strava connection")
            #endif
            return
        }

        guard let stravaURL = await stravaService.getStravaConnectURL(authUserId: authUserId) else {
            #if DEBUG
            print("❌ Unable to generate Strava OAuth URL")
            #endif
            return
        }

        #if DEBUG
        print("🔗 Opening Strava OAuth URL: \(stravaURL)")
        #endif

        // Open Strava OAuth URL in Safari
        await UIApplication.shared.open(stravaURL)

        // Dismiss sheet - user will return via deep link
        dismiss()
    }

    private func getCurrentAuthUserId() async -> String? {
        do {
            let session = try await supabase.auth.session
            return session.user.id.uuidString
        } catch {
            return nil
        }
    }
}

// MARK: - Benefit Row Helper
struct BenefitRow: View {
    @ObservedObject private var themeManager = ThemeManager.shared

    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .foregroundColor(AppTheme.Colors.accent)
                .frame(width: 24)

            Text(text)
                .font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

            Spacer()
        }
    }
}

// MARK: - Strava Integration Row
struct StravaIntegrationRow: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject var stravaService: StravaService
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onSync: () -> Void

    private var textPrimary: Color {
        AppTheme.Colors.adaptiveTextPrimary
    }

    private var textSecondary: Color {
        AppTheme.Colors.adaptiveTextSecondary
    }

    private var cardBackground: Color {
        AppTheme.Colors.adaptiveCardBackground
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // Main connection row
            HStack(spacing: AppTheme.Spacing.md) {
                // Icon
                stravaIcon

                // Content
                stravaContent

                Spacer()

                // Action Button
                actionButton
            }

            // Sync section (only show if connected)
            if stravaService.isConnected {
                Divider()

                syncSection
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(cardBackground)
        .cornerRadius(AppTheme.CornerRadius.large)
        .shadow(color: themeManager.isDarkMode ? Color.black.opacity(0.3) : Color.black.opacity(0.05), radius: 4, x: 0, y: 1)
    }

    private var stravaIcon: some View {
        ZStack {
            Circle()
                .fill(AppTheme.Colors.success.opacity(0.2))
                .frame(width: 40, height: 40)

            Image(systemName: "bolt.fill")
                .font(.title3)
                .foregroundColor(AppTheme.Colors.success)
        }
    }

    private var stravaContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Strava")
                .font(AppTheme.Typography.body.weight(.medium))
                .foregroundColor(textPrimary)

            Text(stravaService.isConnected ? "Connected" : "Not connected")
                .font(AppTheme.Typography.caption)
                .foregroundColor(stravaService.isConnected ? AppTheme.Colors.success : textSecondary)
        }
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            // Sync status
            HStack {
                Image(systemName: stravaService.isSyncing ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                    .foregroundColor(stravaService.isSyncing ? AppTheme.Colors.warning : AppTheme.Colors.success)
                    .imageScale(.small)

                VStack(alignment: .leading, spacing: 2) {
                    Text(stravaService.isSyncing ? "Syncing..." : "Data Sync")
                        .font(AppTheme.Typography.caption.weight(.medium))
                        .foregroundColor(textPrimary)

                    if let progress = stravaService.syncProgress {
                        Text(progress)
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(textSecondary)
                    } else if let lastSync = stravaService.lastSyncDate {
                        Text("Last synced: \(lastSync, style: .relative) ago")
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(textSecondary)
                    } else {
                        Text("Never synced")
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(textSecondary)
                    }
                }

                Spacer()

                // Sync button
                Button(action: onSync) {
                    if stravaService.isSyncing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                    } else {
                        Text("Sync Beta")
                            .font(AppTheme.Typography.caption.weight(.medium))
                            .foregroundColor(AppTheme.Colors.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(AppTheme.Colors.accent.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .disabled(stravaService.isSyncing)
            }
        }
    }

    private var actionButton: some View {
        Group {
            if stravaService.isConnected {
                disconnectButton
            } else {
                connectButton
            }
        }
    }

    private var connectButton: some View {
        Button(action: onConnect) {
            Text("Connect")
                .font(AppTheme.Typography.caption.weight(.medium))
                .foregroundColor(AppTheme.Colors.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppTheme.Colors.accent.opacity(0.1))
                .cornerRadius(8)
        }
    }

    private var disconnectButton: some View {
        Button(action: onDisconnect) {
            Text("Disconnect")
                .font(AppTheme.Typography.caption.weight(.medium))
                .foregroundColor(AppTheme.Colors.error)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppTheme.Colors.error.opacity(0.1))
                .cornerRadius(8)
        }
    }
}

// MARK: - Theme Toggle Row
struct ThemeToggleRow: View {
    @ObservedObject var themeManager: ThemeManager
    let colors: (background: Color, cardBg: Color, textPrimary: Color, textSecondary: Color)

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            // Icon
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.deepPurple.opacity(0.2))
                    .frame(width: 40, height: 40)

                Image(systemName: themeManager.isDarkMode ? "moon.fill" : "sun.max.fill")
                    .font(.title3)
                    .foregroundColor(AppTheme.Colors.deepPurple)
            }

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text("Appearance")
                    .font(AppTheme.Typography.body.weight(.medium))
                    .foregroundColor(colors.textPrimary)

                Text(themeManager.isDarkMode ? "Dark Mode" : "Light Mode")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(colors.textSecondary)
            }

            Spacer()

            // Theme Toggle
            HStack(spacing: AppTheme.Spacing.xs) {
                ForEach(ThemeMode.allCases, id: \.self) { mode in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            themeManager.currentTheme = mode
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: mode.iconName)
                                .font(.caption)
                            Text(mode.displayName)
                                .font(AppTheme.Typography.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            themeManager.currentTheme == mode
                                ? AppTheme.Colors.accent
                                : colors.cardBg
                        )
                        .foregroundColor(
                            themeManager.currentTheme == mode
                                ? .white
                                : colors.textSecondary
                        )
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(colors.cardBg)
        .cornerRadius(AppTheme.CornerRadius.large)
        .shadow(
            color: themeManager.isDarkMode ? Color.black.opacity(0.3) : Color.black.opacity(0.08),
            radius: 4,
            x: 0,
            y: 2
        )
    }
}

// MARK: - Unit Toggle Row
struct UnitToggleRow: View {
    @ObservedObject var unitPreferences: UnitPreferences
    let colors: (background: Color, cardBg: Color, textPrimary: Color, textSecondary: Color)

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            // Icon
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.accent.opacity(0.2))
                    .frame(width: 40, height: 40)

                Image(systemName: "ruler")
                    .font(.title3)
                    .foregroundColor(AppTheme.Colors.accent)
            }

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text("Units")
                    .font(AppTheme.Typography.body.weight(.medium))
                    .foregroundColor(colors.textPrimary)

                Text(unitPreferences.isImperial ? "Imperial (mi, mph)" : "Metric (km, km/h)")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(colors.textSecondary)
            }

            Spacer()

            // Unit Toggle
            HStack(spacing: AppTheme.Spacing.xs) {
                ForEach(DistanceUnit.allCases, id: \.self) { unit in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            unitPreferences.distanceUnit = unit
                        }
                    }) {
                        Text(unit.abbreviation)
                            .font(AppTheme.Typography.caption.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                unitPreferences.distanceUnit == unit
                                    ? AppTheme.Colors.accent
                                    : colors.cardBg
                            )
                            .foregroundColor(
                                unitPreferences.distanceUnit == unit
                                    ? .white
                                    : colors.textSecondary
                            )
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(colors.cardBg)
        .cornerRadius(AppTheme.CornerRadius.large)
        .shadow(
            color: ThemeManager.shared.isDarkMode ? Color.black.opacity(0.3) : Color.black.opacity(0.08),
            radius: 4,
            x: 0,
            y: 2
        )
    }
}

// MARK: - Garmin Connect Sheet
struct GarminConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject var garminService: GarminService
    @State private var isLoading = false
    @State private var webAuthSession: ASWebAuthenticationSession?

    private var background: Color {
        AppTheme.Colors.adaptiveBackground
    }

    private var textPrimary: Color {
        AppTheme.Colors.adaptiveTextPrimary
    }

    private var textSecondary: Color {
        AppTheme.Colors.adaptiveTextSecondary
    }

    var body: some View {
        NavigationView {
            ZStack {
                background.ignoresSafeArea()

                VStack(spacing: AppTheme.Spacing.xl) {
                    // Garmin Logo/Icon
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 100, height: 100)

                        Image(systemName: "applewatch")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                    }
                    .padding(.top, AppTheme.Spacing.xl)

                    // Title and Description
                    VStack(spacing: AppTheme.Spacing.md) {
                        Text("Connect to Garmin")
                            .font(AppTheme.Typography.title)
                            .foregroundColor(textPrimary)

                        Text("Sync your Garmin Connect activities automatically. You can disconnect at any time.")
                            .font(AppTheme.Typography.body)
                            .foregroundColor(textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppTheme.Spacing.lg)
                    }

                    // Benefits List
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        BenefitRow(icon: "arrow.triangle.2.circlepath", text: "Automatic activity sync")
                        BenefitRow(icon: "heart.fill", text: "Heart rate & health metrics")
                        BenefitRow(icon: "lock.shield", text: "Secure OAuth connection")
                    }
                    .padding(.horizontal, AppTheme.Spacing.xl)

                    Spacer()

                    // Connect Button
                    Button(action: {
                        Task {
                            await connectToGarmin()
                        }
                    }) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "applewatch")
                                Text("Connect with Garmin")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(AppTheme.Spacing.md)
                    }
                    .disabled(isLoading)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.bottom, AppTheme.Spacing.lg)
                }
            }
            .navigationTitle("Garmin Integration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.Colors.accent)
                }
            }
        }
    }

    private func connectToGarmin() async {
        isLoading = true

        guard let authUserId = await getCurrentAuthUserId() else {
            #if DEBUG
            print("❌ Unable to get auth user ID for Garmin connection")
            #endif
            isLoading = false
            return
        }

        guard let garminURL = await garminService.getGarminConnectURL(authUserId: authUserId) else {
            #if DEBUG
            print("❌ Unable to generate Garmin OAuth URL")
            #endif
            isLoading = false
            return
        }

        #if DEBUG
        print("🔗 Opening Garmin OAuth URL: \(garminURL)")
        #endif

        // Use ASWebAuthenticationSession for proper OAuth handling
        await MainActor.run {
            let session = ASWebAuthenticationSession(
                url: garminURL,
                callbackURLScheme: "runaway"
            ) { callbackURL, error in
                isLoading = false

                if let error = error {
                    #if DEBUG
                    print("❌ Garmin OAuth error: \(error.localizedDescription)")
                    #endif
                    // User cancelled or error occurred
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        // User cancelled - just dismiss
                    }
                    return
                }

                if let callbackURL = callbackURL {
                    #if DEBUG
                    print("✅ Garmin OAuth callback received: \(callbackURL)")
                    #endif

                    // Parse the callback URL
                    let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
                    let success = components?.queryItems?.first(where: { $0.name == "success" })?.value == "true"

                    // Update service state
                    garminService.handleOAuthCallback(success: success)

                    // Dismiss the sheet
                    dismiss()
                }
            }

            // Set presentation context
            session.presentationContextProvider = GarminAuthPresentationContext.shared
            session.prefersEphemeralWebBrowserSession = false

            // Start the session
            session.start()
            webAuthSession = session
        }
    }

    private func getCurrentAuthUserId() async -> String? {
        do {
            let session = try await supabase.auth.session
            return session.user.id.uuidString
        } catch {
            return nil
        }
    }
}

// MARK: - Garmin Integration Row
struct GarminIntegrationRow: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject var garminService: GarminService
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    private var textPrimary: Color {
        AppTheme.Colors.adaptiveTextPrimary
    }

    private var textSecondary: Color {
        AppTheme.Colors.adaptiveTextSecondary
    }

    private var cardBackground: Color {
        AppTheme.Colors.adaptiveCardBackground
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 40, height: 40)

                Image(systemName: "applewatch")
                    .font(.title3)
                    .foregroundColor(.blue)
            }

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text("Garmin Connect")
                    .font(AppTheme.Typography.body.weight(.medium))
                    .foregroundColor(textPrimary)

                Text(garminService.isConnected ? "Connected" : "Not connected")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(garminService.isConnected ? AppTheme.Colors.success : textSecondary)
            }

            Spacer()

            // Action Button
            if garminService.isConnected {
                Button(action: onDisconnect) {
                    Text("Disconnect")
                        .font(AppTheme.Typography.caption.weight(.medium))
                        .foregroundColor(AppTheme.Colors.error)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppTheme.Colors.error.opacity(0.1))
                        .cornerRadius(8)
                }
            } else {
                Button(action: onConnect) {
                    Text("Connect")
                        .font(AppTheme.Typography.caption.weight(.medium))
                        .foregroundColor(AppTheme.Colors.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppTheme.Colors.accent.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(cardBackground)
        .cornerRadius(AppTheme.CornerRadius.large)
        .shadow(color: themeManager.isDarkMode ? Color.black.opacity(0.3) : Color.black.opacity(0.05), radius: 4, x: 0, y: 1)
    }
}

// MARK: - Audio Coaching Row

/// Phase 1 audio-coaching settings — master toggle plus a Test cue button
/// that speaks a short utterance through `AudioCueService`. Exercises the
/// full session-activation / ducking / deactivation path so the user can
/// verify ducking and recovery before relying on it during a run.
struct AudioCoachingRow: View {
    @ObservedObject private var coachSettings = CoachSettingsStore.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    let colors: (background: Color, cardBg: Color, textPrimary: Color, textSecondary: Color)

    private var isEnabled: Bool {
        coachSettings.settings.isEnabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.success.opacity(0.2))
                        .frame(width: 40, height: 40)

                    Image(systemName: "speaker.wave.2.fill")
                        .font(.title3)
                        .foregroundColor(AppTheme.Colors.success)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Audio Coaching")
                        .font(AppTheme.Typography.body.weight(.medium))
                        .foregroundColor(colors.textPrimary)

                    Text(isEnabled ? "Beta — spoken cues during runs" : "Spoken cues during runs")
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(colors.textSecondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { coachSettings.settings.isEnabled },
                    set: { newValue in
                        coachSettings.settings.isEnabled = newValue
                        AnalyticsService.shared.track(
                            newValue ? .audioCoachingEnabled : .audioCoachingDisabled,
                            category: .audioCoaching
                        )
                        if !newValue {
                            AudioCueService.shared.stop()
                        }
                    }
                ))
                .labelsHidden()
                .tint(AppTheme.Colors.accent)
            }

            if isEnabled {
                Divider()

                Button {
                    AudioCueService.shared.prime()
                    AudioCueService.shared.speakCue(
                        "Audio coaching is working. You're all set."
                    )
                } label: {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: "play.circle.fill")
                        Text("Test cue")
                            .font(AppTheme.Typography.caption.weight(.medium))
                    }
                    .foregroundColor(AppTheme.Colors.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppTheme.Colors.accent.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(colors.cardBg)
        .cornerRadius(AppTheme.CornerRadius.large)
        .shadow(
            color: themeManager.isDarkMode ? Color.black.opacity(0.3) : Color.black.opacity(0.08),
            radius: 4,
            x: 0,
            y: 2
        )
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environment(UserSession.shared)
            .environment(DataManager.shared)
            .environmentObject(ThemeManager.shared)
    }
}
