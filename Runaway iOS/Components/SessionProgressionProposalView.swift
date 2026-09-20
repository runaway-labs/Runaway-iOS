import SwiftUI

/// Keeps numerical proposals beside the existing progression and weekly review.
struct ProgressionAndWeekReview: View {
    let snapshot: TrainingSessionPreviewSnapshot
    let workouts: [DailyWorkout]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TrainingAdaptationReview(snapshot: snapshot, workouts: workouts)
            if let athleteID = snapshot.athleteID {
                Divider()
                Text("Your next-session prescription").font(.headline)
                Text("Explore a proposal from your completed work, then review a future day before accepting it into your plan. This does not schedule a second workout today.")
                    .font(.caption).foregroundStyle(.secondary)
                AcceptedPrescriptionUndoPanel(athleteID: athleteID)
                ForEach(snapshot.goals.filter(\.isActive)) { goal in
                    SessionProgressionGoalProposal(snapshot: snapshot, goal: goal, athleteID: athleteID)
                }
            }
        }
    }
}

private struct SessionProgressionGoalProposal: View {
    let snapshot: TrainingSessionPreviewSnapshot
    let goal: AthleteTrainingGoal
    let athleteID: Int
    @State private var availableMinutes = 30
    @State private var incrementText: [String: String] = [:]

    private var latest: TrainingSessionResult? {
        snapshot.sessionResults.filter {
            $0.reference.athleteID == athleteID && $0.reference.goalID == goal.id &&
            $0.completedAt <= snapshot.generatedAt && $0.recordedAt <= snapshot.generatedAt
        }.max { $0.completedAt < $1.completedAt }
    }

    private var unit: TrainingMassUnit { latest?.reference.massUnit ?? goal.enteredLoadUnit }
    private var unitLabel: String { unit == .pounds ? "lb" : "kg" }
    private var equipmentItems: [TrainingSessionResult.Item] {
        var seen = Set<String>()
        return (latest?.reference.items ?? []).filter { item in
            guard item.kind == .strength, item.convention == .total || item.convention == .perHand,
                  let exercise = item.exerciseID else { return false }
            return seen.insert(exercise).inserted
        }
    }
    private var proposal: SessionProgressionProposalPolicy.Proposal {
        let increments = incrementText.reduce(into: [String: Double]()) { values, pair in
            let formatter = NumberFormatter()
            formatter.locale = .current
            formatter.numberStyle = .decimal
            if let number = formatter.number(from: pair.value)?.doubleValue {
                values[pair.key] = SessionProgressionProposalPolicy.kilograms(number, unit: unit)
            }
        }
        return SessionProgressionProposalPolicy.propose(
            goalID: goal.id, athleteID: athleteID, results: snapshot.sessionResults,
            on: snapshot.generatedAt, availableSeconds: availableMinutes * 60,
            incrementsKilograms: increments
        )
    }

    var body: some View {
        let value = proposal
        VStack(alignment: .leading, spacing: 12) {
            Text(goal.title).font(.headline)
            Stepper("Next-session time budget: \(availableMinutes) min", value: $availableMinutes, in: 5...240, step: 5)
                .font(.subheadline)
            Text("Choose the time available for a future session. The initial 30 minutes is editable, not a scheduled workout.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(equipmentItems) { item in
                if let exercise = item.exerciseID {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.subheadline)
                        TextField("Available increment (\(unitLabel)\(item.convention == .perHand ? " per hand" : " total"))", text: Binding(
                            get: { incrementText[exercise, default: ""] },
                            set: { incrementText[exercise] = $0 }
                        ))
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Available weight increment for \(item.title), \(unitLabel)\(item.convention == .perHand ? " per hand" : " total")")
                    }
                }
            }
            if !equipmentItems.isEmpty {
                Text("Enter only an increment your equipment supports. Blank keeps the load unchanged. These inputs are for this preview only.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(value.items.isEmpty ? "Review needed" : value.hasIncrease ? "Proposed progression" : "Repeatable session")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.blue)
            Text(value.reason).font(.subheadline)
            if value.needsEquipmentIncrement {
                Text("Some loads are unchanged: supply a positive equipment increment no greater than 5% of that recorded load. Larger jumps need a separate review.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(value.items) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.subheadline.weight(.semibold))
                    Text("Completed: \(dose(seconds: item.previous.seconds, reps: item.previous.repetitions, load: item.previous.loadKilograms, assistance: item.previous.assistanceKilograms, convention: item.convention))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Proposed: \(dose(seconds: item.seconds, reps: item.repetitions, load: item.loadKilograms, assistance: item.assistanceKilograms, convention: item.convention))")
                        .font(.subheadline)
                }
            }
            if !value.items.isEmpty {
                Text("Reserve at least \(value.requiredSeconds / 60) min \(value.requiredSeconds % 60) sec including rest and setup. Actual duration can vary.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Based on \(value.evidenceIDs.count) completed session\(value.evidenceIDs.count == 1 ? "" : "s"). Review and accept to change your plan. Reopen after recording new results.")
                    .font(.caption).foregroundStyle(.secondary)
                SessionPrescriptionAcceptanceButton(snapshot: snapshot, goal: goal, proposal: value, athleteID: athleteID)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }

    private func dose(seconds: Double?, reps: Int?, load: Double?, assistance: Double?, convention: LoadConvention?) -> String {
        if let seconds {
            return "\(Int(seconds) / 60) min \(Int(seconds) % 60) sec"
        }
        var text = "\(reps ?? 0) reps"
        if let load {
            let mass = SessionProgressionProposalPolicy.displayMass(load, unit: unit)
            text += " at \(mass.formatted(.number.precision(.fractionLength(0...2)))) \(unitLabel)"
            text += convention == .perHand ? " per hand" : " total"
        } else if convention == .bodyweight {
            text += " at bodyweight"
        }
        if let assistance {
            let mass = SessionProgressionProposalPolicy.displayMass(assistance, unit: unit)
            text += ", \(mass.formatted(.number.precision(.fractionLength(0...2)))) \(unitLabel) assistance"
        }
        return text
    }
}
