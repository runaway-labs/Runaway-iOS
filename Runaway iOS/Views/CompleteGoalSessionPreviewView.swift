import SwiftUI

struct CompleteGoalSessionPreviewView: View {
    let snapshot: TrainingSessionPreviewSnapshot
    @Environment(\.dismiss) private var dismiss
    @State private var recording: TrainingSessionResult.Reference?
    @State private var showingResults = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("See the work.\nUnderstand the why.")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text("Specific options from your saved goals and recorded performance. Choose one, not every session shown here.")
                        .foregroundStyle(.secondary)
                    Label("Options to review. Plan changes require acceptance.", systemImage: "eye").font(.caption)
                    if snapshot.athleteID != nil {
                        Button("Completed session records") { showingResults = true }
                    }
                    if snapshot.sessions.isEmpty {
                        Text("Save an active goal to preview its sessions.")
                        Button("Back to profile") { dismiss() }
                    }
                    ForEach(snapshot.sessions, id: \.goalID) { preview in
                        VStack(alignment: .leading, spacing: 14) {
                            Text(preview.priority == .equalPrimary ? "Equal priority" : "Supporting goal")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(snapshot.goals.first(where: { $0.id == preview.goalID })?.title ?? "Training goal")
                                .font(.headline)
                            prescription(preview)
                            DisclosureGroup("Why this session?") {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(preview.reasons, id: \.self) { reason in
                                        Text(reason == "This is one goal-specific exercise block, not a complete balanced strength program."
                                             ? "The goal exercise anchors a four-pattern session. Complementary movements include their own sets, load guidance, setup, and recovery time; this is not yet a complete weekly program."
                                             : reason)
                                    }
                                    Text("Equal-priority goals remain equal. Card order is not a ranking.")
                                }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(16)
                        .background(AppTheme.Colors.strideBlue.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.Colors.strideBlue.opacity(0.18)))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Keep this snapshot current").font(.subheadline.bold())
                        Text("Reopen after changing goals, availability, or completed performance. Compare with Next Up includes progression proposals and a weekly review. Only explicit acceptance changes your plan.")
                        Text("Generated \(snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                        Text("\(snapshot.policyVersion) / \(CompleteStrengthSessionPolicy.version) / \(RunningPrescriptionPolicy.version)")
                    }.font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: 640, alignment: .leading).padding(20)
            }
            .background(LinearGradient(colors: [AppTheme.Colors.strideBlue.opacity(0.08), Color(.systemBackground)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .navigationTitle("Session previews")
            .navigationBarTitleDisplayMode(.inline)
            .tint(AppTheme.Colors.strideBlue)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $recording) { TrainingSessionResultView(reference: $0) }
            .sheet(isPresented: $showingResults) {
                if let athleteID = snapshot.athleteID { TrainingSessionHistoryView(athleteID: athleteID) }
            }
        }
    }

    @ViewBuilder private func prescription(_ preview: GoalSessionPreview) -> some View {
        switch preview.outcome {
        case .needsInput(let reason): blocker(reason)
        case .running(let run):
            RunningPrescriptionPreview(
                run: run,
                goal: snapshot.goals.first { $0.id == preview.goalID },
                evidence: snapshot.observations.first { preview.evidenceIDs.contains($0.id) },
                onRecord: snapshot.athleteID == nil ? nil : { blocks in
                    recording = TrainingSessionReferenceBuilder.make(snapshot: snapshot, preview: preview, runningBlocks: blocks)
                }
            ).id(snapshot.fingerprint + preview.goalID.uuidString)
        case .strength:
            switch snapshot.completeStrengthSessions[preview.goalID] {
            case .session(let session):
                strengthSession(session, goalID: preview.goalID)
                if snapshot.athleteID != nil {
                    Button("Record completed session") {
                        recording = TrainingSessionReferenceBuilder.make(snapshot: snapshot, preview: preview)
                    }
                    Text("Only record work you have actually done. You will review actual reps, loads and effort before saving.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .needsInput(let reason): blocker(reason)
            case nil: blocker("Reopen session previews to generate the complete strength prescription.")
            }
        }
    }

    private func strengthSession(_ session: CompleteStrengthSessionPolicy.Session, goalID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Full-body strength preview", systemImage: "dumbbell").foregroundStyle(AppTheme.Colors.recoveryMint)
            Text("\(duration(session.totalSeconds)) total").font(.title3.bold())
            Text("\(session.blocks.count) movements. Goal exercise first; complementary patterns follow.")
                .font(.subheadline).foregroundStyle(.secondary)
            if session.setsReducedForTime {
                Label("Fewer sets to fit your available time. Every movement pattern is retained.", systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary)
            }
            timeRow("Warm up", seconds: session.warmupSeconds)
            Text("Easy movement, then rehearse the exercises with a light load or easier variation.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(session.blocks, id: \.exerciseID) { block in
                VStack(alignment: .leading, spacing: 8) {
                    Text(block.name).font(.headline)
                    Text("\(block.sets) \(block.sets == 1 ? "set" : "sets") of \(block.repetitions.lowerBound)-\(block.repetitions.upperBound) reps\(block.eachSide ? " each side" : "")")
                        .font(.subheadline.bold())
                    Text(resistance(block.resistance, goalID: goalID))
                        .foregroundStyle(block.requiresCalibration ? Color.secondary : AppTheme.Colors.recoveryMint)
                    if block.requiresCalibration {
                        Text("Calibration: start with an easy variation or light load. Finish with 2-3 good reps in reserve; this is not a maximum-effort test.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    timeRow("Setup / rehearsal", seconds: block.setupSeconds)
                    timeRow(block.eachSide ? "Work allowance per set, both sides" : "Work allowance per set", seconds: block.secondsPerSet)
                    if block.sets > 1 { timeRow("Rest between sets", seconds: block.restSeconds) }
                }.font(.subheadline).padding(.vertical, 8)
                Divider()
            }
            timeRow("Cool down", seconds: session.cooldownSeconds)
            Text("Easy walking and relaxed breathing. Time allowances include setup and rest, not a requirement to rush. Use a comfortable range, reduce difficulty if needed, and stop if painful.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Four movement patterns do not establish weekly balance, progression, or recovery readiness. Bodyweight upper-back work is not equivalent to loaded pulling or pull-up progression.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func resistance(_ value: GoalSessionPreview.Resistance, goalID: UUID) -> String {
        let pounds = snapshot.goals.first(where: { $0.id == goalID })?.enteredLoadUnit == .pounds
        func load(_ kilograms: Double) -> String {
            let value = pounds ? kilograms / 0.45359237 : kilograms
            return "\(value.formatted(.number.precision(.fractionLength(0...2)))) \(pounds ? "lb" : "kg")"
        }
        switch value {
        case .chooseComfortableLoad(let convention):
            return convention == .bodyweight ? "Choose an easy bodyweight variation" : "Choose a comfortable load; no measured working load available"
        case .external(let kilograms, let convention):
            return "\(load(kilograms)) \(convention == .perHand ? "per hand" : "total external load")"
        case .bodyweight: return "Bodyweight"
        case .assistedBodyweight(let kilograms, let equipmentID):
            return "\(load(kilograms)) assistance, not added weight\(equipmentID.map { " (\($0))" } ?? "")"
        }
    }

    private func duration(_ seconds: Int) -> String {
        seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds / 60) min \(seconds % 60) sec"
    }

    private func timeRow(_ title: String, seconds: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(duration(seconds)).multilineTextAlignment(.trailing)
        }.font(.subheadline)
    }

    private func blocker(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("More context needed", systemImage: "info.circle")
            Text(reason).foregroundStyle(.secondary)
            Button("Back to profile") { dismiss() }
        }
    }
}
