//
//  AnalysisView.swift
//  Runaway iOS
//
//  Created by Jack Rudelic on 6/27/25.
//


import SwiftUI
import Charts
import Foundation

struct AnalysisView: View {
    @Environment(DataManager.self) var dataManager
    @StateObject private var analyzer = RunningAnalyzer()

    var body: some View {
        ZStack {
            (AppTheme.Colors.adaptiveBackground).ignoresSafeArea()

            if dataManager.activities.isEmpty {
                EmptyAnalysisStateView()
            } else {
                ScrollView {
                    LazyVStack(spacing: AppTheme.Spacing.lg) {
                        // Performance Dashboard - Week vs Week
                        PerformanceDashboardCard(activities: dataManager.activities)

                        // Monthly Progress Ring
                        MonthlyProgressRing(activities: dataManager.activities)

                        // AI Analysis Status/Results
                        if analyzer.isAnalyzing {
                            AnalysisLoadingCard()
                        } else if let results = analyzer.analysisResults {
                            QuickInsightsCard(results: results)
                        } else {
                            AnalysisPromptCard {
                                Task {
                                    await analyzer.analyzePerformance(activities: dataManager.activities)
                                }
                            }
                        }

                        // Activity Heatmap
                        ActivityHeatmapCard(activities: dataManager.activities)

                        // Pace Trends Chart
                        PaceTrendsChart(activities: dataManager.activities)

                        // Running Goal Card (if exists)
                        if dataManager.currentGoal != nil || analyzer.analysisResults?.insights.goalReadiness != nil {
                            RunningGoalCard(activities: dataManager.activities, goalReadiness: analyzer.analysisResults?.insights.goalReadiness)
                        }

                        // Full AI Analysis Results (if available)
                        if let results = analyzer.analysisResults {
                            DetailedAnalysisResultsView(results: results, activities: dataManager.activities)
                        }
                    }
                    .padding(AppTheme.Spacing.md)
                }
            }
        }
        .task {
            if analyzer.analysisResults == nil && !dataManager.activities.isEmpty {
                await analyzer.analyzePerformance(activities: dataManager.activities)
            }
        }
        .refreshable {
            Task {
                await dataManager.refreshActivities()
                if !dataManager.activities.isEmpty {
                    await analyzer.analyzePerformance(activities: dataManager.activities)
                }
            }
        }
    }
}

// MARK: - Empty Analysis State

struct EmptyAnalysisStateView: View {
    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 80))
                .foregroundColor(AppTheme.Colors.accent)

            VStack(spacing: AppTheme.Spacing.sm) {
                Text("No Data to Analyze")
                    .font(AppTheme.Typography.title)
                    .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

                Text("Start logging activities to see detailed analytics and insights about your performance.")
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(AppTheme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Analysis Loading Card

struct AnalysisLoadingCard: View {
    @State private var animationPhase = 0.0

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            ZStack {
                Circle()
                    .stroke(AppTheme.Colors.adaptiveCardBackground, lineWidth: 4)
                    .frame(width: 40, height: 40)

                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(AppTheme.Colors.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 40, height: 40)
                    .rotationEffect(.degrees(animationPhase))
                    .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: animationPhase)
            }

            Text("Analyzing...")
                .font(AppTheme.Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

            Text("Generating AI insights")
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(AppTheme.Spacing.lg)
        .background(AppTheme.Colors.adaptiveCardBackground)
        .cornerRadius(AppTheme.CornerRadius.large)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .onAppear {
            animationPhase = 360
        }
    }
}

// MARK: - Analysis Prompt Card

struct AnalysisPromptCard: View {
    let onAnalyze: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 32))
                .foregroundColor(AppTheme.Colors.accent)

            Text("AI Analysis")
                .font(AppTheme.Typography.headline)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

            Text("Get personalized insights about your training")
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                .multilineTextAlignment(.center)

            Button(action: onAnalyze) {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Analyze")
                }
                .font(AppTheme.Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.Colors.pine)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(AppTheme.Colors.strideLime)
                .cornerRadius(AppTheme.CornerRadius.medium)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(AppTheme.Spacing.lg)
        .background(AppTheme.Colors.adaptiveCardBackground)
        .cornerRadius(AppTheme.CornerRadius.large)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Quick Insights Card

struct QuickInsightsCard: View {
    let results: AnalysisResults

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.orange)
                Text("AI Insights")
                    .font(AppTheme.Typography.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
            }

            if !results.insights.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    ForEach(results.insights.recommendations.prefix(2), id: \.self) { recommendation in
                        HStack(alignment: .top, spacing: AppTheme.Spacing.xs) {
                            Circle()
                                .fill(AppTheme.Colors.accent)
                                .frame(width: 4, height: 4)
                                .padding(.top, 6)

                            Text(recommendation)
                                .font(AppTheme.Typography.caption)
                                .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                                .lineLimit(2)
                        }
                    }
                }
            }

            Text("Updated \(results.lastUpdated, style: .relative) ago")
                .font(.caption2)
                .foregroundColor(AppTheme.Colors.adaptiveTextTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .padding(AppTheme.Spacing.lg)
        .background(AppTheme.Colors.adaptiveCardBackground)
        .cornerRadius(AppTheme.CornerRadius.large)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Detailed Analysis Results

struct DetailedAnalysisResultsView: View {
    let results: AnalysisResults
    let activities: [Activity]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("Detailed Analysis")
                .font(AppTheme.Typography.title)
                .fontWeight(.bold)
                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

            LazyVStack(spacing: AppTheme.Spacing.md) {
                // Recommendations
                RecommendationsCard(recommendations: results.insights.recommendations)

                // Performance Overview
                PerformanceOverviewCard(insights: results.insights)

                // Weekly Volume Chart
                WeeklyVolumeChart(weeklyData: results.insights.weeklyVolume)

                // Performance Trend
                PerformanceTrendCard(insights: results.insights)

                // Next Run Prediction
                if let prediction = results.insights.nextRunPrediction {
                    NextRunPredictionCard(prediction: prediction)
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppTheme.Colors.adaptiveCardBackground)
        .cornerRadius(AppTheme.CornerRadius.large)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct EnhancedAnalysisLoadingView: View {
    @State private var animationPhase = 0.0
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            ZStack {
                Circle()
                    .stroke(AppTheme.Colors.adaptiveCardBackground, lineWidth: 8)
                    .frame(width: 80, height: 80)
                
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(AppTheme.Colors.accentGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(animationPhase))
                    .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: animationPhase)
                
                Image(systemName: AppIcons.analyze)
                    .font(.title2)
                    .foregroundColor(AppTheme.Colors.accent)
            }
            
            VStack(spacing: AppTheme.Spacing.sm) {
                Text("Analyzing Performance")
                    .font(AppTheme.Typography.title)
                    .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
                
                Text("Preparing private insights from your running data on this device")
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
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

struct EnhancedEmptyAnalysisView: View {
    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.accentGradient)
                    .frame(width: 120, height: 120)
                    .shadow(color: AppTheme.Colors.accent.opacity(0.3), radius: 20, x: 0, y: 10)
                
                Image(systemName: AppIcons.analysis)
                    .font(.system(size: 40))
                    .foregroundColor(AppTheme.Colors.pine)
            }
            
            VStack(spacing: AppTheme.Spacing.sm) {
                Text("Ready to Analyze")
                    .font(AppTheme.Typography.title)
                    .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
                
                Text("Tap 'Analyze' to generate AI insights and discover patterns in your running performance")
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                FeatureItem(icon: "brain.head.profile", text: "On-device performance analysis")
                FeatureItem(icon: "chart.line.uptrend.xyaxis", text: "Trend identification and predictions")
                FeatureItem(icon: "lightbulb", text: "Personalized training recommendations")
            }
            .padding(.top, AppTheme.Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Spacing.xxl)
    }
}

struct FeatureItem: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .foregroundColor(AppTheme.Colors.accent)
                .font(.title3)
                .frame(width: 24)
            
            Text(text)
                .font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
        }
    }
}

struct AnalysisResultsView: View {
    let results: AnalysisResults
    let activities: [Activity]
    
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            // Recommendations
            RecommendationsCard(recommendations: results.insights.recommendations)
            
            // Goal Readiness Analysis
            if let goalReadiness = results.insights.goalReadiness {
                GoalReadinessCard(goalReadiness: goalReadiness)
            }
            
            // Performance Overview
            PerformanceOverviewCard(insights: results.insights)
            
            // Weekly Volume Chart
            WeeklyVolumeChart(weeklyData: results.insights.weeklyVolume)
            
            // Performance Trend
            PerformanceTrendCard(insights: results.insights)
            
            // Next Run Prediction
            if let prediction = results.insights.nextRunPrediction {
                NextRunPredictionCard(prediction: prediction)
            }
            
            // Last Updated
            Text("Last updated: \(results.lastUpdated, style: .relative) ago")
                .font(.caption)
                .foregroundColor(AppTheme.Colors.textSecondary)
                .padding(.top)
        }
    }
}

struct PerformanceOverviewCard: View {
    let insights: RunningInsights
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Overview")
                .font(.title2)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                MetricBox(
                    title: "Total Distance",
                    value: String(format: "%.1f mi", insights.totalDistance),
                    icon: "road.lanes"
                )
                
                MetricBox(
                    title: "Avg Pace",
                    value: formatPace(insights.averagePace),
                    icon: "speedometer"
                )
                
                MetricBox(
                    title: "Total Time",
                    value: formatTime(insights.totalTime),
                    icon: "clock"
                )
                
                MetricBox(
                    title: "Consistency",
                    value: String(format: "%.0f%%", insights.consistency),
                    icon: "calendar"
                )
            }
        }
        .padding()
        .background(AppTheme.Colors.adaptiveCardBackground)
        .cornerRadius(12)
    }
}

struct MetricBox: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Spacer()
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.adaptiveCardBackground)
        .cornerRadius(AppTheme.CornerRadius.small)
    }
}

struct WeeklyVolumeChart: View {
    let weeklyData: [WeeklyVolume]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Volume Trend")
                .font(.title2)
                .fontWeight(.semibold)
            
            if !weeklyData.isEmpty {
                Chart {
                    ForEach(weeklyData, id: \.weekStart) { week in
                        BarMark(
                            x: .value("Week", week.weekStart),
                            y: .value("Distance (mi)", week.totalDistance)
                        )
                        .foregroundStyle(.blue.gradient)
                    }
                }
                .frame(height: 200)
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let distance = value.as(Double.self) {
                                Text(String(format: "%.0f mi", distance))
                                    .font(.caption2)
                            }
                        }
                    }
                }
            } else {
                Text("Not enough data for weekly analysis")
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .frame(height: 100)
            }
        }
        .padding()
        .background(AppTheme.Colors.adaptiveCardBackground)
        .cornerRadius(12)
    }
}

struct PerformanceTrendCard: View {
    let insights: RunningInsights
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Trend")
                .font(.title2)
                .fontWeight(.semibold)
            
            HStack {
                Image(systemName: trendIcon)
                    .foregroundColor(trendColor)
                    .font(.title)
                
                VStack(alignment: .leading) {
                    Text(insights.performanceTrend.description)
                        .font(.headline)
                        .foregroundColor(trendColor)
                    
                    Text(trendDescription)
                        .font(.subheadline)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(AppTheme.Colors.adaptiveCardBackground)
        .cornerRadius(12)
    }
    
    private var trendIcon: String {
        switch insights.performanceTrend {
        case .improving: return "arrow.up.circle.fill"
        case .stable: return "minus.circle.fill"
        case .declining: return "arrow.down.circle.fill"
        }
    }
    
    private var trendColor: Color {
        switch insights.performanceTrend {
        case .improving: return .green
        case .stable: return .blue
        case .declining: return .red
        }
    }
    
    private var trendDescription: String {
        switch insights.performanceTrend {
        case .improving: return "Your pace has been getting faster"
        case .stable: return "Your performance is consistent"
        case .declining: return "Your pace has been slower recently"
        }
    }
}

struct NextRunPredictionCard: View {
    let prediction: PaceRange
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Next Run Prediction")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(spacing: 8) {
                PredictionRow(
                    label: "Expected Pace",
                    pace: prediction.expected,
                    color: .blue
                )
                
                HStack {
                    PredictionRow(
                        label: "Best Case",
                        pace: prediction.fastest,
                        color: .green
                    )
                    
                    Spacer()
                    
                    PredictionRow(
                        label: "Conservative",
                        pace: prediction.slowest,
                        color: .orange
                    )
                }
            }
        }
        .padding()
        .background(AppTheme.Colors.adaptiveCardBackground)
        .cornerRadius(12)
    }
}

struct PredictionRow: View {
    let label: String
    let pace: Double
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            Text(formatPace(pace))
                .font(.headline)
                .foregroundColor(color)
        }
    }
}

struct RecommendationsCard: View {
    let recommendations: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Recommendations")
                .font(.title2)
                .fontWeight(.semibold)
            
            if recommendations.isEmpty {
                Text("Great job! Keep up your current training.")
                    .foregroundColor(.green)
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(recommendations.enumerated()), id: \.offset) { index, recommendation in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(width: 20, height: 20)
                                .background(Color.blue)
                                .clipShape(Circle())
                            
                            Text(recommendation)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding()
        .background(AppTheme.Colors.adaptiveCardBackground)
        .cornerRadius(12)
    }
}

// MARK: - Goal Readiness Card
struct GoalReadinessCard: View {
    let goalReadiness: GoalReadiness
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Goal Readiness")
                        .font(.headline)
                        .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
                    
                    Text("Marathon Training Assessment")
                        .font(.caption)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                
                Spacer()
                
                // Overall Score Circle
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                        .frame(width: 60, height: 60)
                    
                    Circle()
                        .trim(from: 0, to: goalReadiness.overallScore / 100)
                        .stroke(
                            getScoreColor(goalReadiness.overallScore),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 1.0), value: goalReadiness.overallScore)
                    
                    Text("\(Int(goalReadiness.overallScore))%")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(getScoreColor(goalReadiness.overallScore))
                }
            }
            
            // Readiness Categories
            VStack(spacing: 12) {
                ReadinessRow(
                    title: "Fitness Level",
                    level: goalReadiness.fitnessLevel,
                    icon: "heart.fill"
                )
                
                ReadinessRow(
                    title: "Experience",
                    level: goalReadiness.experienceLevel,
                    icon: "star.fill"
                )
                
                ReadinessRow(
                    title: "Training Volume",
                    level: goalReadiness.volumePreparation,
                    icon: "speedometer"
                )
                
                ReadinessRow(
                    title: "Time Remaining",
                    level: goalReadiness.timeToGoal,
                    icon: "clock.fill"
                )
            }
            
            // Risk Factors (if any)
            if !goalReadiness.riskFactors.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Risk Factors")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                    
                    ForEach(goalReadiness.riskFactors.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                                .padding(.top, 2)
                            
                            Text(goalReadiness.riskFactors[index])
                                .font(.caption)
                                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
                        }
                    }
                }
                .padding(.top, 8)
            }
            
            // Quick Recommendations
            if !goalReadiness.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Key Recommendations")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                    
                    ForEach(goalReadiness.recommendations.prefix(3).indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                                .padding(.top, 2)
                            
                            Text(goalReadiness.recommendations[index])
                                .font(.caption)
                                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(AppTheme.Colors.adaptiveCardBackground)
        .cornerRadius(12)
    }
    
    private func getScoreColor(_ score: Double) -> Color {
        switch score {
        case 80...: return .green
        case 60..<80: return .blue
        case 40..<60: return .orange
        default: return .red
        }
    }
}

struct ReadinessRow: View {
    let title: String
    let level: ReadinessLevel
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(getLevelColor(level))
                .font(.caption)
                .frame(width: 16)
            
            Text(title)
                .font(.caption)
                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
            
            Spacer()
            
            Text(level.displayName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(getLevelColor(level))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(getLevelColor(level).opacity(0.2))
                .cornerRadius(6)
        }
    }
    
    private func getLevelColor(_ level: ReadinessLevel) -> Color {
        switch level {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .orange
        case .poor: return .red
        }
    }
}

// MARK: - Progress Overview Card
struct ProgressOverviewCard: View {
    let activities: [Activity]
    @State private var cachedTotalMiles: Double = 0.0
    private let metricsCache = ActivityMetricsCache()

    // Calculate monthly miles from activities with caching
    private func calculateMonthlyMiles() -> Double {
        let currentMonth = Calendar.current.component(.month, from: Date())
        let currentYear = Calendar.current.component(.year, from: Date())

        #if DEBUG
        print("📊 AnalysisView: Calculating monthly miles - Total activities: \(activities.count)")
        print("📊 AnalysisView: Current month: \(currentMonth), year: \(currentYear)")
        #endif

        // Filter activities for current month only
        let monthlyActivities = activities.filter { activity in
            // Use activity_date if available, otherwise fall back to start_date
            let dateInterval = activity.activity_date ?? activity.start_date
            guard let dateInterval = dateInterval else { return false }
            let activityDate = Date(timeIntervalSince1970: dateInterval)
            return Calendar.current.component(.month, from: activityDate) == currentMonth &&
                   Calendar.current.component(.year, from: activityDate) == currentYear
        }

        #if DEBUG
        print("📊 AnalysisView: Monthly activities found: \(monthlyActivities.count)")
        #endif

        // Calculate monthly miles
        let activitiesWithDistance = monthlyActivities.compactMap { activity -> Double? in
            return activity.distance
        }

        let totalMeters = activitiesWithDistance.reduce(0, +)
        let miles = totalMeters * 0.000621371 // Convert meters to miles

        #if DEBUG
        print("📊 AnalysisView: Monthly miles calculated: \(miles)")
        #endif

        return miles
    }

    private var totalMiles: Double {
        return cachedTotalMiles
    }
    
    private var currentProgress: Double {
        // 50 miles/week = 200 miles/month goal
        let monthlyGoal = 200.0
        return min(totalMiles / monthlyGoal, 1.0)
    }
    
    private var targetProgress: Double { 
        // Calculate expected progress based on days into the month
        let calendar = Calendar.current
        let now = Date()
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let dayOfMonth = calendar.component(.day, from: now)
        
        return Double(dayOfMonth) / Double(daysInMonth)
    }
    
    private var progressColor: Color {
        let ratio = currentProgress / max(targetProgress, 0.01)
        if ratio >= 1.0 { return .green }
        if ratio >= 0.8 { return .blue }
        if ratio >= 0.6 { return .orange }
        return .red
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Monthly Distance Progress")
                .font(.headline)
                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
            
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 20)
                    .frame(width: 160, height: 160)
                
                // Target progress ring (outer)
                Circle()
                    .trim(from: 0, to: targetProgress)
                    .stroke(
                        Color.gray.opacity(0.5),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                
                // Actual progress ring (inner)
                Circle()
                    .trim(from: 0, to: currentProgress)
                    .stroke(
                        LinearGradient(
                            colors: [progressColor.opacity(0.7), progressColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1.0), value: currentProgress)
                
                // Center content
                VStack(spacing: 4) {
                    Text(String(format: "%.1f", totalMiles))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(progressColor)
                    
                    Text("Miles")
                        .font(.caption)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            
            // Progress details
            VStack(spacing: 8) {
                HStack {
                    Circle()
                        .fill(progressColor)
                        .frame(width: 12, height: 12)
                    Text("Current Distance")
                        .font(.caption)
                        .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
                    Spacer()
                    Text(String(format: "%.1f mi", totalMiles))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
                }
                
                HStack {
                    Circle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 12, height: 12)
                    Text("Monthly Goal")
                        .font(.caption)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    Spacer()
                    Text("200.0 mi")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                
                let ratio = currentProgress / targetProgress
                let statusText = ratio >= 1.0 ? "Ahead of Target" : ratio >= 0.8 ? "On Track" : "Behind Target"
                let statusColor = ratio >= 1.0 ? Color.green : ratio >= 0.8 ? Color.blue : Color.orange
                
                HStack {
                    Image(systemName: ratio >= 1.0 ? "checkmark.circle.fill" : ratio >= 0.8 ? "clock.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(statusColor)
                        .font(.caption)
                    Text(statusText)
                        .font(.caption.weight(.medium))
                        .foregroundColor(statusColor)
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
        .padding()
        .background(AppTheme.Colors.adaptiveCardBackground)
        .cornerRadius(12)
        .onAppear {
            // Calculate monthly miles when view appears
            cachedTotalMiles = calculateMonthlyMiles()
        }
        .onChange(of: activities.count) { _, _ in
            // Recalculate when activities change
            cachedTotalMiles = calculateMonthlyMiles()
        }
    }
}

// MARK: - Helper Functions
private func formatPace(_ pace: Double) -> String {
    let minutes = Int(pace)
    let seconds = Int((pace - Double(minutes)) * 60)
    return String(format: "%d:%02d/mi", minutes, seconds)
}

private func formatTime(_ timeInMinutes: Double) -> String {
    let hours = Int(timeInMinutes / 60)
    let minutes = Int(timeInMinutes.truncatingRemainder(dividingBy: 60))
    
    if hours > 0 {
        return String(format: "%dh %dm", hours, minutes)
    } else {
        return String(format: "%dm", minutes)
    }
}
