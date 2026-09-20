import SwiftUI

struct TrainingAdaptationReview: View {
    let snapshot: TrainingSessionPreviewSnapshot
    let workouts: [DailyWorkout]

    var body: some View {
        if let athleteID = snapshot.athleteID {
            VStack(alignment: .leading, spacing: 20) {
                Text("What your completed work supports").font(.headline)
                Text("Results are part of this decision snapshot. These reviews do not increase weights or rewrite your week automatically.")
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(snapshot.goals.filter(\.isActive)) { goal in
                    let assessment = TrainingProgressionService.assess(goalID: goal.id, athleteID: athleteID,
                        results: snapshot.sessionResults, on: snapshot.generatedAt)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(goal.title).font(.subheadline.bold())
                        Text(assessment.state.title).foregroundStyle(AppTheme.Colors.strideBlue)
                        Text(assessment.reason).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                Text("The rest of this week").font(.headline)
                let days = RemainingWeekTrainingPolicy.review(workouts: workouts, results: snapshot.sessionResults,
                    availability: snapshot.availability, on: snapshot.generatedAt)
                if days.isEmpty {
                    Text("No future days remain in this Sunday-to-Saturday training week.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(days) { day in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(day.title).font(.subheadline.bold())
                        Text(day.reason).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Reopen session previews after recording work or changing availability. Exposure counts are recorded days, not physiological workload. Use the prescription review below to accept weekly changes and receive an Undo receipt.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(TrainingProgressionService.version) / \(RemainingWeekTrainingPolicy.version)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
