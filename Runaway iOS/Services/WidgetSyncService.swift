//
//  WidgetSyncService.swift
//  Runaway iOS
//
//  Created by Claude on 12/23/25.
//

import Foundation
import WidgetKit
import UIKit

// MARK: - Widget Sync Service

@MainActor
final class WidgetSyncService {

    // MARK: - Constants

    private static let debounceInterval: TimeInterval = 0.5

    // MARK: - Private Properties

    private var updateTask: Task<Void, Never>?
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Singleton

    static let shared = WidgetSyncService()

    private init() {}

    // MARK: - Public Methods

    func updateProgressSnapshot(_ snapshot: TrainingProgressSnapshot) {
        guard let defaults = UserDefaults(suiteName: AppConstants.AppGroup.identifier),
              defaults.integer(forKey: TrainingProgressSnapshot.athleteKey) == snapshot.athleteID,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: TrainingProgressSnapshot.cacheKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "RunawayWidget")
    }

    func updateCoachDecision(
        _ decision: CoachDecision,
        originalActiveWorkoutID: String,
        proposedActiveWorkoutID: String?
    ) {
        guard let defaults = UserDefaults(suiteName: AppConstants.AppGroup.identifier),
              defaults.integer(forKey: TrainingProgressSnapshot.athleteKey) == decision.athleteID else { return }
        let snapshot = CoachWidgetSnapshot.make(
            decision: decision,
            originalActiveWorkoutID: originalActiveWorkoutID,
            proposedActiveWorkoutID: proposedActiveWorkoutID,
            now: Date()
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: CoachWidgetSnapshot.cacheKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "RunawayWidget")
    }

    func updateBecomingData(
        snapshot: BecomingSnapshot,
        workout: DailyWorkout?,
        readinessScore: Int?,
        weatherTitle: String?,
        weatherDetail: String?
    ) {
        guard let defaults = UserDefaults(suiteName: AppConstants.AppGroup.identifier) else { return }
        defaults.set(snapshot.headline, forKey: "becoming_headline")
        defaults.set(snapshot.detail, forKey: "becoming_detail")
        defaults.set(workout?.title ?? "Today's training", forKey: "becoming_workout")
        let pace = workout?.workoutType.isRunning == true ? workout?.targetPace : nil
        let dose = [workout?.formattedDuration, workout?.formattedDistance, pace]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        defaults.set(dose.isEmpty ? "Ready when you are" : dose, forKey: "becoming_workout_detail")
        if let workout {
            let prescription = WidgetPrescriptionSnapshot(
                title: workout.title,
                detail: dose.isEmpty ? workout.workoutType.displayName : dose,
                status: .resolve(
                    isCompleted: workout.isCompleted,
                    isPartial: workout.acceptedCompletion?.isPartial == true
                )
            )
            if let data = try? JSONEncoder().encode(prescription) {
                defaults.set(data, forKey: WidgetPrescriptionSnapshot.cacheKey)
            }
        } else {
            defaults.removeObject(forKey: WidgetPrescriptionSnapshot.cacheKey)
        }
        defaults.set(String(describing: snapshot.recommendedChoice), forKey: "becoming_recommended_choice")
        defaults.set(UnitPreferences.shared.distanceUnit.rawValue, forKey: "preferred_activity_distance_unit")
        defaults.set(Date().timeIntervalSince1970, forKey: "becoming_updated_at")
        if let readinessScore { defaults.set(readinessScore, forKey: "becoming_readiness") }
        else { defaults.removeObject(forKey: "becoming_readiness") }
        if let weatherTitle { defaults.set(weatherTitle, forKey: "becoming_weather_title") }
        else { defaults.removeObject(forKey: "becoming_weather_title") }
        if let weatherDetail { defaults.set(weatherDetail, forKey: "becoming_weather_detail") }
        else { defaults.removeObject(forKey: "becoming_weather_detail") }
        for path in snapshot.paths {
            let choice = String(describing: path.choice)
            defaults.set(path.title, forKey: "becoming_path_\(choice)_title")
            defaults.set(path.effect, forKey: "becoming_path_\(choice)_effect")
            defaults.set(path.weekEffect, forKey: "becoming_path_\(choice)_week")
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "RunawayWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "CommitmentWidget")
    }

    /// Update training phase and race goal for widgets
    func updateTrainingPhaseData(context: TrainingPhaseContext, goal: RunningGoal?) {
        guard let userDefaults = UserDefaults(suiteName: AppConstants.AppGroup.identifier) else {
            return
        }

        userDefaults.set(context.phase.displayName, forKey: AppConstants.WidgetKeys.currentPhase)
        userDefaults.set(context.phase.icon, forKey: AppConstants.WidgetKeys.currentPhaseIcon)
        userDefaults.set(context.twinMessage, forKey: AppConstants.WidgetKeys.twinMessage)
        userDefaults.set(context.volumeChange, forKey: AppConstants.WidgetKeys.volumeChange)

        if let daysOut = context.daysUntilRace {
            userDefaults.set(daysOut, forKey: AppConstants.WidgetKeys.daysUntilRace)
        } else {
            userDefaults.removeObject(forKey: AppConstants.WidgetKeys.daysUntilRace)
        }

        if let goal = goal {
            userDefaults.set(goal.title, forKey: AppConstants.WidgetKeys.nextRaceName)
        } else {
            userDefaults.removeObject(forKey: AppConstants.WidgetKeys.nextRaceName)
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Update widget data with debouncing (uses client-side calculation for weekly data)
    func updateWidgetData(with activities: [Activity]) {
        // Cancel any pending update
        updateTask?.cancel()

        // Debounce widget updates
        updateTask = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.debounceInterval * 1_000_000_000))

            guard !Task.isCancelled else { return }

            await self?.performWidgetUpdate(with: activities)
        }
    }

    /// Update widget data using database aggregation for yearly/monthly stats
    /// This method fetches accurate totals from the database, not affected by pagination
    func updateWidgetDataFromDatabase(athleteId: Int, activities: [Activity]) {
        // Don't cancel if already running - let it complete
        guard updateTask == nil else {
            return
        }

        updateTask = Task { [weak self] in
            defer { Task { @MainActor in self?.updateTask = nil } }

            try? await Task.sleep(nanoseconds: UInt64(Self.debounceInterval * 1_000_000_000))

            guard !Task.isCancelled else { return }

            await self?.performDatabaseWidgetUpdate(athleteId: athleteId, activities: activities)
        }
    }

    /// Force immediate widget update
    func forceUpdate(with activities: [Activity]) {
        updateTask?.cancel()

        Task.detached(priority: .utility) { [weak self] in
            await self?.performWidgetUpdate(with: activities)
        }
    }

    /// Force immediate widget update using database stats
    func forceUpdateFromDatabase(athleteId: Int, activities: [Activity]) {
        updateTask?.cancel()
        updateTask = nil

        Task { [weak self] in
            await self?.performDatabaseWidgetUpdate(athleteId: athleteId, activities: activities)
        }
    }

    /// Trigger widget timeline reload
    func reloadWidgetTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Semantic Refresh Methods (replaces WidgetRefreshService)

    nonisolated static func refreshForActivityUpdate() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    nonisolated static func refreshForGoalUpdate() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    nonisolated static func refreshForAuthUpdate() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    nonisolated static func refreshForUserUpdate() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    nonisolated static func refreshForLocationUpdate() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Private Methods

    private func performWidgetUpdate(with activities: [Activity]) async {
        await Task.detached(priority: .utility) { [activities] in
            guard let userDefaults = UserDefaults(suiteName: AppConstants.AppGroup.identifier) else {
                return
            }

            autoreleasepool {
                AppConstants.WidgetKeys.allDayKeys.forEach { userDefaults.removeObject(forKey: $0) }

                let filtered = Self.filterActivities(activities)
                Self.storeAggregateStats(filtered, to: userDefaults)
                Self.storeWeeklyActivities(filtered.widgetActivities, to: userDefaults)
            }

            await MainActor.run {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }.value
    }

    // MARK: - Database-Based Widget Update

    private func performDatabaseWidgetUpdate(athleteId: Int, activities: [Activity]) async {
        let yearlyStats: ActivityService.YearlyRunningStats
        let monthlyStats: ActivityService.MonthlyRunningStats

        do {
            yearlyStats = try await ActivityService.getYearlyRunningStats(athleteId: athleteId)
            monthlyStats = try await ActivityService.getMonthlyRunningStats(athleteId: athleteId)
        } catch {
            // Fall back to client-side calculation
            await performWidgetUpdate(with: activities)
            return
        }

        await Task.detached(priority: .utility) { [activities, yearlyStats, monthlyStats] in
            guard let userDefaults = UserDefaults(suiteName: AppConstants.AppGroup.identifier) else {
                return
            }

            autoreleasepool {
                AppConstants.WidgetKeys.allDayKeys.forEach { userDefaults.removeObject(forKey: $0) }

                // Store database-fetched totals (accurate regardless of pagination)
                userDefaults.set(yearlyStats.total_distance_miles, forKey: AppConstants.WidgetKeys.yearlyMiles)
                userDefaults.set(monthlyStats.total_distance_miles, forKey: AppConstants.WidgetKeys.monthlyMiles)
                userDefaults.set(yearlyStats.total_runs, forKey: AppConstants.WidgetKeys.totalRuns)
                userDefaults.set(Calendar.current.component(.year, from: Date()), forKey: "widget_progress_year")
                userDefaults.set(Calendar.current.component(.month, from: Date()), forKey: "widget_progress_month")

                // Process weekly activities (current week only, not affected by pagination)
                let weekStartDate = Date().startOfWeek()
                let weeklyActivities = activities.filter { activity in
                    guard let dateInterval = activity.activity_date ?? activity.start_date else { return false }
                    let normalizedType = (activity.type ?? "").lowercased()
                    return dateInterval > weekStartDate && AppConstants.ActivityTypes.widgetRelevant.contains(normalizedType)
                }
                Self.storeWeeklyActivities(weeklyActivities, to: userDefaults)
            }

            await MainActor.run {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }.value
    }

    // MARK: - Filtering

    private struct FilteredActivities {
        var widgetActivities: [Activity] = []
        var yearlyRunning: [Activity] = []
        var monthlyRunning: [Activity] = []
    }

    nonisolated private static func filterActivities(_ activities: [Activity]) -> FilteredActivities {
        let currentYear = Calendar.current.component(.year, from: Date())
        let currentMonth = Calendar.current.component(.month, from: Date())
        let weekStartDate = Date().startOfWeek()

        return activities.reduce(into: FilteredActivities()) { result, activity in
            let normalizedType = (activity.type ?? "").lowercased()

            let dateInterval = activity.activity_date ?? activity.start_date
            let activityDate = dateInterval.map { Date(timeIntervalSince1970: $0) }
            let activityYear = activityDate.map { Calendar.current.component(.year, from: $0) }
            let activityMonth = activityDate.map { Calendar.current.component(.month, from: $0) }

            if AppConstants.ActivityTypes.widgetRelevant.contains(normalizedType) {
                if let dateInterval, dateInterval > weekStartDate {
                    result.widgetActivities.append(activity)
                }
            }

            if normalizedType.contains("run") && activityYear == currentYear {
                result.yearlyRunning.append(activity)
                if activityMonth == currentMonth {
                    result.monthlyRunning.append(activity)
                }
            }
        }
    }

    // MARK: - Storage Helpers

    nonisolated private static func storeAggregateStats(_ filtered: FilteredActivities, to userDefaults: UserDefaults) {
        let yearlyMiles = filtered.yearlyRunning.reduce(0) { $0 + ($1.distance ?? 0.0) } * AppConstants.Conversion.metersToMiles
        let monthlyMiles = filtered.monthlyRunning.reduce(0) { $0 + ($1.distance ?? 0.0) } * AppConstants.Conversion.metersToMiles
        let totalRuns = filtered.yearlyRunning.count

        userDefaults.set(yearlyMiles, forKey: AppConstants.WidgetKeys.yearlyMiles)
        userDefaults.set(monthlyMiles, forKey: AppConstants.WidgetKeys.monthlyMiles)
        userDefaults.set(totalRuns, forKey: AppConstants.WidgetKeys.totalRuns)
        userDefaults.set(Calendar.current.component(.year, from: Date()), forKey: "widget_progress_year")
        userDefaults.set(Calendar.current.component(.month, from: Date()), forKey: "widget_progress_month")
    }

    nonisolated private static func storeWeeklyActivities(_ activities: [Activity], to userDefaults: UserDefaults) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekStart = calendar.date(byAdding: .day, value: 1 - calendar.component(.weekday, from: today), to: today) ?? today
        userDefaults.set(weekStart.timeIntervalSince1970, forKey: "widget_progress_week_start")
        var weeklyArrays: [String: [String]] = [
            "Sunday": [], "Monday": [], "Tuesday": [],
            "Wednesday": [], "Thursday": [], "Friday": [], "Saturday": []
        ]

        let encoder = JSONEncoder()

        for activity in activities {
            guard let dateInterval = activity.activity_date ?? activity.start_date,
                  let elapsedTime = activity.elapsed_time else {
                continue
            }

            let dayOfWeek = Date(timeIntervalSince1970: dateInterval).dayOfTheWeek
            let displayType = AppConstants.ActivityTypes.normalize(activity.type ?? "Run")

            let raActivity = RAActivity(
                day: String(dayOfWeek.prefix(2)),
                type: displayType,
                distance: (activity.distance ?? 0) * AppConstants.Conversion.metersToMiles,
                time: elapsedTime * AppConstants.Conversion.secondsToMinutes
            )

            do {
                let jsonData = try encoder.encode(raActivity)
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    weeklyArrays[dayOfWeek]?.append(jsonString)
                }
            } catch {
                #if DEBUG
                print("❌ WidgetSyncService: Failed to encode activity: \(error)")
                #endif
            }
        }

        for (dayName, key) in AppConstants.WidgetKeys.dayKeys {
            userDefaults.set(weeklyArrays[dayName], forKey: key)
        }
    }

    // MARK: - Background Task Management

    func startBackgroundTask() {
        backgroundTaskId = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }

    func endBackgroundTask() {
        if backgroundTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
            backgroundTaskId = .invalid
        }
    }
}

extension CoachWidgetSnapshot {
    static func make(
        decision: CoachDecision,
        originalActiveWorkoutID: String,
        proposedActiveWorkoutID: String?,
        now: Date
    ) -> Self {
        let state = CoachWidgetDecisionState(rawValue: decision.state.rawValue) ?? .blocked
        let isApplied = decision.state == .applied
        let reason = decision.reasonCodes.first.map { reason in
            switch reason {
            case .workoutImported: return "New workout imported"
            case .workoutMissed: return "A session was missed"
            case .completionChanged: return "Completion was updated"
            case .recoveryDeclined: return "Recovery declined"
            case .recoveryImproved: return "Recovery improved"
            case .weatherChanged: return "Conditions changed"
            case .availabilityChanged: return "Availability changed"
            case .athleteRequested: return "You requested a change"
            case .unsafeChange: return "The change was not safe"
            case .stalePlan: return "The plan changed"
            }
        } ?? "Training context changed"
        return Self(
            athleteID: decision.athleteID,
            decisionID: decision.id,
            state: state,
            headline: decision.state == .proposed ? "Review change" : isApplied ? "Week updated" : "Coach decision",
            shortReason: reason,
            updatedAt: now,
            undoAvailable: isApplied,
            activeWorkoutID: isApplied ? (proposedActiveWorkoutID ?? originalActiveWorkoutID) : originalActiveWorkoutID
        )
    }
}
