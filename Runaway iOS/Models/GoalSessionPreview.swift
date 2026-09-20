import Foundation

/// Immutable, local-only presentation snapshot. Opening this does not select a workout.
struct TrainingSessionPreviewSnapshot: Identifiable {
    let id = UUID()
    let generatedAt: Date
    let fingerprint: String
    let policyVersion: String
    let goals: [AthleteTrainingGoal]
    let observations: [TrainingObservation]
    let sessions: [GoalSessionPreview]
    var completeStrengthSessions: [UUID: CompleteStrengthSessionPolicy.Result] = [:]
    var athleteID: Int? = nil
    var sessionResults: [TrainingSessionResult] = []
    var availability: [TrainingDayAvailability] = []
    var protectedStorageRevision: String? = nil
}

/// Non-live prescription proposals. These are not completed workouts or medical clearance.
struct GoalSessionPreview: Equatable {
    let goalID: UUID
    let discipline: TrainingDiscipline
    let priority: GoalPriority
    let outcome: Outcome
    let reasons: [String]
    let evidenceIDs: [UUID]

    enum Outcome: Equatable {
        case running(Running)
        case strength(Strength)
        case needsInput(String)
    }

    struct Running: Equatable {
        enum Phase: Equatable {
            case warmup, running, recovery, cooldown
        }

        struct Block: Equatable {
            let phase: Phase
            let durationSeconds: Int
        }

        let warmupSeconds: Int
        let runningSeconds: Int
        let cooldownSeconds: Int
        let effortInstruction: String
        // No pace/distance is fabricated from an aspirational race target.
        var totalSeconds: Int { warmupSeconds + runningSeconds + cooldownSeconds }

        /// The optional recovery replaces main-block time; it never adds training time.
        /// It is a preview choice, not evidence of completion or a saved plan adjustment.
        func blocks(includingWalkBreak: Bool) -> [Block] {
            var result = [Block(phase: .warmup, durationSeconds: warmupSeconds)]
            if includingWalkBreak && runningSeconds > 60 {
                let firstRun = (runningSeconds - 60) / 2
                result.append(Block(phase: .running, durationSeconds: firstRun))
                result.append(Block(phase: .recovery, durationSeconds: 60))
                result.append(Block(phase: .running, durationSeconds: runningSeconds - 60 - firstRun))
            } else {
                result.append(Block(phase: .running, durationSeconds: runningSeconds))
            }
            result.append(Block(phase: .cooldown, durationSeconds: cooldownSeconds))
            return result
        }
    }

    enum Resistance: Equatable {
        case chooseComfortableLoad(LoadConvention)
        case external(kilograms: Double, convention: LoadConvention)
        case bodyweight
        case assistedBodyweight(kilograms: Double, equipmentID: String?)
    }

    struct Strength: Equatable {
        let exerciseID: String
        let sets: Int
        let repetitions: ClosedRange<Int>
        let resistance: Resistance
        let warmupSeconds: Int
        let setupSeconds: Int
        let secondsReservedPerSet: Int
        let restBetweenSetsSeconds: Int
        let cooldownSeconds: Int
        let effortInstruction: String
        // A planning allowance, not a prescribed lifting tempo or predicted duration.
        var totalSeconds: Int {
            warmupSeconds + setupSeconds + sets * secondsReservedPerSet
                + max(0, sets - 1) * restBetweenSetsSeconds + cooldownSeconds
        }
    }
}
