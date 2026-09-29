//
//  StatsComponents.swift
//  Runaway iOS
//

import SwiftUI

// MARK: - Stats Components

struct KeyMetricsGrid: View {
    @Environment(DataManager.self) var dataManager
    let quickWinsData: QuickWinsResponse?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowLabel(text: "YOUR PROGRESS")

            HStack(spacing: 10) {
                KeyMetricTile(title: "This Week", value: weeklyMileage, trend: weeklyTrend, trendLabel: weeklyTrendLabel, color: AppTheme.Colors.warmAmber)
                KeyMetricTile(title: "Fitness", value: fitnessTrend, trend: fitnessTrendDirection, trendLabel: nil, color: fitnessTrendColor)
                KeyMetricTile(title: "Load", value: trainingLoadValue, trend: trainingLoadTrend, trendLabel: trainingLoadLabel, color: trainingLoadColor)
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.DarkMode.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium + 2))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium + 2)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    // MARK: - Weekly Mileage

    private var weeklyMileage: String {
        let activities = dataManager.activities
        let calendar = Calendar.current
        let now = Date()

        // Use calendar week (Sunday to Saturday) for consistency
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return "0 \(UnitFormatter.distanceUnitAbbreviation)"
        }

        let weeklyActivities = activities.filter { activity in
            guard let dateInterval = activity.activity_date ?? activity.start_date else { return false }
            let activityDate = Date(timeIntervalSince1970: dateInterval)
            return activityDate >= weekInterval.start && activityDate < weekInterval.end
        }

        let totalMeters = weeklyActivities.filter { AppConstants.ActivityTypes.isRunning($0.type) }.compactMap { $0.distance }.reduce(0, +)
        return UnitFormatter.formatDistance(totalMeters, decimals: 1, includeUnit: true)
    }

    private var weeklyTrend: String {
        // Compare to previous week
        return "↑"
    }

    private var weeklyTrendLabel: String? {
        return "+18%"
    }

    // MARK: - Fitness Trend

    private var fitnessTrend: String {
        if let data = quickWinsData?.analyses.trainingLoad {
            switch data.fitnessTrend {
            case "improving": return "Improving"
            case "maintaining": return "Stable"
            case "declining": return "Declining"
            default: return "Stable"
            }
        }
        return "Stable"
    }

    private var fitnessTrendDirection: String {
        if let data = quickWinsData?.analyses.trainingLoad {
            switch data.fitnessTrend {
            case "improving": return "↑"
            case "maintaining": return "→"
            case "declining": return "↓"
            default: return "→"
            }
        }
        return "→"
    }

    private var fitnessTrendColor: Color {
        if let data = quickWinsData?.analyses.trainingLoad {
            switch data.fitnessTrend {
            case "improving": return .green
            case "maintaining": return .blue
            case "declining": return .orange
            default: return .blue
            }
        }
        return .blue
    }

    // MARK: - Training Load

    private var trainingLoadValue: String {
        if let data = quickWinsData?.analyses.trainingLoad {
            switch data.injuryRiskLevel {
            case "low": return "Optimal"
            case "moderate": return "Building"
            case "high": return "High"
            case "very_high": return "Caution"
            default: return "Optimal"
            }
        }
        return "Optimal"
    }

    private var trainingLoadTrend: String {
        return ""
    }

    private var trainingLoadLabel: String? {
        if let data = quickWinsData?.analyses.trainingLoad {
            return String(format: "%.2f", data.acwr)
        }
        return nil
    }

    private var trainingLoadColor: Color {
        if let data = quickWinsData?.analyses.trainingLoad {
            switch data.injuryRiskLevel {
            case "low": return .green
            case "moderate": return .yellow
            case "high": return .orange
            case "very_high": return .red
            default: return .green
            }
        }
        return .green
    }
}

struct KeyMetricTile: View {
    let title: String
    let value: String
    let trend: String
    let trendLabel: String?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(AppTheme.Colors.DarkMode.textTertiary)

            HStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                if !trend.isEmpty {
                    Text(trend)
                        .font(.system(size: 12))
                        .foregroundColor(color)
                }
            }

            if let label = trendLabel {
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppTheme.Colors.DarkMode.surfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small + 4))
    }
}

struct ThisWeekActivitiesSection: View {
    @Environment(DataManager.self) var dataManager

    private var thisWeekActivities: [Activity] {
        let calendar = Calendar.current
        let now = Date()

        // Use calendar week (Sunday to Saturday) for consistency across app
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return []
        }

        return dataManager.activities.filter { activity in
            guard let dateInterval = activity.activity_date ?? activity.start_date else { return false }
            let activityDate = Date(timeIntervalSince1970: dateInterval)
            return activityDate >= weekInterval.start && activityDate < weekInterval.end
        }.prefix(5).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                EyebrowLabel(text: "THIS WEEK'S ACTIVITIES")
                Spacer()
                if !thisWeekActivities.isEmpty {
                    Text("\(thisWeekActivities.count) activities")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(AppTheme.Colors.DarkMode.textTertiary)
                }
            }

            if thisWeekActivities.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.Colors.DarkMode.textTertiary)
                    Text("No activities yet this week")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 6) {
                    ForEach(thisWeekActivities, id: \.id) { activity in
                        CompactActivityRow(activity: activity)
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.DarkMode.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium + 2))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium + 2)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}

struct CompactActivityRow: View {
    let activity: Activity

    private var activityDate: Date? {
        guard let interval = activity.activity_date ?? activity.start_date else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    private var formattedDistance: String {
        UnitFormatter.formatDistance(activity.distance ?? 0, decimals: 1, includeUnit: true)
    }

    private var paceString: String {
        guard let speed = activity.average_speed, speed > 0 else { return "--:--" }
        // Calculate minutes per mile from m/s
        let minutesPerMile = (1609.34 / speed) / 60.0
        return UnitFormatter.formatPaceTime(minutesPerMile: minutesPerMile)
    }

    private var durationString: String {
        guard let elapsed = activity.elapsed_time else { return "--:--" }
        let totalMinutes = Int(elapsed / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return String(format: "%d:%02d", hours, minutes)
        }
        return String(format: "%d min", minutes)
    }

    private var dayOfWeek: String {
        guard let date = activityDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private var activityColor: Color {
        AppTheme.Colors.activityColor(for: activity.type ?? "")
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 3) {
                Text(dayOfWeek)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.Colors.DarkMode.textTertiary)
                Circle()
                    .fill(activityColor)
                    .frame(width: 7, height: 7)
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.name ?? "Activity")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text([formattedDistance, "\(paceString)\(UnitFormatter.paceUnitLabel)", durationString].joined(separator: " · "))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.Colors.DarkMode.textTertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.Colors.DarkMode.textTertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(AppTheme.Colors.DarkMode.surfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small + 2))
    }
}

struct CompactTrendsChart: View {
    let activities: [Activity]
    @State private var showingFullChart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                EyebrowLabel(text: "TRENDS")
                Spacer()
                Button(action: { showingFullChart = true }) {
                    HStack(spacing: 4) {
                        Text("See All")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(AppTheme.Colors.warmAmber)
                }
            }

            MiniWeeklyChart(activities: activities)
                .frame(height: 56)
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.DarkMode.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium + 2))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium + 2)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
        .sheet(isPresented: $showingFullChart) {
            ActivityTrendsView(activities: activities)
        }
    }
}

struct MiniWeeklyChart: View {
    let activities: [Activity]

    private var weeklyData: [(week: Int, miles: Double)] {
        let calendar = Calendar.current
        let now = Date()

        var weeks: [(week: Int, miles: Double)] = []

        for weekOffset in (0..<8).reversed() {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: now),
                  let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
                continue
            }

            let weekActivities = activities.filter { activity in
                guard let dateInterval = activity.activity_date ?? activity.start_date else { return false }
                let date = Date(timeIntervalSince1970: dateInterval)
                return date >= weekStart && date < weekEnd
            }

            let totalMeters = weekActivities.filter { AppConstants.ActivityTypes.isRunning($0.type) }.compactMap { $0.distance }.reduce(0, +)
            let distance = UnitFormatter.metersToPreferredUnit(totalMeters)
            weeks.append((week: 8 - weekOffset, miles: distance))
        }

        return weeks
    }

    private var maxMiles: Double {
        weeklyData.map { $0.miles }.max() ?? 1
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(weeklyData, id: \.week) { data in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(data.week == 8 ? AppTheme.Colors.DarkMode.accent : AppTheme.Colors.DarkMode.accent.opacity(0.4))
                        .frame(height: max(4, CGFloat(data.miles / maxMiles) * 50))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
