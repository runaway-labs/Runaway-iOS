import Foundation
import Observation

@MainActor
@Observable
final class TodayWorkoutDecisionViewModel {
    enum Phase: Equatable {
        case loading
        case recommended
        case choosing
        case editing
        case previewing
        case committing
        case committed
        case failed
    }

    private(set) var phase: Phase = .loading
    private(set) var choices: [TodayWorkoutChoice] = []
    private(set) var draft: TodayWorkoutDraft?
    private(set) var preview: TodayWorkoutDecisionPreview?
    private(set) var blockerMessage: String?
    private(set) var errorMessage: String?

    private let plan: WeeklyTrainingPlan
    private let context: TodayWorkoutChoicePolicy.Context

    init(
        plan: WeeklyTrainingPlan,
        profile: TrainingProfile,
        recommendedWorkout: DailyWorkout?,
        date: Date = Date(),
        hasStrengthBenchmarks: Bool = true
    ) {
        self.plan = plan
        self.context = .init(
            profile: profile, date: date, recommendedWorkout: recommendedWorkout,
            hasStrengthBenchmarks: hasStrengthBenchmarks
        )
    }

    var recommendedChoiceID: String {
        choices.first(where: \.isRecommended)?.id ?? choices.first?.id ?? "rest"
    }

    var canPreview: Bool {
        draft?.validationIssues.isEmpty == true && blockerMessage == nil
    }

    func load() {
        choices = TodayWorkoutChoicePolicy.choices(context: context)
        phase = .recommended
    }

    func showChoices() {
        blockerMessage = nil
        phase = .choosing
    }

    func select(_ id: String) {
        blockerMessage = nil
        errorMessage = nil
        guard let choice = choices.first(where: { $0.id == id }) else { return }
        if case .blocked(let blocker) = choice.availability {
            blockerMessage = blocker.message
            draft = nil
            phase = .choosing
            return
        }
        draft = TodayWorkoutChoicePolicy.draft(for: choice, context: context)
        phase = .editing
    }

    func updateDraft(_ updated: TodayWorkoutDraft) {
        draft = updated
        preview = nil
        phase = .editing
    }

    func useCustomRun() {
        draft = .customRun(minutes: 30, miles: nil, date: context.date)
        phase = .editing
    }

    func useCustomStrength() {
        draft = .customStrength(exercises: [
            Exercise(name: "Squat", sets: 3, reps: "8-10", weight: "Comfortable working load"),
            Exercise(name: "Push", sets: 3, reps: "8-10", weight: "Comfortable working load"),
            Exercise(name: "Hinge", sets: 3, reps: "8-10", weight: "Comfortable working load"),
            Exercise(name: "Pull", sets: 3, reps: "8-10", weight: "Comfortable working load"),
        ], date: context.date)
        phase = .editing
    }

    func useLegacyDraft(_ legacyDraft: TodayWorkoutDraft) {
        draft = legacyDraft
        preview = nil
        blockerMessage = nil
        phase = .editing
    }

    func buildPreview() throws {
        guard let draft, canPreview else { throw TodayWorkoutDecisionError.invalidDraft }
        preview = try TodayWorkoutDecisionService.preview(
            draft: draft, currentPlan: plan, now: context.date
        )
        phase = .previewing
    }

    func commit(using persist: (TodayWorkoutDecisionPreview) throws -> Void) throws {
        guard let preview else { throw TodayWorkoutDecisionError.invalidDraft }
        phase = .committing
        do {
            try persist(preview)
            phase = .committed
        } catch {
            errorMessage = error.localizedDescription
            phase = .failed
            throw error
        }
    }
}
