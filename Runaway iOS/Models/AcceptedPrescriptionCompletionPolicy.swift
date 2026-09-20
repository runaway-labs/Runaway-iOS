import Foundation

enum AcceptedPrescriptionCompletionPolicy {
    enum Failure: LocalizedError {
        case invalidPrescription, unavailable, stalePlan
        var errorDescription: String? {
            switch self {
            case .invalidPrescription: return "This accepted prescription could not be matched to its original exercises. Nothing was saved."
            case .unavailable: return "Record this workout on or after its scheduled day, after you have completed the work."
            case .stalePlan: return "The accepted workout or account changed. Reopen its details before recording work."
            }
        }
    }

    static func effortLabel(for workout: DailyWorkout) -> String? {
        guard let accepted = workout.acceptedPrescription else { return nil }
        return accepted.items.contains { $0.kind == .running } ? "Conversational" : "Prescribed"
    }

    static func reference(for workout: DailyWorkout, athleteID: Int) throws -> TrainingSessionResult.Reference {
        guard let accepted = workout.acceptedPrescription,
              accepted.source.isValid, accepted.source.athleteID == athleteID,
              accepted.acceptedAt.timeIntervalSince1970.isFinite,
              accepted.requiredSeconds > 0, accepted.requiredSeconds <= 86400,
              accepted.items.count == accepted.source.items.count,
              Set(accepted.items.map(\.id)).count == accepted.items.count,
              Set(accepted.items.map(\.id)) == Set(accepted.source.items.map(\.id)) else {
            throw Failure.invalidPrescription
        }
        let source = Dictionary(uniqueKeysWithValues: accepted.source.items.map { ($0.id, $0) })
        let items = try accepted.items.map { proposed -> TrainingSessionResult.Item in
            guard let original = source[proposed.id], original.kind == proposed.kind,
                  original.convention == proposed.convention else { throw Failure.invalidPrescription }
            if proposed.kind == .strength {
                guard proposed.repetitions.map({ $0 > 0 }) == true, proposed.seconds == nil else {
                    throw Failure.invalidPrescription
                }
            } else {
                guard proposed.seconds != nil, proposed.repetitions == nil else { throw Failure.invalidPrescription }
            }
            var item = TrainingSessionResult.Item(id: original.id, title: original.title, kind: original.kind,
                exerciseID: original.exerciseID, seconds: nil, repetitions: original.repetitions,
                convention: original.convention, loadKilograms: proposed.loadKilograms,
                assistanceKilograms: proposed.assistanceKilograms)
            item.exactSeconds = proposed.seconds
            item.prescribedRepetitions = proposed.repetitions
            guard item.isValid else { throw Failure.invalidPrescription }
            return item
        }
        guard items.compactMap(\.durationSeconds).reduce(0, +) <= Double(accepted.requiredSeconds) else {
            throw Failure.invalidPrescription
        }
        var reference = TrainingSessionResult.Reference(athleteID: athleteID, goalID: accepted.source.goalID,
            goalTitle: workout.title, fingerprint: "accepted/" + accepted.id.uuidString,
            policyVersion: accepted.source.policyVersion, generatedAt: accepted.acceptedAt,
            distanceUnit: accepted.distanceUnit, massUnit: accepted.massUnit,
            prescribedSeconds: accepted.requiredSeconds, items: items)
        reference.acceptedPrescriptionID = accepted.id
        guard reference.isValid else { throw Failure.invalidPrescription }
        return reference
    }

    static func validate(_ result: TrainingSessionResult, workout: DailyWorkout,
                         currentPlan: WeeklyTrainingPlan?, athleteID: Int, now: Date,
                         calendar: Calendar = .current) throws {
        guard let currentPlan, currentPlan.athleteId == athleteID,
              let current = currentPlan.workouts.first(where: { $0.id == workout.id }),
              current.date == workout.date, current.acceptedPrescription == workout.acceptedPrescription,
              result.reference == (try reference(for: workout, athleteID: athleteID)) else { throw Failure.stalePlan }
        guard result.isValid, result.completedAt >= calendar.startOfDay(for: workout.date),
              result.completedAt >= result.reference.generatedAt, result.completedAt <= now,
              result.recordedAt <= now else { throw Failure.unavailable }
    }
}
