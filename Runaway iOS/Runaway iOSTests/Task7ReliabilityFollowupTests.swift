import XCTest
@testable import Runaway_iOS

@MainActor
final class Task7ReliabilityFollowupTests: XCTestCase {
    func testNumericQueueIdentifierUsesRepositoryLookupPath() async throws {
        let repository = ActivitySyncRepositorySpy(activity: Activity(id: 417, name: "Queued run"))
        let operationID = UUID()
        var receivedOperationID: UUID?
        let coordinator = ActivityCreateSyncCoordinator(
            localRepository: repository,
            acknowledgementStore: ActivitySyncAcknowledgementStore(directoryURL: temporaryDirectory()),
            remoteUpsert: { activity, operationID in
                receivedOperationID = operationID
                return activity
            }
        )

        try await coordinator.sync(operationID: operationID, numericEntityID: "417")

        XCTAssertEqual(repository.lookedUpIDs, [417])
        XCTAssertEqual(repository.appliedServerIDs, [417])
        XCTAssertEqual(receivedOperationID, operationID)
    }

    func testRestartReplaysDurableAcknowledgementWithoutSecondRemoteCreate() async throws {
        let directory = temporaryDirectory()
        let operationID = UUID()
        let firstRepository = ActivitySyncRepositorySpy(
            activity: Activity(id: 912, name: "Crash-safe run"),
            applyFailuresRemaining: 1
        )
        var remoteCreateCount = 0
        var receivedOperationIDs: [UUID] = []
        let firstCoordinator = ActivityCreateSyncCoordinator(
            localRepository: firstRepository,
            acknowledgementStore: ActivitySyncAcknowledgementStore(directoryURL: directory),
            remoteUpsert: { activity, receivedOperationID in
                remoteCreateCount += 1
                receivedOperationIDs.append(receivedOperationID)
                return activity
            }
        )

        do {
            try await firstCoordinator.sync(operationID: operationID, numericEntityID: "912")
            XCTFail("Expected the simulated local save to fail")
        } catch {}

        let restartedRepository = ActivitySyncRepositorySpy(activity: Activity(id: 912))
        let restartedCoordinator = ActivityCreateSyncCoordinator(
            localRepository: restartedRepository,
            acknowledgementStore: ActivitySyncAcknowledgementStore(directoryURL: directory),
            remoteUpsert: { activity, receivedOperationID in
                remoteCreateCount += 1
                receivedOperationIDs.append(receivedOperationID)
                return activity
            }
        )
        try await restartedCoordinator.sync(operationID: operationID, numericEntityID: "912")

        XCTAssertEqual(remoteCreateCount, 1)
        XCTAssertEqual(receivedOperationIDs, [operationID])
        XCTAssertEqual(restartedRepository.lookedUpIDs, [])
        XCTAssertEqual(restartedRepository.appliedServerIDs, [912])
    }

    func testCreateAcknowledgementReconcilesExactLocalRecord() async throws {
        let localRecordID = UUID()
        let repository = ActivitySyncRepositorySpy(activity: Activity(id: 44, name: "Provisional"))
        let coordinator = ActivityCreateSyncCoordinator(
            localRepository: repository,
            acknowledgementStore: ActivitySyncAcknowledgementStore(directoryURL: temporaryDirectory()),
            remoteUpsert: { _, _ in Activity(id: 8044, name: "Canonical") }
        )

        try await coordinator.sync(
            operationID: UUID(),
            numericEntityID: "44",
            localRecordID: localRecordID
        )

        XCTAssertEqual(repository.requestedLocalRecordIDs, [localRecordID])
        XCTAssertEqual(repository.reconciledLocalRecordIDs, [localRecordID])
        XCTAssertEqual(repository.appliedServerIDs, [8044])
        XCTAssertTrue(repository.lookedUpIDs.isEmpty)
    }

    func testReadinessTransitionTriggersOneCoalescedDrain() async {
        let coordinator = WidgetPendingActionDrainCoordinator()
        var drainCount = 0

        if WidgetPendingActionDrainCoordinator.shouldDrain(previousReady: false, newReady: true) {
            coordinator.requestDrain { drainCount += 1 }
        }
        if WidgetPendingActionDrainCoordinator.shouldDrain(previousReady: true, newReady: true) {
            coordinator.requestDrain { drainCount += 1 }
        }
        await coordinator.waitUntilIdle()

        XCTAssertEqual(drainCount, 1)
    }

    func testCommitmentLoadFailureRetainsPendingWithoutChoosingMutation() {
        let result = CommitmentLoadResult.failure(TestError.simulated)
        XCTAssertEqual(WidgetCommitmentPendingDecision.decide(from: result), .retainPending)
    }

    func testCompileFocusedIdempotentSignaturesCarryOperationID() {
        let expectedID = UUID()
        let operation = SyncOperation(
            id: expectedID,
            entityType: .activity,
            entityId: "55",
            operationType: .create
        )
        let serviceCall: (Activity, UUID) async throws -> Activity = { activity, operationID in
            try await ActivityService.createActivity(
                activity: activity,
                clientOperationID: operationID
            )
        }
        let visibleError: Error = SyncEngineError.invalidEntityIdentifier

        XCTAssertEqual(operation.id, expectedID)
        _ = serviceCall
        _ = visibleError
    }

    func testOfflineUpdateOperationStaysUpdateAndUsesUpdateSignature() {
        let operation = SyncOperation(
            entityType: .activity,
            entityId: "73",
            operationType: .update
        )
        let updateCall: (Activity) async throws -> Activity = { activity in
            try await ActivityService.updateActivity(activity: activity)
        }

        XCTAssertEqual(operation.operationType, .update)
        _ = updateCall
    }

    func testNilSyncEngineFailsClosedBeforeRemoteCreateCanStart() {
        XCTAssertThrowsError(try HybridActivityRepository.requireDurableSyncEngine(nil)) { error in
            guard case HybridActivityRepositoryError.syncEngineUnavailable = error else {
                return XCTFail("Expected explicit durable sync configuration failure")
            }
        }
    }

    func testSimulatorHTTPSProxyRequiresExplicitConfiguration() {
        XCTAssertNil(simulatorHTTPSProxyDictionary(environment: [:]))

        let proxy = simulatorHTTPSProxyDictionary(environment: [
            "RUNAWAY_SIMULATOR_HTTPS_PROXY_HOST": "localhost",
            "RUNAWAY_SIMULATOR_HTTPS_PROXY_PORT": "18888",
        ])

        XCTAssertEqual(proxy?["HTTPSEnable"] as? Bool, true)
        XCTAssertEqual(proxy?["HTTPSProxy"] as? String, "localhost")
        XCTAssertEqual(proxy?["HTTPSPort"] as? Int, 18_888)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Task7ReliabilityFollowupTests")
            .appendingPathComponent(UUID().uuidString)
    }
}

@MainActor
final class OnboardingTrainingProfileTests: XCTestCase {
    func testLiveDraftPersistsAcrossInterruptionWithoutNavigation() async throws {
        let defaults = isolatedDefaults()
        defer { clear(defaults) }
        let state = onboardingState(step: .activityMix)

        let first = OnboardingViewModel(
            trainingProfileStore: TrainingProfileStore(defaults: defaults),
            draftDefaults: defaults,
            loadOnboardingState: { _ in state },
            draftDebounceNanoseconds: 0
        )
        await first.loadOnboardingState(for: state.athleteId)
        first.selectPrimaryGoal(.race)
        first.trainingProfileEditor.setActivity(.strength, selected: true)
        first.trainingProfileEditor.setSessions(2, for: .strength)
        first.trainingProfileEditor.setTrainingDays(5)
        first.trainingProfileEditor.setUnavailable(true, weekday: 3)
        first.trainingProfileEditor.setStrengthEquipment(.fullGym)
        first.trainingProfileEditor.setStrengthExperience(.advanced)
        await first.waitForPendingTrainingPersistence()
        let expected = first.onboardingAnswers

        XCTAssertNil(first.trainingPersistenceError)
        XCTAssertFalse(first.hasUnsavedTrainingChanges)

        let reconstructed = OnboardingViewModel(
            trainingProfileStore: TrainingProfileStore(defaults: defaults),
            draftDefaults: defaults,
            loadOnboardingState: { _ in state },
            draftDebounceNanoseconds: 0
        )
        await reconstructed.loadOnboardingState(for: state.athleteId)

        XCTAssertEqual(reconstructed.currentStep, .activityMix)
        XCTAssertEqual(reconstructed.onboardingAnswers, expected)
    }

    func testFailedLiveDraftPersistenceSurfacesRetryAndNeverClaimsSaved() async {
        let state = onboardingState(step: .trainingSchedule)
        var attempts = 0
        var shouldFail = true
        var persisted: OnboardingAnswers?
        let persistence = OnboardingPersistenceClient(
            loadDraft: { _ in nil },
            saveDraft: { answers, _ in
                attempts += 1
                if shouldFail { throw OnboardingTestError.expected }
                persisted = answers
            },
            saveStep: { _, _ in }
        )
        let model = OnboardingViewModel(
            trainingProfileStore: TrainingProfileStore(defaults: isolatedDefaults()),
            persistence: persistence,
            loadOnboardingState: { _ in state },
            draftDebounceNanoseconds: 0
        )
        await model.loadOnboardingState(for: state.athleteId)

        model.trainingProfileEditor.setActivity(.strength, selected: true)
        await model.waitForPendingTrainingPersistence()

        XCTAssertNotNil(model.trainingPersistenceError)
        XCTAssertTrue(model.hasUnsavedTrainingChanges)
        XCTAssertNil(persisted)

        shouldFail = false
        model.retryTrainingPersistence()
        await model.waitForPendingTrainingPersistence()

        XCTAssertNil(model.trainingPersistenceError)
        XCTAssertFalse(model.hasUnsavedTrainingChanges)
        XCTAssertEqual(persisted, model.onboardingAnswers)
    }

    func testRapidNextBackSerializesDraftThenDestinationAndKeepsStateAligned() async {
        let state = onboardingState(step: .goalsSetup)
        let delayed = DelayedOnboardingPersistence()
        let persistence = OnboardingPersistenceClient(
            loadDraft: { _ in nil },
            saveDraft: { answers, athleteId in
                delayed.saveDraft(answers, athleteId: athleteId)
            },
            saveStep: { stateId, step in
                try await delayed.saveStep(stateId: stateId, step: step)
            }
        )
        let model = OnboardingViewModel(
            trainingProfileStore: TrainingProfileStore(defaults: isolatedDefaults()),
            persistence: persistence,
            loadOnboardingState: { _ in state },
            draftDebounceNanoseconds: 0
        )
        await model.loadOnboardingState(for: state.athleteId)
        model.selectPrimaryGoal(.race)
        delayed.resetEvents()

        model.nextStep()
        model.previousStep()

        XCTAssertTrue(model.isNavigationPending)
        XCTAssertEqual(model.currentStep, .goalsSetup)
        await delayed.waitUntilStepSaveStarts()
        delayed.resumeStepSave()
        await model.waitForPendingNavigation()

        XCTAssertFalse(model.isNavigationPending)
        XCTAssertEqual(model.currentStep, .activityMix)
        XCTAssertEqual(delayed.persistedStep, OnboardingStep.activityMix.rawValue)
        XCTAssertEqual(delayed.persistedAnswers?.primaryGoal, .race)
        XCTAssertEqual(delayed.events, ["draft", "step:\(OnboardingStep.activityMix.rawValue)"])
    }

    func testProductionGoalSelectionFlowsThroughAnswersAndRunningPrimaryConversion() async {
        for goal in [OnboardingPrimaryGoal.race, .running] {
            let state = onboardingState(step: .goalsSetup)
            var persisted: OnboardingAnswers?
            let model = OnboardingViewModel(
                trainingProfileStore: TrainingProfileStore(defaults: isolatedDefaults()),
                persistence: OnboardingPersistenceClient(
                    loadDraft: { _ in nil },
                    saveDraft: { answers, _ in persisted = answers },
                    saveStep: { _, _ in }
                ),
                loadOnboardingState: { _ in state },
                draftDebounceNanoseconds: 0
            )
            await model.loadOnboardingState(for: state.athleteId)

            model.selectPrimaryGoal(goal)
            model.nextStep()
            await model.waitForPendingNavigation()

            XCTAssertEqual(model.onboardingAnswers.primaryGoal, goal)
            XCTAssertEqual(persisted?.primaryGoal, goal)
            XCTAssertEqual(model.trainingProfileEditor.draft.primaryActivity, .running)
            XCTAssertEqual(
                OnboardingService.makeTrainingProfile(from: model.onboardingAnswers).primaryActivity,
                .running
            )
        }
    }

    func testSharedControlPresentationTracksStrengthAndAccessibilityMetadata() {
        let defaults = isolatedDefaults()
        defer { clear(defaults) }
        let model = TrainingProfileEditorViewModel(store: TrainingProfileStore(defaults: defaults))

        XCTAssertFalse(model.controlPresentation.showsStrengthControls)
        model.setActivity(.strength, selected: true)

        XCTAssertTrue(model.controlPresentation.showsStrengthControls)
        XCTAssertGreaterThanOrEqual(model.controlPresentation.minimumTargetSize, 44)
        XCTAssertFalse(model.controlPresentation.activitySelectionLabel(for: .strength).isEmpty)

        let navigation = OnboardingTrainingNavigationPresentation(
            continueLabel: "Continue to training schedule"
        )
        XCTAssertEqual(navigation.backLabel, "Back")
        XCTAssertEqual(navigation.continueLabel, "Continue to training schedule")
        XCTAssertGreaterThanOrEqual(navigation.minimumTargetSize, 44)
    }

    func testProductionTimingPersistsLocallyBeforeDebounceAndLifecycleFlushesDefensively() async throws {
        let defaults = isolatedDefaults()
        defer { clear(defaults) }
        let state = onboardingState(step: .activityMix)
        let model = OnboardingViewModel(
            trainingProfileStore: TrainingProfileStore(defaults: defaults),
            draftDefaults: defaults,
            loadOnboardingState: { _ in state }
        )
        await model.loadOnboardingState(for: state.athleteId)

        model.trainingProfileEditor.setActivity(.strength, selected: true)
        model.trainingProfileEditor.setSessions(2, for: .strength)

        XCTAssertEqual(
            try OnboardingTrainingDraftStore(defaults: defaults).load(for: state.athleteId),
            model.onboardingAnswers,
            "The acknowledged edit must be durable before the production 250ms debounce can elapse"
        )
        XCTAssertTrue(OnboardingLifecyclePresentation.shouldFlushDraft(for: .inactive))
        XCTAssertTrue(OnboardingLifecyclePresentation.shouldFlushDraft(for: .background))
        XCTAssertFalse(OnboardingLifecyclePresentation.shouldFlushDraft(for: .active))

        model.trainingProfileEditor.setUnavailable(true, weekday: 4)
        model.flushTrainingDraft()

        XCTAssertEqual(
            try OnboardingTrainingDraftStore(defaults: defaults).load(for: state.athleteId),
            model.onboardingAnswers
        )
        XCTAssertNil(model.trainingPersistenceError)
        XCTAssertFalse(model.hasUnsavedTrainingChanges)
    }

    func testPrimaryGoalSelectionPersistsImmediatelyAndRestoresExactPreservedAnswers() async throws {
        for selectedGoal in [OnboardingPrimaryGoal.race, .running] {
            let defaults = isolatedDefaults()
            defer { clear(defaults) }
            let state = onboardingState(step: .goalsSetup)
            let initialGoal: OnboardingPrimaryGoal = selectedGoal == .race ? .running : .race
            var configuredDraft = trainingFixture
            configuredDraft.activities[0].role = .supporting
            configuredDraft.activities[1].role = .primary
            let draftStore = OnboardingTrainingDraftStore(defaults: defaults)
            try draftStore.save(
                OnboardingAnswers(primaryGoal: initialGoal, draft: configuredDraft),
                for: state.athleteId
            )
            let first = OnboardingViewModel(
                trainingProfileStore: TrainingProfileStore(defaults: defaults),
                draftDefaults: defaults,
                loadOnboardingState: { _ in state }
            )
            await first.loadOnboardingState(for: state.athleteId)

            first.selectPrimaryGoal(selectedGoal)
            let expected = OnboardingAnswers(
                primaryGoal: selectedGoal,
                draft: OnboardingService.normalizingPrimaryGoal(selectedGoal, in: configuredDraft)
            )

            XCTAssertEqual(try draftStore.load(for: state.athleteId), expected)

            let reconstructed = OnboardingViewModel(
                trainingProfileStore: TrainingProfileStore(defaults: defaults),
                draftDefaults: defaults,
                loadOnboardingState: { _ in state }
            )
            await reconstructed.loadOnboardingState(for: state.athleteId)

            XCTAssertEqual(reconstructed.currentStep, .goalsSetup)
            XCTAssertEqual(reconstructed.onboardingAnswers, expected)
        }

        let state = onboardingState(step: .goalsSetup)
        var shouldFail = true
        var persisted: OnboardingAnswers?
        let failingModel = OnboardingViewModel(
            trainingProfileStore: TrainingProfileStore(defaults: isolatedDefaults()),
            persistence: OnboardingPersistenceClient(
                loadDraft: { _ in nil },
                saveDraft: { answers, _ in
                    if shouldFail { throw OnboardingTestError.expected }
                    persisted = answers
                },
                saveStep: { _, _ in }
            ),
            loadOnboardingState: { _ in state }
        )
        await failingModel.loadOnboardingState(for: state.athleteId)

        failingModel.selectPrimaryGoal(.race)

        XCTAssertNotNil(failingModel.trainingPersistenceError)
        XCTAssertTrue(failingModel.hasUnsavedTrainingChanges)
        XCTAssertNil(persisted)

        shouldFail = false
        failingModel.retryTrainingPersistence()

        XCTAssertNil(failingModel.trainingPersistenceError)
        XCTAssertFalse(failingModel.hasUnsavedTrainingChanges)
        XCTAssertEqual(persisted, failingModel.onboardingAnswers)
    }

    func testProductionStepContainerDisallowsGestureMutationAndNavigationRemainsSerialized() async {
        XCTAssertFalse(OnboardingStepContainerPresentation.allowsGestureDrivenStepMutation)

        let state = onboardingState(step: .goalsSetup)
        let delayed = DelayedOnboardingPersistence()
        let model = OnboardingViewModel(
            trainingProfileStore: TrainingProfileStore(defaults: isolatedDefaults()),
            persistence: OnboardingPersistenceClient(
                loadDraft: { _ in nil },
                saveDraft: { answers, athleteId in
                    delayed.saveDraft(answers, athleteId: athleteId)
                },
                saveStep: { stateId, step in
                    try await delayed.saveStep(stateId: stateId, step: step)
                }
            ),
            loadOnboardingState: { _ in state }
        )
        await model.loadOnboardingState(for: state.athleteId)

        model.nextStep()
        await delayed.waitUntilStepSaveStarts()

        XCTAssertEqual(model.currentStep, .goalsSetup)
        XCTAssertTrue(model.isNavigationPending)

        delayed.resumeStepSave()
        await model.waitForPendingNavigation()

        XCTAssertEqual(model.currentStep, .activityMix)
        XCTAssertEqual(delayed.persistedStep, OnboardingStep.activityMix.rawValue)
    }

    func testGoalChangePreservesDraftAndOnlyNormalizesRunningPrimary() {
        let defaults = isolatedDefaults()
        defer { clear(defaults) }
        let model = OnboardingViewModel(trainingProfileStore: TrainingProfileStore(defaults: defaults))
        let original = TrainingProfile(
            schemaVersion: TrainingProfile.currentSchemaVersion,
            activities: [
                TrainingActivityPreference(activity: .running, role: .supporting, sessionsPerWeek: 5),
                TrainingActivityPreference(activity: .strength, role: .primary, sessionsPerWeek: 2),
                TrainingActivityPreference(activity: .cycling, role: .supporting, sessionsPerWeek: 1),
            ],
            trainingDaysPerWeek: 6,
            preferredLongRunWeekday: 6,
            unavailableWeekdays: [2, 5],
            strengthEquipment: .fullGym,
            strengthExperience: .advanced
        )
        model.trainingProfileEditor.draft = original

        model.selectPrimaryGoal(.race)

        let changed = model.trainingProfileEditor.draft
        XCTAssertEqual(changed.activities.map(\.activity), original.activities.map(\.activity))
        XCTAssertEqual(changed.activities.map(\.sessionsPerWeek), original.activities.map(\.sessionsPerWeek))
        XCTAssertEqual(changed.trainingDaysPerWeek, original.trainingDaysPerWeek)
        XCTAssertEqual(changed.preferredLongRunWeekday, original.preferredLongRunWeekday)
        XCTAssertEqual(changed.unavailableWeekdays, original.unavailableWeekdays)
        XCTAssertEqual(changed.strengthEquipment, original.strengthEquipment)
        XCTAssertEqual(changed.strengthExperience, original.strengthExperience)
        XCTAssertEqual(changed.preference(for: .running)?.role, .primary)
        XCTAssertEqual(changed.preference(for: .strength)?.role, .supporting)
    }

    func testGoalsPresentationKeepsContinueReachableAtAccessibilitySizes() {
        let presentation = OnboardingGoalsPresentation()

        XCTAssertTrue(presentation.usesVerticalScroll)
        XCTAssertTrue(presentation.respectsSafeArea)
        XCTAssertTrue(presentation.dismissesKeyboardInteractively)
        XCTAssertTrue(presentation.keepsContinueReachableAtAccessibilitySizes)
        XCTAssertGreaterThanOrEqual(presentation.continueMinimumTargetSize, 44)
    }

    func testCompletionLifecycleClearsDraftOnlyAfterEveryRequiredSuccess() async throws {
        var events: [String] = []
        let persistence = OnboardingPersistenceClient(
            loadDraft: { _ in nil },
            saveDraft: { _, _ in },
            saveStep: { _, _ in },
            clearDraft: { _ in events.append("clear") }
        )

        _ = try await OnboardingCompletionLifecycle.run(
            saveProfile: { events.append("profile") },
            generatePlan: { events.append("plan") },
            complete: {
                events.append("complete")
                return true
            },
            clearDraft: { try persistence.clearDraft(42) }
        )
        XCTAssertEqual(events, ["profile", "plan", "complete", "clear"])

        for failingPhase in ["profile", "plan", "complete"] {
            events = []
            do {
                _ = try await OnboardingCompletionLifecycle.run(
                    saveProfile: {
                        events.append("profile")
                        if failingPhase == "profile" { throw OnboardingTestError.expected }
                    },
                    generatePlan: {
                        events.append("plan")
                        if failingPhase == "plan" { throw OnboardingTestError.expected }
                    },
                    complete: {
                        events.append("complete")
                        if failingPhase == "complete" { throw OnboardingTestError.expected }
                        return true
                    },
                    clearDraft: { try persistence.clearDraft(42) }
                )
                XCTFail("Expected \(failingPhase) failure")
            } catch {
                XCTAssertFalse(events.contains("clear"), "Draft must survive a \(failingPhase) failure")
            }
        }
    }

    func testRunningAndStrengthAnswersMatchSettingsProfileExactly() throws {
        let defaults = isolatedDefaults()
        defer { clear(defaults) }
        let settingsStore = TrainingProfileStore(defaults: defaults)
        let settingsModel = TrainingProfileEditorViewModel(
            store: settingsStore,
            currentPlan: { nil },
            generatePlan: { _, _, _ in throw OnboardingTestError.unused }
        )
        settingsModel.setSessions(4, for: .running)
        settingsModel.setActivity(.strength, selected: true)
        settingsModel.setSessions(2, for: .strength)
        settingsModel.setTrainingDays(6)
        settingsModel.setLongRunWeekday(7)
        settingsModel.setUnavailable(true, weekday: 2)
        settingsModel.draft.strengthEquipment = .dumbbells
        settingsModel.draft.strengthExperience = .intermediate

        let answers = OnboardingTrainingAnswers(
            primaryGoal: .running,
            draft: settingsModel.draft
        )

        XCTAssertEqual(
            OnboardingService.makeTrainingProfile(from: answers),
            settingsModel.draft.validated().profile
        )
    }

    func testRaceAndRunningGoalsStartWithRunningPrimary() {
        for goal in [OnboardingPrimaryGoal.race, .running] {
            let answers = OnboardingTrainingAnswers.default(for: goal)
            XCTAssertEqual(answers.draft.primaryActivity, .running)
            XCTAssertEqual(answers.draft.preference(for: .running)?.role, .primary)
        }
    }

    func testStrengthSelectionUsesSharedEditorStateForConditionalControls() throws {
        let defaults = isolatedDefaults()
        defer { clear(defaults) }
        let store = TrainingProfileStore(defaults: defaults)
        let model = TrainingProfileEditorViewModel(
            store: store,
            currentPlan: { nil },
            generatePlan: { _, _, _ in throw OnboardingTestError.unused }
        )

        XCTAssertFalse(model.showsStrengthDetails)
        model.setActivity(.strength, selected: true)
        model.draft.strengthEquipment = .fullGym
        model.draft.strengthExperience = .advanced

        XCTAssertTrue(model.showsStrengthDetails)
        XCTAssertEqual(model.draft.strengthEquipment, .fullGym)
        XCTAssertEqual(model.draft.strengthExperience, .advanced)
    }

    func testProfilePersistsBeforeInitialGenerationAndGeneratorUsesFingerprint() async throws {
        let defaults = isolatedDefaults()
        defer { clear(defaults) }
        let store = TrainingProfileStore(defaults: defaults)
        var generatedFingerprint: String?
        let answers = OnboardingTrainingAnswers(
            primaryGoal: .running,
            draft: trainingFixture
        )

        let returnedFingerprint = try await OnboardingService.saveTrainingProfileAndGenerateInitialPlan(
            from: answers,
            store: store
        ) { profile in
            XCTAssertFalse(store.needsPersonalization)
            XCTAssertEqual(store.profile, profile)
            generatedFingerprint = profile.fingerprint
            return profile.fingerprint
        }

        XCTAssertEqual(generatedFingerprint, store.profile.fingerprint)
        XCTAssertEqual(returnedFingerprint, store.profile.fingerprint)
    }

    func testResumeAndBackNavigationRetainDraftWithoutPersistingFinalProfile() throws {
        let defaults = isolatedDefaults()
        defer { clear(defaults) }
        let profileStore = TrainingProfileStore(defaults: defaults)
        let draftStore = OnboardingTrainingDraftStore(defaults: defaults)
        let draft = trainingFixture

        let answers = OnboardingAnswers(primaryGoal: .running, draft: draft)
        try draftStore.save(answers, for: 42)

        XCTAssertEqual(try draftStore.load(for: 42), answers)
        XCTAssertTrue(profileStore.needsPersonalization)
        XCTAssertEqual(profileStore.profile, .runningFirstDefault)
        XCTAssertEqual(OnboardingStep.goalsSetup.next, .activityMix)
        XCTAssertEqual(OnboardingStep.activityMix.next, .trainingSchedule)
        XCTAssertEqual(OnboardingStep.trainingSchedule.previous, .activityMix)
        XCTAssertEqual(OnboardingStep.trainingSchedule.next, .experienceAssessment)
        XCTAssertEqual(OnboardingStep.experienceAssessment.rawValue, 3)
    }

    func testProfileMigrationPreservesGoalsAvailabilityEquipmentAndLimitations() {
        let availability = [
            TrainingDayAvailability(weekday: 2, availableMinutes: 75, allowsTwoSessions: true),
            TrainingDayAvailability(weekday: 5, availableMinutes: 45, allowsTwoSessions: false),
        ]
        var profile = AthleteTrainingProfile(
            schemaVersion: 2,
            athleteID: 42,
            outcomes: [.marathonReady, .leanStrong, .durableCore],
            goals: [],
            availability: availability,
            equipment: [.bodyweight, .dumbbells, .fullGym],
            reportedLimitations: "Avoid high-impact jumping.",
            bodyMeasurements: nil,
            strengthRecommendations: nil
        )
        let goals = profile.goals
        let equipment = profile.equipment
        let limitations = profile.reportedLimitations

        profile.migrateStrengthRecommendations()

        XCTAssertEqual(profile.schemaVersion, AthleteTrainingProfile.currentSchemaVersion)
        XCTAssertEqual(profile.goals, goals)
        XCTAssertEqual(profile.availability, availability)
        XCTAssertEqual(profile.equipment, equipment)
        XCTAssertEqual(profile.reportedLimitations, limitations)
        XCTAssertEqual(profile.strengthRecommendations, .default)
    }

    private var trainingFixture: TrainingProfile {
        TrainingProfile(
            schemaVersion: TrainingProfile.currentSchemaVersion,
            activities: [
                TrainingActivityPreference(activity: .running, role: .primary, sessionsPerWeek: 4),
                TrainingActivityPreference(activity: .strength, role: .supporting, sessionsPerWeek: 2),
            ],
            trainingDaysPerWeek: 6,
            preferredLongRunWeekday: 7,
            unavailableWeekdays: [2],
            strengthEquipment: .dumbbells,
            strengthExperience: .intermediate
        )
    }

    private func onboardingState(step: OnboardingStep) -> OnboardingState {
        OnboardingState(
            id: 17,
            athleteId: 42,
            isCompleted: false,
            currentStep: step.rawValue,
            movementTestCadence: nil,
            movementTestVariance: nil,
            locationPermissionGranted: false,
            coachPersonality: .balanced,
            experienceLevel: .intermediate,
            completedAt: nil,
            createdAt: nil,
            updatedAt: nil
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "OnboardingTrainingProfileTests.\(UUID().uuidString)")!
    }

    private func clear(_ defaults: UserDefaults) {
        defaults.dictionaryRepresentation().keys.forEach(defaults.removeObject(forKey:))
    }

    private enum OnboardingTestError: Error {
        case expected
        case unused
    }

    @MainActor
    private final class DelayedOnboardingPersistence {
        private var stepSaveContinuation: CheckedContinuation<Void, Never>?
        private(set) var stepSaveStarted = false
        private(set) var persistedAnswers: OnboardingAnswers?
        private(set) var persistedStep: Int?
        private(set) var events: [String] = []

        func saveDraft(_ answers: OnboardingAnswers, athleteId _: Int) {
            persistedAnswers = answers
            events.append("draft")
        }

        func saveStep(stateId _: Int, step: Int) async throws {
            stepSaveStarted = true
            await withCheckedContinuation { continuation in
                stepSaveContinuation = continuation
            }
            persistedStep = step
            events.append("step:\(step)")
        }

        func waitUntilStepSaveStarts() async {
            while !stepSaveStarted {
                await Task.yield()
            }
        }

        func resumeStepSave() {
            stepSaveContinuation?.resume()
            stepSaveContinuation = nil
        }

        func resetEvents() {
            events = []
        }
    }
}

final class PasswordRecoveryFlowTests: XCTestCase {
    func testPendingRecoveryRequestClassifiesPKCECodeCallback() throws {
        let url = try XCTUnwrap(URL(string: "runaway://auth/callback?code=secret"))

        XCTAssertTrue(PasswordRecoveryLink.shouldPresentReset(for: url, hasPendingRequest: true))
        XCTAssertFalse(PasswordRecoveryLink.shouldPresentReset(for: url, hasPendingRequest: false))
    }

    func testRecoveryRequestExpiresAfterOneHour() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertTrue(
            PasswordRecoveryRequest.isRecent(
                requestedAt: now.addingTimeInterval(-(60 * 60)),
                now: now
            )
        )
        XCTAssertFalse(
            PasswordRecoveryRequest.isRecent(
                requestedAt: now.addingTimeInterval(-(60 * 60 + 1)),
                now: now
            )
        )
    }

    func testRecoveryCallbackIsDetectedInFragment() throws {
        let url = try XCTUnwrap(URL(string: "runaway://auth/callback#access_token=secret&type=recovery"))

        XCTAssertTrue(PasswordRecoveryLink.isRecoveryCallback(url))
    }

    func testRecoveryCallbackIsDetectedInQuery() throws {
        let url = try XCTUnwrap(URL(string: "runaway://auth/callback?code=secret&type=recovery"))

        XCTAssertTrue(PasswordRecoveryLink.isRecoveryCallback(url))
    }

    func testVerificationCallbackDoesNotPresentPasswordReset() throws {
        let url = try XCTUnwrap(URL(string: "runaway://auth/callback#access_token=secret&type=signup"))

        XCTAssertFalse(PasswordRecoveryLink.isRecoveryCallback(url))
    }
}

@MainActor
private final class ActivitySyncRepositorySpy: ActivitySyncLocalRepository {
    private let activity: Activity
    private var applyFailuresRemaining: Int
    private(set) var lookedUpIDs: [Int] = []
    private(set) var appliedServerIDs: [Int] = []
    private(set) var requestedLocalRecordIDs: [UUID] = []
    private(set) var reconciledLocalRecordIDs: [UUID] = []

    init(activity: Activity, applyFailuresRemaining: Int = 0) {
        self.activity = activity
        self.applyFailuresRemaining = applyFailuresRemaining
    }

    func activity(forNumericID id: Int) async throws -> Activity {
        lookedUpIDs.append(id)
        return activity
    }

    func activity(forLocalRecordID id: UUID) throws -> Activity {
        requestedLocalRecordIDs.append(id)
        return activity
    }

    func reconcileCreateAcknowledgement(
        _ activity: Activity,
        localRecordID: UUID?,
        provisionalNumericID: Int
    ) throws {
        if applyFailuresRemaining > 0 {
            applyFailuresRemaining -= 1
            throw TestError.simulated
        }
        if let localRecordID {
            reconciledLocalRecordIDs.append(localRecordID)
        }
        appliedServerIDs.append(activity.id)
    }
}

private enum TestError: Error {
    case simulated
}
