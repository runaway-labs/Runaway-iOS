import Foundation

struct TodayWorkoutDecisionPreview: Identifiable {
    struct Change: Identifiable, Equatable, Sendable {
        enum Kind: String, Equatable, Sendable {
            case replaced
            case moved
            case protected
        }

        let id: String
        let kind: Kind
        let title: String
        let detail: String
    }

    enum Warning: Equatable, Sendable {
        case goalCriticalWorkoutMoved
        case futureDemandingWorkMoved
    }

    let id: UUID
    let originalPlanRevision: String
    let originalPlan: WeeklyTrainingPlan
    let proposedPlan: WeeklyTrainingPlan
    let committedWorkoutID: String
    let changes: [Change]
    let warnings: [Warning]
    let createdAt: Date
}

enum TodayWorkoutDecisionError: Error, Equatable {
    case invalidDraft
    case unavailableDay
    case completedWorkout
    case stalePlan
    case invalidCommitment
}
