import SwiftUI

struct CoachWeekBoard: View {
    enum UserAction {
        case commit(String)
        case change(String)
        case viewWorkout(String)
        case reviewResult(String)
        case reviewCoachDecision(UUID)
    }

    let presentation: CoachWeekBoardPresentation
    var focusTitle: String? = nil
    var focusDescription: String? = nil
    var isRegenerating = false
    var onRegenerate: (() -> Void)? = nil
    let onAction: (UserAction) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            header
            VStack(spacing: 0) {
                ForEach(Array(presentation.days.enumerated()), id: \.element.id) { index, day in
                    dayRow(day, isLast: index == presentation.days.count - 1)
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(TrainingProgressStyle.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.08), lineWidth: 1))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Text("THIS WEEK · \(presentation.weekRange.uppercased())")
                    .font(.system(.caption, design: .rounded, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(TrainingProgressStyle.amber)

                Spacer()

                Text("\(presentation.completedSessionCount)/\(presentation.plannedSessionCount)")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(TrainingProgressStyle.mint)
                    .accessibilityLabel("\(presentation.completedSessionCount) of \(presentation.plannedSessionCount) sessions complete")

                if let onRegenerate {
                    Button(action: onRegenerate) {
                        Group {
                            if isRegenerating {
                                ProgressView()
                                    .tint(TrainingProgressStyle.amber)
                                    .scaleEffect(0.75)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                        }
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TrainingProgressStyle.amber)
                    .disabled(isRegenerating)
                    .accessibilityLabel("Rebuild remaining weekly schedule")
                }
            }

            if let focusTitle {
                VStack(alignment: .leading, spacing: 6) {
                    Text(focusTitle.uppercased())
                        .font(.system(.caption2, design: .rounded, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(TrainingProgressStyle.amber)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(TrainingProgressStyle.amber.opacity(0.12), in: Capsule())

                    if let focusDescription {
                        Text(focusDescription)
                            .font(.subheadline)
                            .foregroundStyle(TrainingProgressStyle.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(presentation.weeklyFocus)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: AppTheme.Spacing.sm)
                Text("\(presentation.plannedMinutes) MIN")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(TrainingProgressStyle.secondary)
            }
        }
    }

    private func dayRow(_ day: CoachWeekBoardPresentation.Day, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                statusNode(day)
                if !isLast {
                    Rectangle()
                        .fill(Color.white.opacity(0.09))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 34)

            VStack(alignment: .leading, spacing: day.isToday ? 9 : 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(day.weekday) \(day.dayNumber)")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(day.isToday ? TrainingProgressStyle.amber : TrainingProgressStyle.secondary)
                    Spacer(minLength: 8)
                    Label(day.status.label, systemImage: statusSymbol(day.status))
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(statusTint(day.status))
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(day.title)
                    .font(.system(.headline, design: .rounded, weight: day.isToday ? .bold : .semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(day.dose)
                    .font(.subheadline)
                    .foregroundStyle(TrainingProgressStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let decisionID = day.adaptationDecisionID {
                    Button { onAction(.reviewCoachDecision(decisionID)) } label: {
                        Label("Rebalanced", systemImage: "arrow.triangle.branch")
                            .font(.caption.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TrainingProgressStyle.blue)
                }

                HStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(day.actions, id: \.self) { action in
                        actionButton(action, day: day)
                    }
                }
            }
            .padding(.vertical, day.isToday ? 15 : 11)
            .padding(.horizontal, day.isToday ? 12 : 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(day.isToday ? TrainingProgressStyle.amber.opacity(0.07) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .contain)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: day.status)
    }

    private func statusNode(_ day: CoachWeekBoardPresentation.Day) -> some View {
        ZStack {
            Circle().fill(statusTint(day.status).opacity(day.isToday ? 0.24 : 0.13))
            Image(systemName: statusSymbol(day.status))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(statusTint(day.status))
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }

    private func actionButton(_ action: CoachWeekBoardPresentation.Action,
                              day: CoachWeekBoardPresentation.Day) -> some View {
        Button {
            switch action {
            case .commit: onAction(.commit(day.workoutID))
            case .change: onAction(.change(day.workoutID))
            case .viewWorkout: onAction(.viewWorkout(day.workoutID))
            case .reviewResult: onAction(.reviewResult(day.workoutID))
            }
        } label: {
            Text(action.label)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .frame(maxWidth: action == .commit ? .infinity : nil, minHeight: 44)
                .padding(.horizontal, action == .commit ? 14 : 4)
        }
        .buttonStyle(.plain)
        .foregroundStyle(action == .commit ? Color.black : TrainingProgressStyle.blue)
        .background(action == .commit ? TrainingProgressStyle.amber : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private func statusTint(_ status: CoachWeekBoardPresentation.Status) -> Color {
        switch status {
        case .recommended, .committed: TrainingProgressStyle.amber
        case .completed: TrainingProgressStyle.mint
        case .partial: .orange
        case .upcoming: TrainingProgressStyle.blue
        case .rest, .missed: TrainingProgressStyle.secondary
        }
    }

    private func statusSymbol(_ status: CoachWeekBoardPresentation.Status) -> String {
        switch status {
        case .recommended: "bolt.fill"
        case .committed: "checkmark.seal.fill"
        case .completed: "checkmark.circle.fill"
        case .partial: "circle.lefthalf.filled"
        case .upcoming: "clock.fill"
        case .rest: "moon.zzz.fill"
        case .missed: "circle.dashed"
        }
    }
}

#Preview("Coach week board") {
    ScrollView {
        CoachWeekBoard(
            presentation: .init(
                weekRange: "Sep 20–26", completedSessionCount: 2, plannedSessionCount: 5,
                plannedMinutes: 220, weeklyFocus: "3 runs · 2 strength sessions",
                days: [
                    previewDay("sun", "SUN", "20", "Endurance Run", .easyRun, "40 min · 4.0 mi · 10:15 /mi", .completed),
                    previewDay("mon", "MON", "21", "Full Body Strength", .strengthTraining, "45 min · 5 exercises", .committed, today: true),
                    previewDay("tue", "TUE", "22", "Recovery Walk", .walking, "30 min · 1.5 mi", .partial),
                    previewDay("wed", "WED", "23", "Intervals", .intervalRun, "35 min · 3.5 mi · 9:10 /mi", .upcoming),
                    previewDay("thu", "THU", "24", "Rest", .rest, "Recovery is part of the plan", .rest),
                    previewDay("fri", "FRI", "25", "Easy Run", .easyRun, "30 min · 3.0 mi", .upcoming),
                    previewDay("sat", "SAT", "26", "Mobility", .yoga, "20 min", .missed)
                ]
            ),
            onAction: { _ in }
        )
        .padding()
    }
    .background(AppTheme.Colors.DarkMode.background)
    .preferredColorScheme(.dark)
    .environment(\.dynamicTypeSize, .accessibility2)
}

private func previewDay(_ id: String, _ weekday: String, _ number: String, _ title: String,
                        _ type: WorkoutType, _ dose: String,
                        _ status: CoachWeekBoardPresentation.Status,
                        today: Bool = false) -> CoachWeekBoardPresentation.Day {
    .init(id: id, workoutID: id, date: Date(), weekday: weekday, dayNumber: number,
          title: title, modality: type, dose: dose, status: status,
          actions: status == .completed || status == .partial ? [.reviewResult] : [.viewWorkout],
          adaptationDecisionID: nil, isToday: today)
}
