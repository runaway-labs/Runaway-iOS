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
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct ReviewTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Review Today's Training"
    static var description = IntentDescription("Open today's adaptive training decision in Runaway.")
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult { .result() }
}
