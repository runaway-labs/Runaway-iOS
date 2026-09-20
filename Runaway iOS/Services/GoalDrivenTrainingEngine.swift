import Foundation

/// A narrow, deterministic preview policy, not the active weekly scheduler.
/// Versioned product heuristics and limits: docs/superpowers/specs/2026-09-13-session-preview-policy.md.
enum GoalDrivenTrainingEngine {
    static let version = "goal-session-preview-v3"

    static func previews(for inputs: TrainingDecisionInputs) -> [GoalSessionPreview] {
        inputs.profile.goals.filter(\.isActive).sorted {
            if $0.priority != $1.priority { return $0.priority == .equalPrimary }
            return $0.id.uuidString < $1.id.uuidString
        }.map { goal in
            func blocked(_ reason: String) -> GoalSessionPreview {
                GoalSessionPreview(goalID: goal.id, discipline: goal.discipline, priority: goal.priority,
                    outcome: .needsInput(reason), reasons: [reason], evidenceIDs: [])
            }
            guard inputs.profile.reportedLimitations.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return blocked("Review your reported limitations before using this preview. This policy cannot interpret injury or movement restrictions.")
            }
            guard let availability = inputs.today else {
                return blocked("Set today's available training time. Missing availability is not a rest-day instruction.")
            }
            guard availability.availableMinutes > 0 else {
                return blocked("Today is marked unavailable. Adjust your availability to preview a session.")
            }
            let trainingToday = inputs.observations.contains {
                guard $0.measuredAt >= inputs.localDayStart else { return false }
                switch $0.value { case .run, .strengthSet: return true; default: return false }
            } || inputs.sessionResults.contains {
                $0.completedAt >= inputs.localDayStart && $0.entries.contains(where: { !$0.skipped })
            }
            if trainingToday {
                return blocked("Training evidence is already recorded today. Review the completed session and remaining time before adding another; a set alone does not establish a full workout.")
            }
            // Whole-day inputs avoid changing an otherwise identical preview every second.
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = inputs.timeZone
            guard let cutoff = calendar.date(byAdding: .day, value: -28, to: inputs.localDayStart) else {
                return blocked("Could not establish the observation window.")
            }
            let recent = inputs.observations.filter { $0.measuredAt >= cutoff }
            let budget = availability.availableMinutes * 60
            switch goal.discipline {
            case .running:
                let runs = recent.filter { if case .run = $0.value { return true }; return false }
                let last = runs.last
                let elapsed: Double?
                if let last, case .run(_, let duration, _) = last.value {
                    elapsed = duration
                } else {
                    elapsed = nil
                }
                switch RunningPrescriptionPolicy.make(recordedElapsedSeconds: elapsed, availableSeconds: budget) {
                case .needsInput(let reason): return blocked(reason)
                case .session(let session):
                    return GoalSessionPreview(goalID: goal.id, discipline: .running, priority: goal.priority,
                        outcome: .running(session),
                        reasons: ["A time-based easy-running preview supports this running goal.",
                            "Working time is capped by your latest recorded elapsed duration, today's budget, and a 20-minute preview limit.",
                            "Elapsed duration does not prove continuous running or current readiness. Confirm that this duration is comfortable before starting."],
                        evidenceIDs: last.map { [$0.id] } ?? [])
                }
            case .strength:
                guard let exercise = goal.target.exerciseID, let convention = goal.target.loadConvention else {
                    return blocked("Choose an exercise variant and load convention.")
                }
                let equipment = Set(inputs.profile.equipment)
                let supported: Bool
                if exercise.hasPrefix("barbell-") { supported = equipment.contains(.fullGym) && convention == .total }
                else if exercise.hasPrefix("dumbbell-") { supported = (equipment.contains(.dumbbells) || equipment.contains(.fullGym)) && convention == .perHand }
                else if exercise == "push-up" || exercise == "pull-up" {
                    // Pull-ups additionally need an explicitly available bar; full gym is the only supported profile proxy.
                    supported = convention == .bodyweight && (exercise == "pull-up" ? equipment.contains(.fullGym) : equipment.contains(.bodyweight) || equipment.contains(.fullGym))
                } else { supported = false }
                guard supported else {
                    return blocked("Confirm compatible equipment and load convention for this exercise. Machine-specific loads and unsupported variants need an explicit equipment-aware policy.")
                }
                let matching = recent.filter {
                    if case .strengthSet(let id, _, _, _, _, let measuredConvention, _) = $0.value {
                        return id == exercise && measuredConvention == convention
                    }
                    return false
                }
                var resistance = GoalSessionPreview.Resistance.chooseComfortableLoad(convention)
                var evidenceIDs: [UUID] = []
                if let last = matching.last,
                   case .strengthSet(_, let machineID, let reps, let load, let assistance, _, let effort) = last.value,
                   reps >= 8, let effort, effort.scale == .repetitionsInReserve, effort.value >= 2 {
                    if convention == .bodyweight {
                        resistance = assistance.map { .assistedBodyweight(kilograms: $0, equipmentID: machineID) } ?? .bodyweight
                    } else if let load {
                        resistance = .external(kilograms: load, convention: convention)
                    }
                    evidenceIDs = [last.id]
                } else if convention == .bodyweight {
                    return blocked("Record a comfortable set of at least eight reps with two or more reps in reserve, or choose an easier supported variant. Bodyweight difficulty cannot be reduced by inventing a lighter load.")
                }
                let session = GoalSessionPreview.Strength(exerciseID: exercise, sets: 2, repetitions: 6...8,
                    resistance: resistance, warmupSeconds: 300, setupSeconds: 120,
                    secondsReservedPerSet: 60, restBetweenSetsSeconds: 90, cooldownSeconds: 180,
                    effortInstruction: "Finish each set with 2-3 good reps in reserve. Rehearse the movement first; reduce difficulty if the observed load is no longer comfortable. Stop if painful.")
                guard session.totalSeconds <= budget else {
                    return blocked("This exercise preview needs 14 minutes including warm-up, setup, sets, rest, and cooldown. Increase available time or explicitly choose another session.")
                }
                return GoalSessionPreview(goalID: goal.id, discipline: .strength, priority: goal.priority,
                    outcome: .strength(session), reasons: [
                        "This is one goal-specific exercise block, not a complete balanced strength program.",
                        evidenceIDs.isEmpty ? "No qualifying load evidence: choose a comfortable load, not your target weight." : "Uses your latest matching set with recorded reps in reserve; does not increase its load.",
                        "Readiness, full-session fatigue, and weekly balance are not evaluated by this preview."
                    ], evidenceIDs: evidenceIDs)
            }
        }
    }
}
