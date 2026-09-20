import Foundation

enum TrainingSessionReferenceBuilder {
    static func make(snapshot: TrainingSessionPreviewSnapshot, preview: GoalSessionPreview,
                     runningBlocks: [GoalSessionPreview.Running.Block]? = nil) -> TrainingSessionResult.Reference? {
        guard let athleteID = snapshot.athleteID,
              let goal = snapshot.goals.first(where: { $0.id == preview.goalID }) else { return nil }
        typealias Item = TrainingSessionResult.Item
        var items: [Item] = []
        let total: Int
        func timed(_ id: String, _ title: String, _ kind: TrainingSessionResult.Kind, _ seconds: Int) -> Item {
            Item(id: id, title: title, kind: kind, exerciseID: nil, seconds: seconds,
                 repetitions: nil, convention: nil, loadKilograms: nil, assistanceKilograms: nil)
        }
        switch preview.outcome {
        case .needsInput: return nil
        case .running(let run):
            total = run.totalSeconds
            for (index, block) in (runningBlocks ?? run.blocks(includingWalkBreak: false)).enumerated() {
                let kind: TrainingSessionResult.Kind
                let title: String
                switch block.phase {
                case .warmup: kind = .warmup; title = "Warm up"
                case .running: kind = .running; title = "Easy run"
                case .recovery: kind = .recovery; title = "Walking recovery"
                case .cooldown: kind = .cooldown; title = "Cool down"
                }
                items.append(timed("running/\(index)", title, kind, block.durationSeconds))
            }
        case .strength:
            guard case .session(let session) = snapshot.completeStrengthSessions[preview.goalID] else { return nil }
            total = session.totalSeconds
            items.append(timed("warmup", "Warm up", .warmup, session.warmupSeconds))
            for block in session.blocks {
                let convention: LoadConvention
                var load: Double?
                var assistance: Double?
                switch block.resistance {
                case .external(let kilograms, let unit): convention = unit; load = kilograms
                case .chooseComfortableLoad(let unit): convention = unit
                case .bodyweight: convention = .bodyweight
                case .assistedBodyweight(let kilograms, _): convention = .bodyweight; assistance = kilograms
                }
                for set in 1...block.sets {
                    for side in (block.eachSide ? ["left", "right"] : [""]) {
                        items.append(Item(id: "\(block.exerciseID)/\(set)/\(side)",
                            title: "\(block.name), set \(set)\(side.isEmpty ? "" : ", " + side)", kind: .strength,
                            exerciseID: block.exerciseID, seconds: nil, repetitions: block.repetitions,
                            convention: convention, loadKilograms: load, assistanceKilograms: assistance))
                    }
                }
            }
            items.append(timed("cooldown", "Cool down", .cooldown, session.cooldownSeconds))
        }
        return .init(athleteID: athleteID, goalID: goal.id, goalTitle: goal.title,
            fingerprint: snapshot.fingerprint,
            policyVersion: "\(snapshot.policyVersion)/\(CompleteStrengthSessionPolicy.version)/\(RunningPrescriptionPolicy.version)",
            generatedAt: snapshot.generatedAt, distanceUnit: goal.enteredDistanceUnit,
            massUnit: goal.enteredLoadUnit, prescribedSeconds: total, items: items)
    }
}
