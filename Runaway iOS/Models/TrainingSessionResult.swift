import Foundation

/// An explicitly confirmed record of actual work, not a plan-completion flag.
struct TrainingSessionResult: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case warmup, running, recovery, cooldown, strength }

    struct Item: Codable, Equatable, Identifiable {
        var id: String
        let title: String
        let kind: Kind
        let exerciseID: String?
        let seconds: Int?
        let repetitions: ClosedRange<Int>?
        let convention: LoadConvention?
        let loadKilograms: Double?
        let assistanceKilograms: Double?
        var exactSeconds: Double? = nil
        var prescribedRepetitions: Int? = nil

        var durationSeconds: Double? { exactSeconds ?? seconds.map(Double.init) }

        var isValid: Bool {
            guard !id.isEmpty, !title.isEmpty else { return false }
            if kind != .strength {
                return durationSeconds.map { $0.isFinite && $0 > 0 && $0 <= 86_400 } == true
                    && (exactSeconds == nil || seconds == nil) && prescribedRepetitions == nil
                    && exerciseID == nil && repetitions == nil && convention == nil
                    && loadKilograms == nil && assistanceKilograms == nil
            }
            guard exerciseID?.isEmpty == false, seconds == nil, exactSeconds == nil,
                  prescribedRepetitions.map({ $0 > 0 }) ?? true,
                  let repetitions, repetitions.lowerBound > 0,
                  let convention, convention != .machine,
                  loadKilograms.map({ $0.isFinite && $0 > 0 }) ?? true,
                  assistanceKilograms.map({ $0.isFinite && $0 > 0 }) ?? true else { return false }
            return convention == .bodyweight ? loadKilograms == nil : assistanceKilograms == nil
        }
    }

    struct Reference: Codable, Equatable, Identifiable {
        let athleteID: Int
        let goalID: UUID
        let goalTitle: String
        let fingerprint: String
        let policyVersion: String
        let generatedAt: Date
        let distanceUnit: TrainingDistanceUnit
        let massUnit: TrainingMassUnit
        let prescribedSeconds: Int
        var items: [Item]
        var acceptedPrescriptionID: UUID? = nil
        var id: String { fingerprint + ":" + goalID.uuidString }

        var isValid: Bool {
            athleteID > 0 && !goalTitle.isEmpty && !fingerprint.isEmpty && !policyVersion.isEmpty
                && generatedAt.timeIntervalSince1970.isFinite && prescribedSeconds > 0
                && !items.isEmpty && items.allSatisfy(\.isValid)
                && Set(items.map(\.id)).count == items.count
        }
    }

    struct Entry: Codable, Equatable {
        let itemID: String
        var skipped: Bool
        var seconds: Double?
        var repetitions: Int?
        var loadKilograms: Double?
        var assistanceKilograms: Double?
        var repsInReserve: Double?

        func isValid(for item: Item) -> Bool {
            if skipped {
                return seconds == nil && repetitions == nil && loadKilograms == nil
                    && assistanceKilograms == nil && repsInReserve == nil
            }
            if item.kind != .strength {
                return seconds.map { $0.isFinite && $0 > 0 } == true
                    && repetitions == nil && loadKilograms == nil
                    && assistanceKilograms == nil && repsInReserve == nil
            }
            guard seconds == nil, let repetitions, repetitions > 0,
                  let reserve = repsInReserve, reserve.isFinite, reserve >= 0,
                  loadKilograms.map({ $0.isFinite && $0 > 0 }) ?? true,
                  assistanceKilograms.map({ $0.isFinite && $0 > 0 }) ?? true else { return false }
            if item.convention == .bodyweight { return loadKilograms == nil }
            return loadKilograms != nil && assistanceKilograms == nil
        }
    }

    var id: UUID
    var reference: Reference
    var completedAt: Date
    let recordedAt: Date
    var elapsedSeconds: Double
    var perceivedEffort: Int
    var bodyState: ReflectionBodyState
    var entries: [Entry]

    var isPartial: Bool {
        entries.contains { entry in
            guard !entry.skipped, let item = reference.items.first(where: { $0.id == entry.itemID }) else { return true }
            if let prescribed = item.durationSeconds, let actual = entry.seconds { return actual < prescribed }
            if let prescribed = item.prescribedRepetitions, let actual = entry.repetitions { return actual < prescribed }
            if let prescribed = item.repetitions, let actual = entry.repetitions { return actual < prescribed.lowerBound }
            return false
        }
    }

    var isValid: Bool {
        guard reference.isValid, completedAt.timeIntervalSince1970.isFinite,
              recordedAt.timeIntervalSince1970.isFinite, completedAt <= recordedAt,
              reference.generatedAt <= recordedAt, elapsedSeconds.isFinite, elapsedSeconds > 0,
              (1...10).contains(perceivedEffort), entries.count == reference.items.count,
              Set(entries.map(\.itemID)).count == entries.count,
              entries.contains(where: { !$0.skipped }) else { return false }
        let items = Dictionary(uniqueKeysWithValues: reference.items.map { ($0.id, $0) })
        guard entries.allSatisfy({ entry in
            guard let item = items[entry.itemID] else { return false }
            return entry.isValid(for: item)
        }) else { return false }
        let timedSeconds = entries.reduce(0.0) { $0 + ($1.seconds ?? 0) }
        return timedSeconds.isFinite && timedSeconds <= elapsedSeconds
    }
}
