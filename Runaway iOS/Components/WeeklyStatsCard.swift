//
//  WeeklyStatsCard.swift
//  Runaway iOS
//

import SwiftUI

struct WeeklyStatsCard: View {
    @Environment(DataManager.self) var dataManager
    @ObservedObject private var goalStore = GoalSettingsStore.shared

    private var stats: WeeklyActivityStats { WeeklyActivityStats(activities: dataManager.activities) }
    private var weeklyGoalMiles: Double { goalStore.settings.weeklyGoalMiles }
    private var progress: Double {
        guard weeklyGoalMiles > 0 else { return 0 }
        return min(stats.totalMiles / weeklyGoalMiles, 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── TOP ROW: date range + trend ────────────────────────────
            HStack {
                EyebrowLabel(text: weekRangeLabel)
                Spacer()
                if let trend = stats.weekOverWeekTrend {
                    TrendChip(percentage: trend * 100)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // ── HERO ROW: big distance + ring ──────────────────────────
            HStack(alignment: .center) {

                // Left: big distance
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: stats.totalMiles >= 10 ? "%.1f" : "%.2f", stats.totalMiles))
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.Colors.infoBlueLight)
                            .monospacedDigit()
                        Text(UnitFormatter.distanceUnitAbbreviation)
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                            .padding(.bottom, 6)
                    }

                    // Supporting stats row
                    HStack(spacing: 16) {
                        statChip(value: "\(stats.activityCount)", label: stats.activityCount == 1 ? "run" : "runs", icon: "figure.run")
                        statChip(value: formatDuration(stats.totalSeconds), label: "time", icon: "clock")
                    }
                }

                Spacer()

                // Right: goal ring
                if weeklyGoalMiles > 0 {
                    goalRing
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            // ── PROGRESS BAR ───────────────────────────────────────────
            if weeklyGoalMiles > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(progressColor)
                                .frame(width: geo.size.width * progress, height: 4)
                                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 16)

                    HStack {
                        if progress >= 1.0 {
                            Label("Goal achieved", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.Colors.success)
                        } else {
                            let remaining = weeklyGoalMiles - stats.totalMiles
                            Text(String(format: "%.1f %@ to goal", remaining, UnitFormatter.distanceUnitAbbreviation))
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.Colors.DarkMode.textTertiary)
                        }
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
            }
        }
        .background(AppTheme.Colors.DarkMode.cardBackground)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    // MARK: - Goal Ring
    private var goalRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 5)
                .frame(width: 72, height: 72)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    progressColor,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .frame(width: 72, height: 72)
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
            VStack(spacing: 1) {
                Text("\(Int(progress * 100))")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                Text("%")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.Colors.DarkMode.textTertiary)
            }
        }
    }

    // MARK: - Stat Chip
    private func statChip(value: String, label: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(AppTheme.Colors.DarkMode.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.Colors.DarkMode.textTertiary)
        }
    }

    // MARK: - Helpers
    private var weekRangeLabel: String {
        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) else { return "This Week" }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return "\(f.string(from: start)) – \(f.string(from: Date()))"
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600; let m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private var progressColor: Color {
        progress >= 1.0 ? AppTheme.Colors.success : AppTheme.Colors.infoBlue
    }
}

// MARK: - Weekly Stats Calculator

struct WeeklyActivityStats {
    let totalMeters: Double
    let totalMiles: Double
    let activityCount: Int
    let totalSeconds: Int
    let weekOverWeekTrend: Double?

    init(activities: [Activity]) {
        let cal = Calendar.current
        let today = Date()
        guard let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)),
              let prevStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekStart) else {
            totalMeters = 0; totalMiles = 0; activityCount = 0; totalSeconds = 0; weekOverWeekTrend = nil; return
        }

        let current = activities.filter {
            guard AppConstants.ActivityTypes.isRunning($0.type) else { return false }
            guard let ts = $0.activity_date ?? $0.start_date else { return false }
            let d = Date(timeIntervalSince1970: ts); return d >= weekStart && d <= today
        }
        let prev = activities.filter {
            guard AppConstants.ActivityTypes.isRunning($0.type) else { return false }
            guard let ts = $0.activity_date ?? $0.start_date else { return false }
            let d = Date(timeIntervalSince1970: ts); return d >= prevStart && d < weekStart
        }

        let dist = current.reduce(0.0) { $0 + ($1.distance ?? 0) }
        totalMeters = dist
        totalMiles = dist / 1609.34
        activityCount = current.count
        totalSeconds = current.reduce(0) { $0 + Int($1.elapsed_time ?? 0) }

        let prevDist = prev.reduce(0.0) { $0 + ($1.distance ?? 0) }
        weekOverWeekTrend = prevDist > 0 ? (dist - prevDist) / prevDist : (dist > 0 ? 1.0 : nil)
    }
}
