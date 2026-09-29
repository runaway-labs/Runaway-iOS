//
//  InsightsSections.swift
//  Runaway iOS
//
//  Section components for Unified Insights View
//

import SwiftUI
import Charts

// MARK: - Section 1: Hero Stats Section (with Adaptive Primary Insight)

struct HeroStatsSection: View {
    let quickWinsData: QuickWinsResponse?
    let activities: [Activity]
    let phaseContext: TrainingPhaseContext?

    init(quickWinsData: QuickWinsResponse?, activities: [Activity] = [], phaseContext: TrainingPhaseContext? = nil) {
        self.quickWinsData = quickWinsData
        self.activities = activities
        self.phaseContext = phaseContext
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            // Show adaptive card if we have phase context, otherwise show legacy carousel
            if let context = phaseContext {
                AdaptivePrimaryInsightCard(
                    phaseContext: context,
                    activities: activities,
                    trainingLoad: quickWinsData?.analyses.trainingLoad,
                    racePredictions: quickWinsData?.analyses.vo2maxEstimate?.racePredictions
                )
                .padding(.horizontal)
            } else {
                // Legacy view
                Text("At a Glance")
                    .font(AppTheme.Typography.headline)
                    .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
                    .padding(.horizontal)

                if let data = quickWinsData {
                    QuickStatsCarousel(data: data)
                }
            }
        }
    }
}

// MARK: - Section 2: Priority Insights Section

struct PriorityInsightsSection: View {
    let recommendations: [String]
    let performanceTrend: PerformanceTrend?
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Performance Status Badge
            if let trend = performanceTrend {
                PerformanceStatusBadge(trend: trend)
            }

            // Unified Recommendations
            if !recommendations.isEmpty {
                UnifiedRecommendationsBanner(
                    recommendations: recommendations,
                    isExpanded: $isExpanded
                )
            }
        }
    }
}

struct PerformanceStatusBadge: View {
    let trend: PerformanceTrend

    var body: some View {
        HStack {
            Image(systemName: trendIcon)
                .font(.title)
                .foregroundColor(trendColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("Performance Trend")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)

                Text(trend.description)
                    .font(AppTheme.Typography.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(trendColor)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(AppTheme.Colors.adaptiveTextTertiary)
        }
        .padding()
        .background(trendColor.opacity(0.1))
        .cornerRadius(AppTheme.CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                .stroke(trendColor.opacity(0.3), lineWidth: 1)
        )
    }

    private var trendIcon: String {
        switch trend {
        case .improving: return "arrow.up.circle.fill"
        case .stable: return "minus.circle.fill"
        case .declining: return "arrow.down.circle.fill"
        }
    }

    private var trendColor: Color {
        switch trend {
        case .improving: return .green
        case .stable: return .blue
        case .declining: return .orange
        }
    }
}

struct UnifiedRecommendationsBanner: View {
    let recommendations: [String]
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(AppTheme.Colors.accent)
                Text("Recommendations")
                    .font(AppTheme.Typography.headline)
                    .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
                Spacer()
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                }
            }

            ForEach(Array(recommendations.prefix(isExpanded ? recommendations.count : 3).enumerated()), id: \.offset) { index, recommendation in
                HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                    Text("\(index + 1)")
                        .font(AppTheme.Typography.caption)
                        .fontWeight(.bold)
                        .foregroundColor(AppTheme.Colors.pine)
                        .frame(width: 20, height: 20)
                        .background(AppTheme.Colors.strideLime)
                        .clipShape(Circle())

                    Text(recommendation)
                        .font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()
                }
            }

            if !isExpanded && recommendations.count > 3 {
                Button(action: { isExpanded = true }) {
                    Text("See \(recommendations.count - 3) more")
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.accent)
                }
            }
        }
        .padding()
        .background(AppTheme.Colors.adaptiveCardBackground)
        .cornerRadius(AppTheme.CornerRadius.large)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Section 3: Performance at a Glance Section

struct PerformanceGlanceSection: View {
    let activities: [Activity]
    let quickWinsData: QuickWinsResponse?

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Week vs Week Comparison
            PerformanceDashboardCard(activities: activities)
        }
    }
}

// MARK: - Section 4: Deep Dive Navigation Grid

struct DeepDiveNavigationGrid: View {
    let quickWinsData: QuickWinsResponse?
    let onWeatherTap: () -> Void
    let onVO2MaxTap: () -> Void
    let onTrainingLoadTap: () -> Void
    let onActivityTrendsTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Deep Dive Analysis")
                .font(AppTheme.Typography.headline)
                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.Spacing.md) {
                if let weather = quickWinsData?.analyses.weatherContext {
                    DeepDiveCard(
                        title: "Weather Impact",
                        subtitle: weather.weatherImpactScore.capitalized,
                        icon: "cloud.sun.fill",
                        color: colorForWeatherImpact(weather.weatherImpactScore),
                        action: onWeatherTap
                    )
                }

                if let vo2max = quickWinsData?.analyses.vo2maxEstimate {
                    DeepDiveCard(
                        title: "Race Predictions",
                        subtitle: "\(vo2max.racePredictions.count) Distances",
                        icon: "flag.fill",
                        color: .blue,
                        action: onVO2MaxTap
                    )
                }

                if let trainingLoad = quickWinsData?.analyses.trainingLoad {
                    DeepDiveCard(
                        title: "Training Load",
                        subtitle: trainingLoad.injuryRiskDisplay,
                        icon: "chart.line.uptrend.xyaxis",
                        color: colorForInjuryRisk(trainingLoad.injuryRiskLevel),
                        action: onTrainingLoadTap
                    )
                }

                DeepDiveCard(
                    title: "Activity Trends",
                    subtitle: "Pace & Heatmap",
                    icon: "chart.xyaxis.line",
                    color: .purple,
                    action: onActivityTrendsTap
                )
            }
        }
    }

    private func colorForWeatherImpact(_ score: String) -> Color {
        switch score {
        case "minimal": return .green
        case "moderate": return .orange
        case "significant": return .red
        case "severe": return .purple
        default: return .gray
        }
    }

    private func colorForInjuryRisk(_ risk: String) -> Color {
        switch risk {
        case "low": return .green
        case "moderate": return .orange
        case "high": return .red
        case "very_high": return .purple
        default: return .gray
        }
    }
}

struct DeepDiveCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(color)
                    Spacer()
                }

                Text(title)
                    .font(AppTheme.Typography.headline)
                    .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

                Text(subtitle)
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
            .padding()
            .background(color.opacity(0.1))
            .cornerRadius(AppTheme.CornerRadius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Section 5: Charts Section

struct ChartsSection: View {
    let activities: [Activity]
    let weeklyData: [WeeklyVolume]

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Pace Trends Chart
            PaceTrendsChart(activities: activities)

            // Weekly Volume Chart
            if !weeklyData.isEmpty {
                WeeklyVolumeChart(weeklyData: weeklyData)
            }

            // Activity Heatmap
            ActivityHeatmapCard(activities: activities)
        }
    }
}

// MARK: - Section 6: Goal & Readiness Section

struct GoalReadinessSection: View {
    let activities: [Activity]
    let goalReadiness: GoalReadiness?
    let nextRunPrediction: PaceRange?

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Running Goal Card
            RunningGoalCard(activities: activities, goalReadiness: goalReadiness)

            // Goal Readiness
            if let goalReadiness = goalReadiness {
                GoalReadinessCard(goalReadiness: goalReadiness)
            }

            // Next Run Prediction
            if let prediction = nextRunPrediction {
                NextRunPredictionCard(prediction: prediction)
            }
        }
    }
}

// MARK: - Weekly Training Plan Section

struct WeeklyPlanSection: View {
    @Environment(DataManager.self) var dataManager
    @State private var isLoading = false
    @State private var isGenerating = false
    @State private var selectedWorkout: DailyWorkout?
    @State private var selectedEntry: WeekDayEntry?

    /// Use the plan from DataManager (which handles regeneration)
    private var weeklyPlan: WeeklyTrainingPlan? {
        dataManager.currentWeeklyPlan
    }

    /// Merged entries combining plan with actual activities
    private var weekEntries: [WeekDayEntry] {
        guard let plan = weeklyPlan else { return [] }
        return plan.mergedWithActivities(dataManager.activities)
    }

    /// Week stats comparing planned vs actual
    private var weekStats: (plannedMiles: Double, actualMiles: Double, completedWorkouts: Int, plannedWorkouts: Int)? {
        guard let plan = weeklyPlan else { return nil }
        return plan.weekStats(with: dataManager.activities)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // Header
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(AppTheme.Colors.accent)
                Text("This Week's Plan")
                    .font(AppTheme.Typography.headline)
                    .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

                // Show regenerating indicator
                if dataManager.isRegeneratingPlan {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Adapting...")
                            .font(.caption2)
                            .foregroundColor(AppTheme.Colors.accent)
                    }
                }

                Spacer()

                if let plan = weeklyPlan {
                    Text(plan.weekRangeString)
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                }
            }
            .padding(.horizontal)

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding()
            } else if weeklyPlan != nil {
                // Week summary with actual vs planned
                if let stats = weekStats {
                    HStack(spacing: AppTheme.Spacing.md) {
                        // Actual vs Planned Miles
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                Text(String(format: "%.1f", stats.actualMiles))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(AppTheme.Colors.accent)
                                Text("/")
                                    .font(.caption)
                                    .foregroundColor(AppTheme.Colors.adaptiveTextTertiary)
                                Text(String(format: "%.0f mi", stats.plannedMiles))
                                    .font(.caption)
                                    .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                            }
                            Text("Miles")
                                .font(.caption2)
                                .foregroundColor(AppTheme.Colors.adaptiveTextTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(AppTheme.Colors.adaptiveSurfaceBackground)
                        .cornerRadius(8)

                        // Completed Workouts
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                Text("\(stats.completedWorkouts)")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.green)
                                Text("/")
                                    .font(.caption)
                                    .foregroundColor(AppTheme.Colors.adaptiveTextTertiary)
                                Text("\(stats.plannedWorkouts)")
                                    .font(.caption)
                                    .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                            }
                            Text("Completed")
                                .font(.caption2)
                                .foregroundColor(AppTheme.Colors.adaptiveTextTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(AppTheme.Colors.adaptiveSurfaceBackground)
                        .cornerRadius(8)

                        // Progress Ring
                        let progress = stats.plannedWorkouts > 0 ? Double(stats.completedWorkouts) / Double(stats.plannedWorkouts) : 0
                        VStack(spacing: 2) {
                            ZStack {
                                Circle()
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                                    .frame(width: 28, height: 28)
                                Circle()
                                    .trim(from: 0, to: progress)
                                    .stroke(AppTheme.Colors.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                    .frame(width: 28, height: 28)
                                    .rotationEffect(.degrees(-90))
                            }
                            Text("\(Int(progress * 100))%")
                                .font(.caption2)
                                .foregroundColor(AppTheme.Colors.adaptiveTextTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(AppTheme.Colors.adaptiveSurfaceBackground)
                        .cornerRadius(8)
                    }
                    .padding(.horizontal)
                }

                // Daily entries (merged with activities)
                VStack(spacing: 8) {
                    ForEach(weekEntries) { entry in
                        WeekDayRow(entry: entry) {
                            selectedEntry = entry
                            selectedWorkout = entry.plannedWorkout
                        }
                    }
                }
                .padding(.horizontal)

                if let notes = weeklyPlan?.notes {
                    Text(notes)
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }
            } else {
                // Empty State with Generate button
                VStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 40))
                        .foregroundColor(AppTheme.Colors.accent.opacity(0.6))

                    Text("No plan for this week")
                        .font(AppTheme.Typography.subheadline)
                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)

                    Button(action: { Task { await generatePlan() } }) {
                        HStack {
                            if isGenerating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(isGenerating ? "Generating..." : "Generate Plan")
                        }
                        .font(AppTheme.Typography.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(AppTheme.Colors.pine)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(AppTheme.Colors.strideLime)
                        .cornerRadius(AppTheme.CornerRadius.medium)
                    }
                    .disabled(isGenerating)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppTheme.Colors.adaptiveCardBackground)
        .cornerRadius(AppTheme.CornerRadius.large)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        .sheet(item: $selectedWorkout) { workout in
            WorkoutDetailSheet(workout: workout)
        }
        .task {
            await loadPlan()
        }
    }

    private func loadPlan() async {
        isLoading = true

        // Load plan through DataManager (handles caching and regeneration checks)
        await dataManager.loadCurrentWeeklyPlan()

        // Also check if regeneration is needed based on current activities
        await dataManager.checkAndRegeneratePlanIfNeeded()

        isLoading = false
    }

    private func generatePlan() async {
        guard let userId = UserSession.shared.userId else { return }
        isGenerating = true

        do {
            let plan = try await TrainingPlanService.generateWeeklyPlan(
                athleteId: userId,
                goal: dataManager.currentGoal
            )
            // The service persists successfully before the active plan is published.
            dataManager.currentWeeklyPlan = plan
        } catch {
            #if DEBUG
            print("Failed to generate plan: \(error)")
            #endif
        }

        isGenerating = false
    }
}

// MARK: - Week Day Row (shows planned workout OR actual activity)

struct WeekDayRow: View {
    let entry: WeekDayEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Day indicator
                VStack {
                    Text(entry.dayOfWeek.shortName)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(dayTextColor)
                }
                .frame(width: 36, height: 36)
                .background(dayBackgroundColor)
                .cornerRadius(8)

                // Icon (checkmark for completed, workout type for planned)
                Image(systemName: entry.icon)
                    .font(.subheadline)
                    .foregroundColor(entry.iconColor)
                    .frame(width: 20)

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(entry.displayTitle)
                            .font(AppTheme.Typography.subheadline)
                            .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
                            .lineLimit(1)
                            .strikethrough(entry.isPast && !entry.isCompleted && entry.plannedWorkout != nil)

                        if let status = entry.statusText {
                            Text(status)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(statusColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(statusColor.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }

                    // Show actual pace if completed
                    if let pace = entry.formattedPace {
                        Text(pace)
                            .font(.caption2)
                            .foregroundColor(AppTheme.Colors.adaptiveTextTertiary)
                    }
                }

                Spacer()

                // Distance or duration
                if let distance = entry.formattedDistance {
                    Text(distance)
                        .font(AppTheme.Typography.caption)
                        .fontWeight(entry.isCompleted ? .semibold : .regular)
                        .foregroundColor(entry.isCompleted ? .green : AppTheme.Colors.adaptiveTextSecondary)
                } else if let duration = entry.formattedDuration {
                    Text(duration)
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                }

                if entry.plannedWorkout != nil || entry.actualActivity != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(AppTheme.Colors.adaptiveTextTertiary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(rowBackgroundColor)
            .cornerRadius(AppTheme.CornerRadius.small)
        }
        .buttonStyle(.plain)
    }

    private var dayTextColor: Color {
        if entry.isToday {
            return .white
        }
        if entry.isCompleted {
            return .green
        }
        return AppTheme.Colors.adaptiveTextSecondary
    }

    private var dayBackgroundColor: Color {
        if entry.isToday {
            return AppTheme.Colors.accent
        }
        if entry.isCompleted {
            return Color.green.opacity(0.15)
        }
        return AppTheme.Colors.adaptiveSurfaceBackground
    }

    private var rowBackgroundColor: Color {
        if entry.isCompleted {
            return Color.green.opacity(0.05)
        }
        if entry.isPast && entry.plannedWorkout != nil {
            return Color.orange.opacity(0.05)
        }
        return AppTheme.Colors.adaptiveSurfaceBackground
    }

    private var statusColor: Color {
        if entry.isCompleted {
            return .green
        }
        if entry.isPast && entry.plannedWorkout != nil {
            return .orange
        }
        if entry.isToday {
            return AppTheme.Colors.accent
        }
        return .gray
    }
}

// MARK: - Compact Workout Row

struct CompactWorkoutRow: View {
    let workout: DailyWorkout
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Day
                VStack {
                    Text(workout.dayOfWeek.shortName)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(isToday ? .white : AppTheme.Colors.adaptiveTextSecondary)
                }
                .frame(width: 36, height: 36)
                .background(isToday ? AppTheme.Colors.accent : AppTheme.Colors.adaptiveSurfaceBackground)
                .cornerRadius(8)

                // Workout type icon
                Image(systemName: workout.workoutType.icon)
                    .font(.subheadline)
                    .foregroundColor(workout.workoutType.color)
                    .frame(width: 20)

                // Title
                Text(workout.title)
                    .font(AppTheme.Typography.subheadline)
                    .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
                    .lineLimit(1)

                Spacer()

                // Distance or duration
                if let distance = workout.formattedDistance {
                    Text(distance)
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                } else if let duration = workout.formattedDuration {
                    Text(duration)
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(AppTheme.Colors.adaptiveTextTertiary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(AppTheme.Colors.adaptiveSurfaceBackground)
            .cornerRadius(AppTheme.CornerRadius.small)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(workout.date)
    }
}

// MARK: - Plan Stat Pill

struct PlanStatPill: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(AppTheme.Colors.accent)
            Text(value)
                .font(AppTheme.Typography.headline)
                .fontWeight(.bold)
                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
            Text(label)
                .font(.caption2)
                .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Legacy Training Journal Section (deprecated)

struct TrainingJournalSection: View {
    let journal: TrainingJournal?

    var body: some View {
        // Replaced by WeeklyPlanSection
        EmptyView()
    }
}

// MARK: - Supporting Components

struct WeekStatsGrid: View {
    let stats: WeekStats

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.Spacing.md) {
            JournalStatBox(icon: "figure.run", title: "Distance", value: String(format: "%.1f mi", stats.totalDistance))
            JournalStatBox(icon: "timer", title: "Time", value: String(format: "%.1f hrs", stats.totalTime))
            JournalStatBox(icon: "speedometer", title: "Avg Pace", value: stats.avgPace)
            JournalStatBox(icon: "flame.fill", title: "Runs", value: "\(stats.activitiesCount)")
        }
    }
}

struct JournalStatBox: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: icon)
                .foregroundColor(AppTheme.Colors.accent)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                Text(value)
                    .font(AppTheme.Typography.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
            }
            Spacer()
        }
        .padding(AppTheme.Spacing.sm)
        .background(AppTheme.Colors.adaptiveSurfaceBackground)
        .cornerRadius(AppTheme.CornerRadius.small)
    }
}

struct InsightRow: View {
    let insight: JournalInsight

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            Image(systemName: insight.type.icon)
                .foregroundColor(insightColor)
                .font(.caption)
                .frame(width: 24)

            Text(insight.text)
                .font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }

    private var insightColor: Color {
        switch insight.type.color {
        case "yellow": return .yellow
        case "blue": return .blue
        case "green": return .green
        case "purple": return .purple
        default: return .gray
        }
    }
}
