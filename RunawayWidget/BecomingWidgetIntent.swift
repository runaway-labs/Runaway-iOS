import AppIntents
import Foundation
import WidgetKit

enum WidgetBecomingChoice: String, AppEnum, CaseIterable {
    case planned, easier, alternate, recover

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Training path")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .planned: "Follow Plan", .easier: "Ease It", .alternate: "Swap", .recover: "Recover"
    ]

    var shortTitle: String {
        switch self {
        case .planned: return "PLAN"
        case .easier: return "EASIER"
        case .alternate: return "SWAP"
        case .recover: return "RECOVER"
        }
    }

    var icon: String {
        switch self {
        case .planned: return "figure.run"
        case .easier: return "dial.low"
        case .alternate: return "arrow.triangle.swap"
        case .recover: return "moon.zzz.fill"
        }
    }
}

struct ChooseBecomingPathIntent: AppIntent {
    static var title: LocalizedStringResource = "Choose Today's Training Path"
    static var description = IntentDescription("Choose how to train today and let Runaway adapt the rest of the week.")
    static var openAppWhenRun = true

    @Parameter(title: "Path") var choice: WidgetBecomingChoice

    init() { choice = .planned }
    init(choice: WidgetBecomingChoice) { self.choice = choice }

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.com.jackrudelic.runawayios")
        defaults?.set(choice.rawValue, forKey: "becoming_pending_choice")
        defaults?.set(choice.rawValue, forKey: "becoming_selected_choice")
        defaults?.set(Date().timeIntervalSince1970, forKey: "becoming_action_date")
        CoachWidgetActionRequest(
            athleteID: defaults?.integer(forKey: TrainingProgressSnapshot.athleteKey) ?? 0,
            decisionID: nil,
            action: .reevaluate,
            selectedPath: choice.rawValue,
            createdAt: Date()
        ).store(in: defaults)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct ReviewCoachDecisionIntent: AppIntent {
    static var title: LocalizedStringResource = "Review Coach Change"
    static var description = IntentDescription("Open the exact plan change and the evidence behind it.")
    static var openAppWhenRun = true

    @Parameter(title: "Decision") var decisionID: String

    init() { decisionID = "" }
    init(decisionID: UUID) { self.decisionID = decisionID.uuidString }

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.com.jackrudelic.runawayios")
        CoachWidgetActionRequest(
            athleteID: defaults?.integer(forKey: TrainingProgressSnapshot.athleteKey) ?? 0,
            decisionID: UUID(uuidString: decisionID),
            action: .review,
            selectedPath: nil,
            createdAt: Date()
        ).store(in: defaults)
        return .result()
    }
}

struct UndoCoachDecisionIntent: AppIntent {
    static var title: LocalizedStringResource = "Request Coach Undo"
    static var description = IntentDescription("Open Runaway to safely undo the latest coach change.")
    static var openAppWhenRun = true

    @Parameter(title: "Decision") var decisionID: String

    init() { decisionID = "" }
    init(decisionID: UUID) { self.decisionID = decisionID.uuidString }

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.com.jackrudelic.runawayios")
        CoachWidgetActionRequest(
            athleteID: defaults?.integer(forKey: TrainingProgressSnapshot.athleteKey) ?? 0,
            decisionID: UUID(uuidString: decisionID),
            action: .undo,
            selectedPath: nil,
            createdAt: Date()
        ).store(in: defaults)
        return .result()
    }
}

struct ReviewTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Review Today's Training"
    static var description = IntentDescription("Open today's adaptive training decision in Runaway.")
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult { .result() }
}
