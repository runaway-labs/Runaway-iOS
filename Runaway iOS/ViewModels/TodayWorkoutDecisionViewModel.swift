import Foundation
import Observation

@MainActor
@Observable
final class TodayWorkoutDecisionViewModel {
    enum Phase: Equatable {
        case loading
        case recommended
        case choosing
        case choosingStrengthZones
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
    private(set) var strengthSelection: Set<StrengthZone> = []
    private(set) var strengthRecommendations: [StrengthZoneRecommendation] = []

    private let plan: WeeklyTrainingPlan
    private let context: TodayWorkoutChoicePolicy.Context
    private let athleteProfile: AthleteTrainingProfile
    private let strengthHistory: StrengthZoneHistorySnapshot

    init(
        plan: WeeklyTrainingPlan,
        profile: TrainingProfile,
        recommendedWorkout: DailyWorkout?,
        date: Date = Date(),
        hasStrengthBenchmarks: Bool = true,
        athleteProfile: AthleteTrainingProfile? = nil,
        strengthHistory: StrengthZoneHistorySnapshot? = nil
    ) {
        self.plan = plan
        self.context = .init(
            profile: profile, date: date, recommendedWorkout: recommendedWorkout,
            hasStrengthBenchmarks: hasStrengthBenchmarks
        )
        self.athleteProfile = athleteProfile ?? AthleteTrainingProfile(athleteID: plan.athleteId)
        self.strengthHistory = strengthHistory ?? StrengthZoneHistorySnapshot(
            generatedAt: date, exposures: [:], hasUnattributedStrengthWork: false
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
        if choice.activity == .strength || choice.workoutType.isStrength {
            beginStrengthSelection()
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
        beginStrengthSelection()
    }

    func toggleStrengthZone(_ zone: StrengthZone) {
        guard athleteProfile.resolvedStrengthRecommendations.availableZones.contains(zone) else { return }
        if strengthSelection.contains(zone) { strengthSelection.remove(zone) }
        else { strengthSelection.insert(zone) }
        errorMessage = nil
    }

    func generateStrengthDraft(duration: Int) throws {
        do {
            let generated = try StrengthWorkoutGenerator.generate(.init(
                selectedZones: strengthSelection,
                availableZones: athleteProfile.resolvedStrengthRecommendations.availableZones,
                durationMinutes: duration,
                equipment: context.profile.strengthEquipment,
                experience: context.profile.strengthExperience,
                outcomes: athleteProfile.outcomes ?? AthleteOutcome.defaults,
                history: strengthHistory,
                upcomingWorkouts: plan.workouts
            ))
            let day = Calendar.current.startOfDay(for: context.date)
            var workout = DailyWorkout(
                id: "zone-strength-\(Int(day.timeIntervalSince1970))", date: day,
                dayOfWeek: .from(date: day), workoutType: .strengthTraining,
                title: strengthSelection.count == 1
                    ? "\(strengthSelection.first!.rawValue.capitalized) Strength"
                    : "Focused Strength",
                description: generated.explanation,
                duration: duration, distance: nil, targetPace: nil,
                exercises: generated.planExercises, isCompleted: false, completedActivityId: nil
            )
            workout.strengthPrescription = generated.metadata
            draft = TodayWorkoutDraft(
                workout: workout, source: .custom,
                reason: generated.explanation
            )
            preview = nil
            errorMessage = nil
            phase = .editing
        } catch {
            errorMessage = error.localizedDescription
            phase = .choosingStrengthZones
            throw error
        }
    }

    private func beginStrengthSelection() {
        draft = nil
        preview = nil
        blockerMessage = nil
        errorMessage = nil
        strengthSelection = []
        let recommendationContext = StrengthZoneRecommendationContext(
            athleteProfile: athleteProfile, trainingProfile: context.profile,
            weeklyPlan: plan, history: strengthHistory,
            date: context.date, calendar: .current
        )
        let recommended = StrengthZoneRecommendationPolicy.recommendations(for: recommendationContext)
        if recommended.isEmpty && !athleteProfile.resolvedStrengthRecommendations.suggestionsEnabled {
            strengthRecommendations = StrengthZone.allCases
                .filter(athleteProfile.resolvedStrengthRecommendations.availableZones.contains)
                .map {
                    StrengthZoneRecommendation(
                        zone: $0, score: 0, reasons: [], context: .noRecentData,
                        isSelectable: true, isCoachPick: false,
                        explanation: "Available for today's strength session."
                    )
                }
        } else {
            strengthRecommendations = recommended
        }
        phase = .choosingStrengthZones
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
