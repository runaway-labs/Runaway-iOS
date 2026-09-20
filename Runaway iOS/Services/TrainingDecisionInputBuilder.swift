import CryptoKit
import Foundation

/// All inputs come from one account and a complete observation history.
/// Plans intentionally cannot enter the completed-evidence channel.
struct TrainingDecisionInputs {
    let profile: AthleteTrainingProfile
    let observations: [TrainingObservation]
    let localDayStart: Date
    let timeZone: TimeZone
    let today: TrainingDayAvailability?
    let fingerprint: String
    var sessionResults: [TrainingSessionResult] = []
}

enum TrainingDecisionInputBuilder {
    enum InputError: Error { case ownershipMismatch, invalidProfile, invalidHistory, invalidDate }

    static func build(profile: AthleteTrainingProfile, history: [TrainingObservation],
                      athleteID: Int, now: Date, timeZone: TimeZone,
                      sessionResults: [TrainingSessionResult] = []) throws -> TrainingDecisionInputs {
        guard athleteID > 0, profile.athleteID == athleteID,
              history.allSatisfy({ $0.athleteID == athleteID }),
              sessionResults.allSatisfy({ $0.reference.athleteID == athleteID }) else { throw InputError.ownershipMismatch }
        guard profile.validationIssues().isEmpty else { throw InputError.invalidProfile }
        guard now.timeIntervalSince1970.isFinite else { throw InputError.invalidDate }
        guard history.allSatisfy(\.isValid), Set(history.map(\.id)).count == history.count else {
            throw InputError.invalidHistory
        }
        guard sessionResults.allSatisfy(\.isValid),
              Set(sessionResults.map(\.id)).count == sessionResults.count,
              Set(sessionResults.map { $0.reference.id }).count == sessionResults.count else {
            throw InputError.invalidHistory
        }
        let currentResults = sessionResults.filter { $0.completedAt <= now && $0.recordedAt <= now }.sorted {
            if $0.completedAt != $1.completedAt { return $0.completedAt < $1.completedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        let records = Dictionary(uniqueKeysWithValues: history.map { ($0.id, $0) })
        var children: [UUID: UUID] = [:]
        for record in history {
            if let parentID = record.supersedesID {
                guard let parent = records[parentID], children[parentID] == nil,
                      parent.value.measurementIdentity == record.value.measurementIdentity else {
                    throw InputError.invalidHistory
                }
                children[parentID] = record.id
            }
            var visited: Set<UUID> = [record.id]
            var cursor = record
            while let parentID = cursor.supersedesID {
                guard visited.insert(parentID).inserted, let parent = records[parentID] else {
                    throw InputError.invalidHistory
                }
                cursor = parent
            }
        }
        // Future records cannot hide currently available evidence.
        let eligible = history.filter { $0.measuredAt <= now && $0.receivedAt <= now }
        let superseded = Set(eligible.compactMap(\.supersedesID))
        let resultIDs = Set(currentResults.map(\.id))
        let current = eligible.filter {
            !superseded.contains($0.id) && $0.sessionID.map { !resultIDs.contains($0) } != false
        }.sorted {
            if $0.measuredAt != $1.measuredAt { return $0.measuredAt < $1.measuredAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let dayStart = calendar.startOfDay(for: now)
        let today = profile.availability.first { $0.weekday == calendar.component(.weekday, from: now) }

        // Display choices and save-only revisions do not change training mathematics.
        var canonicalProfile = profile
        canonicalProfile.revision = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        canonicalProfile.updatedAt = Date(timeIntervalSince1970: 0)
        canonicalProfile.goals = profile.goals.filter(\.isActive).map { original in
            var goal = original
            goal.title = ""
            goal.enteredDistanceUnit = .miles
            goal.enteredLoadUnit = .pounds
            return goal
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        canonicalProfile.availability.sort { $0.weekday < $1.weekday }
        canonicalProfile.equipment = Array(Set(profile.equipment)).sorted { $0.rawValue < $1.rawValue }
        canonicalProfile.bodyMeasurements?.enteredHeightUnit = .inches
        canonicalProfile.bodyMeasurements?.enteredWeightUnit = .pounds
        struct Payload: Encodable {
            let policyVersion: String
            let dayStart: Date
            let timeZone: String
            let profile: AthleteTrainingProfile
            let observations: [TrainingObservation]
            let sessionResults: [TrainingSessionResult]
        }
        let payload = Payload(policyVersion: GoalDrivenTrainingEngine.version, dayStart: dayStart,
            timeZone: timeZone.identifier, profile: canonicalProfile, observations: current, sessionResults: currentResults)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let digest = SHA256.hash(data: try encoder.encode(payload))
        let fingerprint = digest.map { String(format: "%02x", $0) }.joined()
        return TrainingDecisionInputs(profile: profile, observations: current, localDayStart: dayStart,
            timeZone: timeZone, today: today, fingerprint: fingerprint, sessionResults: currentResults)
    }
}
