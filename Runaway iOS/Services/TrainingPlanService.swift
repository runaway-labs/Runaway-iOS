//
//  TrainingPlanService.swift
//  Runaway iOS
//
//  Service for generating and managing weekly training plans
//  Includes rest day awareness for adaptive planning
//

import Foundation

enum PlanRegenerationScope: Sendable {
    case initialCurrentWeek
    case nextWeek
    case remainingCurrentWeek
}

enum CachedTrainingPlanStatus {
    case missing
    case valid(WeeklyTrainingPlan)
    case stale(WeeklyTrainingPlan)
}

private struct TrainingPlanCacheEnvelope: Codable {
    static let currentVersion = 1

    let cacheVersion: Int
    let plan: WeeklyTrainingPlan
    let profileFingerprint: String
    let profileSchemaVersion: Int
    let expiresAt: Date
    var acceptedReceipt: AcceptedPrescriptionPlanReceipt? = nil
}

class TrainingPlanService {

    // MARK: - Rest Day Integration

    /// Check if today should be a rest day based on recovery status
    static func shouldTakeRestDay(athleteId: Int) async -> (shouldRest: Bool, reason: String) {
        do {
            let restDayService = await RestDayService.shared
            let recoveryStatus = try await restDayService.calculateRecoveryStatus(athleteId: athleteId)
            let daysSinceRest = try await restDayService.getDaysSinceLastRest(athleteId: athleteId)

            switch recoveryStatus {
            case .overdue:
                return (true, "You haven't had a rest day in \(daysSinceRest) days. Rest is strongly recommended.")
            case .needsRest:
                return (true, "Recovery indicators suggest you need a rest day today.")
            case .adequate:
                if daysSinceRest >= 5 {
                    return (true, "Consider taking a rest day - it's been \(daysSinceRest) days since your last one.")
                }
                return (false, "Recovery is adequate. You can train today, but listen to your body.")
            case .wellRested, .fullyRecovered:
                return (false, "You're well rested and ready to train!")
            }
        } catch {
            #if DEBUG
            print("📋 TrainingPlan: Failed to check rest day status: \(error)")
            #endif
            return (false, "Unable to determine recovery status.")
        }
    }

    /// Get today's recommendation considering rest days
    static func getTodaysRecommendation(
        athleteId: Int,
        currentPlan: WeeklyTrainingPlan?
    ) async -> String {
        let (shouldRest, restReason) = await shouldTakeRestDay(athleteId: athleteId)

        if shouldRest {
            return restReason
        }

        // If not a rest day, check what's planned
        if let plan = currentPlan {
            let today = DayOfWeek.from(date: Date())
            if let workout = plan.workout(for: today) {
                return "Today's planned workout: \(workout.title). \(workout.description)"
            }
        }

        return "No workout planned for today. Consider an easy run or active recovery."
    }

    // MARK: - Cache Keys
    static let cacheKey = "cached_weekly_training_plan"
    static let cacheExpirationKey = "weekly_plan_cache_expiration"
    static let pendingNextWeekCacheKey = "pending_next_week_training_plan"

    // MARK: - Cache Management

    static func latestAcceptedReceipt(for profile: TrainingProfile, athleteID: Int, defaults: UserDefaults = .standard) -> AcceptedPrescriptionPlanReceipt? {
        guard case let .valid(plan) = cachedPlanStatus(for: profile, defaults: defaults),
              plan.athleteId == athleteID,
              let receipt = decodedCacheEnvelope(defaults: defaults)?.acceptedReceipt,
              (try? receipt.restoredPlan(current: plan, athleteID: athleteID)) != nil else { return nil }
        return receipt
    }

    /// Save plan to local cache with expiration at next Sunday midnight
    static func cachePlan(
        _ plan: WeeklyTrainingPlan,
        profile: TrainingProfile,
        defaults: UserDefaults = .standard,
        acceptedReceipt: AcceptedPrescriptionPlanReceipt? = nil
    ) throws {
        let normalizedProfile = profile.validated(existingPlan: plan).profile
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let expiration = nextSundayMidnight()
        let envelope = TrainingPlanCacheEnvelope(
            cacheVersion: TrainingPlanCacheEnvelope.currentVersion,
            plan: plan,
            profileFingerprint: normalizedProfile.fingerprint,
            profileSchemaVersion: normalizedProfile.schemaVersion,
            expiresAt: expiration,
            acceptedReceipt: acceptedReceipt
        )
        let encoded = try encoder.encode(envelope)
        let previousPlan = defaults.data(forKey: cacheKey)
        let previousExpiration = defaults.object(forKey: cacheExpirationKey)

        defaults.set(encoded, forKey: cacheKey)
        defaults.set(expiration.timeIntervalSince1970, forKey: cacheExpirationKey)
        guard defaults.data(forKey: cacheKey) == encoded else {
            if let previousPlan { defaults.set(previousPlan, forKey: cacheKey) }
            else { defaults.removeObject(forKey: cacheKey) }
            if let previousExpiration { defaults.set(previousExpiration, forKey: cacheExpirationKey) }
            else { defaults.removeObject(forKey: cacheExpirationKey) }
            throw TrainingPlanError.cachePersistenceFailed
        }

        #if DEBUG
        print("📋 TrainingPlan: Cached plan, expires \(expiration)")
        #endif
    }

    static func cachePendingNextWeekPlan(
        _ plan: WeeklyTrainingPlan,
        profile: TrainingProfile,
        defaults: UserDefaults = .standard
    ) throws {
        let normalizedProfile = profile.validated(existingPlan: plan).profile
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let expiration = Calendar.current.date(byAdding: .day, value: 1, to: plan.weekEndDate)
            ?? plan.weekEndDate.addingTimeInterval(86_400)
        let envelope = TrainingPlanCacheEnvelope(
            cacheVersion: TrainingPlanCacheEnvelope.currentVersion,
            plan: plan,
            profileFingerprint: normalizedProfile.fingerprint,
            profileSchemaVersion: normalizedProfile.schemaVersion,
            expiresAt: expiration
        )
        let encoded = try encoder.encode(envelope)
        let previousPlan = defaults.data(forKey: pendingNextWeekCacheKey)

        defaults.set(encoded, forKey: pendingNextWeekCacheKey)
        guard defaults.data(forKey: pendingNextWeekCacheKey) == encoded else {
            if let previousPlan { defaults.set(previousPlan, forKey: pendingNextWeekCacheKey) }
            else { defaults.removeObject(forKey: pendingNextWeekCacheKey) }
            throw TrainingPlanError.cachePersistenceFailed
        }
    }

    static func pendingNextWeekPlan(
        for profile: TrainingProfile,
        defaults: UserDefaults = .standard
    ) -> WeeklyTrainingPlan? {
        guard let data = defaults.data(forKey: pendingNextWeekCacheKey) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(TrainingPlanCacheEnvelope.self, from: data) else {
            return nil
        }

        let normalizedProfile = profile.validated(existingPlan: envelope.plan).profile
        let metadataMatches = envelope.cacheVersion == TrainingPlanCacheEnvelope.currentVersion
            && envelope.profileSchemaVersion == normalizedProfile.schemaVersion
            && envelope.profileSchemaVersion == TrainingProfile.currentSchemaVersion
            && envelope.profileFingerprint == normalizedProfile.fingerprint
        return metadataMatches && Date() < envelope.expiresAt ? envelope.plan : nil
    }

    static func promotePendingNextWeekPlanIfCurrent(
        for profile: TrainingProfile,
        defaults: UserDefaults = .standard
    ) throws -> WeeklyTrainingPlan? {
        guard
            let pendingPlan = pendingNextWeekPlan(for: profile, defaults: defaults),
            Calendar.current.isDate(pendingPlan.weekStartDate, inSameDayAs: currentWeekSunday())
        else {
            return nil
        }

        try cachePlan(pendingPlan, profile: profile, defaults: defaults)
        defaults.removeObject(forKey: pendingNextWeekCacheKey)
        return pendingPlan
    }

    /// Get cached plan if valid (not expired and for current week)
    static func getCachedPlan() -> WeeklyTrainingPlan? {
        nil
    }

    static func cachedPlanStatus(
        for profile: TrainingProfile,
        defaults: UserDefaults = .standard
    ) -> CachedTrainingPlanStatus {
        guard let data = defaults.data(forKey: cacheKey) else { return .missing }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(TrainingPlanCacheEnvelope.self, from: data) else {
            if let legacyPlan = try? decoder.decode(WeeklyTrainingPlan.self, from: data) {
                return .stale(legacyPlan)
            }
            return .missing
        }

        let normalizedProfile = profile.validated(existingPlan: envelope.plan).profile
        let calendar = Calendar.current
        let metadataMatches = envelope.cacheVersion == TrainingPlanCacheEnvelope.currentVersion
            && envelope.profileSchemaVersion == normalizedProfile.schemaVersion
            && envelope.profileSchemaVersion == TrainingProfile.currentSchemaVersion
            && envelope.profileFingerprint == normalizedProfile.fingerprint
        let dateMatches = Date() < envelope.expiresAt
            && calendar.isDate(envelope.plan.weekStartDate, inSameDayAs: currentWeekSunday())

        return metadataMatches && dateMatches ? .valid(envelope.plan) : .stale(envelope.plan)
    }

    static func cachedPlanForProfileMigration(
        defaults: UserDefaults = .standard
    ) -> WeeklyTrainingPlan? {
        guard let data = defaults.data(forKey: cacheKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let envelope = try? decoder.decode(TrainingPlanCacheEnvelope.self, from: data) {
            return envelope.plan
        }
        return try? decoder.decode(WeeklyTrainingPlan.self, from: data)
    }

    private static func decodedCacheEnvelope(defaults: UserDefaults) -> TrainingPlanCacheEnvelope? {
        guard let data = defaults.data(forKey: cacheKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(TrainingPlanCacheEnvelope.self, from: data)
    }

    /// Clear the cached plan
    static func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: cacheExpirationKey)
    }

    /// Calculate next Sunday at midnight (end of current week)
    private static func nextSundayMidnight() -> Date {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)

        // Days until next Sunday (weekday 1 = Sunday)
        let daysUntilSunday = weekday == 1 ? 7 : (8 - weekday)

        // Get next Sunday at start of day (midnight)
        let nextSunday = calendar.safeDate(byAdding: .day, value: daysUntilSunday, to: calendar.startOfDay(for: today))
        return nextSunday
    }

    // MARK: - Generate Weekly Plan

    static func generatePlan(
        athleteId: Int? = nil,
        profile: TrainingProfile,
        scope: PlanRegenerationScope,
        existingPlan: WeeklyTrainingPlan?,
        goal: RunningGoal? = nil,
        settings: PlanGenerationSettings = .default,
        runningPlanGenerator: (() async throws -> WeeklyTrainingPlan)? = nil,
        regenerationDate: Date = Date()
    ) async throws -> WeeklyTrainingPlan {
        let validatedProfile = profile.validated(existingPlan: existingPlan).profile
        let calendar = Calendar.current
        let runningPlan: WeeklyTrainingPlan

        switch scope {
        case .initialCurrentWeek:
            let generated: WeeklyTrainingPlan
            if let runningPlanGenerator {
                generated = try await runningPlanGenerator()
            } else {
                guard let athleteId = athleteId ?? existingPlan?.athleteId, athleteId > 0 else {
                    throw TrainingPlanError.missingAthleteId
                }
                generated = await establishedRunningPlan(
                    athleteId: athleteId,
                    goal: goal,
                    settings: settings
                )
            }
            runningPlan = shiftedPlan(generated, to: currentWeekSunday())
        case .nextWeek:
            let generated: WeeklyTrainingPlan
            if let runningPlanGenerator {
                generated = try await runningPlanGenerator()
            } else {
                generated = await establishedRunningPlan(
                    athleteId: athleteId ?? existingPlan?.athleteId ?? 0,
                    goal: goal,
                    settings: settings
                )
            }
            let nextBoundary = calendar.safeDate(byAdding: .weekOfYear, value: 1, to: currentWeekSunday())
            runningPlan = shiftedPlan(generated, to: nextBoundary)
        case .remainingCurrentWeek:
            guard let existingPlan else { throw TrainingPlanError.noPlanFound }
            runningPlan = existingPlan
        }
        return composeProfileAwarePlan(
            runningPlan: runningPlan,
            profile: validatedProfile,
            scope: scope,
            existingPlan: existingPlan,
            regenerationDate: regenerationDate
        )
    }

    /// Generate a training plan for the current or specified week
    static func generateWeeklyPlan(
        athleteId: Int,
        goal: RunningGoal?,
        weekStartDate: Date? = nil,
        profile: TrainingProfile? = nil,
        settings: PlanGenerationSettings = .default
    ) async throws -> WeeklyTrainingPlan {
        let resolvedProfile = await resolvedProfile(profile)
        let generated = await establishedRunningPlan(
            athleteId: athleteId,
            goal: goal,
            settings: settings
        )
        let targetDate = weekStartDate ?? currentWeekSunday()
        let runningPlan = shiftedPlan(generated, to: targetDate)
        let plan = composeProfileAwarePlan(
            runningPlan: runningPlan,
            profile: resolvedProfile,
            scope: .initialCurrentWeek,
            existingPlan: nil
        )
        try cachePlan(plan, profile: resolvedProfile)
        return plan
    }

    // MARK: - Adaptive Plan Regeneration

    /// Regenerate the remaining days of the plan based on completed activities
    /// Called when activities are synced that differ significantly from the plan
    static func regeneratePlanWithActivities(
        athleteId: Int,
        currentPlan: WeeklyTrainingPlan,
        completedActivities: [Activity],
        goal: RunningGoal?,
        profile: TrainingProfile? = nil
    ) async throws -> WeeklyTrainingPlan {
        _ = athleteId
        let completedPlan = reconciledPlan(
            currentPlan: currentPlan,
            completedActivities: completedActivities,
            now: Date()
        )
        let activityAdjustedPlan = adjustPlanLocally(
            currentPlan: completedPlan,
            completedActivities: completedActivities
        )
        let storedProfile = await resolvedProfile(profile)
        let resolvedProfile = storedProfile.validated(existingPlan: activityAdjustedPlan).profile
        let adjusted = try await generatePlan(
            athleteId: athleteId,
            profile: resolvedProfile,
            scope: .remainingCurrentWeek,
            existingPlan: activityAdjustedPlan,
            goal: goal
        )
        return reconciledPlan(
            currentPlan: adjusted,
            completedActivities: completedActivities,
            now: Date()
        )
    }

    /// Check if plan regeneration is needed based on activity differences
    static func shouldRegeneratePlan(
        currentPlan: WeeklyTrainingPlan,
        newActivity: Activity
    ) -> Bool {
        guard let activityTimestamp = newActivity.activity_date ?? newActivity.start_date else {
            return false
        }

        let activityDate = Date(timeIntervalSince1970: activityTimestamp)

        // Only consider activities from the current week
        guard containsActivityDate(activityDate, in: currentPlan) else {
            return false
        }

        // Find planned workout for this day
        let dayOfWeek = DayOfWeek.from(date: activityDate)
        guard let plannedWorkout = currentPlan.workout(for: dayOfWeek) else {
            // No planned workout - might want to regenerate to add recovery
            let activityDistance = (newActivity.distance ?? 0) * 0.000621371
            return activityDistance > 3.0 // Regenerate if unplanned run > 3 miles
        }

        if workoutType(for: newActivity) != nil,
           !newActivity.isCompatible(with: plannedWorkout.workoutType) {
            return true
        }

        // Compare actual vs planned
        let actualDistanceMiles = (newActivity.distance ?? 0) * 0.000621371
        let plannedDistance = plannedWorkout.distance ?? 0

        // Regenerate if:
        // 1. Distance differs by more than 30%
        // 2. Did a hard workout when easy was planned (or vice versa)

        if plannedDistance > 0 {
            let distanceRatio = actualDistanceMiles / plannedDistance
            if distanceRatio < 0.7 || distanceRatio > 1.3 {
                #if DEBUG
                print("📋 TrainingPlan: Distance deviation detected (\(String(format: "%.1f", actualDistanceMiles)) vs \(String(format: "%.1f", plannedDistance)) mi)")
                #endif
                return true
            }
        }

        // Check workout type mismatch
        let activityType = newActivity.type?.lowercased() ?? ""
        let plannedType = plannedWorkout.workoutType

        // If planned was easy but actual was hard (based on pace or name)
        if plannedType == .easyRun || plannedType == .recoveryRun {
            if activityType.contains("tempo") || activityType.contains("interval") || activityType.contains("race") {
                #if DEBUG
                print("📋 TrainingPlan: Workout type mismatch (planned easy, did hard)")
                #endif
                return true
            }
        }

        return false
    }

    static func reconciledPlan(
        currentPlan: WeeklyTrainingPlan,
        completedActivities: [Activity],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WeeklyTrainingPlan {
        let anchored = anchoringCompletedActivities(
            completedActivities,
            to: currentPlan,
            calendar: calendar
        )
        let today = calendar.startOfDay(for: now)
        var workouts = anchored.workouts
        let historical = workouts.indices
            .filter { calendar.startOfDay(for: workouts[$0].date) <= today }
            .sorted { workouts[$0].date < workouts[$1].date }
        var consecutiveRuns = 0
        var lastHistoricalDate: Date?

        for index in historical {
            let workout = workouts[index]
            let day = calendar.startOfDay(for: workout.date)
            let followsPrevious = lastHistoricalDate.flatMap {
                calendar.date(byAdding: .day, value: 1, to: $0)
            }.map { calendar.isDate($0, inSameDayAs: day) } ?? false
            if workout.isCompleted && workout.workoutType.isRunning {
                consecutiveRuns = followsPrevious ? consecutiveRuns + 1 : 1
            } else {
                consecutiveRuns = 0
            }
            lastHistoricalDate = day
        }

        guard consecutiveRuns >= 2,
              lastHistoricalDate.map({ calendar.isDate($0, inSameDayAs: today) }) == true else {
            return anchored
        }

        let future = workouts.indices
            .filter { calendar.startOfDay(for: workouts[$0].date) > today }
            .sorted { workouts[$0].date < workouts[$1].date }
        var runStreak = consecutiveRuns

        for (position, index) in future.enumerated() {
            let workout = workouts[index]
            if !workout.workoutType.isRunning {
                runStreak = 0
                continue
            }
            guard runStreak >= 2,
                  workout.commitment == nil,
                  !AcceptedPrescriptionPlanPolicy.isExplicitChoice(workout),
                  let swapIndex = future.dropFirst(position + 1).first(where: { candidateIndex in
                      let candidate = workouts[candidateIndex]
                      return !candidate.workoutType.isRunning
                          && candidate.workoutType != .rest
                          && !candidate.isCompleted
                          && candidate.commitment == nil
                          && !AcceptedPrescriptionPlanPolicy.isExplicitChoice(candidate)
                  }) else {
                runStreak += 1
                continue
            }

            let recoveryModality = workouts[swapIndex]
            workouts[index] = relocated(recoveryModality, to: workout)
            workouts[swapIndex] = relocated(workout, to: recoveryModality)
            runStreak = 0
        }

        return replacingWorkouts(in: anchored, with: workouts, generatedAt: now)
    }

    static func containsActivityDate(
        _ date: Date,
        in plan: WeeklyTrainingPlan,
        calendar: Calendar = .current
    ) -> Bool {
        let weekStart = calendar.startOfDay(for: plan.weekStartDate)
        guard let followingWeekStart = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            return false
        }
        return date >= weekStart && date < followingWeekStart
    }

    /// Merge original plan with regenerated plan
    private static func mergePlans(
        original: WeeklyTrainingPlan,
        regenerated: WeeklyTrainingPlan,
        completedActivities: [Activity]
    ) -> WeeklyTrainingPlan {
        let calendar = Calendar.current
        var mergedWorkouts: [DailyWorkout] = []

        for day in DayOfWeek.allCases {
            guard let dayDate = calendar.date(
                byAdding: .day,
                value: day.calendarWeekday - 1,
                to: original.weekStartDate
            ) else { continue }

            // Check if this day has a completed activity
            let hasCompletedActivity = completedActivities.contains { activity in
                guard let ts = activity.activity_date ?? activity.start_date else { return false }
                return calendar.isDate(Date(timeIntervalSince1970: ts), inSameDayAs: dayDate)
            }

            if hasCompletedActivity {
                // Keep original planned workout (will be shown as completed in UI)
                if let originalWorkout = original.workout(for: day) {
                    mergedWorkouts.append(originalWorkout)
                }
            } else {
                // Use regenerated workout for this day
                if let newWorkout = regenerated.workout(for: day) {
                    mergedWorkouts.append(newWorkout)
                } else if let originalWorkout = original.workout(for: day) {
                    // Fallback to original if regenerated doesn't have this day
                    mergedWorkouts.append(originalWorkout)
                }
            }
        }

        // Calculate new total mileage
        let totalMileage = mergedWorkouts.compactMap { $0.distance }.reduce(0, +)

        return WeeklyTrainingPlan(
            id: original.id,
            athleteId: original.athleteId,
            weekStartDate: original.weekStartDate,
            weekEndDate: original.weekEndDate,
            workouts: mergedWorkouts,
            weekNumber: original.weekNumber,
            totalMileage: totalMileage,
            focusArea: regenerated.focusArea ?? original.focusArea,
            notes: regenerated.notes ?? original.notes,
            generatedAt: Date(),
            goalId: original.goalId
        )
    }

    private static func anchoringCompletedActivities(
        _ activities: [Activity],
        to plan: WeeklyTrainingPlan,
        calendar: Calendar = .current
    ) -> WeeklyTrainingPlan {
        let datedActivities = activities.compactMap { activity -> (Activity, Date)? in
            guard let timestamp = activity.activity_date ?? activity.start_date else { return nil }
            let date = Date(timeIntervalSince1970: timestamp)
            guard containsActivityDate(date, in: plan, calendar: calendar) else { return nil }
            return (activity, calendar.startOfDay(for: date))
        }.sorted { $0.0.id < $1.0.id }

        let workouts = plan.workouts.map { workout -> DailyWorkout in
            guard !workout.isCompleted else { return workout }
            let sameDay = datedActivities.filter {
                calendar.isDate($0.1, inSameDayAs: workout.date)
            }.map(\.0)
            guard let activity = sameDay.first(where: { $0.isCompatible(with: workout.workoutType) })
                    ?? sameDay.max(by: { ($0.elapsed_time ?? 0) < ($1.elapsed_time ?? 0) }),
                  let actualType = workoutType(for: activity) else {
                return workout
            }
            let distance = activity.distance.map { $0 * 0.000621371 } ?? workout.distance
            let duration = activity.elapsed_time.map { Int(($0 / 60).rounded()) }
                ?? activity.moving_time.map { Int((Double($0) / 60).rounded()) }
                ?? workout.duration
            if activity.isCompatible(with: workout.workoutType) {
                return DailyWorkout(
                    id: workout.id,
                    date: workout.date,
                    dayOfWeek: workout.dayOfWeek,
                    workoutType: workout.workoutType,
                    title: workout.title,
                    description: workout.description,
                    duration: duration,
                    distance: distance,
                    targetPace: workout.targetPace,
                    exercises: workout.exercises,
                    isCompleted: true,
                    completedActivityId: activity.id,
                    acceptedPrescription: workout.acceptedPrescription,
                    acceptedCompletion: workout.acceptedCompletion,
                    commitment: workout.commitment
                )
            }
            let actualTitle = activity.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            return DailyWorkout(
                id: workout.id,
                date: workout.date,
                dayOfWeek: workout.dayOfWeek,
                workoutType: actualType,
                title: actualTitle?.isEmpty == false ? actualTitle! : actualType.displayName,
                description: "Recorded instead of the planned \(workout.title).",
                duration: duration,
                distance: actualType.isRunning ? distance : nil,
                targetPace: nil,
                exercises: nil,
                isCompleted: true,
                completedActivityId: activity.id
            )
        }

        return WeeklyTrainingPlan(
            id: plan.id,
            athleteId: plan.athleteId,
            weekStartDate: plan.weekStartDate,
            weekEndDate: plan.weekEndDate,
            workouts: workouts,
            weekNumber: plan.weekNumber,
            totalMileage: workouts.filter { $0.workoutType.isRunning }.compactMap(\.distance).reduce(0, +),
            focusArea: plan.focusArea,
            notes: plan.notes,
            generatedAt: plan.generatedAt,
            goalId: plan.goalId
        )
    }

    private static func workoutType(for activity: Activity) -> WorkoutType? {
        let value = (activity.type ?? activity.name ?? "").lowercased()
        if value.contains("run") || value.contains("jog") { return .easyRun }
        if value.contains("ride") || value.contains("cycl") || value.contains("bike") { return .cycling }
        if value.contains("swim") { return .swimming }
        if value.contains("walk") { return .walking }
        if value.contains("hik") { return .hiking }
        if value.contains("strength") || value.contains("weight") || value.contains("workout") || value.contains("crossfit") {
            return .strengthTraining
        }
        if value.contains("yoga") { return .yoga }
        if value.contains("mobility") || value.contains("stretch") { return .stretchMobility }
        return nil
    }

    private static func relocated(_ source: DailyWorkout, to destination: DailyWorkout) -> DailyWorkout {
        DailyWorkout(
            id: source.id,
            date: destination.date,
            dayOfWeek: destination.dayOfWeek,
            workoutType: source.workoutType,
            title: source.title,
            description: source.description,
            duration: source.duration,
            distance: source.distance,
            targetPace: source.targetPace,
            exercises: source.exercises,
            isCompleted: false,
            completedActivityId: nil,
            acceptedPrescription: source.acceptedPrescription,
            acceptedCompletion: nil,
            commitment: nil
        )
    }

    private static func replacingWorkouts(
        in plan: WeeklyTrainingPlan,
        with workouts: [DailyWorkout],
        generatedAt: Date
    ) -> WeeklyTrainingPlan {
        WeeklyTrainingPlan(
            id: plan.id,
            athleteId: plan.athleteId,
            weekStartDate: plan.weekStartDate,
            weekEndDate: plan.weekEndDate,
            workouts: workouts.sorted { $0.date < $1.date },
            weekNumber: plan.weekNumber,
            totalMileage: workouts.filter { $0.workoutType.isRunning }.compactMap(\.distance).reduce(0, +),
            focusArea: plan.focusArea,
            notes: "Plan rebalanced around completed work.",
            generatedAt: generatedAt,
            goalId: plan.goalId
        )
    }

    private static func activity(_ activity: Activity, matches workoutType: WorkoutType) -> Bool {
        let type = (activity.type ?? activity.name ?? "").lowercased()
        if type.contains("run") || type.contains("jog") { return workoutType.isRunning }
        if type.contains("ride") || type.contains("cycl") || type.contains("bike") {
            return workoutType == .cycling
        }
        if type.contains("swim") { return workoutType == .swimming }
        if type.contains("walk") { return workoutType == .walking }
        if type.contains("hik") { return workoutType == .hiking }
        if type.contains("strength") || type.contains("weight") { return workoutType.isStrength }
        if type.contains("yoga") { return workoutType == .yoga }
        return false
    }

    private static func isRunningActivity(_ activity: Activity) -> Bool {
        let type = (activity.type ?? activity.name ?? "").lowercased()
        return type.contains("run") || type.contains("jog")
    }

    /// Local fallback: adjust plan based on simple heuristics
    private static func adjustPlanLocally(
        currentPlan: WeeklyTrainingPlan,
        completedActivities: [Activity]
    ) -> WeeklyTrainingPlan {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Calculate total actual load from completed activities this week
        var actualMileage: Double = 0
        var hardWorkoutDone = false

        for activity in completedActivities {
            guard isRunningActivity(activity) else { continue }
            guard let ts = activity.activity_date ?? activity.start_date else { continue }
            let activityDate = Date(timeIntervalSince1970: ts)
            guard containsActivityDate(activityDate, in: currentPlan, calendar: calendar) else { continue }

            let miles = (activity.distance ?? 0) * 0.000621371
            actualMileage += miles

            // Check if it was a hard effort
            if let speed = activity.average_speed, speed > 0 {
                let paceMinPerMile = (1609.34 / speed) / 60.0
                if paceMinPerMile < 8.0 {
                    hardWorkoutDone = true
                }
            }
        }

        // Adjust remaining workouts based on accumulated load
        var adjustedWorkouts: [DailyWorkout] = []

        for workout in currentPlan.workouts {
            // If workout is in the past or today is past, keep as-is
            if workout.isCompleted || workout.date < today {
                adjustedWorkouts.append(workout)
                continue
            }

            var adjustedWorkout = workout

            // If we've done more than planned, reduce future intensity
            let plannedMileageSoFar = currentPlan.workouts
                .filter { $0.date < today }
                .compactMap { $0.distance }
                .reduce(0, +)

            let loadRatio = plannedMileageSoFar > 0 ? actualMileage / plannedMileageSoFar : 1.0

            if loadRatio > 1.3 {
                // Overloaded - convert hard workouts to easy
                if workout.workoutType == .tempoRun || workout.workoutType == .intervalRun {
                    adjustedWorkout = DailyWorkout(
                        id: workout.id,
                        date: workout.date,
                        dayOfWeek: workout.dayOfWeek,
                        workoutType: .recoveryRun,
                        title: "Recovery Run (Adjusted)",
                        description: "Adjusted to recovery due to higher training load earlier this week. Keep it easy!",
                        duration: workout.duration,
                        distance: (workout.distance ?? 4.0) * 0.6,
                        targetPace: "10:00-11:00/mi",
                        exercises: nil,
                        isCompleted: false,
                        completedActivityId: nil
                    )
                } else if workout.workoutType == .longRun {
                    // Reduce long run distance
                    adjustedWorkout = DailyWorkout(
                        id: workout.id,
                        date: workout.date,
                        dayOfWeek: workout.dayOfWeek,
                        workoutType: .easyRun,
                        title: "Easy Run (Adjusted)",
                        description: "Long run shortened due to higher training load. Focus on recovery.",
                        duration: (workout.duration ?? 60) / 2,
                        distance: (workout.distance ?? 8.0) * 0.5,
                        targetPace: "9:30-10:30/mi",
                        exercises: nil,
                        isCompleted: false,
                        completedActivityId: nil
                    )
                }
            } else if loadRatio < 0.7 && !hardWorkoutDone {
                // Underloaded - could suggest adding intensity (but be conservative)
                // Keep workout as-is but maybe add a note
            }

            adjustedWorkouts.append(adjustedWorkout)
        }

        let totalMileage = adjustedWorkouts.compactMap { $0.distance }.reduce(0, +)

        return WeeklyTrainingPlan(
            id: currentPlan.id,
            athleteId: currentPlan.athleteId,
            weekStartDate: currentPlan.weekStartDate,
            weekEndDate: currentPlan.weekEndDate,
            workouts: adjustedWorkouts,
            weekNumber: currentPlan.weekNumber,
            totalMileage: totalMileage,
            focusArea: currentPlan.focusArea,
            notes: "Plan adjusted based on your actual training load this week.",
            generatedAt: Date(),
            goalId: currentPlan.goalId
        )
    }

    /// Adjust plan based on rest day status
    /// If user needs rest, convert today's workout to a rest day
    static func adjustPlanForRestDays(
        currentPlan: WeeklyTrainingPlan,
        athleteId: Int
    ) async -> WeeklyTrainingPlan {
        let (shouldRest, reason) = await shouldTakeRestDay(athleteId: athleteId)

        guard shouldRest else {
            return currentPlan
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayDayOfWeek = DayOfWeek.from(date: today)

        var adjustedWorkouts: [DailyWorkout] = []

        for workout in currentPlan.workouts {
            if workout.dayOfWeek == todayDayOfWeek && workout.date >= today {
                // Convert today's workout to rest
                let restWorkout = DailyWorkout(
                    id: workout.id,
                    date: workout.date,
                    dayOfWeek: workout.dayOfWeek,
                    workoutType: .rest,
                    title: "Rest Day (Recovery)",
                    description: reason,
                    duration: nil,
                    distance: nil,
                    targetPace: nil,
                    exercises: nil,
                    isCompleted: false,
                    completedActivityId: nil
                )
                adjustedWorkouts.append(restWorkout)
            } else {
                adjustedWorkouts.append(workout)
            }
        }

        let totalMileage = adjustedWorkouts.compactMap { $0.distance }.reduce(0, +)

        return WeeklyTrainingPlan(
            id: currentPlan.id,
            athleteId: currentPlan.athleteId,
            weekStartDate: currentPlan.weekStartDate,
            weekEndDate: currentPlan.weekEndDate,
            workouts: adjustedWorkouts,
            weekNumber: currentPlan.weekNumber,
            totalMileage: totalMileage,
            focusArea: currentPlan.focusArea,
            notes: "Plan adjusted: \(reason)",
            generatedAt: Date(),
            goalId: currentPlan.goalId
        )
    }

    // MARK: - Get Existing Plan

    /// Fetch existing plan for a specific week
    static func getWeeklyPlan(athleteId: Int, weekStartDate: Date) async throws -> WeeklyTrainingPlan? {
        nil
    }

    static func getWeeklyPlan(
        athleteId: Int,
        weekStartDate: Date,
        profile: TrainingProfile
    ) async throws -> WeeklyTrainingPlan? {
        guard case let .valid(plan) = cachedPlanStatus(for: profile),
              plan.athleteId == athleteId else { return nil }
        return Calendar.current.isDate(plan.weekStartDate, inSameDayAs: weekStartDate) ? plan : nil
    }

    private static func personalizePlanLocally(_ plan: WeeklyTrainingPlan) async -> WeeklyTrainingPlan {
        let model = await FoundationModelsService.shared
        guard await model.isAvailable else { return plan }

        let schedule = plan.workouts.map { workout in
            let distance = workout.distance.map { String(format: "%.1f miles", $0) } ?? "no running distance"
            return "\(workout.dayOfWeek.rawValue): \(workout.title), \(distance)"
        }.joined(separator: "\n")

        do {
            let notes = try await model.generateResponse(
                prompt: "Write a concise weekly coaching note for this fixed, safety-checked schedule:\n\(schedule)",
                systemPrompt: "You are a grounded running coach. Explain the week's rhythm in 2-3 short sentences. Do not alter mileage, prescribe medical care, or invent athlete facts.",
                maxTokens: 256
            )
            return WeeklyTrainingPlan(
                id: plan.id,
                athleteId: plan.athleteId,
                weekStartDate: plan.weekStartDate,
                weekEndDate: plan.weekEndDate,
                workouts: plan.workouts,
                weekNumber: plan.weekNumber,
                totalMileage: plan.totalMileage,
                focusArea: plan.focusArea,
                notes: notes,
                generatedAt: plan.generatedAt,
                goalId: plan.goalId
            )
        } catch {
            return plan
        }
    }

    // MARK: - Local Plan Generation (Fallback)

    /// Generate a training plan locally when API is unavailable
    private static func generateLocalPlan(
        athleteId: Int,
        weekStartDate: Date,
        goal: RunningGoal?
    ) -> WeeklyTrainingPlan {
        let calendar = Calendar.current
        let weekEndDate = calendar.safeDate(byAdding: .day, value: 6, to: weekStartDate)

        var workouts: [DailyWorkout] = []

        // Sunday - Long Run
        workouts.append(createWorkout(
            date: weekStartDate,
            dayOfWeek: .sunday,
            type: .longRun,
            title: "Long Run",
            description: "Build your aerobic base with a comfortable long run. Keep the pace conversational.",
            distance: 8.0,
            duration: 70,
            targetPace: "9:00-10:00/mi"
        ))

        // Monday - Upper Body Strength
        workouts.append(createWorkout(
            date: calendar.safeDate(byAdding: .day, value: 1, to: weekStartDate),
            dayOfWeek: .monday,
            type: .upperBody,
            title: "Upper Body Strength",
            description: "Focus on pushing and pulling movements to build upper body strength.",
            duration: 45,
            exercises: [
                Exercise(name: "Bench Press", sets: 4, reps: "8-10"),
                Exercise(name: "Bent Over Rows", sets: 4, reps: "8-10"),
                Exercise(name: "Overhead Press", sets: 3, reps: "10-12"),
                Exercise(name: "Lat Pulldowns", sets: 3, reps: "10-12"),
                Exercise(name: "Face Pulls", sets: 3, reps: "15"),
                Exercise(name: "Bicep Curls", sets: 3, reps: "12"),
                Exercise(name: "Tricep Pushdowns", sets: 3, reps: "12")
            ]
        ))

        // Tuesday - Easy Run
        workouts.append(createWorkout(
            date: calendar.safeDate(byAdding: .day, value: 2, to: weekStartDate),
            dayOfWeek: .tuesday,
            type: .easyRun,
            title: "Easy Run",
            description: "Recover from your long run with an easy effort. Stay in zone 2.",
            distance: 4.0,
            duration: 35,
            targetPace: "9:30-10:30/mi"
        ))

        // Wednesday - Lower Body Strength
        workouts.append(createWorkout(
            date: calendar.safeDate(byAdding: .day, value: 3, to: weekStartDate),
            dayOfWeek: .wednesday,
            type: .lowerBody,
            title: "Lower Body Strength",
            description: "Build leg strength to improve running power and prevent injuries.",
            duration: 50,
            exercises: [
                Exercise(name: "Barbell Squats", sets: 4, reps: "6-8"),
                Exercise(name: "Romanian Deadlifts", sets: 4, reps: "8-10"),
                Exercise(name: "Walking Lunges", sets: 3, reps: "12 each leg"),
                Exercise(name: "Leg Press", sets: 3, reps: "10-12"),
                Exercise(name: "Calf Raises", sets: 4, reps: "15"),
                Exercise(name: "Leg Curls", sets: 3, reps: "12")
            ]
        ))

        // Thursday - Tempo Run
        workouts.append(createWorkout(
            date: calendar.safeDate(byAdding: .day, value: 4, to: weekStartDate),
            dayOfWeek: .thursday,
            type: .tempoRun,
            title: "Tempo Run",
            description: "Comfortably hard effort. Warm up 1 mile, tempo 3 miles, cool down 1 mile.",
            distance: 5.0,
            duration: 40,
            targetPace: "7:30-8:00/mi tempo"
        ))

        // Friday - Yoga & Mobility
        workouts.append(createWorkout(
            date: calendar.safeDate(byAdding: .day, value: 5, to: weekStartDate),
            dayOfWeek: .friday,
            type: .yoga,
            title: "Yoga & Mobility",
            description: "Active recovery with yoga flow. Focus on hip openers and hamstring stretches.",
            duration: 45
        ))

        // Saturday - Easy Run + Core
        workouts.append(createWorkout(
            date: calendar.safeDate(byAdding: .day, value: 6, to: weekStartDate),
            dayOfWeek: .saturday,
            type: .easyRun,
            title: "Easy Run + Core",
            description: "Short easy run followed by core work. Prepare for tomorrow's long run.",
            distance: 3.0,
            duration: 50,
            targetPace: "9:30-10:30/mi",
            exercises: [
                Exercise(name: "Plank", sets: 3, reps: "45 sec"),
                Exercise(name: "Dead Bug", sets: 3, reps: "10 each side"),
                Exercise(name: "Bird Dog", sets: 3, reps: "10 each side"),
                Exercise(name: "Russian Twists", sets: 3, reps: "20"),
                Exercise(name: "Glute Bridges", sets: 3, reps: "15")
            ]
        ))

        // Calculate total mileage
        let totalMileage = workouts.compactMap { $0.distance }.reduce(0, +)

        return WeeklyTrainingPlan(
            id: UUID().uuidString,
            athleteId: athleteId,
            weekStartDate: weekStartDate,
            weekEndDate: weekEndDate,
            workouts: workouts,
            weekNumber: nil,
            totalMileage: totalMileage,
            focusArea: "Base Building",
            notes: "Focus on building your aerobic base while maintaining strength. Keep easy runs truly easy!",
            generatedAt: Date(),
            goalId: goal?.id
        )
    }

    private static func reconcileRunningFrequency(
        in plan: WeeklyTrainingPlan,
        profile: TrainingProfile
    ) -> WeeklyTrainingPlan {
        let requested = profile.preference(for: .running)?.sessionsPerWeek ?? 0
        let runs = plan.workouts.filter { $0.workoutType.isRunning }.sorted { $0.date < $1.date }
        guard runs.count != requested else { return plan }

        func isEasy(_ workout: DailyWorkout) -> Bool {
            workout.workoutType == .easyRun || workout.workoutType == .recoveryRun
        }

        let originalMileage = runs.compactMap(\.distance).reduce(0, +)
        var reconciled = plan.workouts

        if runs.count > requested {
            func preservationRank(_ workout: DailyWorkout) -> Int {
                switch workout.workoutType {
                case .longRun: return 0
                case .tempoRun, .intervalRun, .hillRun: return 1
                case .easyRun: return 2
                case .recoveryRun: return 3
                default: return 4
                }
            }
            let retained = runs.sorted {
                let lhsRank = preservationRank($0)
                let rhsRank = preservationRank($1)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return $0.date < $1.date
            }.prefix(requested)
            let retainedIDs = Set(retained.map(\.id))
            let removed = runs.filter { !retainedIDs.contains($0.id) }
            let removedIDs = Set(removed.map(\.id))
            let retainedEasy = runs.filter { isEasy($0) && retainedIDs.contains($0.id) }
            let removedMileage = removed.compactMap(\.distance).reduce(0, +)
            let bonus = retainedEasy.isEmpty ? 0 : removedMileage / Double(retainedEasy.count)
            let retainedEasyIDs = Set(retainedEasy.map(\.id))
            reconciled = reconciled.compactMap { workout in
                guard !removedIDs.contains(workout.id) else { return nil }
                guard retainedEasyIDs.contains(workout.id) else { return workout }
                return resizingEasyRun(workout, distance: (workout.distance ?? 0) + bonus)
            }
        } else {
            return plan
        }

        let finalRuns = reconciled.filter { $0.workoutType.isRunning }
        let finalMileage = finalRuns.compactMap(\.distance).reduce(0, +)
        guard finalRuns.count == requested else { return plan }
        let preservedMileage = retainedMileageIsExpected(
            requested: requested,
            originalMileage: originalMileage,
            finalMileage: finalMileage,
            runs: finalRuns
        )
        guard preservedMileage else { return plan }
        return WeeklyTrainingPlan(
            id: plan.id,
            athleteId: plan.athleteId,
            weekStartDate: plan.weekStartDate,
            weekEndDate: plan.weekEndDate,
            workouts: reconciled.sorted { $0.date < $1.date },
            weekNumber: plan.weekNumber,
            totalMileage: finalMileage,
            focusArea: plan.focusArea,
            notes: plan.notes,
            generatedAt: plan.generatedAt,
            goalId: plan.goalId
        )
    }

    private static func retainedMileageIsExpected(
        requested: Int,
        originalMileage: Double,
        finalMileage: Double,
        runs: [DailyWorkout]
    ) -> Bool {
        requested == 0
            || runs.contains { $0.workoutType == .easyRun || $0.workoutType == .recoveryRun }
                ? abs(finalMileage - originalMileage) < 0.001
                : finalMileage <= originalMileage
    }

    private static func resizingEasyRun(_ workout: DailyWorkout, distance: Double) -> DailyWorkout {
        let oldDistance = workout.distance ?? distance
        let duration = workout.duration.map {
            oldDistance > 0 ? Int((Double($0) * distance / oldDistance).rounded()) : $0
        }
        return DailyWorkout(
            id: workout.id,
            date: workout.date,
            dayOfWeek: workout.dayOfWeek,
            workoutType: workout.workoutType,
            title: workout.title,
            description: WorkoutDescriptionPolicy.reconciled(
                workout.description, distanceLabel: String(format: "%.1f miles", distance)
            ),
            duration: duration,
            distance: distance,
            targetPace: workout.targetPace,
            exercises: workout.exercises,
            isCompleted: workout.isCompleted,
            completedActivityId: workout.completedActivityId
        )
    }

    private static func rolePrioritizedRemainingSessionBudgets(
        profile: TrainingProfile,
        dates: [Date],
        protectedHistory: [DailyWorkout]
    ) -> [TrainingActivity: Int] {
        let calendar = Calendar.current
        let protectedTrainingDays = Set(protectedHistory.compactMap { workout -> Date? in
            workout.workoutType == .rest ? nil : calendar.startOfDay(for: workout.date)
        })
        let openAvailableDays = dates.filter { date in
            let day = calendar.startOfDay(for: date)
            let weekday = DayOfWeek.from(date: date).calendarWeekday
            return !protectedTrainingDays.contains(day)
                && !profile.unavailableWeekdays.contains(weekday)
        }.count
        var remainingCapacity = min(
            max(0, profile.trainingDaysPerWeek - protectedTrainingDays.count),
            openAvailableDays
        )
        let protectedCounts = protectedHistory.reduce(into: [TrainingActivity: Int]()) { counts, workout in
            if let activity = workout.workoutType.activity {
                counts[activity, default: 0] += 1
            }
        }
        var budgets: [TrainingActivity: Int] = [:]

        for role in [TrainingActivityRole.primary, .supporting, .optional] {
            let preferences = profile.activities
                .filter { $0.role == role }
                .sorted { $0.activity.rawValue < $1.activity.rawValue }
            for preference in preferences {
                let unmet = max(
                    0,
                    preference.sessionsPerWeek - protectedCounts[preference.activity, default: 0]
                )
                let allocation = min(unmet, remainingCapacity)
                budgets[preference.activity] = allocation
                remainingCapacity -= allocation
            }
        }
        return budgets
    }

    private static func composeProfileAwarePlan(
        runningPlan: WeeklyTrainingPlan,
        profile: TrainingProfile,
        scope: PlanRegenerationScope,
        existingPlan: WeeklyTrainingPlan?,
        regenerationDate: Date = Date()
    ) -> WeeklyTrainingPlan {
        var runningPlan = runningPlan
        if scope == .nextWeek || scope == .initialCurrentWeek {
            runningPlan = reconcileRunningFrequency(in: runningPlan, profile: profile)
        }
        let calendar = Calendar.current
        let dates = (0..<7).map {
            calendar.safeDate(byAdding: .day, value: $0, to: runningPlan.weekStartDate)
        }
        let today = calendar.startOfDay(for: regenerationDate)
        let protectedHistory: [DailyWorkout]
        let baselineRunCandidates: [DailyWorkout]
        switch scope {
        case .initialCurrentWeek, .nextWeek:
            protectedHistory = []
            baselineRunCandidates = runningPlan.workouts.filter { $0.workoutType.isRunning }
        case .remainingCurrentWeek:
            let existingWorkouts = existingPlan?.workouts ?? []
            protectedHistory = existingWorkouts.filter {
                $0.isCompleted || calendar.startOfDay(for: $0.date) <= today
                    || AcceptedPrescriptionPlanPolicy.isExplicitChoice($0)
            }
            let protectedIDs = Set(protectedHistory.map(\.id))
            baselineRunCandidates = existingWorkouts.filter {
                $0.workoutType.isRunning && !protectedIDs.contains($0.id)
            }
        }

        let runCandidates = relocatedRunCandidates(
            baselineRunCandidates,
            profile: profile,
            dates: dates,
            protectedHistory: protectedHistory
        )
        let remainingBudgets = rolePrioritizedRemainingSessionBudgets(
            profile: profile,
            dates: dates,
            protectedHistory: protectedHistory
        )
        let fixedRunCandidates = Array(
            runCandidates.prefix(remainingBudgets[.running, default: 0])
        )
        let completedAssignments = protectedHistory.map {
            ScheduledWorkoutAssignment(
                id: $0.id,
                weekday: $0.dayOfWeek,
                date: $0.date,
                workoutType: $0.workoutType,
                reason: .completedWorkoutProtected,
                isCompleted: $0.isCompleted,
                isFixed: true
            )
        }
        let fixedRunAssignments = fixedRunCandidates.map {
            ScheduledWorkoutAssignment(
                id: $0.id,
                weekday: $0.dayOfWeek,
                date: $0.date,
                workoutType: $0.workoutType,
                reason: .requiredPrimary,
                isCompleted: false,
                isFixed: true
            )
        }
        let context = SchedulingContext(
            dates: dates,
            profile: profile,
            fixedPrimaryWorkouts: fixedRunAssignments,
            completedWorkouts: completedAssignments,
            unavailableWeekdays: profile.unavailableWeekdays,
            readinessByWeekday: [:],
            taperProtectedWeekdays: []
        )
        let assignments = ComplementarySchedulingPolicy.buildWeeklyAssignments(context: context)
        let templateIDs = Set((protectedHistory + fixedRunCandidates).map(\.id))
        let addedRunAssignments = assignments.filter {
            !$0.isCompleted && $0.workoutType.isRunning && !templateIDs.contains($0.id)
        }
        let easyPrescriptions = fixedRunCandidates.filter {
            $0.workoutType == .easyRun || $0.workoutType == .recoveryRun
        }
        let addedRunDistance: Double?
        let mileageBalancedCandidates: [DailyWorkout]
        if !addedRunAssignments.isEmpty, !easyPrescriptions.isEmpty {
            let easyMileage = easyPrescriptions.compactMap(\.distance).reduce(0, +)
            let distance = easyMileage / Double(easyPrescriptions.count + addedRunAssignments.count)
            let easyIDs = Set(easyPrescriptions.map(\.id))
            addedRunDistance = distance
            mileageBalancedCandidates = fixedRunCandidates.map {
                easyIDs.contains($0.id) ? resizingEasyRun($0, distance: distance) : $0
            }
        } else {
            addedRunDistance = nil
            mileageBalancedCandidates = fixedRunCandidates
        }
        let runningTemplate = easyPrescriptions.first
        let templatesByID = Dictionary(uniqueKeysWithValues: (protectedHistory + mileageBalancedCandidates).map {
            ($0.id, $0)
        })
        let assignmentByDay = Dictionary(uniqueKeysWithValues: assignments.map {
            (calendar.startOfDay(for: $0.date), $0)
        })

        let workouts = dates.map { date -> DailyWorkout in
            let day = calendar.startOfDay(for: date)
            if let assignment = assignmentByDay[day] {
                if let template = templatesByID[assignment.id] { return template }
                return supportingWorkout(
                    for: assignment,
                    profile: profile,
                    runningDistance: assignment.workoutType.isRunning ? addedRunDistance : nil,
                    runningTargetPace: assignment.workoutType.isRunning ? runningTemplate?.targetPace : nil
                )
            }
            return createWorkout(
                date: date,
                dayOfWeek: DayOfWeek.from(date: date),
                type: .rest,
                title: "Rest Day",
                description: "Recover and prepare for the next scheduled session."
            )
        }
        let runningMileage = workouts
            .filter { $0.workoutType.isRunning }
            .compactMap(\.distance)
            .reduce(0, +)
        let reasons = assignments.filter { !$0.isCompleted }.map {
            "\($0.weekday.shortName): \($0.reason.rawValue)"
        }.joined(separator: "; ")
        let original = scope.isCurrentWeek ? existingPlan : nil

        return WeeklyTrainingPlan(
            id: original?.id ?? runningPlan.id,
            athleteId: original?.athleteId ?? runningPlan.athleteId,
            weekStartDate: runningPlan.weekStartDate,
            weekEndDate: runningPlan.weekEndDate,
            workouts: workouts,
            weekNumber: original?.weekNumber ?? runningPlan.weekNumber,
            totalMileage: runningMileage,
            focusArea: original?.focusArea ?? runningPlan.focusArea,
            notes: original?.notes ?? scheduleNotes(base: runningPlan.notes, reasons: reasons),
            generatedAt: Date(),
            goalId: original?.goalId ?? runningPlan.goalId
        )
    }

    private static func relocatedRunCandidates(
        _ candidates: [DailyWorkout],
        profile: TrainingProfile,
        dates: [Date],
        protectedHistory: [DailyWorkout]
    ) -> [DailyWorkout] {
        guard profile.preference(for: .running)?.sessionsPerWeek ?? 0 > 0 else { return [] }
        let calendar = Calendar.current
        let validDates = dates.filter {
            !profile.unavailableWeekdays.contains(DayOfWeek.from(date: $0).calendarWeekday)
        }
        var occupied = Set(protectedHistory.map { calendar.startOfDay(for: $0.date) })
        let ordered = candidates.sorted {
            if ($0.workoutType == .longRun) != ($1.workoutType == .longRun) {
                return $0.workoutType == .longRun
            }
            return $0.date < $1.date
        }

        return ordered.compactMap { workout in
            // Preserve the prescription by finding a safe day before the scheduler
            // rejects it and manufactures a replacement from another run's mileage.
            let safeDates = validDates.filter { date in
                let day = calendar.startOfDay(for: date)
                guard !occupied.contains(day) else { return false }
                func adjacent(_ delta: Int) -> WorkoutType? {
                    guard let neighbor = calendar.date(byAdding: .day, value: delta, to: day) else { return nil }
                    return protectedHistory.first { calendar.isDate($0.date, inSameDayAs: neighbor) }?.workoutType
                }
                let context = SchedulingDayContext(
                    date: date, weekday: DayOfWeek.from(date: date), profile: profile,
                    plannedOrFixedWorkout: workout.workoutType,
                    previousWorkout: adjacent(-1), nextWorkout: adjacent(1),
                    readiness: .normal, assignedWorkoutTypes: [],
                    isCompletedProtected: false, isUnavailable: false, isTaperProtected: false
                )
                return ComplementarySchedulingPolicy.evaluation(of: workout.workoutType, for: context).candidate != nil
            }
            let preferredDate = workout.workoutType == .longRun
                ? safeDates.first { DayOfWeek.from(date: $0).calendarWeekday == profile.preferredLongRunWeekday }
                : nil
            let originalDay = calendar.startOfDay(for: workout.date)
            let selectedDate = [preferredDate, safeDates.first { calendar.isDate($0, inSameDayAs: originalDay) }]
                .compactMap { $0 }
                .first { !occupied.contains(calendar.startOfDay(for: $0)) }
                ?? safeDates
                    .filter { !occupied.contains(calendar.startOfDay(for: $0)) }
                    .min { lhs, rhs in
                        abs(lhs.timeIntervalSince(workout.date)) < abs(rhs.timeIntervalSince(workout.date))
                    }
            guard let selectedDate else { return nil }
            let day = calendar.startOfDay(for: selectedDate)
            occupied.insert(day)
            return DailyWorkout(
                id: workout.id,
                date: selectedDate,
                dayOfWeek: DayOfWeek.from(date: selectedDate),
                workoutType: workout.workoutType,
                title: workout.title,
                description: workout.description,
                duration: workout.duration,
                distance: workout.distance,
                targetPace: workout.targetPace,
                exercises: workout.exercises,
                isCompleted: false,
                completedActivityId: nil
            )
        }
    }

    @MainActor
    private static func establishedRunningPlan(
        athleteId: Int,
        goal: RunningGoal?,
        settings: PlanGenerationSettings
    ) async -> WeeklyTrainingPlan {
        let algorithm = AdaptiveTrainingAlgorithm()
        return await algorithm.generateAdaptivePlan(
            athleteId: athleteId,
            goal: goal,
            settings: settings
        )
    }

    @MainActor
    private static func resolvedProfile(_ injected: TrainingProfile?) -> TrainingProfile {
        if let injected {
            return injected.validated().profile
        }
        TrainingProfileStore.shared.reloadFromPersistence()
        let profile = TrainingProfileStore.shared.profile
        return profile.validated().profile
    }

    private static func shiftedPlan(_ plan: WeeklyTrainingPlan, to weekStart: Date) -> WeeklyTrainingPlan {
        let calendar = Calendar.current
        let dayDelta = calendar.dateComponents([.day], from: plan.weekStartDate, to: weekStart).day ?? 0
        let workouts = plan.workouts.map { workout in
            DailyWorkout(
                id: workout.id,
                date: calendar.safeDate(byAdding: .day, value: dayDelta, to: workout.date),
                dayOfWeek: workout.dayOfWeek,
                workoutType: workout.workoutType,
                title: workout.title,
                description: workout.description,
                duration: workout.duration,
                distance: workout.distance,
                targetPace: workout.targetPace,
                exercises: workout.exercises,
                isCompleted: workout.isCompleted,
                completedActivityId: workout.completedActivityId
            )
        }
        return WeeklyTrainingPlan(
            id: plan.id,
            athleteId: plan.athleteId,
            weekStartDate: weekStart,
            weekEndDate: calendar.safeDate(byAdding: .day, value: 6, to: weekStart),
            workouts: workouts,
            weekNumber: plan.weekNumber,
            totalMileage: plan.totalMileage,
            focusArea: plan.focusArea,
            notes: plan.notes,
            generatedAt: plan.generatedAt,
            goalId: plan.goalId
        )
    }

    private static func scheduleNotes(base: String?, reasons: String) -> String? {
        guard !reasons.isEmpty else { return base }
        return [base, "Schedule: \(reasons)"].compactMap { $0 }.joined(separator: "\n")
    }

    private static func supportingWorkout(
        for assignment: ScheduledWorkoutAssignment,
        profile: TrainingProfile,
        runningDistance: Double? = nil,
        runningTargetPace: String? = nil
    ) -> DailyWorkout {
        let description = assignment.reason.coachingDescription
        let exercises = StrengthSessionPrescription.exercises(for: assignment.workoutType, profile: profile)
        return createWorkout(
            date: assignment.date,
            dayOfWeek: assignment.weekday,
            type: assignment.workoutType,
            title: assignment.workoutType.displayName,
            description: description,
            distance: runningDistance,
            duration: assignment.workoutType.isStrength ? 45 : 40,
            targetPace: runningTargetPace,
            exercises: exercises
        )
    }

    private static func createWorkout(
        date: Date,
        dayOfWeek: DayOfWeek,
        type: WorkoutType,
        title: String,
        description: String,
        distance: Double? = nil,
        duration: Int? = nil,
        targetPace: String? = nil,
        exercises: [Exercise]? = nil
    ) -> DailyWorkout {
        DailyWorkout(
            id: UUID().uuidString,
            date: date,
            dayOfWeek: dayOfWeek,
            workoutType: type,
            title: title,
            description: description,
            duration: duration,
            distance: distance,
            targetPace: targetPace,
            exercises: exercises,
            isCompleted: false,
            completedActivityId: nil
        )
    }

    // MARK: - Helpers

    /// Get the Sunday of the current week
    static func currentWeekSunday() -> Date {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        // weekday: 1 = Sunday, 2 = Monday, etc.
        let daysToSubtract = weekday - 1
        return calendar.safeDate(byAdding: .day, value: -daysToSubtract, to: calendar.startOfDay(for: today))
    }

    /// Get dates for all days in the current week (Sunday to Saturday)
    static func currentWeekDates() -> [Date] {
        let sunday = currentWeekSunday()
        let calendar = Calendar.current
        return (0..<7).map { calendar.safeDate(byAdding: .day, value: $0, to: sunday) }
    }
}

// MARK: - Errors

enum TrainingPlanError: LocalizedError {
    case invalidResponse
    case generationFailed(String)
    case httpError(Int)
    case noPlanFound
    case missingAthleteId
    case cachePersistenceFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .generationFailed(let message):
            return "Failed to generate plan: \(message)"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .noPlanFound:
            return "No training plan found for this week"
        case .missingAthleteId:
            return "A positive athlete ID is required to generate a training plan."
        case .cachePersistenceFailed:
            return "Failed to persist the generated training plan"
        }
    }
}

private extension PlanRegenerationScope {
    var isCurrentWeek: Bool {
        switch self {
        case .initialCurrentWeek, .remainingCurrentWeek: return true
        case .nextWeek: return false
        }
    }
}
