import AppIntents
import SwiftUI
import WidgetKit

enum BecomingWidgetTheme {
    static let background = Color(red: 0.02, green: 0.05, blue: 0.08)
    static let surface = Color(red: 0.05, green: 0.11, blue: 0.15)
    static let blue = Color(red: 0.20, green: 0.66, blue: 1)
    static let mint = Color(red: 0.22, green: 0.86, blue: 0.65)
    static let caution = Color(red: 1, green: 0.78, blue: 0.18)
    static let secondary = Color.white.opacity(0.58)
}

struct BecomingWidgetPath: Identifiable {
    let choice: WidgetBecomingChoice
    let title: String
    let effect: String
    let weekEffect: String
    let recommended: Bool
    var id: String { choice.rawValue }
}

struct BecomingWidgetEntry: TimelineEntry {
    let date: Date
    let headline: String
    let detail: String
    let workout: String
    let workoutDetail: String
    let readiness: Int?
    let recommendedChoice: WidgetBecomingChoice
    let selectedChoice: WidgetBecomingChoice?
    let weatherTitle: String?
    let weatherDetail: String?
    let paths: [BecomingWidgetPath]
    let weeklyDistance: Double
    let weeklyGoal: Double
    let unit: String
    let updatedAt: Date?
    let prescription: WidgetPrescriptionSnapshot?
    var progress: ProgressWidgetSnapshot = .preview

    var recommendedPath: BecomingWidgetPath {
        paths.first(where: { $0.choice == recommendedChoice }) ?? paths[0]
    }
    var isStale: Bool { updatedAt.map { Date().timeIntervalSince($0) > 14_400 } ?? true }
}

struct BecomingWidgetProvider: AppIntentTimelineProvider {
    typealias Intent = ConfigurationAppIntent
    typealias Entry = BecomingWidgetEntry

    func placeholder(in context: Context) -> BecomingWidgetEntry { sample }
    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> BecomingWidgetEntry {
        context.isPreview ? sample : read(selectedTypes: configuration.selectedActivities?.map(\.name))
    }
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<BecomingWidgetEntry> {
        let now = Date()
        return Timeline(entries: [read(now, selectedTypes: configuration.selectedActivities?.map(\.name))], policy: .after(now.addingTimeInterval(1_800)))
    }

    private func read(_ date: Date = Date(), selectedTypes: [String]? = nil) -> BecomingWidgetEntry {
        let d = UserDefaults(suiteName: "group.com.jackrudelic.runawayios")
        let unitRaw = d?.string(forKey: "preferred_activity_distance_unit") ?? d?.string(forKey: "preferred_distance_unit") ?? "miles"
        let metric = unitRaw.lowercased().contains("kilometer") || unitRaw.lowercased() == "km"
        let conversion = metric ? 1.609344 : 1
        let recommended = WidgetBecomingChoice(rawValue: d?.string(forKey: "becoming_recommended_choice") ?? "planned") ?? .planned
        let selected = WidgetBecomingChoice(rawValue: d?.string(forKey: "becoming_selected_choice") ?? "")
        let paths = WidgetBecomingChoice.allCases.map { choice in
            BecomingWidgetPath(
                choice: choice,
                title: d?.string(forKey: "becoming_path_\(choice.rawValue)_title") ?? fallbackTitle(choice),
                effect: d?.string(forKey: "becoming_path_\(choice.rawValue)_effect") ?? fallbackEffect(choice),
                weekEffect: d?.string(forKey: "becoming_path_\(choice.rawValue)_week") ?? "Your remaining week responds.",
                recommended: choice == recommended
            )
        }
        let stamp = d?.double(forKey: "becoming_updated_at") ?? 0
        let progress = ProgressWidgetSnapshot.read(from: d, at: date, selectedTypes: selectedTypes)
        return BecomingWidgetEntry(
            date: date,
            headline: d?.string(forKey: "becoming_headline") ?? "Build from today's choice",
            detail: d?.string(forKey: "becoming_detail") ?? "Open Runaway to create today's adaptive plan.",
            workout: d?.string(forKey: "becoming_workout") ?? "Today's training",
            workoutDetail: d?.string(forKey: "becoming_workout_detail") ?? "Ready when you are",
            readiness: d?.object(forKey: "becoming_readiness") as? Int,
            recommendedChoice: recommended, selectedChoice: selected,
            weatherTitle: d?.string(forKey: "becoming_weather_title"),
            weatherDetail: d?.string(forKey: "becoming_weather_detail"), paths: paths,
            weeklyDistance: progress.weeklyDistance,
            weeklyGoal: max(1, (d?.double(forKey: "weekly_goal_miles") ?? 20) * conversion),
            unit: metric ? "km" : "mi", updatedAt: stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil,
            prescription: WidgetPrescriptionSnapshot.cached(in: d),
            progress: progress
        )
    }

    private func weeklyMiles(from defaults: UserDefaults?) -> Double {
        struct StoredActivity: Decodable { let distance: Double }
        let keys = ["sunArray", "monArray", "tueArray", "wedArray", "thuArray", "friArray", "satArray"]
        return keys.reduce(0) { total, key in
            total + (defaults?.stringArray(forKey: key) ?? []).reduce(0) { dayTotal, json in
                guard let data = json.data(using: .utf8),
                      let activity = try? JSONDecoder().decode(StoredActivity.self, from: data) else {
                    return dayTotal
                }
                return dayTotal + activity.distance
            }
        }
    }

    private func fallbackTitle(_ choice: WidgetBecomingChoice) -> String {
        switch choice {
        case .planned: return "Follow the plan"
        case .easier: return "Ease the effort"
        case .alternate: return "Change the stimulus"
        case .recover: return "Protect recovery"
        }
    }
    private func fallbackEffect(_ choice: WidgetBecomingChoice) -> String {
        switch choice {
        case .planned: return "Keep today's session intact."
        case .easier: return "Reduce today's training load."
        case .alternate: return "Use another profile activity."
        case .recover: return "Move today's load into the week."
        }
    }
    private var sample: BecomingWidgetEntry {
        let paths = WidgetBecomingChoice.allCases.map {
            BecomingWidgetPath(choice: $0, title: fallbackTitle($0), effect: fallbackEffect($0), weekEffect: "Protects tomorrow's quality session.", recommended: $0 == .easier)
        }
        return BecomingWidgetEntry(date: Date(), headline: "Keep the week moving", detail: "Useful work without forcing it.", workout: "Easy Run", workoutDetail: "28 min · conversational", readiness: 57, recommendedChoice: .easier, selectedChoice: nil, weatherTitle: "RunCast · Clear window", weatherDetail: "Dry · Light breeze", paths: paths, weeklyDistance: 8.1, weeklyGoal: 20, unit: "mi", updatedAt: Date(), prescription: WidgetPrescriptionSnapshot(title: "Easy Run", detail: "28 min · conversational", status: .scheduled))
    }
}

struct RunawayWidgetEntryView: View {
    let entry: BecomingWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall: AccomplishmentWidgetView(progress: entry.progress, prescription: entry.prescription, size: .small)
        case .systemMedium: AccomplishmentWidgetView(progress: entry.progress, prescription: entry.prescription, size: .medium)
        case .systemLarge, .systemExtraLarge: AccomplishmentWidgetView(progress: entry.progress, prescription: entry.prescription, size: .large)
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: AccomplishmentWidgetView(progress: entry.progress, prescription: entry.prescription, size: .small)
        }
    }

    private var readinessColor: Color {
        guard let value = entry.readiness else { return BecomingWidgetTheme.blue }
        return value >= 70 ? BecomingWidgetTheme.mint : value >= 45 ? BecomingWidgetTheme.caution : .red
    }
    private var header: some View {
        HStack {
            Text("THE BECOMING LINE").font(.system(size: 9, weight: .black, design: .rounded)).tracking(1).foregroundStyle(BecomingWidgetTheme.blue).widgetAccentable()
            Spacer()
            if entry.isStale { Image(systemName: "arrow.clockwise").font(.caption2).foregroundStyle(BecomingWidgetTheme.secondary) }
        }
    }
    private var small: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(entry.readiness.map(String.init) ?? "--").font(.system(size: 35, weight: .black, design: .rounded)).foregroundStyle(readinessColor)
                Text("READY").font(.system(size: 8, weight: .bold, design: .rounded)).foregroundStyle(BecomingWidgetTheme.secondary)
            }
            Text(entry.workout).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
            Text("Best path: \(entry.recommendedChoice.shortTitle.capitalized)").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(BecomingWidgetTheme.mint).lineLimit(1)
            Spacer(minLength: 0)
            Button(intent: ChooseBecomingPathIntent(choice: entry.recommendedChoice)) {
                Label("Choose", systemImage: entry.recommendedChoice.icon).font(.system(size: 11, weight: .bold, design: .rounded)).frame(maxWidth: .infinity, minHeight: 30)
            }.buttonStyle(.plain).tint(BecomingWidgetTheme.mint)
        }.padding(14)
    }
    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.headline).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                    Text(entry.workout).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(BecomingWidgetTheme.secondary).lineLimit(1)
                }
                Spacer()
                Text(entry.readiness.map(String.init) ?? "--").font(.system(size: 25, weight: .black, design: .rounded)).foregroundStyle(readinessColor)
            }
            pathButtons
            Text(entry.recommendedPath.weekEffect).font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(BecomingWidgetTheme.mint).lineLimit(1)
        }.padding(14)
    }
    private var large: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.headline).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text(entry.detail).font(.system(size: 11, design: .rounded)).foregroundStyle(BecomingWidgetTheme.secondary).lineLimit(2)
                }
                Spacer()
                readinessGauge.frame(width: 54, height: 54)
            }
            if let weather = entry.weatherTitle {
                Label(weather, systemImage: "cloud.sun.fill").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(BecomingWidgetTheme.blue)
            }
            ForEach(entry.paths) { path in
                Button(intent: ChooseBecomingPathIntent(choice: path.choice)) {
                    HStack(spacing: 10) {
                        Image(systemName: path.choice.icon).frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(path.title).font(.system(size: 13, weight: .bold, design: .rounded))
                            Text(path.effect).font(.system(size: 9, design: .rounded)).foregroundStyle(BecomingWidgetTheme.secondary).lineLimit(1)
                        }
                        Spacer()
                        if path.recommended { Text("BEST").font(.system(size: 8, weight: .black, design: .rounded)).foregroundStyle(BecomingWidgetTheme.mint) }
                        Image(systemName: entry.selectedChoice == path.choice ? "checkmark.circle.fill" : "chevron.right")
                    }.foregroundStyle(.white).padding(.horizontal, 11).padding(.vertical, 8)
                        .background(path.recommended ? BecomingWidgetTheme.mint.opacity(0.1) : BecomingWidgetTheme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Text(String(format: "%.1f / %.0f %@ this week", entry.weeklyDistance, entry.weeklyGoal, entry.unit)).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(BecomingWidgetTheme.secondary)
        }.padding(16)
    }
    private var pathButtons: some View {
        HStack(spacing: 5) {
            ForEach(entry.paths) { path in
                Button(intent: ChooseBecomingPathIntent(choice: path.choice)) {
                    VStack(spacing: 4) {
                        Circle().fill(path.recommended ? BecomingWidgetTheme.mint : BecomingWidgetTheme.blue.opacity(0.4)).frame(width: path.recommended ? 10 : 7, height: path.recommended ? 10 : 7)
                        Text(path.choice.shortTitle).font(.system(size: 7, weight: .bold, design: .rounded)).foregroundStyle(path.recommended ? .white : BecomingWidgetTheme.secondary)
                    }.frame(maxWidth: .infinity, minHeight: 38).background(path.recommended ? BecomingWidgetTheme.mint.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain)
            }
        }
    }
    private var readinessGauge: some View {
        Gauge(value: Double(entry.readiness ?? 0), in: 0...100) { EmptyView() } currentValueLabel: { Text(entry.readiness.map(String.init) ?? "--").font(.system(size: 15, weight: .black, design: .rounded)) }
            .gaugeStyle(.accessoryCircularCapacity).tint(readinessColor)
    }
    private var circular: some View { readinessGauge.widgetAccentable() }
    private var rectangular: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.recommendedChoice.icon).widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.workout).font(.headline).lineLimit(1)
                Text(entry.prescription.map { "\($0.status.label) · \($0.detail)" }
                     ?? "\(entry.readiness.map(String.init) ?? "--") ready · \(entry.recommendedChoice.shortTitle.capitalized)")
                    .font(.caption2).lineLimit(1)
            }
        }
    }
    private var inline: some View {
        Label(entry.prescription.map { "\($0.status.label): \($0.title)" }
              ?? "\(entry.workout) · \(entry.readiness.map(String.init) ?? "--") ready",
              systemImage: entry.prescription?.status == .completed ? "checkmark.circle.fill" : entry.recommendedChoice.icon)
    }
}

struct RunawayWidget: Widget {
    let kind = "RunawayWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: BecomingWidgetProvider()) { entry in
            RunawayWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [ProgressWidgetPalette.ink, Color(red: 0.055, green: 0.105, blue: 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .widgetURL(URL(string: "runaway://today"))
        }
        .configurationDisplayName("Runaway Progress")
        .description("See the distance you've earned, your activity this week, and your goals coming closer.")
        .contentMarginsDisabled()
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
