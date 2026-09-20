import Foundation

/// Evidence review, not an automatic dose increase or medical clearance.
enum TrainingProgressionService {
    static let version = "progression-review-v1"
    enum State {
        case needsEvidence, repeatDose, hold, reviewRecovery, reviewIncrease
        var title: String {
            switch self {
            case .needsEvidence: "Record a completed session"
            case .repeatDose: "Repeat before increasing"
            case .hold: "Hold progression"
            case .reviewRecovery: "Review recovery first"
            case .reviewIncrease: "Ready to review an increase"
            }
        }
    }
    struct Assessment {
        let state: State
        let reason: String
        var evidenceIDs: [UUID] = []
    }

    static func assess(goalID: UUID, athleteID: Int, results: [TrainingSessionResult],
                       on date: Date, calendar: Calendar = .current) -> Assessment {
        guard date.timeIntervalSince1970.isFinite, athleteID > 0,
              results.allSatisfy({ $0.isValid && $0.reference.athleteID == athleteID }),
              Set(results.map(\.id)).count == results.count,
              Set(results.map { $0.reference.id }).count == results.count,
              let cutoff = calendar.date(byAdding: .day, value: -28, to: calendar.startOfDay(for: date)) else {
            return Assessment(state: .needsEvidence, reason: "Valid, account-owned completion records are required.")
        }
        let recent = results.filter {
            $0.reference.goalID == goalID && $0.completedAt >= cutoff
                && $0.completedAt <= date && $0.recordedAt <= date
        }.sorted {
            if $0.completedAt != $1.completedAt { return $0.completedAt > $1.completedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        guard let latest = recent.first else {
            return Assessment(state: .needsEvidence,
                reason: "No confirmed session for this goal in the last 28 days. A target or an isolated set is not proof of completing the whole prescription.")
        }
        func answer(_ state: State, _ reason: String) -> Assessment {
            Assessment(state: state, reason: reason, evidenceIDs: [latest.id])
        }
        if latest.bodyState != .good || latest.perceivedEffort >= 7 {
            return answer(.reviewRecovery,
                "Your latest session reported discomfort or high effort. Review how you feel before adding work; an older easier session does not override this report.")
        }
        if latest.isPartial {
            return answer(.hold,
                "Your latest session was partial. Keep its actual work, but do not count it as full completion or make up skipped work as extra training debt.")
        }
        guard comfortable(latest) else {
            return answer(.hold,
                "The latest result does not establish a comfortable full dose at the prescribed upper rep range. Review the effort and set results before increasing.")
        }
        guard recent.filter({ calendar.isDate($0.completedAt, inSameDayAs: latest.completedAt) }).count == 1 else {
            return answer(.hold, "Multiple records on the latest training day need review; they are not two separate successful training days.")
        }
        guard let previous = recent.dropFirst().first,
              !calendar.isDate(previous.completedAt, inSameDayAs: latest.completedAt),
              comfortable(previous), sameDose(previous, latest) else {
            return answer(.repeatDose,
                "One qualifying recent dose is not enough to justify an increase. Confirm a repeat on another day; a different load or session structure is not matching evidence.")
        }
        return Assessment(state: .reviewIncrease,
            reason: "Two matching, comfortable full sessions on different days support reviewing a small increase. No load, pace or duration has been increased automatically; equipment increments and the next week's capacity still need to be checked.",
            evidenceIDs: [previous.id, latest.id])
    }

    private static func comfortable(_ result: TrainingSessionResult) -> Bool {
        guard !result.isPartial, result.bodyState == .good else { return false }
        let strength = result.reference.items.filter { $0.kind == .strength }
        let running = result.reference.items.filter { $0.kind == .running }
        guard strength.isEmpty != running.isEmpty else { return false }
        if strength.isEmpty { return result.perceivedEffort <= 4 }
        guard result.perceivedEffort <= 6 else { return false }
        return strength.allSatisfy { item in
            guard let entry = result.entries.first(where: { $0.itemID == item.id }),
                  !entry.skipped, let reps = entry.repetitions, let range = item.repetitions,
                  let reserve = entry.repsInReserve else { return false }
            return reps >= range.upperBound && reserve >= 2
        }
    }

    private static func sameDose(_ lhs: TrainingSessionResult, _ rhs: TrainingSessionResult) -> Bool {
        guard lhs.reference.policyVersion == rhs.reference.policyVersion,
              lhs.reference.items.count == rhs.reference.items.count else { return false }
        for item in lhs.reference.items {
            guard let other = rhs.reference.items.first(where: { $0.id == item.id }),
                  item.kind == other.kind, item.exerciseID == other.exerciseID,
                  item.convention == other.convention, item.seconds == other.seconds,
                  item.repetitions == other.repetitions,
                  let first = lhs.entries.first(where: { $0.itemID == item.id }),
                  let second = rhs.entries.first(where: { $0.itemID == item.id }),
                  first.seconds == second.seconds, first.repetitions == second.repetitions,
                  equalLoad(first.loadKilograms, second.loadKilograms),
                  equalLoad(first.assistanceKilograms, second.assistanceKilograms) else { return false }
        }
        return true
    }

    private static func equalLoad(_ lhs: Double?, _ rhs: Double?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (.some(let a), .some(let b)): return abs(a - b) <= max(1, max(abs(a), abs(b))) * 0.000_000_01
        default: return false
        }
    }
}
