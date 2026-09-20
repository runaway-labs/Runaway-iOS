import Foundation

/// Numerical proposals only. Never mutates a plan or treats a proposal as completed work.
enum SessionProgressionProposalPolicy {
    static let version = "session-progression-proposal-v1"

    struct Item: Codable, Equatable, Identifiable {
        let id: String
        let title: String
        let kind: TrainingSessionResult.Kind
        let convention: LoadConvention?
        let previous: TrainingSessionResult.Entry
        var seconds: Double?
        var repetitions: Int?
        var loadKilograms: Double?
        var assistanceKilograms: Double?
    }

    struct Proposal {
        var items: [Item] = []
        var requiredSeconds: Int = 0
        var hasIncrease = false
        var needsEquipmentIncrement = false
        var evidenceIDs: [UUID] = []
        let reason: String
    }

    static func kilograms(_ value: Double, unit: TrainingMassUnit) -> Double {
        unit == .pounds ? value * 0.45359237 : value
    }

    static func displayMass(_ kilograms: Double, unit: TrainingMassUnit) -> Double {
        unit == .pounds ? kilograms / 0.45359237 : kilograms
    }

    static func propose(
        goalID: UUID, athleteID: Int, results: [TrainingSessionResult], on date: Date,
        availableSeconds: Int, incrementsKilograms: [String: Double] = [:],
        calendar: Calendar = .current
    ) -> Proposal {
        guard athleteID > 0, date.timeIntervalSince1970.isFinite,
              availableSeconds > 0, availableSeconds <= 86400,
              results.allSatisfy({ $0.reference.athleteID == athleteID && $0.isValid }),
              Set(results.map(\.id)).count == results.count,
              Set(results.map { $0.reference.id }).count == results.count,
              let cutoff = calendar.date(byAdding: .day, value: -28, to: calendar.startOfDay(for: date)) else {
            return Proposal(reason: "A valid time budget and consistent, account-owned completed-session records are required.")
        }
        let recent = results.filter {
            $0.reference.goalID == goalID && $0.completedAt >= cutoff &&
            $0.completedAt <= date && $0.recordedAt <= date
        }.sorted {
            $0.completedAt == $1.completedAt ? $0.id.uuidString < $1.id.uuidString : $0.completedAt > $1.completedAt
        }
        guard let latest = recent.first else {
            return Proposal(reason: "Record a completed session for this goal within the last 28 days. A goal target is not evidence of current ability.")
        }
        guard !latest.isPartial, latest.bodyState == .good else {
            return Proposal(reason: "The latest session was partial or included discomfort. Review recovery or the unfinished work before prescribing another full dose.")
        }
        let hasRunning = latest.reference.items.contains { $0.kind == .running }
        let hasStrength = latest.reference.items.contains { $0.kind == .strength }
        guard hasRunning != hasStrength else {
            return Proposal(reason: "This proposal needs a running or strength session, not mixed or recovery-only evidence.")
        }
        guard latest.perceivedEffort <= (hasRunning ? 4 : 6) else {
            return Proposal(reason: "The latest effort was above this proposal's easy/moderate threshold. Review recovery rather than automatically repeating or increasing it.")
        }
        guard latest.elapsedSeconds <= 86400 else {
            return Proposal(reason: "Review the recorded elapsed time before using this session.")
        }
        let required = max(latest.reference.prescribedSeconds, Int(ceil(latest.elapsedSeconds)))
        guard required <= availableSeconds else {
            return Proposal(reason: "The complete session needs at least \(required / 60) min \(required % 60) sec, including rest and setup. Choose a longer slot or a different session; blocks will not be silently removed.")
        }
        let actual = Dictionary(uniqueKeysWithValues: latest.entries.map { ($0.itemID, $0) })
        var items = latest.reference.items.compactMap { item -> Item? in
            guard let entry = actual[item.id] else { return nil }
            return Item(id: item.id, title: item.title, kind: item.kind, convention: item.convention,
                        previous: entry, seconds: entry.seconds, repetitions: entry.repetitions,
                        loadKilograms: entry.loadKilograms, assistanceKilograms: entry.assistanceKilograms)
        }
        if hasRunning {
            return Proposal(items: items, requiredSeconds: required, evidenceIDs: [latest.id],
                            reason: "Repeat these completed running and recovery blocks at conversational effort. No pace, distance, or automatic duration increase is inferred from your goal. This is a repeat-session option, not a race-specific progression plan.")
        }
        guard latest.reference.items.filter({ $0.kind == .strength }).allSatisfy({
            (actual[$0.id]?.repsInReserve ?? -1) >= 2
        }) else {
            return Proposal(reason: "The latest sets did not all leave at least two reported reps in reserve. Review the load before proposing another full strength session.")
        }

        let previous = recent.dropFirst().first
        let repeated = previous.map { older in
            !older.isPartial && older.bodyState == .good && older.perceivedEffort <= 6 &&
            !calendar.isDate(older.completedAt, inSameDayAs: latest.completedAt) &&
            recent.filter { calendar.isDate($0.completedAt, inSameDayAs: latest.completedAt) }.count == 1 &&
            recent.filter { calendar.isDate($0.completedAt, inSameDayAs: older.completedAt) }.count == 1 &&
            older.reference.policyVersion == latest.reference.policyVersion &&
            older.reference.items == latest.reference.items && matchingActualDose(older, latest)
        } ?? false
        guard repeated, let previous else {
            return Proposal(items: items, requiredSeconds: required, evidenceIDs: [latest.id],
                            reason: "Repeat the recorded dose. Increasing requires two matching, complete sessions on separate days with manageable effort and at least two reported reps in reserve on every set.")
        }

        var increased = false
        var needsIncrement = false
        let exerciseIDs = Set(latest.reference.items.compactMap { $0.kind == .strength ? $0.exerciseID : nil })
        for exerciseID in exerciseIDs {
            let indices = latest.reference.items.indices.filter { latest.reference.items[$0].exerciseID == exerciseID && latest.reference.items[$0].kind == .strength }
            let allAtCeiling = indices.allSatisfy { index in
                guard let range = latest.reference.items[index].repetitions, let reps = items[index].repetitions else { return false }
                return reps >= range.upperBound
            }
            if !allAtCeiling {
                for index in indices {
                    if let upper = latest.reference.items[index].repetitions?.upperBound,
                       let reps = items[index].repetitions, reps < upper {
                        items[index].repetitions = reps + 1
                        increased = true
                    }
                }
                continue
            }
            // Bodyweight/assistance needs a variation-specific policy, not inverted load math.
            guard indices.allSatisfy({ items[$0].convention == .total || items[$0].convention == .perHand }) else { continue }
            guard let increment = incrementsKilograms[exerciseID], increment.isFinite, increment > 0,
                  indices.allSatisfy({ index in
                      guard let load = items[index].loadKilograms else { return false }
                      return increment / load <= 0.05 && (load + increment).isFinite
                  }) else {
                needsIncrement = true
                continue
            }
            for index in indices {
                items[index].loadKilograms = items[index].loadKilograms.map { $0 + increment }
                items[index].repetitions = latest.reference.items[index].repetitions?.lowerBound
            }
            increased = true
        }
        return Proposal(items: items, requiredSeconds: required, hasIncrease: increased,
                        needsEquipmentIncrement: needsIncrement, evidenceIDs: [latest.id, previous.id],
                        reason: increased
                            ? "Two matching completed sessions support reviewing a small change: one rep within the existing range, or your equipment increment with reps reset to the range minimum. Sets, recovery blocks and exercises stay unchanged. This is a product heuristic, not a guarantee of readiness."
                            : "Repeat the recorded dose. Loaded sets at the rep ceiling need a usable equipment increment; bodyweight and assisted variations stay unchanged. The 5% increment ceiling is a conservative product limit, not a safety guarantee.")
    }

    private static func matchingActualDose(_ older: TrainingSessionResult, _ latest: TrainingSessionResult) -> Bool {
        let entries = Dictionary(uniqueKeysWithValues: older.entries.map { ($0.itemID, $0) })
        return latest.entries.allSatisfy { current in
            guard let prior = entries[current.itemID] else { return false }
            let strength = latest.reference.items.first { $0.id == current.itemID }?.kind == .strength
            return prior.skipped == current.skipped && prior.seconds == current.seconds &&
                prior.repetitions == current.repetitions && sameMass(prior.loadKilograms, current.loadKilograms) &&
                sameMass(prior.assistanceKilograms, current.assistanceKilograms) &&
                (!strength || (prior.repsInReserve ?? -1) >= 2)
        }
    }

    private static func sameMass(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return abs(a - b) <= max(1, abs(a), abs(b)) * 1e-8
        default: return false
        }
    }
}
