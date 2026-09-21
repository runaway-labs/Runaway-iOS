import Foundation

struct CoachEvent: Codable, Equatable, Identifiable, Sendable {
    enum Source: String, Codable, Sendable {
        case app, healthKit, garmin, weather, schedule, athlete, notification
    }

    enum Kind: String, Codable, Sendable {
        case appForegrounded, scheduledCheckIn, workoutImported, sessionResultChanged
        case sessionElapsed, readinessChanged, weatherChanged, availabilityChanged
        case profileChanged, reevaluationRequested, proposalResponded
    }

    enum Payload: Codable, Equatable, Sendable {
        case none
        case workoutImported(activityID: Int)
        case sessionResultChanged(resultID: UUID)
        case sessionElapsed(workoutID: String)
        case readinessChanged(score: Int?)
        case weatherChanged(conditionKey: String, severity: Double)
        case availabilityChanged
        case profileChanged
        case reevaluationRequested(reason: String?)
        case proposalResponded(decisionID: UUID, accepted: Bool)
    }

    let id: UUID
    let athleteID: Int
    let kind: Kind
    let source: Source
    let occurredAt: Date
    let receivedAt: Date
    let sourceRecordID: String
    let payload: Payload

    init(id: UUID = UUID(), athleteID: Int, kind: Kind, source: Source,
         occurredAt: Date, receivedAt: Date, sourceRecordID: String, payload: Payload) {
        self.id = id
        self.athleteID = athleteID
        self.kind = kind
        self.source = source
        self.occurredAt = occurredAt
        self.receivedAt = receivedAt
        self.sourceRecordID = sourceRecordID
        self.payload = payload
    }

    var deduplicationKey: String { "\(athleteID):\(source.rawValue):\(sourceRecordID)" }

    var isValid: Bool {
        athleteID > 0 && !sourceRecordID.isEmpty &&
            occurredAt.timeIntervalSince1970.isFinite &&
            receivedAt.timeIntervalSince1970.isFinite && receivedAt >= occurredAt
    }

    static func remoteScheduledCheckIn(
        from userInfo: [AnyHashable: Any],
        authenticatedAthleteID: Int,
        receivedAt: Date = Date()
    ) -> Self? {
        let payloadAthleteID = (userInfo["athlete_id"] as? Int)
            ?? (userInfo["athlete_id"] as? String).flatMap(Int.init)
        guard authenticatedAthleteID > 0,
              payloadAthleteID == authenticatedAthleteID,
              let rawEventID = userInfo["coach_event_id"] as? String,
              let eventID = UUID(uuidString: rawEventID),
              receivedAt.timeIntervalSince1970.isFinite else { return nil }
        return Self(
            id: eventID,
            athleteID: authenticatedAthleteID,
            kind: .scheduledCheckIn,
            source: .schedule,
            occurredAt: receivedAt,
            receivedAt: receivedAt,
            sourceRecordID: "schedule-\(eventID.uuidString)",
            payload: .none
        )
    }
}
