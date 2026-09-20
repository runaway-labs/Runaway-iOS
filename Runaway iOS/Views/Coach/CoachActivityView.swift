import SwiftUI

struct CoachActivityView: View {
    let athleteID: Int
    @State private var model: CoachActivityViewModel
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
                if !model.pending.isEmpty {
                    heading("NEEDS YOUR CALL", "Nothing changes until you accept it.")
                    ForEach(model.pending) { row($0) }
                }
                heading("DECISION TRAIL", "What changed, why, and what stayed protected.")
                if model.history.isEmpty && model.pending.isEmpty {
                    ContentUnavailableView("No coach decisions yet", systemImage: "figure.run.circle",
                        description: Text("Meaningful plan adjustments will appear here."))
                } else { ForEach(model.history) { row($0) } }
            }.padding(AppTheme.Spacing.md)
        }
        .background(AppTheme.Colors.adaptiveBackground).navigationTitle("Coach activity")
        .task { try? model.load(athleteID: athleteID) }.refreshable { try? model.load(athleteID: athleteID) }
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
                HStack { Text(stateTitle(decision.state)).font(AppTheme.Typography.headline); Spacer()
                    Text(decision.createdAt, style: .date).font(AppTheme.Typography.caption).foregroundStyle(AppTheme.Colors.adaptiveTextSecondary) }
                Text(decision.changes.first?.after ?? "Plan reviewed").font(AppTheme.Typography.body)
                Text("\(decision.changes.count) change\(decision.changes.count == 1 ? "" : "s") · \(Int(decision.confidence * 100))% evidence confidence")
                    .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.Colors.adaptiveTextSecondary)
            }.padding(AppTheme.Spacing.md)
                .background(AppTheme.Colors.adaptiveCardBackground, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large))
        }.buttonStyle(.plain)
    }
    private func stateTitle(_ state: CoachDecisionState) -> String {
        switch state { case .proposed: "Review recommendation"; case .applied: "Plan adjusted"; case .rejected: "Original kept";
        case .superseded: "Replaced by newer evidence"; case .undone: "Change undone"; case .blocked: "Change blocked" }
    }
}
