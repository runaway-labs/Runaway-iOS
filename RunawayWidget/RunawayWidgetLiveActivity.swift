//
//  RunawayWidgetLiveActivity.swift
//  RunawayWidget
//
//  Created by Jack Rudelic on 2/18/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

private enum LiveActivityUnits {
    private static var isMetric: Bool {
        let defaults = UserDefaults(suiteName: "group.com.jackrudelic.runawayios")
        let raw = defaults?.string(forKey: "preferred_activity_distance_unit")
            ?? defaults?.string(forKey: "preferred_distance_unit")
            ?? "miles"
        return raw.lowercased().contains("kilometer") || raw.lowercased() == "km"
    }

    static var distanceLabel: String { isMetric ? "km" : "mi" }
    static var paceLabel: String { isMetric ? "/km" : "/mi" }

    static func distance(_ meters: Double) -> String {
        let value = isMetric ? meters / 1_000 : meters / 1_609.344
        return String(format: "%.2f", value)
    }

    static func pace(_ secondsPerMile: Double) -> String {
        guard secondsPerMile > 0 && secondsPerMile < 3_600 else { return "--:--" }
        let secondsPerUnit = isMetric ? secondsPerMile / 1.609344 : secondsPerMile
        return String(format: "%d:%02d", Int(secondsPerUnit) / 60, Int(secondsPerUnit) % 60)
    }
}

// MARK: - Activity Attributes

struct RunawayWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic state updated during the activity
        var elapsedTime: TimeInterval
        var distance: Double // meters
        var currentPace: Double // seconds per mile
        var averagePace: Double // seconds per mile
        var isPaused: Bool
    }

    // Fixed properties set when activity starts
    var activityType: String
    var startTime: Date
}

// MARK: - Live Activity Widget

struct RunawayWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunawayWidgetAttributes.self) { context in
            // Lock screen / banner UI
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: activityIcon(for: context.attributes.activityType))
                            .foregroundColor(BecomingWidgetTheme.mint)
                        Text(formatDistance(context.state.distance))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("mi")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .foregroundColor(.blue)
                        Text(formatTime(context.state.elapsedTime))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if context.state.isPaused {
                        HStack {
                            Image(systemName: "pause.circle.fill")
                                .foregroundColor(.orange)
                            Text("PAUSED")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 24) {
                        VStack(spacing: 2) {
                            Text(formatPace(context.state.currentPace))
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text("Current")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }

                        Divider()
                            .frame(height: 30)
                            .background(Color.gray.opacity(0.5))

                        VStack(spacing: 2) {
                            Text(formatPace(context.state.averagePace))
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text("Average")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                // Compact leading - show distance
                HStack(spacing: 2) {
                    Image(systemName: "figure.run")
                        .foregroundColor(BecomingWidgetTheme.mint)
                    Text(formatDistance(context.state.distance))
                        .font(.caption)
                        .fontWeight(.bold)
                }
            } compactTrailing: {
                // Compact trailing - show time
                Text(formatTimeCompact(context.state.elapsedTime))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(context.state.isPaused ? .orange : .white)
            } minimal: {
                // Minimal - just running icon
                Image(systemName: context.state.isPaused ? "pause.fill" : "figure.run")
                    .foregroundColor(context.state.isPaused ? .orange : .green)
            }
            .widgetURL(URL(string: "runaway://activity"))
            .keylineTint(BecomingWidgetTheme.mint)
        }
    }

    // MARK: - Helpers

    private func activityIcon(for type: String) -> String {
        switch type.lowercased() {
        case "run": return "figure.run"
        case "walk": return "figure.walk"
        case "ride", "bike": return "bicycle"
        case "hike": return "figure.hiking"
        case "swim": return "figure.pool.swim"
        default: return "figure.run"
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        return LiveActivityUnits.distance(meters)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    private func formatTimeCompact(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func formatPace(_ secondsPerMile: Double) -> String {
        return LiveActivityUnits.pace(secondsPerMile)
    }
}

// MARK: - Lock Screen View

struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<RunawayWidgetAttributes>

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: activityIcon)
                    .font(.title2)
                    .foregroundColor(BecomingWidgetTheme.mint)

                Text(context.attributes.activityType)
                    .font(.headline)
                    .fontWeight(.bold)

                Spacer()

                if context.state.isPaused {
                    HStack(spacing: 4) {
                        Image(systemName: "pause.circle.fill")
                        Text("PAUSED")
                    }
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(8)
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(BecomingWidgetTheme.mint)
                            .frame(width: 8, height: 8)
                        Text("ACTIVE")
                    }
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(BecomingWidgetTheme.mint)
                }
            }

            // Main metrics
            HStack(spacing: 0) {
                // Distance
                MetricColumn(
                    value: formatDistance(context.state.distance),
                    unit: LiveActivityUnits.distanceLabel,
                    label: "DISTANCE",
                    color: BecomingWidgetTheme.mint
                )

                Spacer()

                // Time
                MetricColumn(
                    value: formatTime(context.state.elapsedTime),
                    unit: "",
                    label: "TIME",
                    color: .blue
                )

                Spacer()

                // Pace
                MetricColumn(
                    value: formatPace(context.state.averagePace),
                    unit: LiveActivityUnits.paceLabel,
                    label: "AVG PACE",
                    color: .orange
                )
            }
        }
        .padding()
        .activityBackgroundTint(BecomingWidgetTheme.background)
        .activitySystemActionForegroundColor(.white)
    }

    private var activityIcon: String {
        switch context.attributes.activityType.lowercased() {
        case "run": return "figure.run"
        case "walk": return "figure.walk"
        case "ride", "bike": return "bicycle"
        case "hike": return "figure.hiking"
        case "swim": return "figure.pool.swim"
        default: return "figure.run"
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        return LiveActivityUnits.distance(meters)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    private func formatPace(_ secondsPerMile: Double) -> String {
        return LiveActivityUnits.pace(secondsPerMile)
    }
}

// MARK: - Metric Column

struct MetricColumn: View {
    let value: String
    let unit: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

extension RunawayWidgetAttributes {
    fileprivate static var preview: RunawayWidgetAttributes {
        RunawayWidgetAttributes(activityType: "Run", startTime: Date())
    }
}

extension RunawayWidgetAttributes.ContentState {
    fileprivate static var running: RunawayWidgetAttributes.ContentState {
        RunawayWidgetAttributes.ContentState(
            elapsedTime: 1847,
            distance: 4023,
            currentPace: 512,
            averagePace: 498,
            isPaused: false
        )
    }

    fileprivate static var paused: RunawayWidgetAttributes.ContentState {
        RunawayWidgetAttributes.ContentState(
            elapsedTime: 1847,
            distance: 4023,
            currentPace: 0,
            averagePace: 498,
            isPaused: true
        )
    }
}

#Preview("Notification", as: .content, using: RunawayWidgetAttributes.preview) {
    RunawayWidgetLiveActivity()
} contentStates: {
    RunawayWidgetAttributes.ContentState.running
    RunawayWidgetAttributes.ContentState.paused
}
