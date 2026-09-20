import Foundation

/// Complete four-pattern preview, not a progression or medical clearance policy.
enum CompleteStrengthSessionPolicy {
    static let version = "complete-strength-preview-v1"
    enum Equipment { case bodyweight, dumbbells, fullGym }
    enum Pattern: String, Hashable { case push, pull, squat, hinge }

    struct Evidence: Equatable {
        let exerciseID: String
        let loadKilograms: Double?
        let convention: LoadConvention
        let repetitions: Int
        let repsInReserve: Double?
        let measuredAt: Date
    }

    struct Block {
        let exerciseID: String
        let name: String
        let pattern: Pattern
        var sets: Int
        let repetitions: ClosedRange<Int>
        let eachSide: Bool
        let resistance: GoalSessionPreview.Resistance
        let requiresCalibration: Bool
        let setupSeconds: Int
        let secondsPerSet: Int
        let restSeconds: Int
        var totalSeconds: Int { setupSeconds + sets * secondsPerSet + max(0, sets - 1) * restSeconds }
    }

    struct Session {
        let warmupSeconds: Int
        let cooldownSeconds: Int
        var blocks: [Block]
        var setsReducedForTime = false
        var totalSeconds: Int { warmupSeconds + cooldownSeconds + blocks.reduce(0) { $0 + $1.totalSeconds } }
    }

    enum Result { case session(Session), needsInput(String) }

    private struct Movement {
        let id: String
        let name: String
        let pattern: Pattern
        let convention: LoadConvention
        var eachSide = false
        var needsGym = false
    }

    private static let floorPress = Movement(id: "dumbbell-floor-press", name: "Dumbbell floor press", pattern: .push, convention: .perHand)
    private static let row = Movement(id: "dumbbell-row", name: "One-arm dumbbell row", pattern: .pull, convention: .perHand, eachSide: true)
    private static let squat = Movement(id: "dumbbell-goblet-squat", name: "Goblet squat", pattern: .squat, convention: .total)
    private static let hinge = Movement(id: "dumbbell-romanian-deadlift", name: "Dumbbell Romanian deadlift", pattern: .hinge, convention: .perHand)
    private static let bodyweight = [
        Movement(id: "wall-push-up", name: "Wall push-up", pattern: .push, convention: .bodyweight),
        Movement(id: "prone-w-raise", name: "Prone W raise", pattern: .pull, convention: .bodyweight),
        Movement(id: "bodyweight-squat", name: "Bodyweight squat", pattern: .squat, convention: .bodyweight),
        Movement(id: "glute-bridge", name: "Glute bridge", pattern: .hinge, convention: .bodyweight)
    ]

    private static func movement(for id: String) -> Movement? {
        let movements = [floorPress, row, squat, hinge] + bodyweight + [
            Movement(id: "barbell-bench-press", name: "Barbell bench press", pattern: .push, convention: .total, needsGym: true),
            Movement(id: "dumbbell-bench-press", name: "Dumbbell bench press", pattern: .push, convention: .perHand, needsGym: true),
            Movement(id: "barbell-overhead-press", name: "Barbell overhead press", pattern: .push, convention: .total, needsGym: true),
            Movement(id: "dumbbell-overhead-press", name: "Dumbbell overhead press", pattern: .push, convention: .perHand),
            Movement(id: "barbell-squat", name: "Barbell squat", pattern: .squat, convention: .total, needsGym: true),
            Movement(id: "barbell-back-squat", name: "Barbell back squat", pattern: .squat, convention: .total, needsGym: true),
            Movement(id: "barbell-deadlift", name: "Barbell deadlift", pattern: .hinge, convention: .total, needsGym: true),
            Movement(id: "barbell-row", name: "Barbell row", pattern: .pull, convention: .total, needsGym: true),
            Movement(id: "push-up", name: "Push-up", pattern: .push, convention: .bodyweight),
            Movement(id: "pull-up", name: "Pull-up", pattern: .pull, convention: .bodyweight, needsGym: true)
        ]
        return movements.first { $0.id == id }
    }

    static func make(anchor: GoalSessionPreview.Strength, equipment: Equipment,
                     availableSeconds: Int, evidence: [Evidence], now: Date) -> Result {
        guard availableSeconds > 0, now.timeIntervalSince1970.isFinite,
              anchor.sets > 0, anchor.repetitions.lowerBound > 0, anchor.repetitions.upperBound <= 12 else {
            return .needsInput("A valid time budget and supported introductory rep range are required.")
        }
        guard let goal = movement(for: anchor.exerciseID) else {
            return .needsInput("This goal exercise needs a supported movement-pattern mapping before a complete session can be assembled.")
        }
        guard (!goal.needsGym || equipment == .fullGym),
              (goal.convention == .bodyweight || equipment != .bodyweight) else {
            return .needsInput("Your selected equipment does not support the goal exercise. Bench and barbell goals require confirmed full-gym access in this preview.")
        }
        guard matches(anchor.resistance, convention: goal.convention) else {
            return .needsInput("The goal exercise's load convention does not match its recorded prescription.")
        }
        let complements = equipment == .bodyweight ? bodyweight : [floorPress, row, squat, hinge]
        let movements = [goal] + complements.filter { $0.pattern != goal.pattern }
        var session = Session(warmupSeconds: 300, cooldownSeconds: 180, blocks: movements.enumerated().map { index, movement in
            let resistance = index == 0 ? anchor.resistance : measuredResistance(for: movement, evidence: evidence, now: now)
            let calibration: Bool
            if case .chooseComfortableLoad = resistance { calibration = true } else { calibration = false }
            return Block(exerciseID: movement.id, name: movement.name, pattern: movement.pattern,
                         sets: index == 0 ? min(2, anchor.sets) : 2,
                         repetitions: index == 0 ? anchor.repetitions : 6...8,
                         eachSide: movement.eachSide, resistance: resistance, requiresCalibration: calibration,
                         setupSeconds: 120, secondsPerSet: movement.eachSide ? 120 : 60, restSeconds: 90)
        })
        // Preserve every movement. Reduce complementary sets before the goal lift.
        for index in session.blocks.indices.reversed() where session.totalSeconds > availableSeconds {
            if session.blocks[index].sets > 1 {
                session.blocks[index].sets = 1
                session.setsReducedForTime = true
            }
        }
        guard session.totalSeconds <= availableSeconds else {
            return .needsInput("This four-pattern session needs at least \(session.totalSeconds / 60) min \(session.totalSeconds % 60) sec including setup and recovery. Increase today's available time; no movements have been silently removed.")
        }
        return .session(session)
    }

    private static func matches(_ resistance: GoalSessionPreview.Resistance, convention: LoadConvention) -> Bool {
        switch resistance {
        case .external(let kilograms, let recorded): return recorded == convention && kilograms.isFinite && kilograms > 0
        case .chooseComfortableLoad(let recorded): return recorded == convention
        case .bodyweight: return convention == .bodyweight
        case .assistedBodyweight(let kilograms, _): return convention == .bodyweight && kilograms.isFinite && kilograms > 0
        }
    }

    private static func measuredResistance(for movement: Movement, evidence: [Evidence], now: Date) -> GoalSessionPreview.Resistance {
        let fallback = GoalSessionPreview.Resistance.chooseComfortableLoad(movement.convention)
        guard movement.convention != .bodyweight,
              let start = Calendar.current.date(byAdding: .day, value: -28, to: now) else { return fallback }
        let matching = evidence.filter {
            $0.exerciseID == movement.id && $0.convention == movement.convention
                && $0.measuredAt >= start && $0.measuredAt <= now
        }
        guard let latestDate = matching.map(\.measuredAt).max(),
              let latest = matching.first(where: { $0.measuredAt == latestDate }),
              matching.filter({ $0.measuredAt == latestDate }).allSatisfy({ $0 == latest }),
              latest.repetitions >= 8, let reserve = latest.repsInReserve, reserve.isFinite, reserve >= 2,
              let load = latest.loadKilograms, load.isFinite, load > 0 else { return fallback }
        return .external(kilograms: load, convention: movement.convention)
    }

    static func previews(for inputs: TrainingDecisionInputs) -> [UUID: Result] {
        let equipment: Equipment = inputs.profile.equipment.contains(.fullGym) ? .fullGym
            : inputs.profile.equipment.contains(.dumbbells) ? .dumbbells : .bodyweight
        let evidence = inputs.observations.compactMap { observation -> Evidence? in
            guard case .strengthSet(let set) = observation.value else { return nil }
            return Evidence(exerciseID: set.exerciseID, loadKilograms: set.externalLoadKilograms,
                            convention: set.convention, repetitions: set.repetitions,
                            repsInReserve: set.effort?.scale == .repetitionsInReserve ? set.effort?.value : nil,
                            measuredAt: observation.measuredAt)
        }
        return Dictionary(uniqueKeysWithValues: GoalDrivenTrainingEngine.previews(for: inputs).compactMap { preview in
            guard case .strength(let anchor) = preview.outcome else { return nil }
            return (preview.goalID, make(anchor: anchor, equipment: equipment,
                availableSeconds: (inputs.today?.availableMinutes ?? 0) * 60,
                evidence: evidence, now: inputs.localDayStart))
        })
    }
}
