import Foundation

enum WidgetBecomingActionPolicy {
    static let pendingChoiceKey = "becoming_pending_choice"
    static let selectedChoiceKey = "becoming_selected_choice"
    static let actionDateKey = "becoming_action_date"

    static func adjustment(for rawChoice: String, alternate: WorkoutType?) -> TodayWorkoutAdjustment? {
        switch rawChoice {
        case "easier": return .easierWorkout
        case "recover": return .recoveryDay
        case "alternate": return alternate.map(TodayWorkoutAdjustment.chosenWorkout)
        default: return nil
        }
    }

    static func consumePendingChoice(from defaults: UserDefaults?) -> String? {
        guard let defaults, let choice = defaults.string(forKey: pendingChoiceKey) else { return nil }
        defaults.removeObject(forKey: pendingChoiceKey)
        return choice
    }
}
