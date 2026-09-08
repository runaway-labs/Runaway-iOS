//
//  TrainingView.swift
//  Runaway iOS
//
//  Training view with streamlined hierarchy:
//  Earned progress → Next Up → Context → Details
//
//  Based on UX research for athletic apps:
//  - Eastern Peak fitness app best practices
//  - Output Sports athlete monitoring dashboards
//  - Strava case study by Samantha Marin
//

import SwiftUI

struct TrainingView: View {
    @Environment(DataManager.self) var dataManager
    @EnvironmentObject private var trainingProfileStore: TrainingProfileStore
    @State private var selectedActivity: LocalActivity?
    let onSeeAllActivities: () -> Void

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 12 ? "Morning" : hour < 17 ? "Afternoon" : "Evening"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(Date(), format: .dateTime.weekday(.wide).month(.abbreviated).day())
                            .font(.subheadline).foregroundStyle(TrainingProgressStyle.secondary)
                        Text("\(greeting), \(dataManager.athlete?.firstname ?? "there")")
                            .font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(.white)
                    }
                    Spacer()
                    Text(String((dataManager.athlete?.firstname ?? "R").prefix(1)).uppercased())
                        .font(.system(.headline, design: .rounded)).foregroundStyle(TrainingProgressStyle.amber)
                        .frame(width: 42, height: 42).background(.white.opacity(0.06), in: Circle())
                }.padding(.top, 8)

                TrainingProgressCard()
                TodaysFocusCard()
                ReadinessBanner(compact: true)
                TodayWeatherChip()
                TrainingPersonalizationPromptCard(store: trainingProfileStore)

                if let latest = dataManager.activities.first {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            EyebrowLabel(text: "LATEST WORK")
                            Spacer()
                            Button("See all", action: onSeeAllActivities)
                                .font(.subheadline.weight(.semibold)).foregroundStyle(TrainingProgressStyle.blue)
                                .frame(minHeight: 44)
                        }
                        CardView(activity: toLocal(latest), onTap: { selectedActivity = toLocal(latest) })
                    }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 110)
        }
        .background {
            LinearGradient(colors: [AppTheme.Colors.DarkMode.backgroundElevated, AppTheme.Colors.DarkMode.background], startPoint: .topTrailing, endPoint: .bottomLeading).ignoresSafeArea()
        }
        .navigationBarHidden(true)
        .refreshable {
            await dataManager.refreshActivities()
            if let id = dataManager.athlete?.id { await TrainingProgressStore.shared.refresh(athleteID: id, force: true) }
        }
        .sheet(item: $selectedActivity) { activity in NavigationStack { ActivityDetailView(activity: activity) } }
    }

    private func toLocal(_ activity: Activity) -> LocalActivity {
        LocalActivity(id: activity.id, name: activity.name ?? "Activity", type: activity.type ?? "Other",
            summary_polyline: activity.summary_polyline ?? "", distance: activity.distance ?? 0,
            start_date: (activity.activity_date ?? activity.start_date).map { Date(timeIntervalSince1970: $0) },
            elapsed_time: activity.elapsed_time ?? 0)
    }
}

// MARK: - Empty State

struct EmptyInsightsStateView: View {
    private var colors: (textPrimary: Color, textSecondary: Color) {
        (AppTheme.Colors.adaptiveTextPrimary, AppTheme.Colors.adaptiveTextSecondary)
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 80))
                .foregroundColor(AppTheme.Colors.accent)

            VStack(spacing: AppTheme.Spacing.sm) {
                Text("Your Today view is ready")
                    .font(AppTheme.Typography.title)
                    .foregroundColor(colors.textPrimary)

                Text("Log your first activity to unlock private, on-device guidance and performance trends.")
                    .font(AppTheme.Typography.body)
                    .foregroundColor(colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(AppTheme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Loading State

struct LoadingInsightsStateView: View {
    @State private var animationPhase = 0.0

    private var colors: (textPrimary: Color, textSecondary: Color) {
        (AppTheme.Colors.adaptiveTextPrimary, AppTheme.Colors.adaptiveTextSecondary)
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(AppTheme.Colors.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(animationPhase))
                    .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: animationPhase)
            }

            VStack(spacing: AppTheme.Spacing.sm) {
                Text("Loading Insights")
                    .font(AppTheme.Typography.title)
                    .foregroundColor(colors.textPrimary)

                Text("Analyzing your performance data...")
                    .font(AppTheme.Typography.body)
                    .foregroundColor(colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Spacing.xxl)
        .onAppear {
            animationPhase = 360
        }
    }
}

// MARK: - Preview

struct TrainingView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            TrainingView(onSeeAllActivities: {})
                .environment(DataManager.shared)
                .environmentObject(TrainingProfileStore())
        }
    }
}
