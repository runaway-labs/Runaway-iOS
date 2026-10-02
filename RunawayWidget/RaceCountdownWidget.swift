//
//  RaceCountdownWidget.swift
//  RunawayWidget
//
//  Lock screen and accessory widgets for race countdown and training phase.
//

import WidgetKit
import SwiftUI

// MARK: - Entry

struct RaceCountdownEntry: TimelineEntry {
    let date: Date
    let phaseName: String?
    let phaseIcon: String?
    let daysUntilRace: Int?
    let raceName: String?
    let twinMessage: String?
}

// MARK: - Provider

struct RaceCountdownProvider: TimelineProvider {
    func placeholder(in context: Context) -> RaceCountdownEntry {
        RaceCountdownEntry(
            date: Date(),
            phaseName: "Peak Intensity",
            phaseIcon: "flame.fill",
            daysUntilRace: 14,
            raceName: "Marathon",
            twinMessage: "Intensity is high. Your ratio is 1.42."
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (RaceCountdownEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RaceCountdownEntry>) -> Void) {
        let entry = readEntry()
        let nextUpdate = Calendar.current.safeDate(byAdding: .hour, value: 1, to: Date())
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func readEntry() -> RaceCountdownEntry {
        // We can't import AppConstants here easily if it's in the app target,
        // so we'll use the hardcoded keys or share the constants file.
        // For now, hardcoding to match AppConstants.WidgetKeys.
        let userDefaults = UserDefaults(suiteName: "group.com.jackrudelic.runawayios")
        
        return RaceCountdownEntry(
            date: Date(),
            phaseName: userDefaults?.string(forKey: "current_training_phase"),
            phaseIcon: userDefaults?.string(forKey: "current_phase_icon"),
            daysUntilRace: userDefaults?.object(forKey: "days_until_race") as? Int,
            raceName: userDefaults?.string(forKey: "next_race_name"),
            twinMessage: userDefaults?.string(forKey: "widget_twin_message")
        )
    }
}

// MARK: - Entry View

struct RaceCountdownWidgetEntryView: View {
    let entry: RaceCountdownEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularCountdownView(entry: entry)
        case .accessoryRectangular:
            RectangularCountdownView(entry: entry)
        case .accessoryInline:
            InlineCountdownView(entry: entry)
        case .systemSmall:
            SmallCountdownView(entry: entry)
        default:
            SmallCountdownView(entry: entry)
        }
    }
}

// MARK: - Lock Screen: Circular

struct CircularCountdownView: View {
    let entry: RaceCountdownEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            
            if let days = entry.daysUntilRace {
                VStack(spacing: 0) {
                    Text("\(days)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("DAYS")
                        .font(.system(size: 8, weight: .heavy))
                }
            } else {
                Image(systemName: entry.phaseIcon ?? "figure.run")
                    .font(.title2)
                    .widgetAccentable()
            }
        }
    }
}

// MARK: - Lock Screen: Rectangular

struct RectangularCountdownView: View {
    let entry: RaceCountdownEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: entry.phaseIcon ?? "figure.run")
                    .font(.caption)
                    .widgetAccentable()
                Text(entry.raceName ?? "Next Race")
                    .font(.caption)
                    .fontWeight(.bold)
            }
            
            if let days = entry.daysUntilRace {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(days)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("days until race day")
                        .font(.caption2)
                }
            } else {
                Text(entry.phaseName ?? "Training Steady")
                    .font(.system(size: 16, weight: .semibold))
            }
            
            if let message = entry.twinMessage {
                Text(message)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .opacity(0.8)
            }
        }
    }
}

// MARK: - Lock Screen: Inline

struct InlineCountdownView: View {
    let entry: RaceCountdownEntry

    var body: some View {
        HStack {
            Image(systemName: entry.phaseIcon ?? "figure.run").widgetAccentable()
            if let days = entry.daysUntilRace {
                Text("\(days) days to \(entry.raceName ?? "Race")")
            } else {
                Text(entry.phaseName ?? "Runaway")
            }
        }
    }
}

// MARK: - System Small

struct SmallCountdownView: View {
    let entry: RaceCountdownEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: entry.phaseIcon ?? "figure.run")
                    .font(.title3)
                    .widgetAccentable()
                Spacer()
                Text("Runaway")
                    .font(.system(size: 14, weight: .heavy))
                    .italic()
            }
            
            if let days = entry.daysUntilRace {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(days)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("DAYS UNTIL RACE")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(RunawayPalette.strideLime)
                }
            } else {
                Text(entry.phaseName ?? "Training Steady")
                    .font(.title3)
                    .fontWeight(.bold)
            }
            
            Spacer()
            
            if let message = entry.twinMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
            }
        }
        .padding()
        .containerBackground(for: .widget) {
            RunawayPalette.nightPine
        }
    }
}

// MARK: - Widget

struct RaceCountdownWidget: Widget {
    let kind: String = "RaceCountdownWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RaceCountdownProvider()) { entry in
            RaceCountdownWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Race Countdown")
        .description("Track days until your goal race and training phase.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }
}
