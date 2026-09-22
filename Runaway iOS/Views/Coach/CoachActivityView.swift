import SwiftUI

struct CoachActivityView: View {
    let athleteID: Int
    @State private var model: CoachActivityViewModel
    @State private var selectedRecommendation: CoachRecommendationJournalEntry?
    init(athleteID: Int) {
        self.athleteID = athleteID
        let repo = ProtectedTrainingRepository(activeAthleteID: { UserSession.shared.userId })
        let ledger = CoachDecisionLedger(repository: repo, athleteID: athleteID)
        _model = State(initialValue: CoachActivityViewModel(ledger: ledger,
            currentPlan: { DataManager.shared.currentWeeklyPlan },
            activate: { plan, expected in
                guard let current = DataManager.shared.currentWeeklyPlan,
                      try CoachDecisionLedger.fingerprint(of: current) == expected else {
                    throw ProtectedTrainingRepository.RepositoryError.staleCoachDecision
                }
                try DataManager.shared.updateCurrentWeeklyPlan(plan)
            }))
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                heading("RECENT RECOMMENDATIONS", "What Runaway prescribed, why, and when it reached you.")
                if model.recommendations.isEmpty {
                    ContentUnavailableView("No recommendations delivered yet", systemImage: "bolt.heart",
                        description: Text("Scheduled workout recommendations will build your Coach history here."))
                } else {
                    ForEach(model.recommendations.prefix(30)) { recommendationRow($0) }
                }
                if !model.pending.isEmpty {
                    heading("NEEDS YOUR CALL", "Nothing changes until you accept it.")
                    ForEach(model.pending) { row($0) }
                }
                heading("DECISION TRAIL", "What changed, why, and what stayed protected.")
                if model.history.isEmpty {
                    ContentUnavailableView("No coach decisions yet", systemImage: "figure.run.circle",
                        description: Text("Meaningful plan adjustments will appear here."))
                } else { ForEach(model.history) { row($0) } }
            }.padding(AppTheme.Spacing.md)
        }
        .background(AppTheme.Colors.adaptiveBackground).navigationTitle("Coach activity")
        .task { try? model.load(athleteID: athleteID) }.refreshable { try? model.load(athleteID: athleteID) }
        .sheet(item: $selectedRecommendation) { entry in
            WorkoutDetailSheet(
                workout: entry.workout,
                whyToday: entry.whyToday,
                recommendationOnly: entry.recommendationOnly
            )
        }
    }
    private func heading(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(title).font(AppTheme.Typography.caption.weight(.bold)).foregroundStyle(AppTheme.Colors.warmAmber)
            Text(detail).font(AppTheme.Typography.caption).foregroundStyle(AppTheme.Colors.adaptiveTextSecondary)
        }
    }
    private func row(_ decision: CoachDecision) -> some View {
        NavigationLink(value: AppRouter.Route.coachDecision(decision.id)) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack { Text(stateTitle(decision)).font(AppTheme.Typography.headline); Spacer()
                    Text(decision.createdAt, style: .date).font(AppTheme.Typography.caption).foregroundStyle(AppTheme.Colors.adaptiveTextSecondary) }
                Text(decision.changes.first?.after ?? "Plan reviewed").font(AppTheme.Typography.body)
                Text("\(decision.changes.count) change\(decision.changes.count == 1 ? "" : "s") · \(Int(decision.confidence * 100))% evidence confidence")
                    .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.Colors.adaptiveTextSecondary)
            }.padding(AppTheme.Spacing.md)
                .background(AppTheme.Colors.adaptiveCardBackground, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large))
        }.buttonStyle(.plain)
    }
    private func recommendationRow(_ entry: CoachRecommendationJournalEntry) -> some View {
        Button {
            try? model.openRecommendation(entry.id, athleteID: athleteID)
            selectedRecommendation = model.recommendations.first(where: { $0.id == entry.id }) ?? entry
        } label: {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "bolt.heart.fill").foregroundStyle(AppTheme.Colors.warmAmber)
                    Text(entry.workout.title).font(AppTheme.Typography.headline)
                    Spacer()
                    Text(entry.openedAt == nil ? "Delivered" : "Opened")
                        .font(AppTheme.Typography.caption.weight(.semibold))
                        .foregroundStyle(entry.openedAt == nil ? AppTheme.Colors.warmAmber : AppTheme.Colors.adaptiveTextSecondary)
                }
                Text(dose(for: entry.workout))
                    .font(AppTheme.Typography.body.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.adaptiveTextPrimary)
                Text(entry.whyToday)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.adaptiveTextSecondary)
                    .lineLimit(2)
                Text(entry.deliveredAt, format: .dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
                    .font(AppTheme.Typography.caption2)
                    .foregroundStyle(AppTheme.Colors.adaptiveTextSecondary)
            }
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.Colors.adaptiveCardBackground, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large))
        }
        .buttonStyle(.plain)
    }
    private func dose(for workout: DailyWorkout) -> String {
        var pieces: [String] = []
        if let duration = workout.formattedDuration { pieces.append(duration) }
        if workout.workoutType.isRunning, let distance = workout.distance {
            pieces.append(UnitFormatter.formatDistance(distance * 1609.344, decimals: 1, includeUnit: true))
        } else if let count = workout.exercises?.count, count > 0 {
            pieces.append("\(count) exercise\(count == 1 ? "" : "s")")
        }
        return pieces.isEmpty ? workout.workoutType.displayName : pieces.joined(separator: " · ")
    }
    private func stateTitle(_ decision: CoachDecision) -> String {
        if decision.state == .applied,
           decision.reasonCodes.contains(.athleteRequested),
           decision.changes.first?.after.hasPrefix("Committed to ") == true {
            return "Workout committed"
        }
        return switch decision.state { case .proposed: "Review recommendation"; case .applied: "Plan adjusted"; case .rejected: "Original kept";
        case .superseded: "Replaced by newer evidence"; case .undone: "Change undone"; case .blocked: "Change blocked" }
    }
}
