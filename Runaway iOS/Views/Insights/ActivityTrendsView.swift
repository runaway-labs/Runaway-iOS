//
//  ActivityTrendsView.swift
//  Runaway iOS
//
//  Detailed activity trends analysis view
//

import SwiftUI

struct ActivityTrendsView: View {
    let activities: [Activity]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {
                    // Pace Trends Chart
                    PaceTrendsChart(activities: activities)

                    // Activity Heatmap
                    ActivityHeatmapCard(activities: activities)

                    // Consistency Score
                    ConsistencyCard(activities: activities)

                    // Best & Worst Runs
                    BestWorstRunsCard(activities: activities)
                }
                .padding()
            }
            .tint(AppTheme.Colors.accent)
            .navigationTitle("Activity Trends")
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

// MARK: - Consistency Card

struct ConsistencyCard: View {
    let activities: [Activity]

    private var consistencyScore: Double {
        guard !activities.isEmpty else { return 0 }

        let calendar = Calendar.current
        let last30Days = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()

        let recentActivities = activities.filter { activity in
            guard let dateInterval = activity.activity_date ?? activity.start_date else { return false }
            let activityDate = Date(timeIntervalSince1970: dateInterval)
            return activityDate >= last30Days
        }

        let activeDays = Set(recentActivities.compactMap { activity -> Int? in
            guard let dateInterval = activity.activity_date ?? activity.start_date else { return nil }
            let activityDate = Date(timeIntervalSince1970: dateInterval)
            return calendar.ordinality(of: .day, in: .year, for: activityDate)
        }).count

        return (Double(activeDays) / 30.0) * 100.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("Consistency Score")
                .font(AppTheme.Typography.headline)
                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

            HStack {
                // Circular progress
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                        .frame(width: 80, height: 80)

                    Circle()
                        .trim(from: 0, to: consistencyScore / 100)
                        .stroke(consistencyColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 1.0), value: consistencyScore)

                    Text("\(Int(consistencyScore))%")
                        .font(AppTheme.Typography.headline)
                        .foregroundColor(consistencyColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(consistencyLabel)
                        .font(AppTheme.Typography.headline)
                        .foregroundColor(consistencyColor)

                    Text("Based on activity frequency over the last 30 days")
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                }

                Spacer()
            }
        }
        .padding()
        .background(AppTheme.Colors.adaptiveCardBackground)
        .cornerRadius(AppTheme.CornerRadius.large)
    }

    private var consistencyColor: Color {
        if consistencyScore >= 80 { return .green }
        else if consistencyScore >= 60 { return .blue }
        else if consistencyScore >= 40 { return .orange }
        else { return .red }
    }

    private var consistencyLabel: String {
        if consistencyScore >= 80 { return "Excellent" }
        else if consistencyScore >= 60 { return "Good" }
        else if consistencyScore >= 40 { return "Fair" }
        else { return "Needs Improvement" }
    }
}

// MARK: - Best & Worst Runs Card

struct BestWorstRunsCard: View {
    let activities: [Activity]

    private var bestRun: Activity? {
        activities
            .filter { $0.average_speed != nil && $0.distance != nil && $0.distance! > 0 }
            .max(by: { ($0.average_speed ?? 0) < ($1.average_speed ?? 0) }) // Max speed = fastest = best
    }

    private var worstRun: Activity? {
        activities
            .filter { $0.average_speed != nil && $0.distance != nil && $0.distance! > 0 }
            .min(by: { ($0.average_speed ?? 0) < ($1.average_speed ?? 0) }) // Min speed = slowest = worst
    }

    private func calculatePace(from speed: Double) -> Double {
        // speed is in meters/second
        // pace is minutes per mile
        guard speed > 0 else { return 0 }
        let milesPerHour = speed * 2.23694 // Convert m/s to mph
        let minutesPerMile = 60.0 / milesPerHour
        return minutesPerMile
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("Best & Worst Runs")
                .font(AppTheme.Typography.headline)
                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

            if let best = bestRun {
                RunSummaryRow(
                    title: "Fastest Pace",
                    activity: best,
                    color: .green,
                    icon: "bolt.fill"
                )
            }

            if let worst = worstRun {
                RunSummaryRow(
                    title: "Slowest Pace",
                    activity: worst,
                    color: .orange,
                    icon: "tortoise.fill"
                )
            }
        }
        .padding()
        .background(AppTheme.Colors.adaptiveCardBackground)
        .cornerRadius(AppTheme.CornerRadius.large)
    }
}

struct RunSummaryRow: View {
    let title: String
    let activity: Activity
    let color: Color
    let icon: String

    private func calculatePace(from speed: Double) -> Double {
        guard speed > 0 else { return 0 }
        let milesPerHour = speed * 2.23694
        let minutesPerMile = 60.0 / milesPerHour
        return minutesPerMile
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)

                if let speed = activity.average_speed {
                    let pace = calculatePace(from: speed)
                    Text(formatPace(pace))
                        .font(AppTheme.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
                }

                if let distance = activity.distance {
                    Text(String(format: "%.2f mi", distance * 0.000621371))
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.adaptiveTextTertiary)
                }
            }

            Spacer()

            if let dateInterval = activity.activity_date ?? activity.start_date {
                let date = Date(timeIntervalSince1970: dateInterval)
                Text(date, style: .date)
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.adaptiveTextTertiary)
            }
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(AppTheme.CornerRadius.small)
    }
}

// MARK: - Helper Functions

private func formatPace(_ pace: Double) -> String {
    let minutes = Int(pace)
    let seconds = Int((pace - Double(minutes)) * 60)
    return String(format: "%d:%02d/mi", minutes, seconds)
}

// MARK: - Preview

struct ActivityTrendsView_Previews: PreviewProvider {
    static var previews: some View {
        ActivityTrendsView(activities: [])
    }
}
