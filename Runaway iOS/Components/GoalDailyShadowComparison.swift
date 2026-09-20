import SwiftUI

struct GoalDailyShadowComparisonEntry: View {
    let snapshot: TrainingSessionPreviewSnapshot
    @State private var showingComparison = false

    var body: some View {
        Button {
            showingComparison = true
        } label: {
            Label("Compare with Next Up", systemImage: "arrow.left.arrow.right")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(AppTheme.Colors.strideBlue)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .accessibilityIdentifier("compareGoalSelection")
        .sheet(isPresented: $showingComparison) {
            GoalDailyShadowComparisonView(snapshot: snapshot)
        }
    }
}

private struct GoalDailyShadowComparisonView: View {
    let snapshot: TrainingSessionPreviewSnapshot
    @Environment(\.dismiss) private var dismiss
    @Environment(DataManager.self) private var dataManager
    @StateObject private var trainingProfileStore = TrainingProfileStore()
    @StateObject private var readinessService = ReadinessService.shared

    var body: some View {
        let now = Date()
        let plan = dataManager.currentWeeklyPlan
        let planned = plan?.isCurrentWeek == true ? plan?.workout(for: now) : nil
        let readiness = readinessService.todaysReadiness?.score
        let current = TodayRecommendationExplanation.evaluate(
            date: now, profile: trainingProfileStore.profile, plannedWorkout: planned,
            planWorkouts: plan?.workouts ?? [], activities: dataManager.activities,
            readinessScore: readiness
        )
        let candidates = GoalDailyShadowPolicy.candidates(in: snapshot)
        let sameDay = Calendar.current.isDate(snapshot.generatedAt, inSameDayAs: now)
        let decision = sameDay ? GoalDailyShadowPolicy.select(
            candidates: candidates, history: GoalDailyShadowPolicy.history(in: snapshot),
            on: snapshot.generatedAt, readinessScore: readiness,
            preserveUserChoice: current.recommendation.status == "Your Choice"
        ) : GoalDailyShadowPolicy.Decision(blocker: "This profile preview is from another day. Reopen session previews before comparing.")

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Two engines.\nOne honest comparison.")
                            .font(.title2.bold())
                        Text("Compare recommendations without changing anything. Below, you can review a future prescription and explicitly accept its weekly changes. This screen does not start workouts or schedule notifications.")
                            .foregroundStyle(.secondary)
                    }

                    section("Current Next Up") {
                        Text(current.recommendation.title).font(.title3.bold())
                        Text(current.recommendation.reason ?? current.recommendation.detail)
                            .foregroundStyle(.secondary)
                        Text("Recomputed from the existing activity mix and current app data.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    section("Goal-based shadow selection") {
                        if decision.preservesUserChoice {
                            Label("Your choice stays in place", systemImage: "hand.raised")
                            Text("The comparison will not replace an explicit workout or recovery-day choice.")
                        } else if let blocker = decision.blocker {
                            Label("More context needed", systemImage: "info.circle")
                            Text(blocker)
                        } else if let selected = decision.selectedGoalID {
                            Text(goalTitle(selected)).font(.title3.bold())
                            Text(prescriptionSummary(selected))
                            Text("This eligible goal has the largest recent training-share deficit; an older last training day breaks unequal recency ties.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if let rank = decision.rankings.first {
                                let agrees = rank.discipline == .running
                                    ? current.recommendation.workoutType?.isRunning == true
                                    : current.recommendation.workoutType?.isStrength == true
                                Label(agrees ? "Same discipline as Next Up" : "Different discipline from Next Up",
                                      systemImage: agrees ? "equal.circle" : "arrow.left.arrow.right")
                                    .foregroundStyle(AppTheme.Colors.strideBlue)
                            }
                        } else {
                            Text("Both fit. Your preference breaks the tie.").font(.headline)
                            ForEach(decision.choiceGoalIDs, id: \.self) { id in
                                Text(goalTitle(id))
                            }
                            Text("The inputs do not justify ranking one above the other. These are alternatives, not a request to complete all of them.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !decision.rankings.isEmpty {
                        section("The selection math") {
                            Text("Equal-priority disciplines get equal target shares of recorded training days. A positive share deficit means less recent exposure, not lower fitness.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            ForEach(decision.rankings, id: \.goalID) { rank in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(goalTitle(rank.goalID)).font(.subheadline.bold())
                                    Text("\(rank.discipline.rawValue.capitalized): \(rank.completedDays) training \(rank.completedDays == 1 ? "day" : "days") in the previous 7 days")
                                    Text("Share deficit: \(String(format: "%.0f", rank.shareDeficit * 100)) percentage points")
                                    if let last = rank.latestTrainingDay {
                                        Text("Last recorded: \(last.formatted(date: .abbreviated, time: .omitted))")
                                    } else {
                                        Text("No recorded training day in this window")
                                    }
                                }.font(.caption)
                            }
                            Text("Several strength sets on one day count once. Planned and missed sessions do not count. Missing records can affect the comparison.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    if candidates.contains(where: { $0.blocker != nil }) {
                        section("Preview blockers") {
                            ForEach(candidates.filter { $0.blocker != nil }, id: \.goalID) { candidate in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(goalTitle(candidate.goalID)).font(.subheadline.bold())
                                    Text(candidate.blocker ?? "Preview unavailable")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if sameDay, let athleteID = snapshot.athleteID {
                        ProgressionAndWeekReview(snapshot: snapshot,
                            workouts: plan?.athleteId == athleteID ? (plan?.workouts ?? []) : [])
                    }

                    section("What this changes") {
                        Text("Confirmed results support session proposals and progression review. Accepting a prescription updates a future day and the reviewed weekly changes; Undo is available while the plan and training data remain unchanged. The scheduler still uses your existing activity mix. These are not physiological workload or injury-risk predictions.")
                        Text("The goal snapshot was captured \(snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened)); Next Up was evaluated \(current.evaluatedAt.formatted(date: .omitted, time: .shortened)). They may contain different records. Reopen previews after saving goals or performance.")
                        Text("Policy: \(GoalDailyShadowPolicy.version)")
                    }.font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(20)
            }
            .navigationTitle("Daily comparison")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func goalTitle(_ id: UUID) -> String {
        snapshot.goals.first(where: { $0.id == id })?.title ?? "Training goal"
    }

    private func prescriptionSummary(_ id: UUID) -> String {
        guard let session = snapshot.sessions.first(where: { $0.goalID == id }) else { return "Preview unavailable" }
        switch session.outcome {
        case .running(let run):
            return "\(run.totalSeconds / 60) min including warm-up and cooldown. See the session preview for the full effort guidance."
        case .strength:
            guard case .session(let strength) = snapshot.completeStrengthSessions[id] else {
                return "Complete strength prescription unavailable. Resolve the preview blockers first."
            }
            return "\(strength.blocks.count) movements, \(strength.totalSeconds / 60) min \(strength.totalSeconds % 60) sec including warm-up, setup, rest and cooldown. See session previews for each exercise's sets, reps and load guidance."
        case .needsInput(let message):
            return message
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
