import SwiftUI

struct GoalSessionPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: TrainingSessionPreviewSnapshot

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introduction
                    if snapshot.sessions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Give your training a destination", systemImage: "target")
                                .font(.headline)
                            Text("Add and save an active running or strength goal to see a session preview. No goal has been invented for you.")
                                .foregroundStyle(.secondary)
                            Button("Back to profile") { dismiss() }
                        }
                        .padding(20)
                        .background(AppTheme.Colors.adaptiveCardBackground, in: RoundedRectangle(cornerRadius: 20))
                    }
                    ForEach(snapshot.sessions, id: \.goalID) { preview in
                        sessionCard(preview)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Keep this snapshot current").font(.subheadline.bold())
                        Text("Reopen this screen after changing goals, availability, or completed performance. These are session options, not automatic changes to your weekly plan.")
                        Text(snapshot.generatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        Text("Policy: \(snapshot.policyVersion)")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(LinearGradient(colors: [AppTheme.Colors.adaptiveBackground, Color.teal.opacity(0.08)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .navigationTitle("Session previews")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.teal)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onReceive(NotificationCenter.default.publisher(for: .trainingSessionInvalidated)) { _ in dismiss() }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GOALS INTO ACTION").font(AppTheme.Typography.caption).foregroundStyle(.teal)
            Text("See the work.\nUnderstand the why.")
                .font(AppTheme.Typography.title)
                .fixedSize(horizontal: false, vertical: true)
            Text("Options from your saved goals and recorded performance, not a generic workout title.")
                .foregroundStyle(.secondary)
            Label("Options to review. Plan changes require acceptance.", systemImage: "eye")
                .font(.subheadline.weight(.medium))
            Text("These are alternatives, not instructions to do every card today. Equal-priority goals remain equal; card order is not a ranking.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func sessionCard(_ preview: GoalSessionPreview) -> some View {
        let goal = snapshot.goals.first { $0.id == preview.goalID }
        let accent: Color = preview.discipline == .running ? .blue : .teal
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Label(preview.discipline == .running ? "Running" : "Strength",
                    systemImage: preview.discipline == .running ? "figure.run" : "dumbbell.fill")
                    .foregroundStyle(accent).font(.headline)
                Spacer(minLength: 8)
                Text(preview.priority == .equalPrimary ? "Equal priority" : "Supporting")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(goal?.title ?? "Saved goal")
                .font(AppTheme.Typography.headline)
                .fixedSize(horizontal: false, vertical: true)
            switch preview.outcome {
            case .needsInput(let reason):
                Label("One more piece of context", systemImage: "info.circle")
                    .font(.subheadline.bold())
                Text(reason).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Back to profile") { dismiss() }
            case .running(let session):
                Text("\(duration(session.totalSeconds)) total")
                    .font(.title2.bold()).monospacedDigit()
                detail("Warm up", duration(session.warmupSeconds))
                detail("Easy running", duration(session.runningSeconds))
                detail("Cool down", duration(session.cooldownSeconds))
                Text(session.effortInstruction).font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                explanation(preview)
            case .strength(let session):
                Text(TrainingExerciseCatalog.title(session.exerciseID))
                    .font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                Text("\(session.sets) sets of \(session.repetitions.lowerBound)-\(session.repetitions.upperBound) reps")
                    .font(.title2.bold()).monospacedDigit()
                Text(resistance(session.resistance, unit: goal?.enteredLoadUnit ?? .pounds))
                    .font(.headline).foregroundStyle(accent)
                    .fixedSize(horizontal: false, vertical: true)
                detail("Planned time", duration(session.totalSeconds))
                detail("Warm up", duration(session.warmupSeconds))
                detail("Setup allowance", duration(session.setupSeconds))
                detail("Work allowance per set", duration(session.secondsReservedPerSet))
                detail("Rest between sets", duration(session.restBetweenSetsSeconds))
                detail("Cool down", duration(session.cooldownSeconds))
                Text(session.effortInstruction).font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                explanation(preview)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Colors.adaptiveCardBackground, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(accent.opacity(0.22), lineWidth: 1))
    }

    private func explanation(_ preview: GoalSessionPreview) -> some View {
        DisclosureGroup("Why this session?") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(preview.reasons.enumerated()), id: \.offset) { _, reason in
                    Text(reason).fixedSize(horizontal: false, vertical: true)
                }
                if !preview.evidenceIDs.isEmpty {
                    let evidence = snapshot.observations.filter { preview.evidenceIDs.contains($0.id) }
                    Text("Based on \(evidence.count) recorded performance(s).")
                    if let date = evidence.map(\.measuredAt).max() {
                        Text("Latest supporting performance: \(date.formatted(date: .abbreviated, time: .omitted))")
                    }
                } else {
                    Text("No measured working load is being assumed.")
                }
            }
            .font(.footnote).foregroundStyle(.secondary)
            .padding(.top, 8)
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }.font(.subheadline).fixedSize(horizontal: false, vertical: true)
    }

    private func duration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        if minutes == 0 { return "\(remainder) sec" }
        return remainder == 0 ? "\(minutes) min" : "\(minutes) min \(remainder) sec"
    }

    private func resistance(_ value: GoalSessionPreview.Resistance, unit: TrainingMassUnit) -> String {
        func mass(_ kilograms: Double) -> String {
            let number = unit == .pounds ? kilograms / 0.45359237 : kilograms
            return "\(number.formatted(.number.precision(.fractionLength(0...2)))) \(unit == .pounds ? "lb" : "kg")"
        }
        func convention(_ value: LoadConvention) -> String {
            switch value {
            case .total: return "total external load"
            case .perHand: return "per hand"
            case .machine: return "on this machine"
            case .bodyweight: return "bodyweight"
            }
        }
        switch value {
        case .chooseComfortableLoad(let loadConvention):
            return "Choose a comfortable load (\(convention(loadConvention))). No weight inferred."
        case .external(let kilograms, let loadConvention):
            return "\(mass(kilograms)) \(convention(loadConvention))"
        case .bodyweight: return "Bodyweight, no added load"
        case .assistedBodyweight(let kilograms, let equipmentID):
            return "\(mass(kilograms)) assistance, not added load" + (equipmentID.map { " (\($0))" } ?? "")
        }
    }
}
