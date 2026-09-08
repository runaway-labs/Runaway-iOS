import SwiftUI

/// A restrained palette shared by the app's accomplishment surfaces.
enum TrainingProgressStyle {
    static let blue = Color(red: 0.32, green: 0.68, blue: 1)
    static let mint = Color(red: 0.32, green: 0.84, blue: 0.66)
    static let amber = Color(red: 1, green: 0.72, blue: 0.29)
    static let secondary = Color(red: 0.66, green: 0.73, blue: 0.80)
    static let surface = LinearGradient(colors: [Color(red: 0.10, green: 0.17, blue: 0.22), Color(red: 0.05, green: 0.10, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static func color(_ kind: ProgressActivityKind) -> Color {
        switch kind {
        case .run: return blue
        case .strength: return amber
        case .walk, .mobility: return mint
        case .bike: return Color(red: 0.87, green: 0.55, blue: 0.41)
        case .swim: return .cyan
        case .hike: return Color(red: 0.67, green: 0.78, blue: 0.49)
        case .other: return secondary
        }
    }
    static func duration(_ seconds: Double) -> String {
        let minutes = Int(TrainingProgressPolicy.clean(seconds) / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

struct TrainingProgressHero: View {
    let snapshot: TrainingProgressSnapshot
    let unit: String
    let goalUnit: String
    let weeklyGoalMeters: Double?
    let monthlyGoalMeters: Double?
    var onOpenActivities: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var divisor: Double { unit == "km" ? 1000 : TrainingProgressSnapshot.metersPerMile }
    private var earned: String {
        if let goal = weeklyGoalMeters, goal > 0, snapshot.week.runningMeters >= goal { return "Weekly goal reached" }
        let days = snapshot.week.activeDays
        if days > 0 { return "\(days) active \(days == 1 ? "day" : "days"). That work is yours." }
        return "A fresh week. Your next chapter."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text("YOUR WEEK").font(.system(.caption2, design: .rounded, weight: .heavy)).tracking(2)
                    .foregroundStyle(TrainingProgressStyle.amber)
                Spacer()
                Text(snapshot.weekStart, format: .dateTime.month(.abbreviated).day())
                    .font(.caption).foregroundStyle(TrainingProgressStyle.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text((snapshot.week.runningMeters / divisor).formatted(.number.precision(.fractionLength(1))))
                        .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 52 : 70, weight: .bold, design: .rounded))
                        .tracking(-3).monospacedDigit().minimumScaleFactor(0.65).lineLimit(1)
                        .foregroundStyle(.white)
                    Text("\(unit) run").font(.title3.weight(.medium)).foregroundStyle(TrainingProgressStyle.secondary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { facts }
                    VStack(alignment: .leading, spacing: 8) { facts }
                }
            }
            TrainingActivityChart(days: snapshot.days, today: snapshot.refreshedAt)
            Text(earned).font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(snapshot.week.activeDays > 0 ? TrainingProgressStyle.mint : TrainingProgressStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(.white.opacity(0.09)).frame(height: 1)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) { goals }
                VStack(alignment: .leading, spacing: 16) { goals }
            }
            if let onOpenActivities {
                Button(action: onOpenActivities) {
                    HStack {
                        Text("See this week's work")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(TrainingProgressStyle.blue).frame(minHeight: 44)
                }.buttonStyle(.plain)
            }
        }
        .padding(22)
        .background(TrainingProgressStyle.surface, in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.10), lineWidth: 1))
        .accessibilityIdentifier("trainingProgressHero")
    }

    @ViewBuilder private var facts: some View {
        Label("\(snapshot.week.runs) \(snapshot.week.runs == 1 ? "run" : "runs")", systemImage: "figure.run")
        Label("\(TrainingProgressStyle.duration(snapshot.week.seconds)) training", systemImage: "clock")
    }

    @ViewBuilder private var goals: some View {
        TrainingGoalRing(title: "WEEK", meters: snapshot.week.runningMeters, goalMeters: weeklyGoalMeters, unit: goalUnit, color: TrainingProgressStyle.blue)
        TrainingGoalRing(title: "MONTH", meters: snapshot.month.runningMeters, goalMeters: monthlyGoalMeters, unit: goalUnit, color: TrainingProgressStyle.mint)
    }
}

#if canImport(UIKit)
struct TrainingProgressCard: View {
    @Environment(DataManager.self) private var dataManager
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var store = TrainingProgressStore.shared
    @ObservedObject private var units = UnitPreferences.shared
    @ObservedObject private var goals = GoalSettingsStore.shared
    @State private var showingWeek = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let snapshot = store.snapshot, snapshot.athleteID == dataManager.athlete?.id, snapshot.isCurrent() {
                TrainingProgressHero(snapshot: snapshot, unit: units.distanceUnit.abbreviation,
                    goalUnit: goals.settings.resolvedDistanceUnit(fallback: units.distanceUnit).abbreviation,
                    weeklyGoalMeters: goals.settings.weeklyGoalMiles * TrainingProgressSnapshot.metersPerMile,
                    monthlyGoalMeters: goals.settings.monthlyGoalMiles * TrainingProgressSnapshot.metersPerMile,
                    onOpenActivities: { showingWeek = true })
                Text("Synced \(snapshot.refreshedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(TrainingProgressStyle.secondary).padding(.horizontal, 8)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your week is taking shape").font(.title3.bold())
                    Text(store.isRefreshing ? "Gathering your completed training..." : "Sync activities to see your earned progress.")
                        .font(.subheadline).foregroundStyle(TrainingProgressStyle.secondary)
                    if store.isRefreshing { ProgressView().tint(TrainingProgressStyle.blue) }
                    else { Button("Sync progress") { Task { await refresh(force: true) } }.frame(minHeight: 44) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
                    .background(TrainingProgressStyle.surface, in: RoundedRectangle(cornerRadius: 26))
            }
            if let error = store.errorMessage {
                Button { Task { await refresh(force: true) } } label: {
                    Label("\(error) Tap to retry.", systemImage: "arrow.clockwise")
                        .font(.caption).foregroundStyle(TrainingProgressStyle.secondary)
                }.buttonStyle(.plain).frame(minHeight: 44)
            }
        }
        .foregroundStyle(.white)
        .task(id: dataManager.athlete?.id) { await refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh() } } }
        .sheet(isPresented: $showingWeek) {
            NavigationStack {
                ActivitiesView(initialPeriod: .week)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingWeek = false } } }
                    .toolbarVisibility(.visible, for: .navigationBar)
            }
        }
    }
    private func refresh(force: Bool = false) async {
        guard let id = dataManager.athlete?.id else { return }
        await store.refresh(athleteID: id, force: force)
    }
}

#endif
