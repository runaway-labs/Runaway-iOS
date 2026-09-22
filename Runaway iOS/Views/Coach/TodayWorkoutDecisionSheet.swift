import SwiftUI

struct TodayWorkoutDecisionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataManager.self) private var dataManager
    @State private var model: TodayWorkoutDecisionViewModel
    private let startChoosing: Bool

    init(
        plan: WeeklyTrainingPlan,
        profile: TrainingProfile,
        recommendedWorkout: DailyWorkout,
        startChoosing: Bool
    ) {
        _model = State(initialValue: TodayWorkoutDecisionViewModel(
            plan: plan, profile: profile, recommendedWorkout: recommendedWorkout,
            date: recommendedWorkout.date
        ))
        self.startChoosing = startChoosing
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    coachHeader
                    if model.phase == .previewing || model.phase == .committing || model.phase == .failed {
                        previewContent
                    } else {
                        decisionContent
                    }
                }
                .padding(20)
            }
            .background(AppTheme.Colors.DarkMode.background.ignoresSafeArea())
            .navigationTitle("Performance Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task {
            guard model.phase == .loading else { return }
            model.load()
            if startChoosing { model.showChoices() }
            else { model.select(model.recommendedChoiceID) }
        }
    }

    private var coachHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("TODAY'S DECISION", systemImage: "bolt.heart.fill")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(TrainingProgressStyle.amber)
            Text("Choose the work. See the consequence.")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
            Text("Nothing changes until you review the week and commit.")
                .font(.subheadline)
                .foregroundStyle(TrainingProgressStyle.secondary)
        }
    }

    @ViewBuilder private var decisionContent: some View {
        if model.phase == .choosing {
            choiceCatalog
        }
        if let draft = model.draft {
            TodayWorkoutPrescriptionEditor(draft: draft, onUpdate: model.updateDraft)
            Button {
                do { try model.buildPreview() } catch { }
            } label: {
                Label("Review week impact", systemImage: "calendar.badge.clock")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.black)
            .background(TrainingProgressStyle.amber, in: RoundedRectangle(cornerRadius: 16))
            .disabled(!model.canPreview)

            if model.phase != .choosing {
                Button("Choose something else") { model.showChoices() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TrainingProgressStyle.blue)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        if let blocker = model.blockerMessage {
            Label(blocker, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(TrainingProgressStyle.amber)
                .padding(14)
                .background(TrainingProgressStyle.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var choiceCatalog: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ALL OF YOUR OPTIONS")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(TrainingProgressStyle.secondary)
            ForEach(model.choices) { choice in
                Button { model.select(choice.id) } label: {
                    HStack(spacing: 13) {
                        Image(systemName: choice.workoutType.icon)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(choice.isRecommended ? TrainingProgressStyle.amber : TrainingProgressStyle.blue)
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(choice.title).font(.headline)
                                if choice.isRecommended {
                                    Text("COACH PICK").font(.caption2.bold()).foregroundStyle(TrainingProgressStyle.amber)
                                }
                            }
                            Text(choice.reason).font(.caption).foregroundStyle(TrainingProgressStyle.secondary).lineLimit(2)
                            if case .blocked(let blocker) = choice.availability {
                                Text(blocker.message).font(.caption2).foregroundStyle(TrainingProgressStyle.amber)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(TrainingProgressStyle.secondary)
                    }
                    .padding(14)
                    .background(TrainingProgressStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .accessibilityIdentifier("todayChoice.\(choice.id)")
            }
            if let legacy = dataManager.todaysCommitment,
               let plan = dataManager.currentWeeklyPlan,
               let proposal = LegacyCommitmentMigrationService.proposal(
                legacy: legacy, plan: plan, profile: TrainingProfileStore.shared.profile
               ) {
                Button { model.useLegacyDraft(proposal.draft) } label: {
                    Label("Review old commitment", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.plain)
                .foregroundStyle(TrainingProgressStyle.mint)
                .background(TrainingProgressStyle.mint.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
            }
            Menu {
                Button("Custom run") { model.useCustomRun() }
                Button("Custom strength") { model.useCustomStrength() }
            } label: {
                Label("Build my own", systemImage: "slider.horizontal.3")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .foregroundStyle(TrainingProgressStyle.blue)
            .background(TrainingProgressStyle.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder private var previewContent: some View {
        if let preview = model.preview, let draft = model.draft {
            WeekImpactPreview(preview: preview)
            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Button {
                do {
                    try model.commit { try dataManager.commitTodayWorkout($0) }
                    dismiss()
                } catch { }
            } label: {
                Text(model.phase == .committing ? "Committing..." : "Commit to \(draft.workout.title)")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.black)
            .background(TrainingProgressStyle.amber, in: RoundedRectangle(cornerRadius: 16))
            .disabled(model.phase == .committing)
            Button("Back to choices") { model.showChoices() }
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(TrainingProgressStyle.blue)
        }
    }
}

struct TodayWorkoutPrescriptionEditor: View {
    let draft: TodayWorkoutDraft
    let onUpdate: (TodayWorkoutDraft) -> Void
    @State private var minutes: Int
    @State private var distanceText: String

    init(draft: TodayWorkoutDraft, onUpdate: @escaping (TodayWorkoutDraft) -> Void) {
        self.draft = draft
        self.onUpdate = onUpdate
        _minutes = State(initialValue: draft.workout.duration ?? 30)
        _distanceText = State(initialValue: draft.workout.distance.map { String(format: "%.1f", $0) } ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Image(systemName: draft.workout.workoutType.icon)
                    .font(.title2).foregroundStyle(TrainingProgressStyle.amber)
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.workout.title).font(.title3.bold())
                    Text(draft.reason).font(.caption).foregroundStyle(TrainingProgressStyle.secondary)
                }
            }
            if draft.workout.workoutType != .rest {
                Stepper("\(minutes) minutes", value: $minutes, in: 10...180, step: 5)
                    .onChange(of: minutes) { _, value in publish(minutes: value) }
            }
            if draft.workout.workoutType.isRunning {
                TextField("Distance in miles, optional", text: $distanceText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: distanceText) { _, _ in publish(minutes: minutes) }
            }
            if let exercises = draft.workout.exercises {
                ForEach(exercises) { exercise in
                    HStack {
                        Text(exercise.name).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(exercise.sets ?? 0) × \(exercise.reps ?? "-")")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(TrainingProgressStyle.secondary)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(TrainingProgressStyle.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private func publish(minutes: Int) {
        onUpdate(draft.updating(duration: draft.workout.workoutType == .rest ? nil : minutes,
                                distance: Double(distanceText)))
    }
}

struct WeekImpactPreview: View {
    let preview: TodayWorkoutDecisionPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("WEEK IMPACT")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.2).foregroundStyle(TrainingProgressStyle.mint)
            ForEach(preview.changes) { change in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: change.kind == .moved ? "arrow.right.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(change.kind == .moved ? TrainingProgressStyle.blue : TrainingProgressStyle.mint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(change.title).font(.subheadline.weight(.semibold))
                        Text(change.detail).font(.caption).foregroundStyle(TrainingProgressStyle.secondary)
                    }
                }
            }
            Label("Completed sessions stay protected", systemImage: "lock.fill")
                .font(.caption).foregroundStyle(TrainingProgressStyle.secondary)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(TrainingProgressStyle.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}
