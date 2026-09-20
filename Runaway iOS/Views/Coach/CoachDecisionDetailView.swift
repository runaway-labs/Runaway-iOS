import SwiftUI

struct CoachDecisionDetailView: View {
    let athleteID: Int
    let decisionID: UUID
    @Environment(DataManager.self) private var dataManager
    @State private var decision: CoachDecision?
    @State private var model: CoachActivityViewModel?
    @State private var errorMessage: String?
    var body: some View {
        ScrollView {
            if let decision { VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text(decision.state == .proposed ? "YOU DECIDE" : "DECISION RECORDED")
                        .font(AppTheme.Typography.caption.weight(.bold)).foregroundStyle(AppTheme.Colors.warmAmber)
                    Text(decision.state == .proposed ? "A meaningful change needs your approval" : "Your week changed with a paper trail")
                        .font(AppTheme.Typography.title)
                    Text("Deterministic training policy made this call. On-device intelligence may explain it, but cannot alter the prescription.")
                        .font(AppTheme.Typography.body).foregroundStyle(AppTheme.Colors.adaptiveTextSecondary)
                }
                ForEach(decision.changes) { change in
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Label(change.kind.rawValue.capitalized, systemImage: "arrow.left.arrow.right").font(AppTheme.Typography.headline)
                        if let before = change.before { comparison("BEFORE", before, false) }
                        comparison("AFTER", change.after, true)
                    }.padding(AppTheme.Spacing.lg)
                        .background(AppTheme.Colors.adaptiveCardBackground, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large))
                }
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Label("Why this call", systemImage: "scope").font(AppTheme.Typography.headline)
                    Text(decision.reasonCodes.map(\.rawValue).joined(separator: " · ").capitalized)
                        .foregroundStyle(AppTheme.Colors.adaptiveTextSecondary)
                    Text("Evidence confidence \(Int(decision.confidence * 100))%").font(AppTheme.Typography.caption.weight(.semibold))
                    if !decision.missingData.isEmpty { Text("Missing: " + decision.missingData.joined(separator: ", ")).foregroundStyle(AppTheme.Colors.warning) }
                }
                actionButtons(decision)
            }.padding(AppTheme.Spacing.md) } else { ProgressView().padding(.top, 80) }
        }.background(AppTheme.Colors.adaptiveBackground).navigationTitle("Coach decision").navigationBarTitleDisplayMode(.inline)
            .task { load() }
            .alert("Couldn’t apply that change", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { }
            } message: { Text(errorMessage ?? "Review the current plan and try again.") }
    }
    private func comparison(_ label: String, _ value: String, _ emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) { Text(label).font(AppTheme.Typography.caption.weight(.bold)).foregroundStyle(AppTheme.Colors.adaptiveTextSecondary)
            Text(value).font(emphasized ? AppTheme.Typography.headline : AppTheme.Typography.body) }
    }
    @ViewBuilder private func actionButtons(_ decision: CoachDecision) -> some View {
        if let model { let actions = model.availableActions(for: decision)
            if actions.contains(.accept) {
                Button("Accept updated week") { perform { try model.accept(decision.id) } }.buttonStyle(.borderedProminent).tint(AppTheme.Colors.warmAmber)
                Button("Keep my original week") { perform { try model.keepOriginal(decision.id) } }.buttonStyle(.bordered)
            } else if actions.contains(.undo) { Button("Undo this change") { perform { _ = try model.undo(decision.id) } }.buttonStyle(.bordered) }
        }
    }
    private func load() {
        let repo = ProtectedTrainingRepository(activeAthleteID: { UserSession.shared.userId })
        let ledger = CoachDecisionLedger(repository: repo, athleteID: athleteID)
        let vm = CoachActivityViewModel(ledger: ledger, currentPlan: { dataManager.currentWeeklyPlan }, activate: { plan, expected in
            guard let current = dataManager.currentWeeklyPlan, try CoachDecisionLedger.fingerprint(of: current) == expected else { throw ProtectedTrainingRepository.RepositoryError.staleCoachDecision }
            try dataManager.updateCurrentWeeklyPlan(plan) })
        model = vm; try? vm.load(athleteID: athleteID); decision = (vm.pending + vm.history).first { $0.id == decisionID }
    }
    private func perform(_ operation: () throws -> Void) { do { try operation(); load() } catch { errorMessage = model?.errorMessage ?? error.localizedDescription } }
}
