import SwiftUI
import WidgetKit

struct CommitmentWidgetEntryView: View {
    let entry: BecomingWidgetEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("CHOOSE YOUR MOVE").font(.system(size: 9, weight: .black, design: .rounded)).tracking(1).foregroundStyle(BecomingWidgetTheme.blue).widgetAccentable()
                Spacer()
                Text(entry.readiness.map { "\($0) READY" } ?? "CALIBRATING").font(.system(size: 8, weight: .bold, design: .rounded)).foregroundStyle(BecomingWidgetTheme.secondary)
            }
            if family == .systemSmall {
                Text(entry.recommendedPath.title).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(2)
                Text(entry.recommendedPath.weekEffect).font(.system(size: 10, design: .rounded)).foregroundStyle(BecomingWidgetTheme.secondary).lineLimit(2)
                Spacer(minLength: 0)
                Button(intent: ChooseBecomingPathIntent(choice: entry.recommendedChoice)) {
                    Label("Choose best path", systemImage: entry.recommendedChoice.icon).font(.system(size: 10, weight: .bold, design: .rounded)).frame(maxWidth: .infinity, minHeight: 31)
                }.buttonStyle(.plain).tint(BecomingWidgetTheme.mint)
            } else {
                Text("One choice now. The rest of the week responds.").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                HStack(spacing: 7) {
                    ForEach(entry.paths) { path in
                        Button(intent: ChooseBecomingPathIntent(choice: path.choice)) {
                            VStack(spacing: 5) { Image(systemName: path.choice.icon); Text(path.choice.shortTitle).font(.system(size: 7, weight: .black, design: .rounded)) }
                                .foregroundStyle(path.recommended ? BecomingWidgetTheme.mint : .white).frame(maxWidth: .infinity, minHeight: 48)
                                .background(path.recommended ? BecomingWidgetTheme.mint.opacity(0.12) : BecomingWidgetTheme.surface, in: RoundedRectangle(cornerRadius: 11))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.padding(14)
    }
}

struct CommitmentWidget: Widget {
    let kind = "CommitmentWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: BecomingWidgetProvider()) { entry in
            CommitmentWidgetEntryView(entry: entry).containerBackground(for: .widget) { LinearGradient(colors: [BecomingWidgetTheme.background, BecomingWidgetTheme.surface], startPoint: .top, endPoint: .bottomTrailing) }
        }
        .configurationDisplayName("Choose Your Move")
        .description("Make today's training decision without hunting through the app.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
