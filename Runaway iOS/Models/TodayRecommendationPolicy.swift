import Foundation

enum TodayTrainingDirective: Equatable {
    case recover
    case reduceIntensity
    case proceed
    case unknown
}

struct TodayRecommendation: Equatable {
    let directive: TodayTrainingDirective
    let status: String
    let title: String
    let detail: String
    let systemImage: String
    let workoutType: WorkoutType?
    let reason: String?
    let schedulingReason: SchedulingReason?
    let adjustment: TodayWorkoutAdjustment

    init(
        directive: TodayTrainingDirective,
        status: String,
        title: String,
        detail: String,
        systemImage: String,
        workoutType: WorkoutType? = nil,
        reason: String? = nil,
        schedulingReason: SchedulingReason? = nil,
        adjustment: TodayWorkoutAdjustment = .keepPlan
    ) {
        self.directive = directive
        self.status = status
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.workoutType = workoutType
        self.reason = reason
        self.schedulingReason = schedulingReason
        self.adjustment = adjustment
    }

    var badgeTitle: String {
        workoutType?.displayName ?? status
    }
}

struct TodayRecommendationContext {
    let recentCompletedWorkouts: [DailyWorkout]
    let schedulingContext: SchedulingDayContext
}

enum TodayRecommendationAccent: Equatable {
    case runningPrimary
    case aerobic
    case recovery
    case workout(WorkoutType)
}

struct TodayRecommendationPresentation: Equatable {
    let badgeText: String
    let title: String
    let reason: String?
    let systemImage: String
    let accent: TodayRecommendationAccent

    init(recommendation: TodayRecommendation) {
        badgeText = recommendation.workoutType?.displayName ?? recommendation.status
        title = recommendation.title
        reason = recommendation.reason
        systemImage = recommendation.systemImage

        switch recommendation.workoutType {
        case .easyRun, .recoveryRun, .longRun, .tempoRun, .intervalRun, .hillRun:
            accent = .runningPrimary
        case .cycling, .swimming, .crossTraining:
            accent = .aerobic
        case .rest, .yoga, .walking, .stretchMobility:
            accent = .recovery
        case .some(let workoutType):
            accent = .workout(workoutType)
        case .none:
            accent = .recovery
        }
    }
}

enum TodayRecommendationContextBuilder {
    static func build(
        date: Date,
        profile: TrainingProfile,
        plannedWorkout: DailyWorkout?,
        planWorkouts: [DailyWorkout],
        activities: [Activity],
        readinessScore: Int?,
        calendar: Calendar = .current
    ) -> TodayRecommendationContext {
        let today = calendar.startOfDay(for: date)
        let recentStart = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today

        let completedPlanWorkouts = planWorkouts.filter {
            $0.isCompleted && $0.date >= recentStart && $0.date < today
        }
        let recordedWorkouts = activities.compactMap { activity -> DailyWorkout? in
            guard let timestamp = activity.activity_date ?? activity.start_date else { return nil }
            let activityDate = Date(timeIntervalSince1970: timestamp)
            guard activityDate >= recentStart,
                  activityDate < today,
                  let workoutType = workoutType(for: activity) else {
                return nil
            }

            return DailyWorkout(
                id: "recorded-\(activity.id)",
                date: activityDate,
                dayOfWeek: DayOfWeek.from(date: activityDate),
                workoutType: workoutType,
                title: activity.name ?? workoutType.displayName,
                description: "Recorded activity",
                duration: activity.elapsed_time.map { max(0, Int($0 / 60)) },
                distance: activity.distance.map { $0 / 1_609.344 },
                targetPace: nil,
                exercises: nil,
                isCompleted: true,
                completedActivityId: activity.id
            )
        }

        var completedBySession: [String: DailyWorkout] = [:]
        for workout in completedPlanWorkouts {
            completedBySession[sessionKey(for: workout, calendar: calendar)] = workout
        }
        for workout in recordedWorkouts {
            let key = sessionKey(for: workout, calendar: calendar)
            if let plannedWorkout = completedBySession[key] {
                completedBySession[key] = preferredClassification(
                    plannedWorkout: plannedWorkout,
                    recordedWorkout: workout
                )
            } else {
                completedBySession[key] = workout
            }
        }
        let recentCompleted = completedBySession.values.sorted {
            if $0.date == $1.date { return $0.id < $1.id }
            return $0.date < $1.date
        }

        let incompleteAssignments = planWorkouts.filter {
            !$0.isCompleted && !calendar.isDate($0.date, inSameDayAs: date)
        }.map(\.workoutType)
        let assignedWorkoutTypes = incompleteAssignments + recentCompleted.map(\.workoutType)
        let previousWorkout = recentCompleted.last(where: {
            calendar.isDate($0.date, inSameDayAs: yesterday)
        })?.workoutType ?? planWorkouts.last(where: {
            calendar.isDate($0.date, inSameDayAs: yesterday)
        })?.workoutType
        let nextWorkout = planWorkouts.first(where: {
            calendar.isDate($0.date, inSameDayAs: tomorrow)
        })?.workoutType

        return TodayRecommendationContext(
            recentCompletedWorkouts: recentCompleted,
            schedulingContext: SchedulingDayContext(
                date: date,
                weekday: DayOfWeek.from(date: date),
                profile: profile,
                plannedOrFixedWorkout: plannedWorkout?.workoutType,
                previousWorkout: previousWorkout,
                nextWorkout: nextWorkout,
                readiness: (readinessScore ?? 100) < 50 ? .low : .normal,
                assignedWorkoutTypes: assignedWorkoutTypes,
                isCompletedProtected: false,
                isUnavailable: profile.unavailableWeekdays.contains(DayOfWeek.from(date: date).calendarWeekday),
                isTaperProtected: false
            )
        )
    }

    private static func sessionKey(for workout: DailyWorkout, calendar: Calendar) -> String {
        if let activityID = workout.completedActivityId {
            return "activity:\(activityID)"
        }
        return "workout:\(calendar.startOfDay(for: workout.date).timeIntervalSince1970):\(workout.id)"
    }

    private static func preferredClassification(
        plannedWorkout: DailyWorkout,
        recordedWorkout: DailyWorkout
    ) -> DailyWorkout {
        let plannedSpecificity = classificationSpecificity(of: plannedWorkout.workoutType)
        let recordedSpecificity = classificationSpecificity(of: recordedWorkout.workoutType)
        let recordedWinsNonGenericTie = recordedSpecificity == plannedSpecificity
            && recordedSpecificity > 1
        return recordedSpecificity > plannedSpecificity || recordedWinsNonGenericTie
            ? recordedWorkout
            : plannedWorkout
    }

    private static func classificationSpecificity(of workoutType: WorkoutType) -> Int {
        switch workoutType {
        case .longRun, .tempoRun, .intervalRun, .hillRun:
            return 4
        case .recoveryRun, .upperBody, .lowerBody, .fullBody:
            return 3
        case .cycling, .swimming, .walking, .hiking, .yoga, .stretchMobility, .strengthTraining:
            return 2
        case .easyRun, .crossTraining:
            return 1
        case .rest:
            return 0
        }
    }

    private static func workoutType(for activity: Activity) -> WorkoutType? {
        let description = [activity.name, activity.type]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        if description.contains("long run") { return .longRun }
        if description.contains("run") { return .easyRun }
        if description.contains("ride") || description.contains("cycl") || description.contains("bike") { return .cycling }
        if description.contains("swim") { return .swimming }
        if description.contains("walk") { return .walking }
        if description.contains("hike") { return .hiking }
        if description.contains("yoga") { return .yoga }
        if description.contains("stretch") || description.contains("mobility") { return .stretchMobility }
        if description.contains("strength") || description.contains("weight") { return .strengthTraining }
        return nil
    }
}

enum TodayWorkoutAdjustment: Equatable {
    case recoveryDay
    case easierWorkout
    case chosenWorkout(WorkoutType)
    case keepPlan
}

struct TodayWorkoutAdjustmentResult {
    let plan: WeeklyTrainingPlan
    let originalWorkout: DailyWorkout
    let updatedWorkout: DailyWorkout
    let receiptTitle: String
    let receiptDetail: String
}

enum TodayRecommendationPolicy {
    typealias RemainingWeekRegenerator = (
        WeeklyTrainingPlan,
        TrainingProfile
    ) async throws -> WeeklyTrainingPlan

    static func canChooseTodaysTraining(
        plannedWorkout: DailyWorkout?,
        hasCompletedActivity: Bool
    ) -> Bool {
        plannedWorkout != nil && !hasCompletedActivity
    }

    static func workoutAlternatives(
        profile: TrainingProfile,
        readinessScore: Int?
    ) -> [WorkoutType] {
        let score = readinessScore ?? 100
        let ordered = profile.activities
            .filter { $0.sessionsPerWeek > 0 }
            .sorted {
                let lhs = rolePriority($0.role)
                let rhs = rolePriority($1.role)
                return lhs == rhs ? $0.activity.rawValue < $1.activity.rawValue : lhs < rhs
            }
            .map { preference -> WorkoutType in
                switch preference.activity {
                case .running: return score < 70 ? .recoveryRun : .easyRun
                case .strength: return .upperBody
                case .cycling: return .cycling
                case .swimming: return .swimming
                case .walking: return .walking
                case .hiking: return .hiking
                case .mobility: return .stretchMobility
                }
            }

        let readinessSafe: [WorkoutType]
        if score < 50 {
            readinessSafe = ordered.filter { $0.isRecoveryCompatible }
        } else if score < 70 {
            readinessSafe = ordered.filter {
                !$0.isHighIntensity
                    && (!$0.isLowerBodyDemanding || $0.isRecoveryCompatible)
            }
        } else {
            readinessSafe = ordered
        }
        return readinessSafe.uniqued()
    }

    static func recommendation(readinessScore: Int?) -> TodayRecommendation {
        guard let readinessScore else {
            return TodayRecommendation(
                directive: .unknown,
                status: "Check In",
                title: "Check Your Readiness",
                detail: "Calculate readiness before choosing today's effort.",
                systemImage: "heart.text.square"
            )
        }

        switch readinessScore {
        case ..<50:
            return TodayRecommendation(
                directive: .recover,
                status: "Recovery",
                title: "Recovery Day",
                detail: "Your readiness is low. Rest or choose very light movement today.",
                systemImage: "moon.zzz.fill"
            )
        case 50..<70:
            return TodayRecommendation(
                directive: .reduceIntensity,
                status: "Adjusted",
                title: "Keep It Easy",
                detail: "Keep today's effort conversational and reduce intensity.",
                systemImage: "figure.walk"
            )
        default:
            return TodayRecommendation(
                directive: .proceed,
                status: "Ready",
                title: "Follow Today's Plan",
                detail: "Your readiness supports the planned training.",
                systemImage: "figure.run"
            )
        }
    }

    static func recommendation(
        plannedWorkout: DailyWorkout?,
        profile: TrainingProfile,
        recentCompletedWorkouts: [DailyWorkout],
        readinessScore: Int?,
        schedulingContext: SchedulingDayContext
    ) -> TodayRecommendation {
        let readinessRecommendation = recommendation(readinessScore: readinessScore)
        let adjustment = adjustment(for: readinessRecommendation.directive)

        if let plannedWorkout, isUserSelectedToday(plannedWorkout) {
            return TodayRecommendation(
                directive: .proceed,
                status: "Your Choice",
                title: plannedWorkout.title,
                detail: "You chose this session for today. Future workouts were adapted around it.",
                systemImage: plannedWorkout.workoutType.icon,
                workoutType: plannedWorkout.workoutType,
                reason: "Your selection is locked for today.",
                schedulingReason: .requiredPrimary,
                adjustment: .keepPlan
            )
        }

        if let plannedWorkout,
           readinessRecommendation.directive == .proceed,
           isSelected(plannedWorkout.workoutType, by: profile) {
            return TodayRecommendation(
                directive: readinessRecommendation.directive,
                status: readinessRecommendation.status,
                title: plannedWorkout.title,
                detail: readinessRecommendation.detail,
                systemImage: plannedWorkout.workoutType.icon,
                workoutType: plannedWorkout.workoutType,
                reason: "Scheduled in your plan.",
                schedulingReason: .requiredPrimary,
                adjustment: .keepPlan
            )
        }

        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: schedulingContext.date)
        let previousWorkout = yesterday.flatMap { previousDate in
            recentCompletedWorkouts
                .filter { calendar.isDate($0.date, inSameDayAs: previousDate) }
                .sorted { lhs, rhs in
                    if lhs.date != rhs.date { return lhs.date < rhs.date }
                    return lhs.id < rhs.id
                }
                .last?
                .workoutType
        } ?? schedulingContext.previousWorkout

        let selectionReadiness: SchedulingReadiness = switch readinessRecommendation.directive {
        case .recover, .reduceIntensity: .low
        case .proceed, .unknown: schedulingContext.readiness
        }
        let context = SchedulingDayContext(
            date: schedulingContext.date,
            weekday: schedulingContext.weekday,
            profile: profile,
            plannedOrFixedWorkout: nil,
            previousWorkout: previousWorkout,
            nextWorkout: schedulingContext.nextWorkout,
            readiness: selectionReadiness,
            assignedWorkoutTypes: schedulingContext.assignedWorkoutTypes,
            isCompletedProtected: false,
            isUnavailable: schedulingContext.isUnavailable,
            isTaperProtected: schedulingContext.isTaperProtected
        )

        var candidates = ComplementarySchedulingPolicy.rankedCandidates(for: context)
        if readinessRecommendation.directive == .recover {
            candidates = candidates.filter { candidate in
                candidate.workoutType == .rest
                    || (candidate.workoutType.isRecoveryCompatible
                        && !candidate.workoutType.isHighIntensity
                        && !candidate.workoutType.isLowerBodyDemanding)
            }
        } else if readinessRecommendation.directive == .reduceIntensity, let plannedWorkout {
            candidates = candidates.filter { candidate in
                candidate.workoutType != plannedWorkout.workoutType
                    && candidate.workoutType.loadClass < plannedWorkout.workoutType.loadClass
            }
        }

        let candidate = candidates.first ?? WorkoutCandidate(
            workoutType: .rest,
            score: 0,
            reason: readinessRecommendation.directive == .recover ? .supportsRecovery : .restRequired
        )

        return TodayRecommendation(
            directive: readinessRecommendation.directive,
            status: readinessRecommendation.status,
            title: candidate.workoutType.displayName,
            detail: readinessRecommendation.detail,
            systemImage: candidate.workoutType.icon,
            workoutType: candidate.workoutType,
            reason: placementReason(for: candidate.reason),
            schedulingReason: candidate.reason,
            adjustment: adjustment
        )
    }

    private static func adjustment(for directive: TodayTrainingDirective) -> TodayWorkoutAdjustment {
        switch directive {
        case .recover: return .recoveryDay
        case .reduceIntensity: return .easierWorkout
        case .proceed, .unknown: return .keepPlan
        }
    }

    private static func isSelected(_ workoutType: WorkoutType, by profile: TrainingProfile) -> Bool {
        guard workoutType != .rest else { return true }
        guard let activity = workoutType.activity,
              let preference = profile.preference(for: activity) else {
            return false
        }
        return preference.sessionsPerWeek > 0
    }

    private static func isUserSelectedToday(_ workout: DailyWorkout) -> Bool {
        workout.description.hasPrefix("Adjusted for today's readiness")
            || workout.description.hasPrefix("Chosen for today")
    }

    private static func placementReason(for reason: SchedulingReason) -> String? {
        switch reason {
        case .requiredPrimary:
            return "Scheduled in your plan."
        case .profileFrequency:
            return "Selected to support your weekly training mix."
        case .preservesLegRecovery:
            return "Placed after yesterday's long run to preserve leg recovery."
        case .supportsRecovery:
            return "Selected to support recovery on a low-readiness day."
        case .fillsAvailableDay:
            return "Best fit for today's available training slot."
        case .restRequired:
            return "Rest is the best profile-valid choice today."
        case .unavailableDay, .completedWorkoutProtected, .unselectedActivity,
             .lowerBodyRecoveryConflict, .highIntensityReadinessConflict,
             .trainingDayLimit, .taperProtectedLoad:
            return nil
        }
    }

    static func applying(
        _ adjustment: TodayWorkoutAdjustment,
        to plan: WeeklyTrainingPlan,
        on date: Date = Date(),
        readinessScore: Int?
    ) -> TodayWorkoutAdjustmentResult? {
        guard adjustment != .keepPlan else { return nil }

        let calendar = Calendar.current
        var workouts = plan.workouts
        let existingWorkoutIndex = workouts.firstIndex(where: {
            calendar.isDate($0.date, inSameDayAs: date)
        })
        let workoutIndex: Int
        let original: DailyWorkout
        if let existingWorkoutIndex {
            workoutIndex = existingWorkoutIndex
            original = workouts[existingWorkoutIndex]
        } else {
            let generatedType: WorkoutType
            switch adjustment {
            case .recoveryDay:
                generatedType = .easyRun
            case .easierWorkout:
                generatedType = .easyRun
            case .chosenWorkout(let workoutType):
                generatedType = workoutType
            case .keepPlan:
                return nil
            }
            original = DailyWorkout(
                id: "today-\(Int(calendar.startOfDay(for: date).timeIntervalSince1970))",
                date: calendar.startOfDay(for: date),
                dayOfWeek: DayOfWeek.from(date: date),
                workoutType: generatedType,
                title: generatedType.displayName,
                description: "Generated recommendation for today.",
                duration: nil,
                distance: nil,
                targetPace: nil,
                exercises: nil,
                isCompleted: false,
                completedActivityId: nil
            )
            workouts.append(original)
            workoutIndex = workouts.count - 1
        }

        let updated: DailyWorkout
        switch adjustment {
        case .recoveryDay:
            guard original.workoutType != .rest else { return nil }
            updated = DailyWorkout(
                id: original.id,
                date: original.date,
                dayOfWeek: original.dayOfWeek,
                workoutType: .rest,
                title: "Recovery Day (Adjusted)",
                description: "Adjusted for today's readiness. Rest, hydrate, and resume the plan when you feel recovered.",
                duration: nil,
                distance: nil,
                targetPace: nil,
                exercises: nil,
                isCompleted: original.isCompleted,
                completedActivityId: original.completedActivityId
            )
        case .easierWorkout:
            guard original.workoutType != .rest else { return nil }
            if original.workoutType.isRunning {
                updated = DailyWorkout(
                    id: original.id,
                    date: original.date,
                    dayOfWeek: original.dayOfWeek,
                    workoutType: .recoveryRun,
                    title: "Easy Run (Adjusted)",
                    description: "Adjusted for today's readiness. Keep the effort conversational and stop if recovery feels incomplete.",
                    duration: original.duration.map { max(15, Int((Double($0) * 0.75).rounded())) },
                    distance: original.distance.map { $0 * 0.65 },
                    targetPace: "Conversational effort",
                    exercises: nil,
                    isCompleted: original.isCompleted,
                    completedActivityId: original.completedActivityId
                )
            } else {
                updated = DailyWorkout(
                    id: original.id,
                    date: original.date,
                    dayOfWeek: original.dayOfWeek,
                    workoutType: .stretchMobility,
                    title: "Mobility (Adjusted)",
                    description: "Adjusted for today's readiness. Replace the planned session with gentle mobility and recovery work.",
                    duration: original.duration.map { max(15, Int((Double($0) * 0.6).rounded())) } ?? 20,
                    distance: nil,
                    targetPace: nil,
                    exercises: nil,
                    isCompleted: original.isCompleted,
                    completedActivityId: original.completedActivityId
                )
            }
        case .chosenWorkout(let workoutType):
            guard workoutType != .rest else { return nil }
            let template = plan.workouts.first {
                $0.id != original.id
                    && $0.workoutType.activity == workoutType.activity
                    && $0.workoutType != .rest
            }
            let defaultDuration: Int
            switch workoutType {
            case .recoveryRun, .easyRun, .walking, .stretchMobility, .yoga:
                defaultDuration = 30
            case .upperBody, .strengthTraining, .fullBody, .lowerBody:
                defaultDuration = 40
            default:
                defaultDuration = 40
            }
            updated = DailyWorkout(
                id: original.id,
                date: original.date,
                dayOfWeek: original.dayOfWeek,
                workoutType: workoutType,
                title: workoutType.displayName,
                description: "Chosen for today. The remaining week will adapt around this session.",
                duration: template?.duration ?? defaultDuration,
                distance: workoutType.isRunning ? (template?.distance ?? 3) : nil,
                targetPace: workoutType.isRunning
                    ? (template?.targetPace ?? "Conversational effort")
                    : nil,
                exercises: workoutType.isStrength ? template?.exercises : nil,
                isCompleted: original.isCompleted,
                completedActivityId: original.completedActivityId
            )
        case .keepPlan:
            return nil
        }

        workouts[workoutIndex] = updated
        workouts.sort { $0.date < $1.date }
        let updatedPlan = WeeklyTrainingPlan(
            id: plan.id,
            athleteId: plan.athleteId,
            weekStartDate: plan.weekStartDate,
            weekEndDate: plan.weekEndDate,
            workouts: workouts,
            weekNumber: plan.weekNumber,
            totalMileage: workouts.filter { $0.workoutType.isRunning }.compactMap(\.distance).reduce(0, +),
            focusArea: plan.focusArea,
            notes: plan.notes,
            generatedAt: Date(),
            goalId: plan.goalId
        )

        let scoreContext = readinessScore.map { "Readiness was \($0), so " } ?? "Based on today's readiness, "
        let changeDescription: String
        if adjustment == .recoveryDay {
            changeDescription = "\(original.title) was replaced with recovery."
        } else if case .chosenWorkout = adjustment {
            changeDescription = "\(updated.title) was added for today."
        } else if let oldDistance = original.distance, let newDistance = updated.distance {
            changeDescription = "\(original.title) changed from \(String(format: "%.1f", oldDistance)) to \(String(format: "%.1f", newDistance)) mi at an easy effort."
        } else {
            changeDescription = "\(original.title) was replaced with \(updated.title.lowercased())."
        }

        return TodayWorkoutAdjustmentResult(
            plan: updatedPlan,
            originalWorkout: original,
            updatedWorkout: updated,
            receiptTitle: adjustment == .recoveryDay
                ? "Recovery added"
                : (adjustment == .easierWorkout ? "Today's effort reduced" : "Workout added"),
            receiptDetail: scoreContext + changeDescription.prefix(1).lowercased() + changeDescription.dropFirst()
        )
    }

    static func adaptingRemainingWeek(
        _ result: TodayWorkoutAdjustmentResult,
        profile: TrainingProfile,
        on date: Date = Date(),
        regenerate: RemainingWeekRegenerator = { plan, profile in
            try await TrainingPlanService.generatePlan(
                profile: profile,
                scope: .remainingCurrentWeek,
                existingPlan: plan
            )
        }
    ) async throws -> TodayWorkoutAdjustmentResult {
        let adaptedPlan = try await regenerate(result.plan, profile)
        let changedDays = changedFutureDayNames(
            before: result.plan,
            after: adaptedPlan,
            after: date
        )
        let adaptationDetail = changedDays.isEmpty
            ? "The rest of the week already fits this choice."
            : "Rebalanced \(changedDays.joined(separator: ", ")) to keep the week on track."
        let calendar = Calendar.current
        let adaptedWorkout = adaptedPlan.workouts.first {
            calendar.isDate($0.date, inSameDayAs: date)
        } ?? result.updatedWorkout

        return TodayWorkoutAdjustmentResult(
            plan: adaptedPlan,
            originalWorkout: result.originalWorkout,
            updatedWorkout: adaptedWorkout,
            receiptTitle: result.receiptTitle,
            receiptDetail: "\(result.receiptDetail) \(adaptationDetail)"
        )
    }

    private static func rolePriority(_ role: TrainingActivityRole) -> Int {
        switch role {
        case .primary: return 0
        case .supporting: return 1
        case .optional: return 2
        }
    }

    private static func changedFutureDayNames(
        before: WeeklyTrainingPlan,
        after: WeeklyTrainingPlan,
        after date: Date
    ) -> [String] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let previous = Dictionary(uniqueKeysWithValues: before.workouts.map {
            (calendar.startOfDay(for: $0.date), $0)
        })

        return after.workouts
            .filter { calendar.startOfDay(for: $0.date) > start }
            .filter { workout in
                guard let original = previous[calendar.startOfDay(for: workout.date)] else { return true }
                return original.workoutType != workout.workoutType
                    || original.distance != workout.distance
                    || original.duration != workout.duration
            }
            .map { $0.dayOfWeek.rawValue.capitalized }
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
