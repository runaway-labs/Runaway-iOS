//
//  DataManager.swift
//  Runaway iOS
//
//  Created by Jack Rudelic on 9/14/25.
//  Refactored to coordinate focused stores on 12/23/25.
//

import Foundation
import SwiftUI
import WidgetKit
import Observation

// MARK: - Centralized Data Manager
// Acts as a facade/coordinator for focused stores while maintaining backward compatibility

@MainActor
@Observable
class DataManager {

    // MARK: - Focused Stores

    private let activityStore: ActivityStore
    private let athleteStore: AthleteStore
    private let commitmentManager: CommitmentManager
    private let goalManager: GoalManager
    private let widgetSyncService: WidgetSyncService

    // MARK: - Observable Properties (Forwarded from stores)

    var activities: [Activity] = [] {
        didSet {
            guard activities != oldValue, let id = UserSession.shared.userId else { return }
            Task { await TrainingProgressStore.shared.refresh(athleteID: id, force: true) }
        }
    }
    var athlete: Athlete?
    var stats: AthleteStats?
    var currentGoal: RunningGoal?
    var todaysCommitment: DailyCommitment?
    var currentWeeklyPlan: WeeklyTrainingPlan?
    var pendingNextWeekPlan: WeeklyTrainingPlan?
    var isLoadingActivities = false
    var isLoadingAthlete = false
    var isLoadingCommitment = false
    var isRegeneratingPlan = false
    var lastDataRefresh: Date?
    private var trainingPlanGenerationToken: UInt64 = 0
    private var trainingPlanGenerationFingerprint: String?

    // MARK: - Singleton

    static let shared = DataManager()

    // MARK: - Initialization

    private init(
        activityStore: ActivityStore? = nil,
        athleteStore: AthleteStore? = nil,
        commitmentManager: CommitmentManager? = nil,
        goalManager: GoalManager? = nil,
        widgetSyncService: WidgetSyncService? = nil
    ) {
        self.activityStore = activityStore ?? .shared
        self.athleteStore = athleteStore ?? .shared
        self.commitmentManager = commitmentManager ?? .shared
        self.goalManager = goalManager ?? .shared
        self.widgetSyncService = widgetSyncService ?? .shared

        setupStoreBindings()
    }

    // MARK: - Store Bindings

    private func setupStoreBindings() {
        // Bind ActivityStore changes
        activityStore.onActivitiesChanged = { [weak self] activities in
            Task { @MainActor in
                self?.activities = activities
                // Use database-based widget update for accurate yearly/monthly stats
                self?.updateWidgetData()
            }
        }

        activityStore.onNewActivityAdded = { [weak self] activity in
            Task { @MainActor in
                await self?.handleNewActivity(activity)
            }
        }
    }

    private func handleNewActivity(_ activity: Activity) async {
        // Check if from today before checking commitment
        let today = Calendar.current.startOfDay(for: Date())
        let activityDate = activity.activity_date ?? activity.start_date
        let isFromToday = activityDate.map {
            Calendar.current.isDate(Date(timeIntervalSince1970: $0), inSameDayAs: today)
        } ?? false

        if isFromToday {
            await commitmentManager.checkActivityFulfillsCommitment(activity)
        }
    }

    // MARK: - Data Loading Methods

    func loadAllData(for userId: Int) async {
        TrainingProgressStore.shared.activate(athleteID: userId)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadActivities(for: userId) }
            group.addTask { await self.loadAthlete(for: userId) }
            group.addTask { await self.loadStats(for: userId) }
            group.addTask { await self.loadCurrentGoal(for: userId) }
            group.addTask { await self.loadTodaysCommitment(for: userId) }
        }

        syncFromStores()
        updateWidgetData()
        lastDataRefresh = Date()
        await processPendingCoachEvents(athleteID: userId)
    }

    func loadActivities(for userId: Int) async {
        isLoadingActivities = true
        defer { isLoadingActivities = false }

        widgetSyncService.startBackgroundTask()
        defer { widgetSyncService.endBackgroundTask() }

        await activityStore.loadActivities(for: userId)
        activities = activityStore.activities
        updateWidgetData()
    }

    func loadAthlete(for userId: Int) async {
        isLoadingAthlete = true
        defer { isLoadingAthlete = false }

        await athleteStore.loadAthlete(for: userId)
        athlete = athleteStore.athlete
    }

    func loadStats(for userId: Int) async {
        await athleteStore.loadStats(for: userId)
        stats = athleteStore.stats
    }

    func loadCurrentGoal(for userId: Int) async {
        await goalManager.loadCurrentGoal(for: userId)
        currentGoal = goalManager.currentGoal
    }

    func loadTodaysCommitment(for userId: Int) async {
        isLoadingCommitment = true
        defer { isLoadingCommitment = false }

        _ = await commitmentManager.loadTodaysCommitment(for: userId)
        todaysCommitment = commitmentManager.todaysCommitment
    }

    // MARK: - Data Refresh Methods

    func refreshAllData() async {
        guard let userId = UserSession.shared.userId else {
            #if DEBUG
            print("❌ DataManager: No user ID available for refresh")
            #endif
            return
        }

        await loadAllData(for: userId)
    }

    func refreshActivities() async {
        guard let userId = UserSession.shared.userId else {
            #if DEBUG
            print("❌ DataManager: No user ID available for activities refresh")
            #endif
            return
        }

        #if DEBUG
        print("🔄 DataManager: Refreshing activities...")
        #endif
        await loadActivities(for: userId)
        #if DEBUG
        print("✅ DataManager: Activities refreshed. Total: \(activities.count)")
        #endif

        // Check if plan needs regeneration based on new activities
        await checkAndRegeneratePlanIfNeeded()
    }

    private func processPendingCoachEvents(athleteID: Int) async {
        await loadCurrentWeeklyPlan()
        guard currentWeeklyPlan?.athleteId == athleteID else { return }
        let repository = ProtectedTrainingRepository(activeAthleteID: {
            UserSession.shared.userId
        })
        let ledger = CoachDecisionLedger(repository: repository, athleteID: athleteID)
        let coordinator = CoachCoordinator(ledger: ledger)
        let service = CoachEventService(
            ledger: ledger,
            coordinator: coordinator,
            context: { [weak self] event in
                guard let self, let active = self.currentWeeklyPlan,
                      active.athleteId == athleteID else {
                    throw ProtectedTrainingRepository.RepositoryError.ownershipMismatch
                }
                let candidate: WeeklyTrainingPlan
                if event.kind == .workoutImported {
                    let weekActivities = self.activities.filter { activity in
                        guard let timestamp = activity.activity_date ?? activity.start_date else { return false }
                        return TrainingPlanService.containsActivityDate(
                            Date(timeIntervalSince1970: timestamp), in: active
                        )
                    }
                    candidate = try await TrainingPlanService.regeneratePlanWithActivities(
                        athleteId: athleteID,
                        currentPlan: active,
                        completedActivities: weekActivities,
                        goal: self.currentGoal,
                        profile: self.resolvedTrainingProfile(nil, existingPlan: active)
                    )
                } else {
                    candidate = RemainingWeekTrainingPolicy.candidatePlan(for: event, in: active)
                }
                return CoachContext(
                    athleteID: athleteID,
                    activePlan: active,
                    candidatePlan: candidate,
                    planRevision: try TrainingDecisionInputBuilder.revision(for: active),
                    reasonCodes: Self.reasonCodes(for: event),
                    safetyFlags: [],
                    missingData: []
                )
            },
            activate: { [weak self] plan, expectedRevision in
                guard let self, let current = self.currentWeeklyPlan,
                      try TrainingDecisionInputBuilder.revision(for: current) == expectedRevision else {
                    throw ProtectedTrainingRepository.RepositoryError.staleCoachDecision
                }
                try self.updateCurrentWeeklyPlan(plan)
            }
        )
        do {
            try await service.processPending(athleteID: athleteID)
        } catch {
            #if DEBUG
            print("Coach catch-up preserved pending events: \(error.localizedDescription)")
            #endif
        }
    }

    private static func reasonCodes(for event: CoachEvent) -> [CoachReasonCode] {
        switch event.kind {
        case .workoutImported: [.workoutImported]
        case .sessionResultChanged, .sessionElapsed: [.completionChanged]
        case .readinessChanged: [.recoveryDeclined]
        case .weatherChanged: [.weatherChanged]
        case .availabilityChanged: [.availabilityChanged]
        case .reevaluationRequested, .proposalResponded: [.athleteRequested]
        case .appForegrounded, .scheduledCheckIn, .profileChanged: []
        }
    }

    // MARK: - Adaptive Training Plan

    /// Load the current week's training plan
    func loadCurrentWeeklyPlan(
        profile: TrainingProfile? = nil,
        defaults: UserDefaults = .standard
    ) async {
        defer { if defaults === UserDefaults.standard { try? refreshAcceptedWorkoutCompletions() } }
        let migrationPlan = currentWeeklyPlan
            ?? TrainingPlanService.cachedPlanForProfileMigration(defaults: defaults)
        let normalizedProfile = resolvedTrainingProfile(profile, existingPlan: migrationPlan)

        if let promotedPlan = try? TrainingPlanService.promotePendingNextWeekPlanIfCurrent(
            for: normalizedProfile,
            defaults: defaults
        ) {
            currentWeeklyPlan = promotedPlan
            pendingNextWeekPlan = nil
            return
        }
        pendingNextWeekPlan = TrainingPlanService.pendingNextWeekPlan(
            for: normalizedProfile,
            defaults: defaults
        )

        // Check cache first
        if case let .valid(cachedPlan) = TrainingPlanService.cachedPlanStatus(
            for: normalizedProfile,
            defaults: defaults
        ) {
            currentWeeklyPlan = cachedPlan
            return
        }
    }

    /// Load only an account-owned, current-week plan for prescription review.
    /// This never generates a replacement plan or applies a prescription.
    @discardableResult
    @MainActor
    func loadPlanForPrescriptionAcceptance(
        athleteID: Int,
        profile: TrainingProfile? = nil,
        defaults: UserDefaults = .standard,
        activeAthleteID: @MainActor () -> Int? = {
            UserSession.shared.isReady ? UserSession.shared.userId : nil
        }
    ) async -> Bool {
        guard athleteID > 0, activeAthleteID() == athleteID else { return false }
        if let current = currentWeeklyPlan, current.athleteId == athleteID, current.isCurrentWeek {
            return true
        }
        let migrationPlan = currentWeeklyPlan ?? TrainingPlanService.cachedPlanForProfileMigration(defaults: defaults)
        let normalized = resolvedTrainingProfile(profile, existingPlan: migrationPlan)
        if let pending = TrainingPlanService.pendingNextWeekPlan(for: normalized, defaults: defaults), pending.isCurrentWeek {
            guard pending.athleteId == athleteID else { return false }
        } else {
            guard case let .valid(cached) = TrainingPlanService.cachedPlanStatus(for: normalized, defaults: defaults),
                  cached.athleteId == athleteID else { return false }
        }
        await loadCurrentWeeklyPlan(profile: normalized, defaults: defaults)
        return activeAthleteID() == athleteID && currentWeeklyPlan?.athleteId == athleteID && currentWeeklyPlan?.isCurrentWeek == true
    }

    /// Check if any new activities require plan regeneration and regenerate if needed
    func checkAndRegeneratePlanIfNeeded(profile: TrainingProfile? = nil) async {
        let normalizedProfile = resolvedTrainingProfile(profile)
        guard let plan = currentWeeklyPlan ?? validCachedPlan(for: normalizedProfile, defaults: .standard) else {
            #if DEBUG
            print("📋 DataManager: No current plan to check for regeneration")
            #endif
            return
        }

        guard UserSession.shared.userId != nil else { return }

        // Get activities from this week
        let weekActivities = activities.filter { activity in
            guard let ts = activity.activity_date ?? activity.start_date else { return false }
            let activityDate = Date(timeIntervalSince1970: ts)
            return TrainingPlanService.containsActivityDate(activityDate, in: plan)
        }

        // Check if any activity warrants regeneration
        var needsRegeneration = false
        for activity in weekActivities {
            if TrainingPlanService.shouldRegeneratePlan(currentPlan: plan, newActivity: activity) {
                needsRegeneration = true
                break
            }
        }

        if needsRegeneration {
            #if DEBUG
            print("📋 DataManager: Triggering plan regeneration based on activity differences")
            #endif
            await regenerateWeeklyPlan(
                currentPlan: plan,
                activities: weekActivities,
                profile: normalizedProfile
            )
        }
    }

    /// Regenerate the weekly plan based on completed activities
    func regenerateWeeklyPlan(
        currentPlan: WeeklyTrainingPlan,
        activities: [Activity],
        profile: TrainingProfile? = nil
    ) async {
        guard let userId = UserSession.shared.userId else { return }

        let normalizedProfile = resolvedTrainingProfile(profile)
        let generationToken = beginTrainingPlanGeneration(
            profileFingerprint: normalizedProfile.fingerprint
        )
        isRegeneratingPlan = true
        defer { isRegeneratingPlan = false }

        do {
            let regeneratedPlan = try await TrainingPlanService.regeneratePlanWithActivities(
                athleteId: userId,
                currentPlan: currentPlan,
                completedActivities: activities,
                goal: currentGoal,
                profile: normalizedProfile
            )

            guard isCurrentTrainingPlanGeneration(
                generationToken,
                profileFingerprint: normalizedProfile.fingerprint
            ) else { return }
            _ = try publish(
                regeneratedPlan,
                profile: normalizedProfile,
                scope: .remainingCurrentWeek,
                defaults: .standard
            )

            #if DEBUG
            print("📋 DataManager: Plan regenerated successfully")
            #endif
        } catch {
            #if DEBUG
            print("📋 DataManager: Plan regeneration failed: \(error)")
            #endif
        }
    }

    func generateTrainingPlan(
        profile: TrainingProfile,
        scope: PlanRegenerationScope,
        athleteId: Int? = nil,
        regenerationInput: WeeklyTrainingPlan? = nil,
        defaults: UserDefaults = .standard
    ) async throws -> WeeklyTrainingPlan {
        let normalizedProfile = profile.validated(
            existingPlan: regenerationInput ?? currentWeeklyPlan
        ).profile
        let generationToken = beginTrainingPlanGeneration(
            profileFingerprint: normalizedProfile.fingerprint
        )
        let existingPlan = resolvedRegenerationInput(
            explicit: regenerationInput,
            scope: scope,
            profile: normalizedProfile,
            defaults: defaults
        )
        let generatedPlan = try await TrainingPlanService.generatePlan(
            athleteId: resolvedAthleteID(athleteId, existingPlan: existingPlan),
            profile: normalizedProfile,
            scope: scope,
            existingPlan: existingPlan,
            goal: currentGoal
        )
        guard isCurrentTrainingPlanGeneration(
            generationToken,
            profileFingerprint: normalizedProfile.fingerprint
        ) else { throw CancellationError() }
        return try publish(generatedPlan, profile: normalizedProfile, scope: scope, defaults: defaults)
    }

    func generateTrainingPlan(
        profile: TrainingProfile,
        scope: PlanRegenerationScope,
        regenerationInput: WeeklyTrainingPlan? = nil,
        defaults: UserDefaults = .standard,
        generator: (TrainingProfile, PlanRegenerationScope, WeeklyTrainingPlan?) async throws -> WeeklyTrainingPlan
    ) async throws -> WeeklyTrainingPlan {
        let normalizedProfile = profile.validated(
            existingPlan: regenerationInput ?? currentWeeklyPlan
        ).profile
        let generationToken = beginTrainingPlanGeneration(
            profileFingerprint: normalizedProfile.fingerprint
        )
        let existingPlan = resolvedRegenerationInput(
            explicit: regenerationInput,
            scope: scope,
            profile: normalizedProfile,
            defaults: defaults
        )
        let generatedPlan = try await generator(normalizedProfile, scope, existingPlan)
        guard isCurrentTrainingPlanGeneration(
            generationToken,
            profileFingerprint: normalizedProfile.fingerprint
        ) else { throw CancellationError() }
        return try publish(generatedPlan, profile: normalizedProfile, scope: scope, defaults: defaults)
    }

    /// Force regenerate the plan (user-triggered)
    func forceRegeneratePlan(profile: TrainingProfile? = nil) async {
        let normalizedProfile = resolvedTrainingProfile(profile)
        guard let plan = currentWeeklyPlan ?? validCachedPlan(for: normalizedProfile, defaults: .standard) else { return }

        let weekActivities = activities.filter { activity in
            guard let ts = activity.activity_date ?? activity.start_date else { return false }
            let activityDate = Date(timeIntervalSince1970: ts)
            return TrainingPlanService.containsActivityDate(activityDate, in: plan)
        }

        await regenerateWeeklyPlan(
            currentPlan: plan,
            activities: weekActivities,
            profile: normalizedProfile
        )
    }

    /// Keep all plan surfaces synchronized after a deterministic on-device edit.
    func updateCurrentWeeklyPlan(
        _ plan: WeeklyTrainingPlan,
        profile: TrainingProfile? = nil,
        acceptedReceipt: AcceptedPrescriptionPlanReceipt? = nil
    ) throws {
        let normalizedProfile = resolvedTrainingProfile(profile)
        try TrainingPlanService.cachePlan(plan, profile: normalizedProfile, acceptedReceipt: acceptedReceipt)
        trainingPlanGenerationToken &+= 1
        currentWeeklyPlan = plan
    }

    private func resolvedTrainingProfile(
        _ injected: TrainingProfile?,
        existingPlan: WeeklyTrainingPlan? = nil
    ) -> TrainingProfile {
        let plan = existingPlan ?? currentWeeklyPlan
        if let injected {
            return injected.validated(existingPlan: plan).profile
        }
        TrainingProfileStore.shared.reloadFromPersistence(existingPlan: plan)
        let profile = TrainingProfileStore.shared.profile
        return profile.validated(existingPlan: plan).profile
    }

    private func resolvedRegenerationInput(
        explicit: WeeklyTrainingPlan?,
        scope: PlanRegenerationScope,
        profile: TrainingProfile,
        defaults: UserDefaults
    ) -> WeeklyTrainingPlan? {
        if let explicit { return explicit }
        if let currentWeeklyPlan { return currentWeeklyPlan }

        switch TrainingPlanService.cachedPlanStatus(for: profile, defaults: defaults) {
        case let .valid(plan):
            return plan
        case let .stale(plan) where scope == .remainingCurrentWeek:
            return plan
        case .missing, .stale:
            return nil
        }
    }

    private func validCachedPlan(
        for profile: TrainingProfile,
        defaults: UserDefaults
    ) -> WeeklyTrainingPlan? {
        guard case let .valid(plan) = TrainingPlanService.cachedPlanStatus(
            for: profile,
            defaults: defaults
        ) else { return nil }
        return plan
    }

    private func resolvedAthleteID(
        _ explicitAthleteID: Int?,
        existingPlan: WeeklyTrainingPlan?
    ) -> Int? {
        if let explicitAthleteID { return explicitAthleteID }
        if let existingAthleteID = existingPlan?.athleteId, existingAthleteID > 0 {
            return existingAthleteID
        }
        if let loadedAthleteID = athlete?.id, loadedAthleteID > 0 {
            return loadedAthleteID
        }
        return UserSession.shared.userId
    }

    private func publish(
        _ plan: WeeklyTrainingPlan,
        profile: TrainingProfile,
        scope: PlanRegenerationScope,
        defaults: UserDefaults
    ) throws -> WeeklyTrainingPlan {
        switch scope {
        case .initialCurrentWeek, .remainingCurrentWeek:
            try TrainingPlanService.cachePlan(plan, profile: profile, defaults: defaults)
            currentWeeklyPlan = plan
        case .nextWeek:
            try TrainingPlanService.cachePendingNextWeekPlan(
                plan,
                profile: profile,
                defaults: defaults
            )
            pendingNextWeekPlan = plan
        }
        return plan
    }

    private func beginTrainingPlanGeneration(profileFingerprint: String) -> UInt64 {
        trainingPlanGenerationToken &+= 1
        trainingPlanGenerationFingerprint = profileFingerprint
        return trainingPlanGenerationToken
    }

    private func isCurrentTrainingPlanGeneration(
        _ token: UInt64,
        profileFingerprint: String
    ) -> Bool {
        token == trainingPlanGenerationToken
            && profileFingerprint == trainingPlanGenerationFingerprint
    }

    // MARK: - Data Modification Methods

    func addActivity(_ activity: Activity) {
        activityStore.addActivity(activity)
        activities = activityStore.activities
    }

    func removeActivity(id: Int) {
        activityStore.removeActivity(id: id)
        activities = activityStore.activities
    }

    func updateActivity(_ updatedActivity: Activity) {
        activityStore.updateActivity(updatedActivity)
        activities = activityStore.activities
    }

    // MARK: - Commitment Management

    func createCommitment(_ activityType: CommitmentActivityType) async throws {
        isLoadingCommitment = true
        defer { isLoadingCommitment = false }

        try await commitmentManager.createCommitment(activityType)
        todaysCommitment = commitmentManager.todaysCommitment
    }

    func checkActivityFulfillsCommitment(_ activity: Activity) async {
        await commitmentManager.checkActivityFulfillsCommitment(activity)
        todaysCommitment = commitmentManager.todaysCommitment
    }

    func refreshTodaysCommitment() async {
        await commitmentManager.refresh()
        todaysCommitment = commitmentManager.todaysCommitment
    }

    func updateCommitment(to activityType: CommitmentActivityType) async throws {
        isLoadingCommitment = true
        defer { isLoadingCommitment = false }

        try await commitmentManager.updateCommitment(to: activityType)
        todaysCommitment = commitmentManager.todaysCommitment
    }

    func deleteCommitment() async throws {
        isLoadingCommitment = true
        defer { isLoadingCommitment = false }

        try await commitmentManager.deleteCommitment()
        todaysCommitment = commitmentManager.todaysCommitment
    }

    // MARK: - Widget Data Management

    func updateWidgetData() {
        // Use database-based stats when athlete ID is available (accurate totals)
        if let athleteId = athlete?.id {
            widgetSyncService.updateWidgetDataFromDatabase(athleteId: athleteId, activities: activities)
        } else if let userId = UserSession.shared.userId {
            widgetSyncService.updateWidgetDataFromDatabase(athleteId: userId, activities: activities)
        } else {
            // Fallback to client-side calculation
            widgetSyncService.updateWidgetData(with: activities)
        }
    }

    // MARK: - Sync Helpers

    private func syncFromStores() {
        activities = activityStore.activities
        athlete = athleteStore.athlete
        stats = athleteStore.stats
        currentGoal = goalManager.currentGoal
        todaysCommitment = commitmentManager.todaysCommitment
    }

    // MARK: - Cache Management

    func clearCache() {
        TrainingProgressStore.shared.reset()
        activityStore.clearCache()
        PerformanceCache.shared.clearAll()
    }
}

// MARK: - DataManager + RealtimeService Integration

extension DataManager {

    func handleRealtimeUpdate(activities: [Activity]) {
        activityStore.handleRealtimeUpdate(activities: activities)
        self.activities = activityStore.activities
        lastDataRefresh = Date()
    }

    func forceRefreshWidget(with activities: [Activity]) {
        activityStore.handleRealtimeUpdate(activities: activities)
        self.activities = activityStore.activities
        // Use database-based widget update for accurate yearly/monthly stats
        if let athleteId = athlete?.id {
            widgetSyncService.forceUpdateFromDatabase(athleteId: athleteId, activities: activities)
        } else if let userId = UserSession.shared.userId {
            widgetSyncService.forceUpdateFromDatabase(athleteId: userId, activities: activities)
        } else {
            widgetSyncService.forceUpdate(with: activities)
        }
    }

    // MARK: - Computed Properties

    var daysSinceLastActivity: Int {
        activityStore.daysSinceLastActivity
    }

    var daysSinceLastActivityText: String {
        activityStore.daysSinceLastActivityText
    }
}

// MARK: - DataManager Errors

enum DataManagerError: Error, LocalizedError {
    case noUserId

    var errorDescription: String? {
        switch self {
        case .noUserId:
            return "No user ID available"
        }
    }
}
