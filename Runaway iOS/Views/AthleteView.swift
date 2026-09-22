//
//  Profile.swift
//  RunawayUI
//
//  Created by Jack Rudelic on 7/17/24.
//

import SwiftUI
import Charts

enum AthleteAccountAction: Equatable {
    case integrations
    case systemSettings
    case trainingPreferences
}

enum AthleteAccountItem: CaseIterable {
    case devicesAndSensors
    case trainingPreferences
    case notifications

    var action: AthleteAccountAction {
        switch self {
        case .devicesAndSensors:
            return .integrations
        case .notifications:
            return .systemSettings
        case .trainingPreferences:
            return .trainingPreferences
        }
    }
}

struct AthleteView: View {
    let athlete: Athlete
    let stats: AthleteStats
    @Environment(DataManager.self) private var dataManager
    @Environment(AppRouter.self) private var router
    @EnvironmentObject private var trainingProfileStore: TrainingProfileStore
    @StateObject private var garminService = GarminService.shared
    @State private var personalBests: [SupportedPersonalBest] = []
    @State private var isLoadingPRs = false
    @State private var prLoadError = false
    @State private var selectedRecordActivity: LocalActivity?
    @State private var showingRunningGoals = false
    @State private var milestones: [RunnerIdentityMilestone] = []
    @State private var showingTrainingPreferences = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppTheme.Colors.DarkMode.backgroundElevated,
                    AppTheme.Colors.DarkMode.background
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── Profile header ─────────────────────────────────────
                    HStack(spacing: 16) {
                        AsyncImage(url: athlete.profile) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            ZStack {
                                Circle().fill(AppTheme.Colors.warmAmber.opacity(0.16))
                                Text(String((athlete.firstname ?? "?").prefix(1)).uppercased())
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundColor(AppTheme.Colors.warmAmber)
                            }
                        }
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppTheme.Colors.warmAmber.opacity(0.25), lineWidth: 1.5))

                        VStack(alignment: .leading, spacing: 3) {
                            Text([athlete.firstname, athlete.lastname].compactMap { $0 }.joined(separator: " "))
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text(locationSubtitle)
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(AppTheme.Colors.DarkMode.textTertiary)
                        }
                        Spacer()
                    }

                    AthleteAchievementSummary(athleteID: athlete.id)

                    // ── MILESTONES ─────────────────────────────────────────
                    if !earnedMilestones.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            EyebrowLabel(text: "MILESTONES")
                            VStack(spacing: 0) {
                                ForEach(Array(earnedMilestones.enumerated()), id: \.element.id) { index, milestone in
                                    if index > 0 {
                                        Divider().background(Color.white.opacity(0.06))
                                    }
                                    RunnerMilestoneRow(milestone: milestone)
                                }
                            }
                            .background(AppTheme.Colors.DarkMode.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.07), lineWidth: 1))
                        }
                    }

                    PersonalBestCollection(records: personalBests, isLoading: isLoadingPRs, hasError: prLoadError,
                        onRetry: { Task { await loadRecords() } }, onOpen: { selectedRecordActivity = $0 })
                    
                    // ── ACCOUNT ────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        EyebrowLabel(text: "ACCOUNT")
                        VStack(spacing: 0) {
                            AccountRow(icon: "bolt.fill", title: "Strava", subtitle: stravaSubtitle)
                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 64)
                            AccountRow(icon: "watch.analog", title: "Devices & sensors", subtitle: deviceSubtitle, action: {
                                performAccountAction(for: .devicesAndSensors)
                            })
                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 64)
                            AccountRow(icon: "chart.bar.fill", title: "Training Profile", subtitle: "Marathon readiness, strength, core & schedule", action: {
                                performAccountAction(for: .trainingPreferences)
                            })
                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 64)
                            AccountRow(icon: "bell.fill", title: "Notifications", subtitle: "Workout reminders", action: {
                                performAccountAction(for: .notifications)
                            })
                        }
                        .background(AppTheme.Colors.DarkMode.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.07), lineWidth: 1))
                    }

                    Spacer(minLength: 32)
                }
                .padding(20)
            }
        }
        .task(id: athlete.id) {
            personalBests = []
            milestones = []
            prLoadError = false
            guard let athleteId = athlete.id else { return }
            async let progress: Void = TrainingProgressStore.shared.refresh(athleteID: athleteId)
            async let records: Void = loadRecords()
            async let garminStatus: Void = garminService.checkConnectionStatus()
            async let earned = RunnerMindsetService.fetchMilestones(athleteId: athleteId)
            let loaded = (try? await earned) ?? []
            if !Task.isCancelled { milestones = loaded }
            _ = await (progress, records, garminStatus)
        }
        .sheet(item: $selectedRecordActivity) { activity in
            NavigationStack { ActivityDetailView(activity: activity) }
        }
        .sheet(isPresented: $showingRunningGoals) { GoalSettingsView() }
        .sheet(isPresented: $showingTrainingPreferences) {
            if let athleteID = athlete.id {
                AthleteTrainingProfileView(athleteID: athleteID)
            } else {
                ContentUnavailableView("Sign in required", systemImage: "lock")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: MilestoneService.didUpdateNotification)) { _ in
            guard let athleteId = athlete.id else { return }
            Task {
                milestones = (try? await RunnerMindsetService.fetchMilestones(athleteId: athleteId)) ?? []
            }
        }
    }

    private var earnedMilestones: [RunnerIdentityMilestone] {
        Array(milestones.filter { $0.earned && $0.earnedAt != nil }
            .sorted { ($0.earnedAt ?? .distantPast) > ($1.earnedAt ?? .distantPast) }.prefix(3))
    }
    
    @MainActor
    private func loadRecords() async {
        guard let id = athlete.id else { return }
        isLoadingPRs = true
        prLoadError = false
        do {
            let records = try await PersonalBestService.shared.fetchSupportedPRs(athleteId: id)
            guard !Task.isCancelled, dataManager.athlete?.id == id else { return }
            personalBests = records
        } catch {
            guard !Task.isCancelled, dataManager.athlete?.id == id else { return }
            prLoadError = true
        }
        isLoadingPRs = false
    }
    
    // MARK: - Computed strings

    private var trainingPreferencesSubtitle: String {
        "\(TrainingPersonalizationPresentation.settingsStatus(for: trainingProfileStore).rawValue) · Weekly mix, schedule & strength"
    }

    private var deviceSubtitle: String {
        DeviceIdentityPresentation.subtitle(
            activities: dataManager.activities,
            garminConnected: garminService.isConnected
        )
    }

    private func performAccountAction(for item: AthleteAccountItem) {
        switch item.action {
        case .integrations:
            router.navigate(to: .settings)
        case .systemSettings:
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            openURL(url)
        case .trainingPreferences:
            showingTrainingPreferences = true
        }
    }

    private var locationSubtitle: String {
        var parts: [String] = []
        if let city = athlete.city, !city.isEmpty { parts.append(city) }
        if let state = athlete.state, !state.isEmpty { parts.append(state) }
        if parts.isEmpty, let country = athlete.country, !country.isEmpty { parts.append(country) }
        let location = parts.joined(separator: ", ")
        let since = joinYear.map { "Runner since \($0)" }
        return [location, since].compactMap { $0 }.joined(separator: " · ")
    }

    private var joinYear: String? {
        guard let date = athlete.createdAt else { return nil }
        return "\(Calendar.current.component(.year, from: date))"
    }

    private var stravaSubtitle: String {
        guard athlete.stravaConnected == true else { return "Not connected" }
        if let syncedAt = athlete.stravaConnectedAt {
            let interval = Date().timeIntervalSince(syncedAt)
            if interval < 3600 { return "Synced · \(Int(interval / 60))m ago" }
            if interval < 86400 { return "Synced · \(Int(interval / 3600))h ago" }
            let days = Int(interval / 86400)
            return "Synced · \(days)d ago"
        }
        return "Connected"
    }
}

struct DeviceIdentityPresentation {
    private static let softwareOnlyNames = Set([
        "strava app",
        "runaway ios",
        "nike"
    ])

    static func subtitle(activities: [Activity], garminConnected: Bool) -> String {
        let newestPhysicalDevice = activities
            .compactMap { activity -> (name: String, date: TimeInterval)? in
                guard let rawName = activity.device_name?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !rawName.isEmpty,
                      !softwareOnlyNames.contains(rawName.lowercased()) else {
                    return nil
                }
                return (rawName, activity.activity_date ?? activity.start_date ?? 0)
            }
            .max { $0.date < $1.date }

        if let newestPhysicalDevice {
            return newestPhysicalDevice.name
        }
        if garminConnected {
            return "Garmin Connect"
        }
        return "No device detected"
    }
}

// MARK: - Personal Best Row
private struct PersonalBestRow: View {
    let distance: String
    let time: String? // nil = no PR yet

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(time != nil
                          ? AppTheme.Colors.warmAmber.opacity(0.16)
                          : Color.white.opacity(0.05))
                    .frame(width: 36, height: 36)
                Image(systemName: "star.fill")
                    .font(.system(size: 14))
                    .foregroundColor(time != nil
                                     ? AppTheme.Colors.warmAmber
                                     : AppTheme.Colors.DarkMode.textTertiary.opacity(0.4))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(distance)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text(time != nil ? "Personal best" : "No PR yet")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(AppTheme.Colors.DarkMode.textTertiary)
            }
            Spacer()
            Text(time ?? "--:--")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(time != nil ? .white : AppTheme.Colors.DarkMode.textTertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 56)
    }
}

// MARK: - Milestone Row

private struct RunnerMilestoneRow: View {
    let milestone: RunnerIdentityMilestone

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(milestone.earned
                          ? AppTheme.Colors.warmAmber
                          : Color.white.opacity(0.06))
                    .frame(width: 32, height: 32)
                Image(systemName: "medal.fill")
                    .font(.system(size: 13))
                    .foregroundColor(milestone.earned ? .black : AppTheme.Colors.DarkMode.textTertiary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(milestone.label)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(milestone.earned ? .white : AppTheme.Colors.DarkMode.textSecondary)
                Text(milestone.description)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(AppTheme.Colors.DarkMode.textTertiary)
            }
            Spacer()
            if milestone.earned, let date = milestone.earnedAt {
                Text(date, format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.Colors.warmAmber)
            } else {
                Text("Not yet")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(AppTheme.Colors.DarkMode.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 56)
        .opacity(milestone.earned ? 1.0 : 0.55)
    }
}

// MARK: - Profile Header
struct ProfileHeader: View {
    let athlete: Athlete

    private var textPrimary: Color {
        AppTheme.Colors.adaptiveTextPrimary
    }

    private var textSecondary: Color {
        AppTheme.Colors.adaptiveTextSecondary
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Profile Image - Compact & Refined
            AsyncImage(url: athlete.profile) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(AppTheme.Colors.primaryGradient)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    )
            }
            .frame(width: 100, height: 100)
            .clipShape(Circle())
            .overlay(Circle().stroke(AppTheme.Colors.accent.opacity(0.2), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)

            // Name and Identity
            VStack(spacing: AppTheme.Spacing.xs) {
                Text("\(athlete.firstname ?? "Unknown") \(athlete.lastname ?? "Athlete")")
                    .font(.system(.title, design: .monospaced).weight(.bold))
                    .foregroundColor(textPrimary)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    
                    Text("Digital Twin • Active Trajectory")
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(textSecondary)
                        .tracking(0.5)
                }
            }
        }
    }
}

// MARK: - Quick Stats Grid
struct QuickStatsGrid: View {
    let runs: String
    let miles: String
    let hours: String
    
    var body: some View {
        HStack(spacing: 0) {
            QuickStatItem(value: runs, label: "RUNS", color: AppTheme.Colors.accent)
            
            Divider()
                .frame(height: 40)
                .background(Color.white.opacity(0.08))
            
            QuickStatItem(value: miles, label: "MILES", color: AppTheme.Colors.accent)
            
            Divider()
                .frame(height: 40)
                .background(Color.white.opacity(0.08))
            
            QuickStatItem(value: hours, label: "HOURS", color: AppTheme.Colors.accent)
        }
        .padding(.vertical, 20)
        .background(AppTheme.Colors.DarkMode.cardBackground)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}

// MARK: - Quick Stat Item
struct QuickStatItem: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 24, weight: .heavy, design: .monospaced))
                .foregroundColor(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                .tracking(1.2)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Athlete Weekly Stats Card
struct AthleteWeeklyStatsCard: View {
    let stats: AthleteStats
    @Environment(DataManager.self) private var dataManager
    @State private var weeklyRuns = 0
    @State private var weeklyDistanceValue: Double = 0.0
    @State private var weeklyTime = "0h 0m"

    private let weeklyGoal: Double = 50.0

    private var weeklyProgress: Double {
        min(weeklyDistanceValue / weeklyGoal, 1.0)
    }

    private var textPrimary: Color {
        AppTheme.Colors.adaptiveTextPrimary
    }

    private var textSecondary: Color {
        AppTheme.Colors.adaptiveTextSecondary
    }

    private var surfaceBackground: Color {
        AppTheme.Colors.adaptiveSurfaceBackground
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(AppTheme.Colors.accent)
                    .font(.title2)

                Text("This Week")
                    .font(AppTheme.Typography.headline)
                    .foregroundColor(textPrimary)

                Spacer()
            }

            HStack(spacing: AppTheme.Spacing.lg) {
                StatPair(label: "Runs", value: String(weeklyRuns), color: AppTheme.Colors.accent)
                StatPair(label: "Distance", value: String(format: "%.1f / %.0f mi", weeklyDistanceValue, weeklyGoal), color: AppTheme.Colors.accent)
                StatPair(label: "Time", value: weeklyTime, color: AppTheme.Colors.warning)
                Spacer()
            }

            // Progress bar
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(surfaceBackground)
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppTheme.Colors.accent)
                            .frame(width: geometry.size.width * weeklyProgress, height: 8)
                    }
                }
                .frame(height: 8)

                Text(String(format: "%.0f%% of weekly goal", weeklyProgress * 100))
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(textSecondary)
            }
        }
        .surfaceCard()
        .onAppear {
            loadWeeklyStats()
        }
        .onChange(of: dataManager.activities) { _, _ in
            loadWeeklyStats()
        }
    }

    private func loadWeeklyStats() {
        guard let userDefaults = UserDefaults(suiteName: "group.com.jackrudelic.runawayios") else {
            #if DEBUG
            print("❌ WeeklyStatsCard: Failed to access shared UserDefaults")
            #endif
            return
        }

        #if DEBUG
        print("🔍 WeeklyStatsCard: Loading weekly stats from UserDefaults")
        #endif

        let dayArrays = [
            userDefaults.stringArray(forKey: "sunArray") ?? [],
            userDefaults.stringArray(forKey: "monArray") ?? [],
            userDefaults.stringArray(forKey: "tueArray") ?? [],
            userDefaults.stringArray(forKey: "wedArray") ?? [],
            userDefaults.stringArray(forKey: "thuArray") ?? [],
            userDefaults.stringArray(forKey: "friArray") ?? [],
            userDefaults.stringArray(forKey: "satArray") ?? []
        ]

        var totalRuns = 0
        var totalDistance = 0.0
        var totalTime = 0.0

        for dayArray in dayArrays {
            for activityJson in dayArray {
                if let data = activityJson.data(using: .utf8),
                   let activity = try? JSONDecoder().decode(RAActivity.self, from: data),
                   AppConstants.ActivityTypes.isRunning(activity.type) {
                    totalRuns += 1
                    totalDistance += activity.distance
                    totalTime += activity.time
                }
            }
        }

        weeklyRuns = totalRuns
        weeklyDistanceValue = totalDistance
        weeklyTime = formatTime(minutes: totalTime)

        #if DEBUG
        print("✅ WeeklyStatsCard: Loaded - Runs: \(totalRuns), Distance: \(totalDistance) mi, Time: \(totalTime) min")
        #endif
    }
}

// MARK: - Monthly Stats Card
struct MonthlyStatsCard: View {
    let stats: AthleteStats
    @Environment(DataManager.self) private var dataManager
    @State private var monthlyRuns = 0
    @State private var monthlyDistanceValue: Double = 0.0
    @State private var averagePace = "0:00"

    private let monthlyGoal: Double = 200.0

    private var monthlyProgress: Double {
        min(monthlyDistanceValue / monthlyGoal, 1.0)
    }

    private var textPrimary: Color {
        AppTheme.Colors.adaptiveTextPrimary
    }

    private var textSecondary: Color {
        AppTheme.Colors.adaptiveTextSecondary
    }

    private var surfaceBackground: Color {
        AppTheme.Colors.adaptiveSurfaceBackground
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(AppTheme.Colors.accent)
                    .font(.title2)

                Text("This Month")
                    .font(AppTheme.Typography.headline)
                    .foregroundColor(textPrimary)

                Spacer()
            }

            HStack(spacing: AppTheme.Spacing.lg) {
                StatPair(label: "Runs", value: String(monthlyRuns), color: AppTheme.Colors.accent)
                StatPair(label: "Distance", value: String(format: "%.1f / %.0f mi", monthlyDistanceValue, monthlyGoal), color: AppTheme.Colors.accent)
                StatPair(label: "Avg Pace", value: averagePace, color: AppTheme.Colors.warning)
                Spacer()
            }

            // Progress bar
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(surfaceBackground)
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppTheme.Colors.accent)
                            .frame(width: geometry.size.width * monthlyProgress, height: 8)
                    }
                }
                .frame(height: 8)

                Text(String(format: "%.0f%% of monthly goal", monthlyProgress * 100))
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(textSecondary)
            }
        }
        .surfaceCard()
        .onAppear {
            loadMonthlyStats()
        }
        .onChange(of: dataManager.activities) { _, _ in
            loadMonthlyStats()
        }
    }
    
    private func loadMonthlyStats() {
        guard let userDefaults = UserDefaults(suiteName: "group.com.jackrudelic.runawayios") else {
            #if DEBUG
            print("❌ MonthlyStatsCard: Failed to access shared UserDefaults")
            #endif
            return
        }

        #if DEBUG
        print("🔍 MonthlyStatsCard: Loading monthly stats from UserDefaults")
        #endif
        
        // Get monthly distance from UserDefaults
        let monthlyMiles = userDefaults.double(forKey: "monthlyMiles")
        
        // Calculate monthly runs and pace from all activity data
        let dayArrays = [
            userDefaults.stringArray(forKey: "sunArray") ?? [],
            userDefaults.stringArray(forKey: "monArray") ?? [],
            userDefaults.stringArray(forKey: "tueArray") ?? [],
            userDefaults.stringArray(forKey: "wedArray") ?? [],
            userDefaults.stringArray(forKey: "thuArray") ?? [],
            userDefaults.stringArray(forKey: "friArray") ?? [],
            userDefaults.stringArray(forKey: "satArray") ?? []
        ]
        
        var totalMonthlyRuns = 0
        var totalMonthlyTime = 0.0
        var totalMonthlyDistance = 0.0
        
        // Count all activities (not just this week) for monthly stats
        // Note: This is an approximation since UserDefaults only stores weekly data
        // For more accurate monthly data, you'd need to store monthly activity arrays separately
        for dayArray in dayArrays {
            for activityJson in dayArray {
                if let data = activityJson.data(using: .utf8),
                   let activity = try? JSONDecoder().decode(RAActivity.self, from: data),
                   AppConstants.ActivityTypes.isRunning(activity.type) {
                    totalMonthlyRuns += 1
                    totalMonthlyTime += activity.time
                    totalMonthlyDistance += activity.distance
                }
            }
        }
        
        // Use the stored monthly miles if available, otherwise use calculated value
        let displayDistance = monthlyMiles > 0 ? monthlyMiles : totalMonthlyDistance

        monthlyRuns = totalMonthlyRuns
        monthlyDistanceValue = displayDistance

        // Calculate average pace (minutes per mile)
        if displayDistance > 0 && totalMonthlyTime > 0 {
            let avgPaceMinutes = totalMonthlyTime / displayDistance
            let paceMinutes = Int(avgPaceMinutes)
            let paceSeconds = Int((avgPaceMinutes - Double(paceMinutes)) * 60)
            averagePace = String(format: "%d:%02d", paceMinutes, paceSeconds)
        } else {
            averagePace = "0:00"
        }

        #if DEBUG
        print("✅ MonthlyStatsCard: Loaded - Runs: \(totalMonthlyRuns), Distance: \(displayDistance) mi, Time: \(totalMonthlyTime) min, MonthlyMiles from UserDefaults: \(monthlyMiles)")
        #endif
    }
}

// MARK: - All Time Stats Card
struct AllTimeStatsCard: View {
    let stats: AthleteStats

    private var textPrimary: Color {
        AppTheme.Colors.adaptiveTextPrimary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundColor(AppTheme.Colors.warning)
                    .font(.title2)

                Text("All Time")
                    .font(AppTheme.Typography.headline)
                    .foregroundColor(textPrimary)

                Spacer()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: AppTheme.Spacing.md) {
                StatPair(label: "Total Runs", value: "\(stats.count ?? 0)", color: AppTheme.Colors.accent)
                StatPair(label: "Total Distance", value: String(format: "%.1f mi", (stats.distance ?? 0.0) * 0.000621371), color: AppTheme.Colors.accent)
                StatPair(label: "Total Time", value: formatTime(minutes: (stats.elapsedTime ?? 0.0) / 60), color: AppTheme.Colors.warning)
                StatPair(label: "Best Pace", value: "6:45/mi", color: AppTheme.Colors.accent)
            }
        }
        .surfaceCard()
    }
}

// MARK: - Stat Pair
struct StatPair: View {
    let label: String
    let value: String
    let color: Color

    private var textSecondary: Color {
        AppTheme.Colors.adaptiveTextSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(value)
                .font(.system(.headline, design: .monospaced).weight(.bold))
                .foregroundColor(color)

            Text(label)
                .font(AppTheme.Typography.caption)
                .foregroundColor(textSecondary)
        }
    }
}

// MARK: - Helper Functions
private func formatTime(minutes: Double) -> String {
    let hours = Int(minutes) / 60
    let mins = Int(minutes) % 60
    
    if hours > 0 {
        return "\(hours)h \(mins)m"
    } else {
        return "\(mins)m"
    }
}

// MARK: - Twin Identity
struct TwinIdentityBadge: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    
    private var cardBg: Color {
        AppTheme.Colors.adaptiveCardBackground
    }
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.accent.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: "brain.head.profile")
                    .foregroundColor(AppTheme.Colors.accent)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("TWIN IDENTITY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AppTheme.Colors.accent)
                    .tracking(1.2)
                Text("The Consistent Builder")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(themeManager.isDarkMode ? .white : .black)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(AppTheme.Colors.DarkMode.textTertiary)
        }
        .padding()
        .background(cardBg)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}
