//
//  TrainingProfileTests.swift
//  Runaway iOSTests
//

import Foundation
import Testing
@testable import Runaway_iOS

@Suite("Training Profile")
struct TrainingProfileTests {
    @Test("The running-first default uses schema version 1 and running as the primary activity")
    func defaultUsesRunningPrimary() {
        let profile = TrainingProfile.runningFirstDefault

        #expect(profile.schemaVersion == 1)
        #expect(profile.primaryActivity == .running)
    }

    @Test("Validation keeps running primary and reduces excess sessions by role")
    func validationRepairsMultiplePrimariesAndExcessSessions() {
        let profile = TrainingProfile(
            schemaVersion: 1,
            activities: [
                TrainingActivityPreference(activity: .running, role: .primary, sessionsPerWeek: 6),
                TrainingActivityPreference(activity: .cycling, role: .primary, sessionsPerWeek: 3),
                TrainingActivityPreference(activity: .strength, role: .optional, sessionsPerWeek: 2),
            ],
            trainingDaysPerWeek: 7,
            preferredLongRunWeekday: 7,
            unavailableWeekdays: [],
            strengthEquipment: .bodyweight,
            strengthExperience: .beginner
        )

        let result = profile.validated()

        #expect(result.profile.primaryActivity == .running)
        #expect(result.profile.preference(for: .cycling)?.role == .supporting)
        #expect(result.profile.preference(for: .strength)?.sessionsPerWeek == 0)
        #expect(result.profile.preference(for: .cycling)?.sessionsPerWeek == 1)
        #expect(result.profile.activities.reduce(0) { $0 + $1.sessionsPerWeek } == 7)
        #expect(result.wasRepaired)
        #expect(!result.repairReasons.isEmpty)
    }

    @Test("Validation restores the running-first default when no activities are selected")
    func validationRestoresRunningForEmptyActivities() {
        let profile = TrainingProfile(
            schemaVersion: 1,
            activities: [],
            trainingDaysPerWeek: 3,
            preferredLongRunWeekday: 7,
            unavailableWeekdays: [],
            strengthEquipment: .bodyweight,
            strengthExperience: .beginner
        )

        let result = profile.validated()

        #expect(result.profile.primaryActivity == .running)
        #expect(result.profile.activities == TrainingProfile.runningFirstDefault.activities)
        #expect(result.wasRepaired)
    }

    @Test("Validation retains the first duplicate and removes invalid unavailable weekdays")
    func validationRepairsDuplicateActivitiesAndInvalidWeekdaysDeterministically() {
        let profile = TrainingProfile(
            schemaVersion: 1,
            activities: [
                TrainingActivityPreference(activity: .running, role: .primary, sessionsPerWeek: 3),
                TrainingActivityPreference(activity: .cycling, role: .supporting, sessionsPerWeek: 2),
                TrainingActivityPreference(activity: .running, role: .optional, sessionsPerWeek: 7),
            ],
            trainingDaysPerWeek: 5,
            preferredLongRunWeekday: 9,
            unavailableWeekdays: [0, 2, 8],
            strengthEquipment: .dumbbells,
            strengthExperience: .intermediate
        )

        let result = profile.validated()

        #expect(result.profile.activities == [
            TrainingActivityPreference(activity: .running, role: .primary, sessionsPerWeek: 3),
            TrainingActivityPreference(activity: .cycling, role: .supporting, sessionsPerWeek: 2),
        ])
        #expect(result.profile.preferredLongRunWeekday == 7)
        #expect(result.profile.unavailableWeekdays == [2])
        #expect(result.wasRepaired)
    }

    @Test("Fingerprint is stable for equivalent profiles and changes for scheduling input")
    func fingerprintIsStableAndTracksSchedulingInputs() {
        let profile = TrainingProfile.runningFirstDefault
        var changedProfile = profile
        changedProfile.trainingDaysPerWeek = 4

        #expect(profile.fingerprint == TrainingProfile.runningFirstDefault.fingerprint)
        #expect(profile.fingerprint != changedProfile.fingerprint)
    }

    @Test("Fingerprint is independent of activity preference array order")
    func fingerprintIsIndependentOfActivityArrayOrder() {
        var orderedProfile = TrainingProfile.runningFirstDefault
        orderedProfile.activities = [
            TrainingActivityPreference(activity: .running, role: .primary, sessionsPerWeek: 2),
            TrainingActivityPreference(activity: .cycling, role: .supporting, sessionsPerWeek: 1),
            TrainingActivityPreference(activity: .mobility, role: .optional, sessionsPerWeek: 0),
        ]
        var reorderedProfile = orderedProfile
        reorderedProfile.activities = [
            TrainingActivityPreference(activity: .mobility, role: .optional, sessionsPerWeek: 0),
            TrainingActivityPreference(activity: .running, role: .primary, sessionsPerWeek: 2),
            TrainingActivityPreference(activity: .cycling, role: .supporting, sessionsPerWeek: 1),
        ]

        #expect(orderedProfile.fingerprint == reorderedProfile.fingerprint)
    }

    @Test("Fingerprint excludes schema version")
    func fingerprintIsIndependentOfSchemaVersion() {
        let profile = TrainingProfile.runningFirstDefault
        var versionChangedProfile = profile
        versionChangedProfile.schemaVersion = 99

        #expect(profile.fingerprint == versionChangedProfile.fingerprint)
    }

    @MainActor
    @Test("A missing stored profile restores a usable default and requests personalization")
    func missingStoredProfileUsesDefaultAndRequestsPersonalization() {
        let (defaults, suiteName) = makeDefaults()
        defer { clear(defaults, suiteName: suiteName) }

        let store = TrainingProfileStore(defaults: defaults, existingPlan: nil)

        #expect(store.profile.primaryActivity == .running)
        #expect(store.needsPersonalization)
    }

    @MainActor
    @Test("A saved profile reloads from injected UserDefaults")
    func savedProfileReloadsFromInjectedDefaults() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { clear(defaults, suiteName: suiteName) }
        let store = TrainingProfileStore(defaults: defaults, existingPlan: nil)
        var savedProfile = TrainingProfile.runningFirstDefault
        savedProfile.trainingDaysPerWeek = 4
        savedProfile.activities.append(
            TrainingActivityPreference(activity: .strength, role: .supporting, sessionsPerWeek: 1)
        )

        try store.save(savedProfile)
        let reloadedStore = TrainingProfileStore(defaults: defaults, existingPlan: nil)

        #expect(reloadedStore.profile == savedProfile.validated().profile)
        #expect(!reloadedStore.needsPersonalization)
    }

    @MainActor
    @Test("Corrupt profile data restores the default and requests personalization")
    func corruptStoredDataRepairsSafely() {
        let (defaults, suiteName) = makeDefaults()
        defer { clear(defaults, suiteName: suiteName) }
        defaults.set(Data("corrupt".utf8), forKey: "trainingProfile.v1")
        defaults.set(true, forKey: "trainingProfile.personalized.v1")

        let store = TrainingProfileStore(defaults: defaults, existingPlan: nil)

        #expect(store.profile == TrainingProfile.runningFirstDefault)
        #expect(store.needsPersonalization)
    }

    @MainActor
    @Test("Dismissing personalization leaves the profile unchanged")
    func dismissingPersonalizationDoesNotChangeProfile() {
        let (defaults, suiteName) = makeDefaults()
        defer { clear(defaults, suiteName: suiteName) }
        let store = TrainingProfileStore(defaults: defaults, existingPlan: nil)
        let profileBeforeDismissal = store.profile

        store.dismissPersonalizationPrompt()

        #expect(store.profile == profileBeforeDismissal)
        #expect(!store.needsPersonalization)
    }

    @MainActor
    @Test("Weekly summary reflects the activity mix and preferred long-run day")
    func editorSummaryReflectsMixAndLongRunDay() {
        let (defaults, suiteName) = makeDefaults()
        defer { clear(defaults, suiteName: suiteName) }
        let store = TrainingProfileStore(defaults: defaults)
        let model = TrainingProfileEditorViewModel(store: store)
        model.draft.activities = [
            TrainingActivityPreference(activity: .running, role: .primary, sessionsPerWeek: 4),
            TrainingActivityPreference(activity: .strength, role: .supporting, sessionsPerWeek: 2),
        ]
        model.draft.trainingDaysPerWeek = 6
        model.draft.preferredLongRunWeekday = 1

        #expect(model.summary == "4 runs + 2 strength sessions, long run Sunday")
    }

    @MainActor
    @Test("Strength detail visibility follows selection without changing saved strength values")
    func strengthVisibilityTracksSelectionWithoutCorruptingValues() {
        let (defaults, suiteName) = makeDefaults()
        defer { clear(defaults, suiteName: suiteName) }
        let model = TrainingProfileEditorViewModel(store: TrainingProfileStore(defaults: defaults))
        model.draft.strengthEquipment = .fullGym
        model.draft.strengthExperience = .advanced

        model.setActivity(.strength, selected: true)
        #expect(model.showsStrengthDetails)

        model.setActivity(.strength, selected: false)
        #expect(!model.showsStrengthDetails)
        #expect(model.draft.strengthEquipment == .fullGym)
        #expect(model.draft.strengthExperience == .advanced)
    }

    @MainActor
    @Test("The sole primary activity cannot be removed")
    func editorPreventsRemovingSolePrimary() {
        let (defaults, suiteName) = makeDefaults()
        defer { clear(defaults, suiteName: suiteName) }
        let model = TrainingProfileEditorViewModel(store: TrainingProfileStore(defaults: defaults))

        model.setActivity(.running, selected: false)

        #expect(model.isSelected(.running))
        #expect(!model.canRemove(.running))
    }

    @MainActor
    @Test("Validation copy explains repairs before save")
    func validationCopyReflectsRepairs() {
        let (defaults, suiteName) = makeDefaults()
        defer { clear(defaults, suiteName: suiteName) }
        let model = TrainingProfileEditorViewModel(store: TrainingProfileStore(defaults: defaults))
        model.draft.activities = [
            TrainingActivityPreference(activity: .running, role: .primary, sessionsPerWeek: 4),
            TrainingActivityPreference(activity: .strength, role: .supporting, sessionsPerWeek: 2),
        ]
        model.draft.trainingDaysPerWeek = 4

        #expect(model.validationCopy == "Activity sessions were reduced to fit the selected training days.")
    }

    @MainActor
    @Test("An unchanged save dismisses without regeneration")
    func unchangedSaveDoesNotRegenerate() {
        let (defaults, suiteName) = makeDefaults()
        defer { clear(defaults, suiteName: suiteName) }
        var generationCount = 0
        let store = TrainingProfileStore(defaults: defaults)
        let model = TrainingProfileEditorViewModel(
            store: store,
            generatePlan: { _, _ in
                generationCount += 1
                return makePresentationPlan(id: "unexpected")
            }
        )

        model.save()

        #expect(model.shouldDismiss)
        #expect(!model.isPresentingRegenerationChoices)
        #expect(generationCount == 0)
        #expect(store.hasPersonalizedProfile)
        #expect(!store.needsPersonalization)
    }

    @MainActor
    @Test("A material save persists before presenting regeneration choices")
    func materialSavePersistsBeforePrompt() {
        let (defaults, suiteName) = makeDefaults()
        defer { clear(defaults, suiteName: suiteName) }
        let store = TrainingProfileStore(defaults: defaults)
        let model = TrainingProfileEditorViewModel(store: store)
        model.draft.trainingDaysPerWeek = 4
        model.draft.activities[0].sessionsPerWeek = 4

        model.save()

        #expect(store.profile.trainingDaysPerWeek == 4)
        #expect(store.profile.activities[0].sessionsPerWeek == 4)
        #expect(model.isPresentingRegenerationChoices)
        #expect(!model.shouldDismiss)
    }

    @MainActor
    @Test("First-time personalization creates the current week when no plan exists")
    func firstProfileCreatesCurrentWeekInsteadOfRebalancingMissingPlan() async {
        let (defaults, suiteName) = makeDefaults()
        defer { clear(defaults, suiteName: suiteName) }
        var receivedScope: PlanRegenerationScope?
        var receivedInput: WeeklyTrainingPlan?
        let model = TrainingProfileEditorViewModel(
            store: TrainingProfileStore(defaults: defaults),
            currentPlan: { nil },
            generatePlan: { _, scope, input in
                receivedScope = scope
                receivedInput = input
                return makePresentationPlan(id: "first-current-week")
            }
        )
        model.draft.trainingDaysPerWeek = 4
        model.draft.activities[0].sessionsPerWeek = 4

        model.save()
        #expect(model.currentWeekActionTitle == "Create This Week")
        await model.regenerate(scope: .remainingCurrentWeek)

        if case .initialCurrentWeek = receivedScope {} else {
            Issue.record("Expected first-time personalization to create the current week")
        }
        #expect(receivedInput == nil)
        #expect(!model.isPresentingRegenerationChoices)
        #expect(model.shouldDismiss)
    }

    @MainActor
    @Test("Both regeneration choices forward the approved Task 4 scopes")
    func regenerationChoicesUseApprovedScopes() async {
        let (defaults, suiteName) = makeDefaults()
        defer { clear(defaults, suiteName: suiteName) }
        var scopes: [PlanRegenerationScope] = []
        let currentPlan = makePresentationPlan(id: "current")
        let model = TrainingProfileEditorViewModel(
            store: TrainingProfileStore(defaults: defaults),
            currentPlan: { currentPlan },
            generatePlan: { _, scope, _ in
                scopes.append(scope)
                return makePresentationPlan(id: "generated-\(scopes.count)")
            }
        )

        await model.regenerate(scope: .nextWeek)
        await model.regenerate(scope: .remainingCurrentWeek)

        #expect(scopes.count == 2)
        if scopes.count == 2 {
            if case .nextWeek = scopes[0] {} else { Issue.record("Expected next-week scope") }
            if case .remainingCurrentWeek = scopes[1] {} else { Issue.record("Expected current-week scope") }
        }
    }

    @MainActor
    @Test("A failed regeneration preserves the previous plan and retry reuses the same scope")
    func failedRegenerationPreservesPlanAndRetryScope() async {
        let (defaults, suiteName) = makeDefaults()
        defer { clear(defaults, suiteName: suiteName) }
        let previousPlan = makePresentationPlan(id: "previous")
        let replacementPlan = makePresentationPlan(id: "replacement")
        var activePlan = previousPlan
        var scopes: [PlanRegenerationScope] = []
        let model = TrainingProfileEditorViewModel(
            store: TrainingProfileStore(defaults: defaults),
            currentPlan: { previousPlan },
            generatePlan: { _, scope, _ in
                scopes.append(scope)
                if scopes.count == 1 { throw PresentationFailure.expected }
                activePlan = replacementPlan
                return replacementPlan
            }
        )

        await model.regenerate(scope: .remainingCurrentWeek)

        #expect(activePlan.id == previousPlan.id)
        #expect(model.errorMessage != nil)
        #expect(model.canRetry)

        await model.retry()

        #expect(activePlan.id == replacementPlan.id)
        #expect(scopes.count == 2)
        if scopes.count == 2 {
            if case .remainingCurrentWeek = scopes[0] {} else { Issue.record("Expected current-week scope") }
            if case .remainingCurrentWeek = scopes[1] {} else { Issue.record("Retry changed scope") }
        }
    }

    @MainActor
    @Test("The editor retains the shared profile store instance supplied by its route")
    func editorUsesSharedStoreInstance() {
        let (defaults, suiteName) = makeDefaults()
        defer { clear(defaults, suiteName: suiteName) }
        let store = TrainingProfileStore(defaults: defaults)
        let model = TrainingProfileEditorViewModel(store: store)

        #expect(model.trainingProfileStore === store)
    }

    private enum PresentationFailure: Error {
        case expected
    }

    private func makePresentationPlan(id: String) -> WeeklyTrainingPlan {
        let start = Calendar.current.startOfDay(for: Date())
        return WeeklyTrainingPlan(
            id: id,
            athleteId: 42,
            weekStartDate: start,
            weekEndDate: Calendar.current.date(byAdding: .day, value: 6, to: start)!,
            workouts: [],
            weekNumber: nil,
            totalMileage: 0,
            focusArea: nil,
            notes: nil,
            generatedAt: start,
            goalId: nil
        )
    }

    @MainActor
    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "TrainingProfileTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    @MainActor
    private func clear(_ defaults: UserDefaults, suiteName: String) {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
