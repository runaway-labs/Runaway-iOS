import Foundation

enum StrengthZoneHistoryService {
    private struct Accumulator {
        var effectiveWorkingSets: Double = 0
        var lastTrainedAt = Date.distantPast
        var sourceResultIDs: Set<UUID> = []
    }

    static func snapshot(
        workouts: [DailyWorkout],
        observations: [TrainingObservation],
        sessionResults: [TrainingSessionResult],
        unattributedStrengthDates: [Date],
        generatedAt: Date = Date()
    ) -> StrengthZoneHistorySnapshot {
        var accumulators: [StrengthZone: Accumulator] = [:]
        var seenResultIDs: Set<UUID> = []
        var seenAcceptedPrescriptionIDs: Set<UUID> = []
        var seenObservationIDs: Set<UUID> = []
        var seenObservationRecords: Set<String> = []

        func credit(
            _ definition: StrengthExerciseDefinition,
            fraction: Double,
            at date: Date,
            sourceID: UUID
        ) {
            guard fraction > 0 else { return }
            add(fraction, to: definition.primaryZone, at: date, sourceID: sourceID,
                accumulators: &accumulators)
            for zone in definition.secondaryZones {
                add(fraction * 0.5, to: zone, at: date, sourceID: sourceID,
                    accumulators: &accumulators)
            }
        }

        for result in sessionResults {
            guard seenResultIDs.insert(result.id).inserted else { continue }
            if let acceptedID = result.reference.acceptedPrescriptionID,
               !seenAcceptedPrescriptionIDs.insert(acceptedID).inserted {
                continue
            }
            let items = Dictionary(uniqueKeysWithValues: result.reference.items.map { ($0.id, $0) })
            for entry in result.entries {
                guard !entry.skipped,
                      let item = items[entry.itemID], item.kind == .strength,
                      let exerciseID = item.exerciseID,
                      let definition = StrengthExerciseCatalog.definition(id: exerciseID),
                      let completed = entry.repetitions,
                      let prescribed = item.prescribedRepetitions ?? item.repetitions?.lowerBound,
                      prescribed > 0,
                      completed * 2 >= prescribed else { continue }
                let fraction = min(1, Double(completed) / Double(prescribed))
                credit(definition, fraction: fraction, at: result.completedAt, sourceID: result.id)
            }
        }

        for observation in observations {
            guard seenObservationIDs.insert(observation.id).inserted,
                  seenObservationRecords.insert(observation.sourceRecordID).inserted else { continue }
            if let sessionID = observation.sessionID, seenResultIDs.contains(sessionID) { continue }
            guard case let .strengthSet(exerciseID, _, repetitions, _, _, _, _) = observation.value,
                  repetitions > 0,
                  let definition = StrengthExerciseCatalog.definition(id: exerciseID) else { continue }
            credit(definition, fraction: 1, at: observation.measuredAt,
                   sourceID: observation.sessionID ?? observation.id)
        }

        _ = workouts
        let exposures = Dictionary(uniqueKeysWithValues: accumulators.map { zone, accumulator in
            (zone, StrengthZoneExposure(
                zone: zone,
                effectiveWorkingSets: accumulator.effectiveWorkingSets,
                lastTrainedAt: accumulator.lastTrainedAt,
                sourceResultIDs: accumulator.sourceResultIDs
            ))
        })

        return StrengthZoneHistorySnapshot(
            generatedAt: generatedAt,
            exposures: exposures,
            hasUnattributedStrengthWork: !unattributedStrengthDates.isEmpty
        )
    }

    private static func add(
        _ sets: Double,
        to zone: StrengthZone,
        at date: Date,
        sourceID: UUID,
        accumulators: inout [StrengthZone: Accumulator]
    ) {
        var value = accumulators[zone] ?? Accumulator()
        value.effectiveWorkingSets += sets
        value.lastTrainedAt = max(value.lastTrainedAt, date)
        value.sourceResultIDs.insert(sourceID)
        accumulators[zone] = value
    }
}
