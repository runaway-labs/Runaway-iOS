import Foundation

@MainActor
final class CoachEventService {
    typealias ContextProvider = @MainActor (CoachEvent) async throws -> CoachContext
    typealias PlanActivator = @MainActor (WeeklyTrainingPlan, String) async throws -> Void

    private let ledger: CoachDecisionLedger
    private let coordinator: CoachCoordinator
    private let context: ContextProvider
    private let activate: PlanActivator

    init(ledger: CoachDecisionLedger, coordinator: CoachCoordinator,
         context: @escaping ContextProvider, activate: @escaping PlanActivator) {
        self.ledger = ledger
        self.coordinator = coordinator
        self.context = context
        self.activate = activate
    }

    func processPending(athleteID: Int) async throws {
        for event in try ledger.pendingEvents() {
            guard event.athleteID == athleteID else {
                throw ProtectedTrainingRepository.RepositoryError.ownershipMismatch
            }
            let input = try await context(event)
            let result = try await coordinator.process(event, context: input)
            if result.decision?.state == .applied {
                try await activate(result.activePlan, input.planRevision)
            }
        }
    }

    @discardableResult
    static func persistRemotePayload(_ userInfo: [AnyHashable: Any], athleteID: Int) throws -> Bool {
        let event: CoachEvent
        if let scheduled = CoachEvent.remoteScheduledCheckIn(
            from: userInfo,
            authenticatedAthleteID: athleteID
        ) {
            event = scheduled
        } else {
            let value = userInfo["coach_event"]
            let data: Data
            if let text = value as? String, let decoded = Data(base64Encoded: text) {
                data = decoded
            } else if let object = value as? [String: Any], JSONSerialization.isValidJSONObject(object) {
                data = try JSONSerialization.data(withJSONObject: object)
            } else {
                return false
            }
            event = try JSONDecoder().decode(CoachEvent.self, from: data)
        }
        guard event.athleteID == athleteID else {
            throw ProtectedTrainingRepository.RepositoryError.ownershipMismatch
        }
        let repository = ProtectedTrainingRepository(activeAthleteID: { UserSession.shared.userId })
        let ledger = CoachDecisionLedger(repository: repository, athleteID: athleteID)
        try ledger.append(event)
        return true
    }
}
