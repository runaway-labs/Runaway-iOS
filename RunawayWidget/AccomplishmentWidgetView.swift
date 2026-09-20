import SwiftUI
import WidgetKit

enum ProgressWidgetPalette {
    static let ink = Color(red: 0.035, green: 0.065, blue: 0.10)
    static let amber = Color(red: 1, green: 0.72, blue: 0.29)
    static let blue = Color(red: 0.32, green: 0.68, blue: 1)
    static let mint = Color(red: 0.32, green: 0.84, blue: 0.66)
    static let secondary = Color.white.opacity(0.62)

    static func activity(_ kind: ProgressActivityKind) -> Color {
        switch kind {
        case .run: return amber
        case .strength: return blue
        case .walk, .hike: return mint
        case .bike, .swim: return Color(red: 0.32, green: 0.79, blue: 0.89)
        case .mobility: return Color(red: 0.55, green: 0.77, blue: 0.72)
        case .other: return Color.white.opacity(0.52)
        }
    }
}

struct AccomplishmentWidgetView: View {
    enum Size { case small, medium, large }
    let progress: ProgressWidgetSnapshot
    let prescription: WidgetPrescriptionSnapshot?
    let size: Size

    var body: some View {
        Group {
            switch size {
            case .small: small
            case .medium: medium
            case .large: large
            }
        }
        .foregroundStyle(.white)
        .padding(size == .small ? 16 : 18)
    }

    private var wordmark: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("RUNAWAY")
                .font(.system(size: 12, weight: .black, design: .rounded)).italic().tracking(1.4)
                .foregroundStyle(ProgressWidgetPalette.amber).widgetAccentable()
            Spacer(minLength: 6)
            if size == .small {
                Image(systemName: "figure.run").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ProgressWidgetPalette.amber.opacity(0.7))
            } else {
                Text(String(progress.year))
                    .font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1)
                    .foregroundStyle(ProgressWidgetPalette.secondary)
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 7) {
            wordmark
            Spacer(minLength: 0)
            distance(progress.weeklyDistance, available: progress.hasWeeklyData, fontSize: 43)
            Text("RUNNING THIS WEEK")
                .font(.system(size: 8, weight: .bold, design: .rounded)).tracking(1)
                .foregroundStyle(ProgressWidgetPalette.secondary)
            Spacer(minLength: 0)
            if let goal = progress.weeklyGoal, progress.hasWeeklyData {
                EarnedProgressTrack(value: progress.goalWeeklyDistance, goal: goal)
                Text(progress.goalWeeklyDistance >= goal ? "Weekly goal reached" : "\(number(progress.goalWeeklyDistance)) / \(number(goal)) \(progress.goalUnit) goal")
                    .font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(progress.goalWeeklyDistance >= goal ? ProgressWidgetPalette.mint : ProgressWidgetPalette.secondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
            } else {
                Text(progress.hasWeeklyData ? progress.accomplishment : "Open Runaway to sync")
                    .font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(ProgressWidgetPalette.secondary)
            }
            prescriptionStrip(compact: true)
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 11) {
            wordmark
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    distance(progress.weeklyDistance, available: progress.hasWeeklyData, fontSize: 42)
                    Text("RUNNING THIS WEEK").font(.system(size: 8, weight: .bold, design: .rounded)).tracking(0.8)
                        .foregroundStyle(ProgressWidgetPalette.secondary)
                    Text(progress.hasWeeklyData ? progress.accomplishment : "Open Runaway to sync")
                        .font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(ProgressWidgetPalette.mint)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }.frame(maxWidth: .infinity, alignment: .leading)
                ActivityWeekChart(days: progress.days).frame(maxWidth: .infinity).frame(height: 74)
            }
            if let goal = progress.weeklyGoal, progress.hasWeeklyData {
                HStack(spacing: 10) {
                    EarnedProgressTrack(value: progress.goalWeeklyDistance, goal: goal)
                    Text("\(number(progress.goalWeeklyDistance)) / \(number(goal)) \(progress.goalUnit)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(ProgressWidgetPalette.secondary)
                }
            }
            prescriptionStrip(compact: false)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 13) {
            wordmark
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DISTANCE THIS YEAR")
                        .font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.2)
                        .foregroundStyle(ProgressWidgetPalette.secondary)
                    distance(progress.annualDistance, available: progress.hasAnnualData, fontSize: 52)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(progress.hasAnnualData ? String(progress.annualRuns) : "--")
                        .font(.system(size: 23, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("RUNS").font(.system(size: 8, weight: .bold, design: .rounded)).tracking(1)
                        .foregroundStyle(ProgressWidgetPalette.secondary)
                }.padding(.bottom, 5)
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("THIS WEEK").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1)
                    Spacer()
                    Text(progress.hasWeeklyData ? progress.accomplishment : "Open Runaway to sync")
                        .font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(ProgressWidgetPalette.mint)
                        .lineLimit(1)
                }
                ActivityWeekChart(days: progress.days).frame(maxHeight: .infinity)
                HStack(spacing: 10) {
                    ForEach(Array(progress.kinds.prefix(3)), id: \.self) { kind in
                        HStack(spacing: 4) {
                            Circle().fill(ProgressWidgetPalette.activity(kind)).frame(width: 5, height: 5).widgetAccentable()
                            Text(kind.title).font(.system(size: 9, weight: .medium, design: .rounded))
                        }
                    }
                    if progress.kinds.count > 3 { Text("+\(progress.kinds.count - 3)").font(.system(size: 9)) }
                    Spacer(minLength: 0)
                    Text(duration(progress.trainingMinutes)).font(.system(size: 9, weight: .medium, design: .rounded)).monospacedDigit()
                }.foregroundStyle(ProgressWidgetPalette.secondary)
            }.frame(maxHeight: .infinity)

            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            prescriptionStrip(compact: false)
            HStack(spacing: 16) {
                GoalProgressRing(title: "WEEK", value: progress.goalWeeklyDistance, goal: progress.weeklyGoal, unit: progress.goalUnit, available: progress.hasWeeklyData, color: ProgressWidgetPalette.amber)
                GoalProgressRing(title: "MONTH", value: progress.goalMonthlyDistance, goal: progress.monthlyGoal, unit: progress.goalUnit, available: progress.hasMonthlyData, color: ProgressWidgetPalette.mint)
            }
        }
    }

    @ViewBuilder
    private func prescriptionStrip(compact: Bool) -> some View {
        if let prescription {
            HStack(spacing: 7) {
                Image(systemName: prescription.status == .completed ? "checkmark.circle.fill" : "bolt.fill")
                    .foregroundStyle(prescription.status == .completed ? ProgressWidgetPalette.mint : ProgressWidgetPalette.blue)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(prescription.status.label.uppercased()) · \(prescription.title)")
                        .font(.system(size: compact ? 8 : 9, weight: .bold, design: .rounded)).tracking(0.4)
                        .lineLimit(1)
                    if !compact {
                        Text(prescription.detail).font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundStyle(ProgressWidgetPalette.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(prescription.status.label), \(prescription.title), \(prescription.detail)")
        }
    }

    private func distance(_ value: Double, available: Bool, fontSize: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(available ? number(value) : "--")
                .font(.system(size: fontSize, weight: .heavy, design: .rounded)).tracking(-1.5).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(progress.unit).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(ProgressWidgetPalette.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(available ? "\(number(value)) \(progress.unit == "mi" ? "miles" : "kilometers")" : "Distance awaiting sync")
    }

    private func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
    private func duration(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        return total >= 60 ? "\(total / 60)h \(total % 60)m active" : "\(total)m active"
    }
}

private struct EarnedProgressTrack: View {
    let value: Double
    let goal: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(ProgressWidgetPalette.amber)
                    .frame(width: geometry.size.width * min(max(value / max(goal, 0.001), 0), 1))
                    .widgetAccentable()
            }
        }
        .frame(height: 5)
        .accessibilityLabel("Goal progress")
        .accessibilityValue("\(Int((min(max(value / max(goal, 0.001), 0), 1) * 100).rounded())) percent")
    }
}

private struct ActivityWeekChart: View {
    let days: [ProgressWidgetSnapshot.Day]

    var body: some View {
        GeometryReader { geometry in
            let maximum = max(1, days.map(\.minutes).max() ?? 1)
            let barHeight = max(0, geometry.size.height - 20)
            HStack(alignment: .bottom, spacing: 9) {
                ForEach(days) { day in
                    VStack(spacing: 7) {
                        VStack(spacing: 1) {
                            ForEach(day.segments.reversed()) { segment in
                                Rectangle().fill(ProgressWidgetPalette.activity(segment.kind))
                                    .frame(height: max(0, barHeight - CGFloat(max(0, day.segments.count - 1))) * segment.minutes / maximum)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .overlay(alignment: .bottom) {
                            if day.minutes == 0 { Capsule().fill(Color.white.opacity(0.1)).frame(height: 3) }
                        }
                        .widgetAccentable()
                        Text(day.label).font(.system(size: 9, weight: day.isToday ? .bold : .medium, design: .rounded))
                            .foregroundStyle(day.isToday ? Color.white : ProgressWidgetPalette.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.fullLabel), \(Int(day.minutes.rounded())) active minutes")
                }
            }
        }
    }
}

private struct GoalProgressRing: View {
    let title: String
    let value: Double
    let goal: Double?
    let unit: String
    let available: Bool
    let color: Color

    private var fraction: Double { available ? goal.map { min(max(value / $0, 0), 1) } ?? 0 : 0 }

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.09), lineWidth: 4)
                Circle().trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90)).widgetAccentable()
                if fraction >= 1 {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(color)
                } else {
                    Text(available && goal != nil ? "\(Int((fraction * 100).rounded()))%" : "--")
                        .font(.system(size: 10, weight: .bold, design: .rounded)).monospacedDigit()
                }
            }.frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 8, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(ProgressWidgetPalette.secondary)
                Text(available ? "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)" : "Awaiting sync")
                    .font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                Text(goal.map { "of \($0.formatted(.number.precision(.fractionLength(0...1)))) \(unit)" } ?? "No goal set")
                    .font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(ProgressWidgetPalette.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
