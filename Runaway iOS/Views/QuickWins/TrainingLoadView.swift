//
//  TrainingLoadView.swift
//  Runaway iOS
//
//  Training load and recovery analysis view
//

import SwiftUI

struct TrainingLoadView: View {
    let trainingLoad: TrainingLoadAnalysis
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // ACWR Circular Gauge
                    ACWRCircularGauge(trainingLoad: trainingLoad)

                    // ACWR Zone Indicator
                    ACWRZoneIndicator(trainingLoad: trainingLoad)

                    // Stats Grid (2x2)
                    TrainingStatsGrid(trainingLoad: trainingLoad)

                    // Recovery Status Banner
                    RecoveryStatusBanner(trainingLoad: trainingLoad)

                    // Training Trends Row
                    TrainingTrendsRow(trainingLoad: trainingLoad)

                    // 7-Day Workout Plan
                    SevenDayWorkoutPlan(trainingLoad: trainingLoad)

                    // Recommendations
                    RecommendationsList(
                        recommendations: trainingLoad.recommendations,
                        icon: "chart.bar.fill",
                        iconColor: .blue
                    )
                }
                .padding()
            }
            .tint(AppTheme.Colors.accent)
            .navigationTitle("Training Load")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.Colors.LightMode.accent)
                }
            }
        }
        .tint(AppTheme.Colors.LightMode.accent)
    }
}

// MARK: - ACWR Circular Gauge

struct ACWRCircularGauge: View {
    let trainingLoad: TrainingLoadAnalysis

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 20)
                    .frame(width: 200, height: 200)

                // Progress circle
                Circle()
                    .trim(from: 0, to: progressValue)
                    .stroke(acwrColor, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1.0), value: progressValue)

                // Center value
                VStack(spacing: 4) {
                    Text(String(format: "%.2f", trainingLoad.acwr))
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(acwrColor)

                    Text("ACWR")
                        .font(.caption)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }

            // Risk Level
            Text(trainingLoad.injuryRiskDisplay)
                .font(.headline)
                .foregroundColor(riskColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(riskColor.opacity(0.2))
                .cornerRadius(20)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var progressValue: Double {
        // Scale ACWR to 0-1 range (0.5 to 2.0 -> 0 to 1)
        let minACWR = 0.5
        let maxACWR = 2.0
        let normalized = min(max(trainingLoad.acwr, minACWR), maxACWR)
        return (normalized - minACWR) / (maxACWR - minACWR)
    }

    private var acwrColor: Color {
        if trainingLoad.acwr < 0.8 { return .blue }
        else if trainingLoad.acwr <= 1.3 { return .green }
        else if trainingLoad.acwr <= 1.5 { return .orange }
        else { return .red }
    }

    private var riskColor: Color {
        switch trainingLoad.injuryRiskLevel {
        case "low": return .green
        case "moderate": return .orange
        case "high": return .red
        case "very_high": return .purple
        default: return .gray
        }
    }
}

// MARK: - ACWR Zone Indicator

struct ACWRZoneIndicator: View {
    let trainingLoad: TrainingLoadAnalysis

    let zones: [(String, Range<Double>, Color)] = [
        ("Detraining", 0.0..<0.8, .blue),
        ("Optimal", 0.8..<1.3, .green),
        ("Moderate", 1.3..<1.5, .orange),
        ("High Risk", 1.5..<3.0, .red)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACWR Zones")
                .font(.headline)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Zone bars
                    HStack(spacing: 0) {
                        ForEach(zones, id: \.0) { zone in
                            zone.2.opacity(0.3)
                                .frame(width: zoneWidth(for: zone.1, totalWidth: geometry.size.width))
                        }
                    }
                    .frame(height: 30)
                    .cornerRadius(15)

                    // Current position marker
                    Circle()
                        .fill(currentColor)
                        .frame(width: 20, height: 20)
                        .offset(x: calculatePosition(width: geometry.size.width) - 10)
                }
            }
            .frame(height: 30)

            // Zone labels
            HStack {
                ForEach(zones, id: \.0) { zone in
                    Text(zone.0)
                        .font(.caption2)
                        .foregroundColor(zone.2)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func zoneWidth(for range: Range<Double>, totalWidth: Double) -> Double {
        let totalRange = 3.0 // 0 to 3
        let zoneSize = range.upperBound - range.lowerBound
        return (zoneSize / totalRange) * totalWidth
    }

    private func calculatePosition(width: Double) -> Double {
        let normalized = min(max(trainingLoad.acwr, 0.0), 3.0)
        return (normalized / 3.0) * width
    }

    private var currentColor: Color {
        if trainingLoad.acwr < 0.8 { return .blue }
        else if trainingLoad.acwr <= 1.3 { return .green }
        else if trainingLoad.acwr <= 1.5 { return .orange }
        else { return .red }
    }
}

// MARK: - Training Stats Grid

struct TrainingStatsGrid: View {
    let trainingLoad: TrainingLoadAnalysis

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            StatBox(
                title: "Acute Load (7d)",
                value: String(format: "%.1f", trainingLoad.acuteLoad7Days),
                color: .orange
            )

            StatBox(
                title: "Chronic Load (28d)",
                value: String(format: "%.1f", trainingLoad.chronicLoad28Days),
                color: .blue
            )

            StatBox(
                title: "Weekly TSS",
                value: String(format: "%.1f", trainingLoad.weeklyTss),
                color: .red
            )

            StatBox(
                title: "Weekly Volume",
                value: String(format: "%.1f km", trainingLoad.totalVolumeKm),
                subtitle: String(format: "%.1f mi", trainingLoad.totalVolumeMiles),
                color: .green
            )
        }
    }
}

struct StatBox: View {
    let title: String
    let value: String
    var subtitle: String = ""
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }

            Text(title)
                .font(.caption)
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Recovery Status Banner

struct RecoveryStatusBanner: View {
    let trainingLoad: TrainingLoadAnalysis
    @State private var showDetails = false

    var body: some View {
        Button(action: { showDetails.toggle() }) {
            HStack(spacing: 12) {
                Image(systemName: recoveryIcon)
                    .font(.title2)
                    .foregroundColor(recoveryColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Recovery Status")
                        .font(.caption)
                        .foregroundColor(AppTheme.Colors.textSecondary)

                    Text(trainingLoad.recoveryStatusDisplay)
                        .font(.headline)
                        .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            .padding()
            .background(recoveryColor.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetails) {
            RecoveryDetailsSheet(trainingLoad: trainingLoad)
        }
    }

    private var recoveryColor: Color {
        switch trainingLoad.recoveryStatus {
        case "well_recovered": return .green
        case "adequate": return .blue
        case "fatigued": return .orange
        case "overreaching": return .red
        case "overtrained": return .purple
        default: return .gray
        }
    }

    private var recoveryIcon: String {
        switch trainingLoad.recoveryStatus {
        case "well_recovered": return "checkmark.circle.fill"
        case "adequate": return "checkmark.circle"
        case "fatigued": return "exclamationmark.triangle.fill"
        case "overreaching": return "exclamationmark.triangle.fill"
        case "overtrained": return "x.circle.fill"
        default: return "circle"
        }
    }
}

struct RecoveryDetailsSheet: View {
    let trainingLoad: TrainingLoadAnalysis
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("Recovery Essentials") {
                    Label("7-9 hours of sleep", systemImage: "bed.double.fill")
                    Label("Protein within 30min post-run", systemImage: "fork.knife")
                    Label("Foam rolling and stretching", systemImage: "figure.flexibility")
                    Label("Hydration: 2-3L daily", systemImage: "drop.fill")
                }
            }
            .navigationTitle("Recovery Tips")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Training Trends Row

struct TrainingTrendsRow: View {
    let trainingLoad: TrainingLoadAnalysis

    var body: some View {
        HStack(spacing: 16) {
            TrendBox(
                title: "Training Trend",
                trend: trainingLoad.trainingTrendDisplay,
                icon: trendIcon(for: trainingLoad.trainingTrend),
                color: .orange
            )

            TrendBox(
                title: "Fitness Trend",
                trend: trainingLoad.fitnessTrendDisplay,
                icon: trendIcon(for: trainingLoad.fitnessTrend),
                color: .blue
            )
        }
    }

    private func trendIcon(for trend: String) -> String {
        if trend.contains("ramping") || trend.contains("improving") {
            return "arrow.up.right"
        } else if trend.contains("steady") || trend.contains("maintaining") {
            return "arrow.right"
        } else {
            return "arrow.down.right"
        }
    }
}

struct TrendBox: View {
    let title: String
    let trend: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(AppTheme.Colors.textSecondary)

                Text(trend)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - 7-Day Workout Plan

struct SevenDayWorkoutPlan: View {
    let trainingLoad: TrainingLoadAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("7-Day Workout Plan")
                .font(.headline)

            ForEach(trainingLoad.sortedDailyRecommendations, id: \.0) { day, workout in
                DayWorkoutCard(day: day, workout: workout)
            }
        }
    }
}

struct DayWorkoutCard: View {
    let day: String
    let workout: String

    var body: some View {
        HStack(spacing: 12) {
            // Day Badge
            Text(day)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 60, height: 60)
                .background(workoutColor)
                .cornerRadius(8)

            // Workout Description
            VStack(alignment: .leading, spacing: 4) {
                Text(workout)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(workoutType)
                    .font(.caption)
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var workoutColor: Color {
        if workout.lowercased().contains("rest") {
            return .green
        } else if workout.lowercased().contains("tempo") || workout.lowercased().contains("interval") {
            return .red
        } else if workout.lowercased().contains("long") {
            return .purple
        } else {
            return .blue
        }
    }

    private var workoutType: String {
        if workout.lowercased().contains("rest") {
            return "Recovery"
        } else if workout.lowercased().contains("tempo") || workout.lowercased().contains("interval") {
            return "High Intensity"
        } else if workout.lowercased().contains("long") {
            return "Endurance"
        } else {
            return "Base Building"
        }
    }
}

// MARK: - Preview

struct TrainingLoadView_Previews: PreviewProvider {
    static var previews: some View {
        TrainingLoadView(trainingLoad: QuickWinsResponse.mock.analyses.trainingLoad!)
    }
}
