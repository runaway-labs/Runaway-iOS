import SwiftUI
import Foundation
import UIKit
import WidgetKit

enum ActivityLogPeriod: String, CaseIterable {
    case week = "This week"
    case recent = "Recent"
}

struct ActivitiesView: View {
    @Environment(UserSession.self) var userSession
    @Environment(DataManager.self) var dataManager
    @Environment(RealtimeService.self) var realtimeService
    @ObservedObject private var progress = TrainingProgressStore.shared
    @ObservedObject private var units = UnitPreferences.shared
    @State private var selectedActivity: LocalActivity?
    @State private var period: ActivityLogPeriod
    @State private var activeFilter = "All"
    @State private var visibleActivities: [LocalActivity] = []
    @State private var summary = TrainingProgressSnapshot.Totals.zero
    private let filters = ["All", "Run", "Strength", "Bike", "Swim", "Walk", "Trail", "Mobility"]

    init(initialPeriod: ActivityLogPeriod = .week) { _period = State(initialValue: initialPeriod) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        EyebrowLabel(text: "YOUR WORK, RECORDED")
                        Text("Activities").font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(.white)
                    }
                    Spacer()
                    Button { Task { await refresh() } } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                            .background(.white.opacity(0.06), in: Circle())
                    }.foregroundStyle(TrainingProgressStyle.blue)
                        .disabled(dataManager.isLoadingActivities || progress.isRefreshing)
                        .accessibilityLabel("Refresh activities")
                }
                Picker("Activity period", selection: $period) {
                    ForEach(ActivityLogPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters, id: \.self) { filter in
                            FilterChip(label: filter, isActive: activeFilter == filter) { activeFilter = filter }
                        }
                    }.padding(.vertical, 2)
                }
                summaryCard
                if let message = progress.errorMessage, period == .week {
                    Button { Task { await refresh() } } label: {
                        Label("\(message) Retry", systemImage: "arrow.clockwise").font(.caption)
                    }.frame(minHeight: 44)
                }
                if visibleActivities.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        if progress.isRefreshing || dataManager.isLoadingActivities { ProgressView() }
                        Text(period == .week ? "Your week has room for more." : "No matching activities loaded.")
                            .font(.headline)
                        Text("Completed sessions appear here. Change the activity filter or sync your latest work.")
                            .font(.subheadline).foregroundStyle(TrainingProgressStyle.secondary)
                    }.padding(20)
                } else {
                    ForEach(visibleActivities, id: \.id) { activity in
                        CardView(activity: activity, onTap: { selectedActivity = activity })
                    }
                }
            }.padding(18).padding(.bottom, 100)
        }
        .background {
            LinearGradient(colors: [AppTheme.Colors.DarkMode.backgroundElevated, AppTheme.Colors.DarkMode.background], startPoint: .topTrailing, endPoint: .bottomLeading).ignoresSafeArea()
        }
        .foregroundStyle(.white)
        .navigationBarHidden(true)
        .task(id: dataManager.athlete?.id) {
            applyFilter()
            if let id = dataManager.athlete?.id { await progress.refresh(athleteID: id) }
            applyFilter()
        }
        .onChange(of: period) { _, _ in applyFilter() }
        .onChange(of: activeFilter) { _, _ in applyFilter() }
        .onChange(of: dataManager.activities) { _, _ in applyFilter() }
        .onChange(of: progress.weekActivities) { _, _ in applyFilter() }
        .refreshable { await refresh() }
        .sheet(item: $selectedActivity) { activity in NavigationStack { ActivityDetailView(activity: activity) } }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(period == .week ? "THIS WEEK / \(activeFilter.uppercased())" : "LOADED HISTORY / \(activeFilter.uppercased())")
                .font(.system(.caption2, design: .rounded, weight: .heavy)).tracking(1.3).foregroundStyle(TrainingProgressStyle.amber)
            HStack(alignment: .firstTextBaseline) {
                Text("\(summary.sessions)").font(.system(size: 42, weight: .bold, design: .rounded)).monospacedDigit()
                Text(summary.sessions == 1 ? "session" : "sessions").foregroundStyle(TrainingProgressStyle.secondary)
                Spacer()
                Text(TrainingProgressStyle.duration(summary.seconds)).font(.system(.title3, design: .rounded, weight: .bold))
            }
            if activeFilter == "All" || activeFilter == "Run" || activeFilter == "Trail" {
                Text("\(UnitFormatter.formatDistance(summary.runningMeters, unit: units.distanceUnit, decimals: 1)) running")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(TrainingProgressStyle.blue)
            }
            if period == .recent {
                Text("Latest \(dataManager.activities.count) loaded activities, filtered above. This is not a lifetime total.")
                    .font(.caption2).foregroundStyle(TrainingProgressStyle.secondary)
            } else if progress.isRefreshing {
                Text("Syncing this week's sessions...").font(.caption2).foregroundStyle(TrainingProgressStyle.secondary)
            }
        }.padding(20).background(TrainingProgressStyle.surface, in: RoundedRectangle(cornerRadius: 22))
    }

    private func applyFilter() {
        guard let id = dataManager.athlete?.id else { visibleActivities = []; summary = .zero; return }
        let source: [TrainingProgressActivity]
        if period == .week {
            source = progress.snapshot?.athleteID == id && progress.snapshot?.isCurrent() == true ? progress.weekActivities : []
        } else {
            source = dataManager.activities.compactMap { TrainingProgressActivity($0, athleteID: id) }
        }
        let filtered = TrainingProgressPolicy.unique(source, athleteID: id, through: Date()).filter { activity in
            switch activeFilter {
            case "Run": return activity.kind == .run
            case "Strength": return activity.kind == .strength
            case "Bike": return activity.kind == .bike
            case "Swim": return activity.kind == .swim
            case "Walk": return activity.kind == .walk
            case "Trail": return activity.type.lowercased().contains("trail") || activity.kind == .hike
            case "Mobility": return activity.kind == .mobility
            default: return true
            }
        }.sorted { $0.date > $1.date }
        summary = TrainingProgressPolicy.totals(filtered)
        visibleActivities = filtered.map(\.localActivity)
    }
    private func refresh() async {
        await dataManager.refreshActivities()
        if let id = dataManager.athlete?.id { await progress.refresh(athleteID: id, force: true) }
        applyFilter()
    }
}

// MARK: - Empty Activities View
struct EmptyActivitiesView: View {
    private var colors: (textPrimary: Color, textSecondary: Color) {
        (AppTheme.Colors.adaptiveTextPrimary, AppTheme.Colors.adaptiveTextSecondary)
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 80))
                .foregroundColor(AppTheme.Colors.accent)

            VStack(spacing: AppTheme.Spacing.sm) {
                Text("No Activities Yet")
                    .font(AppTheme.Typography.title)
                    .foregroundColor(colors.textPrimary)

                Text("Your completed activities will appear here once you start tracking your workouts.")
                    .font(AppTheme.Typography.body)
                    .foregroundColor(colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(AppTheme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ActivitiesView_Previews: PreviewProvider {
    static var previews: some View {
        ActivitiesView()
            .environment(UserSession.shared)
            .environment(DataManager.shared)
            .environment(RealtimeService.shared)
    }
}
