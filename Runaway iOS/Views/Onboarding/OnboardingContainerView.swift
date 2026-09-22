//
//  OnboardingContainerView.swift
//  Runaway iOS
//
//  Created by Claude on 1/12/26.
//

import SwiftUI

@MainActor
struct OnboardingPersistenceClient {
    let loadDraft: @MainActor (Int) async throws -> OnboardingAnswers?
    let saveDraft: @MainActor (OnboardingAnswers, Int) throws -> Void
    let saveStep: @MainActor (Int, Int) async throws -> Void
    let clearDraft: @MainActor (Int) throws -> Void

    init(
        loadDraft: @escaping @MainActor (Int) async throws -> OnboardingAnswers?,
        saveDraft: @escaping @MainActor (OnboardingAnswers, Int) throws -> Void,
        saveStep: @escaping @MainActor (Int, Int) async throws -> Void,
        clearDraft: @escaping @MainActor (Int) throws -> Void = { _ in }
    ) {
        self.loadDraft = loadDraft
        self.saveDraft = saveDraft
        self.saveStep = saveStep
        self.clearDraft = clearDraft
    }

    static func production(defaults: UserDefaults) -> OnboardingPersistenceClient {
        let draftStore = OnboardingTrainingDraftStore(defaults: defaults)
        return OnboardingPersistenceClient(
            loadDraft: { athleteId in try draftStore.load(for: athleteId) },
            saveDraft: { answers, athleteId in try draftStore.save(answers, for: athleteId) },
            saveStep: { stateId, step in
                try await OnboardingService.updateCurrentStep(stateId: stateId, step: step)
            },
            clearDraft: { athleteId in draftStore.clear(for: athleteId) }
        )
    }
}

@MainActor
enum OnboardingCompletionLifecycle {
    static func run<Completion>(
        saveProfile: @MainActor () throws -> Void,
        generatePlan: @MainActor () async throws -> Void,
        complete: @MainActor () async throws -> Completion,
        clearDraft: @MainActor () throws -> Void
    ) async throws -> Completion {
        try saveProfile()
        try await generatePlan()
        let completion = try await complete()
        try clearDraft()
        return completion
    }
}

enum OnboardingLifecyclePresentation {
    static func shouldFlushDraft(for scenePhase: ScenePhase) -> Bool {
        scenePhase == .inactive || scenePhase == .background
    }
}

@MainActor
enum OnboardingInitialPlanGenerator {
    static func generate(
        profile: TrainingProfile,
        manager: DataManager? = nil,
        defaults: UserDefaults = .standard
    ) async throws -> WeeklyTrainingPlan {
        let manager = manager ?? .shared
        return try await generate(
            profile: profile,
            athleteId: manager.athlete?.id,
            manager: manager,
            defaults: defaults
        )
    }

    static func generate(
        profile: TrainingProfile,
        athleteId: Int?,
        manager: DataManager? = nil,
        defaults: UserDefaults = .standard
    ) async throws -> WeeklyTrainingPlan {
        let manager = manager ?? .shared
        guard let athleteId, athleteId > 0 else {
            throw TrainingPlanError.missingAthleteId
        }
        return try await manager.generateTrainingPlan(
            profile: profile,
            scope: .initialCurrentWeek,
            athleteId: athleteId,
            defaults: defaults
        )
    }
}

struct OnboardingStepContainerPresentation: Equatable {
    static let allowsGestureDrivenStepMutation = false
}

@MainActor
private final class OnboardingPersistenceQueue {
    private var tail = Task<Void, Never> {}

    func run(_ operation: @escaping @MainActor () async throws -> Void) async throws {
        let previous = tail
        let operationTask = Task { @MainActor () -> Result<Void, Error> in
            await previous.value
            do {
                try await operation()
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        tail = Task { @MainActor in
            _ = await operationTask.value
        }
        try await operationTask.value.get()
    }

    func waitUntilIdle() async {
        await tail.value
    }
}

// MARK: - Onboarding Container View

struct OnboardingContainerView: View {
    @Environment(UserSession.self) var userSession
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = OnboardingViewModel()

    var body: some View {
        ZStack {
            // Background
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress indicator
                if viewModel.currentStep != .welcome && viewModel.currentStep != .completion {
                    OnboardingProgressBar(
                        currentStep: viewModel.currentStep,
                        totalSteps: OnboardingStep.totalSteps
                    )
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                // Step content
                Group {
                    switch viewModel.currentStep {
                    case .welcome:
                    OnboardingWelcomeView(onContinue: viewModel.nextStep)
                    case .profileSetup:
                    OnboardingProfileSetupView(
                        firstName: $viewModel.firstName,
                        lastName: $viewModel.lastName,
                        onContinue: viewModel.nextStep
                    )
                    case .goalsSetup:
                    OnboardingGoalsSetupView(
                        primaryGoal: Binding(
                            get: { viewModel.primaryGoal },
                            set: viewModel.selectPrimaryGoal
                        ),
                        weeklyGoal: $viewModel.weeklyGoal,
                        monthlyGoal: $viewModel.monthlyGoal,
                        isNavigationDisabled: viewModel.isNavigationPending,
                        onContinue: viewModel.nextStep
                    )
                    case .activityMix:
                    OnboardingActivityMixView(
                        model: viewModel.trainingProfileEditor,
                        onBack: viewModel.previousStep,
                        onContinue: viewModel.nextStep,
                        isNavigationDisabled: viewModel.isNavigationPending
                    )
                    case .trainingSchedule:
                    OnboardingTrainingScheduleView(
                        model: viewModel.trainingProfileEditor,
                        onBack: viewModel.previousStep,
                        onContinue: viewModel.nextStep,
                        isNavigationDisabled: viewModel.isNavigationPending
                    )
                    case .experienceAssessment:
                    OnboardingExperienceView(
                        selectedLevel: $viewModel.experienceLevel,
                        onContinue: viewModel.nextStep,
                        onSkip: viewModel.skipStep
                    )
                    case .movementTest:
                    OnboardingMovementTestView(
                        onContinue: viewModel.nextStep,
                        onSkip: viewModel.skipStep,
                        onResult: viewModel.saveMovementResult
                    )
                    case .runnerMindset, .locationPermission:
                    OnboardingLocationView(
                        onContinue: viewModel.nextStep,
                        onSkip: viewModel.skipStep,
                        onPermissionResult: viewModel.saveLocationPermission
                    )
                    case .coachSelection:
                    OnboardingCoachSelectionView(
                        selectedPersonality: $viewModel.coachPersonality,
                        onContinue: viewModel.nextStep
                    )
                    case .completion:
                    OnboardingCompletionView(
                        experienceLevel: viewModel.experienceLevel,
                        coachPersonality: viewModel.coachPersonality,
                        onComplete: completeOnboarding
                    )
                    }
                }
                .animation(.easeInOut, value: viewModel.currentStep)
            }
        }
        .task {
            await viewModel.loadOnboardingState(for: userSession.userId)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if OnboardingLifecyclePresentation.shouldFlushDraft(for: newPhase) {
                viewModel.flushTrainingDraft()
            }
        }
        .alert(
            "Training setup was not saved",
            isPresented: Binding(
                get: { viewModel.trainingPersistenceError != nil },
                set: { if !$0 { viewModel.dismissTrainingPersistenceError() } }
            )
        ) {
            Button("Retry") { viewModel.retryTrainingPersistence(athleteId: userSession.userId) }
            Button("Not Now", role: .cancel) { viewModel.dismissTrainingPersistenceError() }
        } message: {
            Text(viewModel.trainingPersistenceError ?? "Your latest training choices are still unsaved.")
        }
    }

    private func completeOnboarding() {
        Task {
            if await viewModel.completeOnboarding(athleteId: userSession.userId) {
                // Use markOnboardingCompleted to prevent re-checking from database
                userSession.markOnboardingCompleted()
            }
        }
    }
}

// MARK: - Onboarding View Model

@MainActor
class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep = .welcome
    @Published var experienceLevel: ExperienceLevel = .intermediate
    @Published var coachPersonality: CoachPersonality = .balanced
    @Published var movementResult: MovementTestResult?
    @Published var locationPermissionGranted = false
    @Published var isLoading = false
    @Published private(set) var isCompleting = false
    @Published private(set) var isNavigationPending = false
    @Published private(set) var trainingPersistenceError: String?
    @Published private(set) var hasUnsavedTrainingChanges = false
    @Published private(set) var primaryGoal: OnboardingPrimaryGoal = .running

    let trainingProfileEditor: TrainingProfileEditorViewModel

    // Profile setup fields
    @Published var firstName: String = ""
    @Published var lastName: String = ""
    @Published var weeklyGoal: Double = 20.0
    @Published var monthlyGoal: Double = 80.0

    private var onboardingState: OnboardingState?
    private var hasLoadedInitialState = false
    private var athleteId: Int?
    private let trainingProfileStore: TrainingProfileStore
    private let persistence: OnboardingPersistenceClient
    private let persistenceQueue = OnboardingPersistenceQueue()
    private let loadOnboardingStateOperation: @MainActor (Int) async throws -> OnboardingState
    private let generateInitialPlan: @MainActor (TrainingProfile, Int) async throws -> WeeklyTrainingPlan
    private var navigationTask: Task<Void, Never>?
    private var failedNavigationDestination: OnboardingStep?
    private var isRestoringTrainingAnswers = false

    init(
        trainingProfileStore: TrainingProfileStore = .shared,
        draftDefaults: UserDefaults = .standard,
        persistence: OnboardingPersistenceClient? = nil,
        loadOnboardingState: @escaping @MainActor (Int) async throws -> OnboardingState = {
            try await OnboardingService.getOrCreateOnboardingState(athleteId: $0)
        },
        draftDebounceNanoseconds: UInt64 = 250_000_000,
        generateInitialPlan: @escaping @MainActor (TrainingProfile, Int) async throws -> WeeklyTrainingPlan = { profile, athleteId in
            try await OnboardingInitialPlanGenerator.generate(
                profile: profile,
                athleteId: athleteId
            )
        }
    ) {
        self.trainingProfileStore = trainingProfileStore
        self.trainingProfileEditor = TrainingProfileEditorViewModel(store: trainingProfileStore)
        self.persistence = persistence ?? .production(defaults: draftDefaults)
        self.loadOnboardingStateOperation = loadOnboardingState
        _ = draftDebounceNanoseconds
        self.generateInitialPlan = generateInitialPlan
        self.trainingProfileEditor.draft = OnboardingAnswers.default(for: .running).draft
        self.trainingProfileEditor.onDraftChangeAcknowledged = { [weak self] draft in
            self?.persistTrainingDraft(draft)
        }
    }

    var onboardingAnswers: OnboardingAnswers {
        OnboardingAnswers(primaryGoal: primaryGoal, draft: trainingProfileEditor.draft)
    }

    // MARK: - Load State

    func loadOnboardingState(for userId: Int?) async {
        // Only load once - prevent re-loading from overwriting local navigation state
        guard !hasLoadedInitialState else { return }
        guard let userId = userId else { return }

        self.athleteId = userId
        isLoading = true
        defer { isLoading = false }

        do {
            let state = try await loadOnboardingStateOperation(userId)
            self.onboardingState = state
            self.hasLoadedInitialState = true

            isRestoringTrainingAnswers = true
            defer { isRestoringTrainingAnswers = false }
            let savedAnswers = try await persistence.loadDraft(userId)
            if let savedAnswers {
                primaryGoal = savedAnswers.primaryGoal
                trainingProfileEditor.draft = savedAnswers.draft
            } else {
                let answers = OnboardingAnswers.default(for: primaryGoal)
                trainingProfileEditor.draft = answers.draft
            }
            if let step = OnboardingStep.resumeStep(
                persistedRawValue: state.currentStep,
                trainingDraftFlowVersion: savedAnswers?.flowVersion
            ) {
                currentStep = step
            }
            coachPersonality = state.coachPersonality
            if let level = state.experienceLevel {
                experienceLevel = level
            }
            locationPermissionGranted = state.locationPermissionGranted

            // Load existing goal settings
            let goalStore = GoalSettingsStore.shared
            weeklyGoal = goalStore.weeklyGoal
            monthlyGoal = goalStore.monthlyGoal
        } catch {
            #if DEBUG
            print("❌ OnboardingViewModel: Failed to load state: \(error)")
            #endif
            // Mark as loaded even on error to prevent infinite retry
            self.hasLoadedInitialState = true
        }
    }

    // MARK: - Navigation

    func nextStep() {
        guard let next = currentStep.next else { return }
        navigate(to: next)
    }

    func previousStep() {
        guard let previous = currentStep.previous else { return }
        navigate(to: previous)
    }

    func skipStep() {
        nextStep()
    }

    // MARK: - Save Methods

    func selectPrimaryGoal(_ goal: OnboardingPrimaryGoal) {
        guard primaryGoal != goal else { return }
        primaryGoal = goal
        let normalizedDraft = OnboardingService.normalizingPrimaryGoal(
            goal,
            in: trainingProfileEditor.draft
        )
        trainingProfileEditor.draft = normalizedDraft
        persistTrainingDraft(normalizedDraft, force: true)
    }

    func saveExperienceLevel() {
        guard let stateId = onboardingState?.id else { return }

        Task {
            try? await OnboardingService.updateExperienceLevel(stateId: stateId, level: experienceLevel)
        }
    }

    func saveMovementResult(_ result: MovementTestResult) {
        movementResult = result

        guard let stateId = onboardingState?.id else { return }

        Task {
            try? await OnboardingService.updateMovementTestResults(
                stateId: stateId,
                cadence: result.averageCadence,
                variance: result.variance
            )
        }
    }

    func saveLocationPermission(_ granted: Bool) {
        locationPermissionGranted = granted

        guard let stateId = onboardingState?.id else { return }

        Task {
            try? await OnboardingService.updateLocationPermission(stateId: stateId, granted: granted)
        }
    }

    func saveCoachPersonality() {
        guard let stateId = onboardingState?.id else { return }

        Task {
            try? await OnboardingService.updateCoachPersonality(stateId: stateId, personality: coachPersonality)
        }
    }

    func completeOnboarding(athleteId authenticatedAthleteId: Int? = nil) async -> Bool {
        guard let stateId = onboardingState?.id, !isCompleting else { return false }
        let planAthleteId = authenticatedAthleteId ?? athleteId
        isCompleting = true
        defer { isCompleting = false }
        trainingPersistenceError = nil

        do {
            let profile = OnboardingService.makeTrainingProfile(from: onboardingAnswers)
            let completedState = try await OnboardingCompletionLifecycle.run(
                saveProfile: {
                    try self.trainingProfileStore.save(profile)
                },
                generatePlan: {
                    guard let planAthleteId, planAthleteId > 0 else {
                        throw TrainingPlanError.missingAthleteId
                    }
                    _ = try await self.generateInitialPlan(
                        self.trainingProfileStore.profile,
                        planAthleteId
                    )
                },
                complete: {
                    self.saveExperienceLevel()
                    self.saveCoachPersonality()
                    await self.saveProfileData()
                    self.saveGoals()
                    return try await OnboardingService.completeOnboarding(stateId: stateId)
                },
                clearDraft: {
                    guard let planAthleteId, planAthleteId > 0 else {
                        throw TrainingPlanError.missingAthleteId
                    }
                    try self.persistence.clearDraft(planAthleteId)
                }
            )
            self.onboardingState = completedState
            #if DEBUG
            print("✅ OnboardingViewModel: Onboarding completed!")
            #endif
            return true
        } catch {
            trainingPersistenceError = error.localizedDescription
            #if DEBUG
            print("❌ OnboardingViewModel: Failed to complete onboarding: \(error)")
            #endif
            return false
        }
    }

    func retryTrainingPersistence(athleteId: Int? = nil) {
        trainingPersistenceError = nil
        if currentStep == .completion {
            Task { _ = await completeOnboarding(athleteId: athleteId) }
            return
        }
        if let destination = failedNavigationDestination {
            failedNavigationDestination = nil
            navigate(to: destination)
        } else {
            flushTrainingDraft()
        }
    }

    func dismissTrainingPersistenceError() {
        trainingPersistenceError = nil
    }

    func waitForPendingTrainingPersistence() async {
        await persistenceQueue.waitUntilIdle()
    }

    func flushTrainingDraft() {
        persistTrainingDraft(trainingProfileEditor.draft, force: true)
    }

    func waitForPendingNavigation() async {
        await navigationTask?.value
    }

    private func navigate(to destination: OnboardingStep) {
        guard !isNavigationPending else { return }
        guard let athleteId, let stateId = onboardingState?.id else {
            trainingPersistenceError = "Onboarding progress is not ready to save. Please retry."
            hasUnsavedTrainingChanges = true
            return
        }

        let answers = onboardingAnswers
        isNavigationPending = true
        hasUnsavedTrainingChanges = true
        trainingPersistenceError = nil

        navigationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await persistenceQueue.run {
                    try self.persistence.saveDraft(answers, athleteId)
                    try await self.persistence.saveStep(stateId, destination.rawValue)
                }
                self.currentStep = destination
                self.failedNavigationDestination = nil
                if self.onboardingAnswers == answers {
                    self.hasUnsavedTrainingChanges = false
                }
            } catch {
                self.failedNavigationDestination = destination
                self.trainingPersistenceError = "Your training choices and onboarding progress were not saved. \(error.localizedDescription)"
                self.hasUnsavedTrainingChanges = true
            }
            self.isNavigationPending = false
        }
    }

    private func persistTrainingDraft(_ draft: TrainingProfile, force: Bool = false) {
        guard !isRestoringTrainingAnswers,
              force || currentStep == .activityMix || currentStep == .trainingSchedule,
              athleteId != nil else { return }

        hasUnsavedTrainingChanges = true
        let answers = OnboardingAnswers(primaryGoal: primaryGoal, draft: draft)
        guard let athleteId else { return }
        do {
            try persistence.saveDraft(answers, athleteId)
            if onboardingAnswers == answers {
                hasUnsavedTrainingChanges = false
                trainingPersistenceError = nil
            }
        } catch {
            trainingPersistenceError = "Your latest training choices were not saved. \(error.localizedDescription)"
            hasUnsavedTrainingChanges = true
        }
    }

    // MARK: - Profile Data Saving

    private func saveProfileData() async {
        guard let athleteId = athleteId else {
            #if DEBUG
            print("⚠️ OnboardingViewModel: No athlete ID, skipping profile save")
            #endif
            return
        }

        do {
            try await AthleteService.shared.updateAthlete(
                athleteId: athleteId,
                firstname: firstName.trimmingCharacters(in: .whitespaces),
                lastname: lastName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : lastName.trimmingCharacters(in: .whitespaces),
                profileURL: nil
            )
            #if DEBUG
            print("✅ OnboardingViewModel: Profile data saved")
            #endif
        } catch {
            #if DEBUG
            print("❌ OnboardingViewModel: Failed to save profile data: \(error)")
            #endif
        }
    }

    private func saveGoals() {
        let goalStore = GoalSettingsStore.shared
        goalStore.weeklyGoal = weeklyGoal
        goalStore.monthlyGoal = monthlyGoal
        #if DEBUG
        print("✅ OnboardingViewModel: Goals saved - Weekly: \(weeklyGoal)mi, Monthly: \(monthlyGoal)mi")
        #endif
    }
}

// MARK: - Progress Bar

struct OnboardingProgressBar: View {
    let currentStep: OnboardingStep
    let totalSteps: Int

    private var progress: Double {
        return Double(currentStep.flowIndex) / Double(totalSteps - 1)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 4)

                // Progress
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * progress, height: 4)
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Preview

#Preview {
    OnboardingContainerView()
        .environment(UserSession.shared)
}
