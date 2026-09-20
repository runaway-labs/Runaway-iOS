import Foundation

/// Read-only scheduling experiment. Exposure balance is not physiological load.
enum GoalDailyShadowPolicy {
    static let version = "daily-shadow-v2"

    enum Discipline: String, Hashable {
        case running, strength
    }

    struct Candidate {
        let goalID: UUID
        let discipline: Discipline
        let isPrimary: Bool
        let blocker: String?
    }

    struct CompletedDay {
        let discipline: Discipline
        let date: Date
    }

    struct Ranking {
        let goalID: UUID
        let discipline: Discipline
        let completedDays: Int
        let shareDeficit: Double
        let latestTrainingDay: Date?
    }

    struct Decision {
        var selectedGoalID: UUID? = nil
        var choiceGoalIDs: [UUID] = []
        var rankings: [Ranking] = []
        var blocker: String? = nil
        var preservesUserChoice = false
    }

    static func select<C: Collection>(
        candidates: C,
        history: [CompletedDay],
        on date: Date,
        readinessScore: Int?,
        preserveUserChoice: Bool = false,
        calendar: Calendar = .current
    ) -> Decision where C.Element == Candidate {
        if preserveUserChoice { return Decision(preservesUserChoice: true) }
        guard date.timeIntervalSince1970.isFinite else {
            return Decision(blocker: "A valid decision date is required.")
        }
        guard let score = readinessScore, (0...100).contains(score) else {
            return Decision(blocker: "A current readiness score is required for this comparison.")
        }
        guard score >= 70 else {
            return Decision(blocker: "Readiness calls for a recovery or reduced-intensity review. This experimental selector does not yet adapt prescriptions for that state.")
        }
        let today = calendar.startOfDay(for: date)
        guard let start = calendar.date(byAdding: .day, value: -7, to: today) else {
            return Decision(blocker: "The recent training window could not be determined.")
        }
        let known = history.filter { $0.date.timeIntervalSince1970.isFinite && $0.date <= date }
        if known.contains(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            return Decision(blocker: "Training is already recorded today. Additional-session planning is not supported by this comparison yet.")
        }
        let candidates = Array(candidates)
        guard !candidates.isEmpty else {
            return Decision(blocker: "Save an active running or strength goal and generate its session preview first.")
        }
        let hasPrimary = candidates.contains(where: \.isPrimary)
        let priorityPool = candidates.filter { $0.isPrimary == hasPrimary }
        let eligible = priorityPool.filter { $0.blocker == nil }
        guard !eligible.isEmpty else {
            return Decision(blocker: "No prescription at the highest goal priority is available. Resolve the preview blockers rather than silently replacing a primary goal with supporting work.")
        }
        let disciplines = Set(priorityPool.map(\.discipline))
        let recent = known.filter { $0.date >= start && $0.date < today }
        let days = Dictionary(uniqueKeysWithValues: disciplines.map { discipline in
            (discipline, Set(recent.filter { $0.discipline == discipline }.map { calendar.startOfDay(for: $0.date) }))
        })
        let total = days.values.reduce(0) { $0 + $1.count }
        let targetShare = 1.0 / Double(disciplines.count)
        let rankings = eligible.map { candidate in
            let recorded = days[candidate.discipline] ?? []
            let observedShare = total == 0 ? 0 : Double(recorded.count) / Double(total)
            return Ranking(
                goalID: candidate.goalID, discipline: candidate.discipline,
                completedDays: recorded.count, shareDeficit: targetShare - observedShare,
                latestTrainingDay: recorded.max()
            )
        }.sorted {
            if $0.shareDeficit != $1.shareDeficit { return $0.shareDeficit > $1.shareDeficit }
            let left = $0.latestTrainingDay ?? .distantPast
            let right = $1.latestTrainingDay ?? .distantPast
            if left != right { return left < right }
            // Stable presentation only. Exact ties below remain athlete choices.
            return $0.goalID.uuidString < $1.goalID.uuidString
        }
        guard let best = rankings.first else { return Decision(blocker: "No eligible session preview is available.") }
        let ties = rankings.filter {
            $0.shareDeficit == best.shareDeficit && $0.latestTrainingDay == best.latestTrainingDay
        }
        if ties.count > 1 {
            return Decision(choiceGoalIDs: ties.map(\.goalID), rankings: rankings)
        }
        return Decision(selectedGoalID: best.goalID, rankings: rankings)
    }

    static func candidates(in snapshot: TrainingSessionPreviewSnapshot) -> [Candidate] {
        snapshot.sessions.compactMap { preview in
            let discipline: Discipline
            switch preview.discipline {
            case .running: discipline = .running
            case .strength: discipline = .strength
            default: return nil
            }
            let blocker: String?
            switch preview.outcome {
            case .needsInput(let reason): blocker = reason
            case .running: blocker = nil
            case .strength:
                switch snapshot.completeStrengthSessions[preview.goalID] {
                case .session: blocker = nil
                case .needsInput(let reason): blocker = reason
                case nil: blocker = "Reopen session previews to generate a complete strength prescription."
                }
            }
            return Candidate(goalID: preview.goalID, discipline: discipline,
                             isPrimary: preview.priority == .equalPrimary, blocker: blocker)
        }
    }

    static func history(in snapshot: TrainingSessionPreviewSnapshot) -> [CompletedDay] {
        let observations = snapshot.observations.compactMap { observation -> CompletedDay? in
            let discipline: Discipline
            switch observation.value {
            case .run: discipline = .running
            case .strengthSet: discipline = .strength
            default: return nil
            }
            return CompletedDay(discipline: discipline, date: observation.measuredAt)
        }
        let sessions = snapshot.sessionResults.flatMap { result -> [CompletedDay] in
            var disciplines: Set<Discipline> = []
            for entry in result.entries where !entry.skipped {
                guard let item = result.reference.items.first(where: { $0.id == entry.itemID }) else { continue }
                if item.kind == .running { disciplines.insert(.running) }
                if item.kind == .strength { disciplines.insert(.strength) }
            }
            return disciplines.map { CompletedDay(discipline: $0, date: result.completedAt) }
        }
        // select() deduplicates local days, not session volume. Do not add tonnage or
        // running distance here: result/import reconciliation has not been implemented.
        return observations + sessions
    }
}
