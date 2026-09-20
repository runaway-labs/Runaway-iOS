import SwiftUI

/// Local presentation of a prescription. No plan, account, or notification writes.
struct RunningPrescriptionPreview: View {
    let run: GoalSessionPreview.Running
    let goal: AthleteTrainingGoal?
    let evidence: TrainingObservation?
    var onRecord: (([GoalSessionPreview.Running.Block]) -> Void)? = nil
    @State private var includeWalkBreak = false

    var body: some View {
        let blocks = run.blocks(includingWalkBreak: includeWalkBreak)
        VStack(alignment: .leading, spacing: 16) {
            Label("Easy running preview", systemImage: "figure.run")
                .foregroundStyle(AppTheme.Colors.strideBlue)
            Text("\(duration(run.totalSeconds)) total").font(.title3.bold())
            Text(goalPurpose).font(.subheadline).foregroundStyle(.secondary)

            Toggle("Plan a 1-minute walk break", isOn: $includeWalkBreak)
                .font(.subheadline)
                .accessibilityIdentifier("runningPreviewWalkBreak")
                .accessibilityHint("Replaces one minute of running in this preview. Does not save or change your plan.")
            Text(includeWalkBreak
                 ? "The walk replaces running time. Total session time stays the same. This choice is preview-only and is not saved."
                 : "Walking is always allowed. Turn this on to put a recovery break into the middle of the main block.")
                .font(.caption).foregroundStyle(.secondary)

            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.caption.bold()).monospacedDigit()
                        .frame(width: 26, height: 26)
                        .background(AppTheme.Colors.strideBlue.opacity(0.12), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(title(block.phase)).font(.subheadline.bold())
                                Spacer(minLength: 12)
                                Text(duration(block.durationSeconds)).font(.subheadline.monospacedDigit())
                            }.fixedSize(horizontal: true, vertical: false)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(title(block.phase)).font(.subheadline.bold())
                                Text(duration(block.durationSeconds)).font(.subheadline.monospacedDigit())
                            }
                        }
                        Text(instruction(block.phase)).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityElement(children: .combine)
            }

            Text("Walk longer or finish early if needed; do not make up those minutes afterward. Stop if painful or unwell.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            evidenceSummary
            Text("No pace or distance target is estimated from this record. This is an easy calibration session, not a race-specific workout or a progression plan.")
                .font(.caption).foregroundStyle(.secondary)
            if let onRecord {
                Button("Record completed session") { onRecord(blocks) }
                Text("Only use this after completing the work. Review actual times and any skipped blocks before saving.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var goalPurpose: String {
        guard let goal else { return "A time-based session grounded in recorded running activity." }
        switch goal.metric {
        case .racePerformance:
            return "Easy running supports your race preparation. Your race target is not treated as a pace you can already sustain."
        case .weeklyRunningDistance:
            return "Build running consistency toward your weekly distance goal. Actual distance counts after completion; no mileage is promised here."
        case .weeklyRunningDuration:
            return "Build running consistency toward your weekly time goal. Planned minutes are not counted as completed training."
        case .strengthPerformance, .bodyweightRepetitions:
            return "A time-based session grounded in recorded running activity."
        }
    }

    @ViewBuilder private var evidenceSummary: some View {
        if let evidence, case .run(let meters, let elapsed, _) = evidence.value {
            let unit = goal?.enteredDistanceUnit ?? .miles
            let value = RunningPrescriptionPolicy.distanceValue(meters: meters, unit: unit)
            VStack(alignment: .leading, spacing: 5) {
                Text("The record behind this session").font(.subheadline.bold())
                Text("\(evidence.measuredAt.formatted(date: .abbreviated, time: .omitted)): \(value.formatted(.number.precision(.fractionLength(0...2)))) \(unit == .miles ? "mi" : "km"), \((elapsed / 60).formatted(.number.precision(.fractionLength(0...1)))) min elapsed")
                    .font(.subheadline)
                Text("Elapsed time can include pauses and walking. It does not prove continuous running ability or readiness today.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text("Reopen session previews to view the performance record used for this session.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func title(_ phase: GoalSessionPreview.Running.Phase) -> String {
        switch phase {
        case .warmup: "Warm up"
        case .running: "Easy run"
        case .recovery: "Walk and recover"
        case .cooldown: "Cool down"
        }
    }

    private func instruction(_ phase: GoalSessionPreview.Running.Phase) -> String {
        switch phase {
        case .warmup: "Start with easy walking and gradually get moving."
        case .running: run.effortInstruction
        case .recovery: "Walk at a comfortable pace. Resume only if you feel ready; this is not a hard interval session."
        case .cooldown: "Ease into walking and let your breathing settle."
        }
    }

    private func duration(_ seconds: Int) -> String {
        seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds / 60) min \(seconds % 60) sec"
    }
}
