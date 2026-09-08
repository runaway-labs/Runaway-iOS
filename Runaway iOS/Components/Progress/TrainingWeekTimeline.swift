import SwiftUI

struct TrainingWeekTimeline: View {
    let plan: WeeklyTrainingPlan
    let onSelect: (DailyWorkout) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A week you're building").font(.system(.title3, design: .rounded, weight: .bold))
            Text(PlanProgressPresentation(plan: plan).completionLabel)
                .font(.subheadline).foregroundStyle(TrainingProgressStyle.mint)
            ForEach(plan.workouts.sorted { $0.date < $1.date }) { workout in
                Button { onSelect(workout) } label: {
                    HStack(spacing: 14) {
                        VStack(spacing: 4) {
                            Text(workout.date, format: .dateTime.weekday(.abbreviated)).font(.caption2.bold())
                            Image(systemName: workout.isCompleted && workout.workoutType != .rest ? "checkmark.circle.fill" : workout.workoutType.icon)
                                .font(.title3)
                        }.frame(width: 38).foregroundStyle(tint(workout))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workout.title).font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(.white)
                            Text(status(workout)).font(.caption).foregroundStyle(TrainingProgressStyle.secondary)
                        }
                        Spacer(minLength: 4)
                        if let distance = workout.distance, workout.workoutType.isRunning {
                            Text(UnitFormatter.formatMiles(distance)).font(.caption.weight(.semibold)).foregroundStyle(.white)
                        } else if let duration = workout.duration, workout.workoutType != .rest {
                            Text("\(duration)m").font(.caption.weight(.semibold)).foregroundStyle(.white)
                        }
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(TrainingProgressStyle.secondary)
                    }.padding(.vertical, 12).padding(.horizontal, 10)
                        .frame(minHeight: 58)
                        .background(Calendar.current.isDateInToday(workout.date) ? TrainingProgressStyle.blue.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 14))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }.padding(18).background(TrainingProgressStyle.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.08), lineWidth: 1))
    }
    private func status(_ workout: DailyWorkout) -> String {
        if workout.workoutType == .rest { return "Recovery is part of the plan" }
        if workout.isCompleted { return "Completed" }
        if Calendar.current.isDateInToday(workout.date) { return "Today" }
        return workout.date < Calendar.current.startOfDay(for: Date()) ? "No matching session recorded" : "Planned"
    }
    private func tint(_ workout: DailyWorkout) -> Color {
        workout.isCompleted || workout.workoutType == .rest ? TrainingProgressStyle.mint : TrainingProgressStyle.blue
    }
}
