import Foundation

enum SchedulingReason: String, Equatable, Sendable {
    case requiredPrimary
    case profileFrequency
    case preservesLegRecovery
    case supportsRecovery
    case fillsAvailableDay
    case restRequired
    case unavailableDay
    case completedWorkoutProtected
    case unselectedActivity
    case lowerBodyRecoveryConflict
    case highIntensityReadinessConflict
    case trainingDayLimit
    case taperProtectedLoad

    var coachingDescription: String {
        switch self {
        case .requiredPrimary:
            "Scheduled to move your primary goal forward."
        case .profileFrequency:
            "Selected to support your weekly training mix."
        case .preservesLegRecovery:
            "Placed here to preserve leg recovery around harder running."
        case .supportsRecovery:
            "Selected to support recovery while keeping your routine moving."
        case .fillsAvailableDay:
            "Matched to an available training day in your week."
        case .restRequired:
            "Rest is scheduled here to protect recovery and future quality work."
        case .unavailableDay:
            "No workout is scheduled because this day is unavailable."
        case .completedWorkoutProtected:
            "Kept because completed training should not be rewritten."
        case .unselectedActivity:
            "Excluded because this activity is not in your training mix."
        case .lowerBodyRecoveryConflict:
            "Avoided here to protect lower-body recovery."
        case .highIntensityReadinessConflict:
            "Avoided because today's readiness does not support high intensity."
        case .trainingDayLimit:
            "Limited to match the number of training days in your profile."
        case .taperProtectedLoad:
            "Kept lighter to protect your taper."
        }
    }
}

enum SchedulingReadiness: String, Equatable, Sendable {
    case normal
    case low
}

struct WorkoutCandidate: Equatable, Sendable {
    let workoutType: WorkoutType
    let score: Int
    let reason: SchedulingReason
}

struct WorkoutCandidateEvaluation: Equatable, Sendable {
    let workoutType: WorkoutType
    let candidate: WorkoutCandidate?
    let rejectionReason: SchedulingReason?
}

enum SchedulingDiagnostic: Equatable, Sendable {
    case invalidContext
    case anchorOutsideContext(assignmentID: String)
    case duplicateFixedSlot(assignmentID: String)
    case unavoidableCompletedConflict(assignmentID: String, reason: SchedulingReason)
    case rejectedFixedWorkout(assignmentID: String, reason: SchedulingReason)
}

struct SchedulingDayContext: Equatable, Sendable {
    let date: Date
    let weekday: DayOfWeek
    let profile: TrainingProfile
    let plannedOrFixedWorkout: WorkoutType?
    let previousWorkout: WorkoutType?
    let nextWorkout: WorkoutType?
    let readiness: SchedulingReadiness
    let assignedWorkoutTypes: [WorkoutType]
    let isCompletedProtected: Bool
    let isUnavailable: Bool
    let isTaperProtected: Bool
}

struct SchedulingContext: Equatable, Sendable {
    let dates: [Date]
    let profile: TrainingProfile
    let fixedPrimaryWorkouts: [ScheduledWorkoutAssignment]
    let completedWorkouts: [ScheduledWorkoutAssignment]
    let unavailableWeekdays: Set<Int>
    let readinessByWeekday: [DayOfWeek: SchedulingReadiness]
    let taperProtectedWeekdays: Set<DayOfWeek>
}

struct ScheduledWorkoutAssignment: Equatable, Sendable {
    let id: String
    let weekday: DayOfWeek
    let date: Date
    let workoutType: WorkoutType
    let reason: SchedulingReason
    let isCompleted: Bool
    let isFixed: Bool
}

enum ComplementarySchedulingPolicy {
    private static let requiredPrimaryScore = 1_000
    private static let unmetFrequencyScore = 300
    private static let recoveryFitScore = 150
    private static let preferredAdjacencyScore = 100
    private static let duplicateCategoryPenalty = -120
    private static let highLoadReadinessPenalty = -500

    static func rankedCandidates(for context: SchedulingDayContext) -> [WorkoutCandidate] {
        let candidateWorkoutTypes: [WorkoutType]
        if let fixedWorkout = context.plannedOrFixedWorkout {
            candidateWorkoutTypes = [fixedWorkout]
        } else {
            candidateWorkoutTypes = context.profile.activities
            .filter { $0.sessionsPerWeek > 0 }
            .flatMap { workoutTypes(for: $0.activity) }
                + [.rest]
        }

        var seen = Set<WorkoutType>()
        let candidates = candidateWorkoutTypes
            .filter { seen.insert($0).inserted }
            .compactMap { evaluation(of: $0, for: context).candidate }

        return candidates.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.workoutType.rawValue < $1.workoutType.rawValue
        }
    }

    static func evaluation(
        of workoutType: WorkoutType,
        for context: SchedulingDayContext
    ) -> WorkoutCandidateEvaluation {
        func rejected(_ reason: SchedulingReason) -> WorkoutCandidateEvaluation {
            WorkoutCandidateEvaluation(
                workoutType: workoutType,
                candidate: nil,
                rejectionReason: reason
            )
        }

        if context.isCompletedProtected { return rejected(.completedWorkoutProtected) }
        if context.isUnavailable { return rejected(.unavailableDay) }
        if let fixedWorkout = context.plannedOrFixedWorkout {
            guard workoutType == fixedWorkout else { return rejected(.requiredPrimary) }
            guard workoutType == .rest || isSelected(workoutType, by: context.profile) else {
                return rejected(.unselectedActivity)
            }
            if violatesLegRecovery(
                workoutType,
                previous: context.previousWorkout,
                next: context.nextWorkout
            ) {
                return rejected(.lowerBodyRecoveryConflict)
            }
            let candidate = WorkoutCandidate(
                workoutType: workoutType,
                score: requiredPrimaryScore,
                reason: .requiredPrimary
            )
            return WorkoutCandidateEvaluation(
                workoutType: workoutType,
                candidate: candidate,
                rejectionReason: nil
            )
        }

        if workoutType == .rest {
            let candidate = WorkoutCandidate(
                workoutType: .rest,
                score: context.readiness == .low ? recoveryFitScore : 0,
                reason: context.readiness == .low ? .supportsRecovery : .restRequired
            )
            return WorkoutCandidateEvaluation(
                workoutType: workoutType,
                candidate: candidate,
                rejectionReason: nil
            )
        }

        guard let activity = workoutType.activity,
              let preference = context.profile.preference(for: activity),
              preference.sessionsPerWeek > 0 else {
            return rejected(.unselectedActivity)
        }
        if violatesLegRecovery(
            workoutType,
            previous: context.previousWorkout,
            next: context.nextWorkout
        ) {
            return rejected(.lowerBodyRecoveryConflict)
        }
        if context.isTaperProtected && workoutType.loadClass >= .moderate {
            return rejected(.taperProtectedLoad)
        }
        if context.readiness == .low && workoutType.isHighIntensity {
            return rejected(.highIntensityReadinessConflict)
        }

        let assignedForActivity = context.assignedWorkoutTypes.reduce(into: 0) { count, assigned in
            if assigned.activity == activity { count += 1 }
        }
        var score = assignedForActivity < preference.sessionsPerWeek ? unmetFrequencyScore : 0
        var reason: SchedulingReason = assignedForActivity < preference.sessionsPerWeek
            ? .profileFrequency
            : .fillsAvailableDay

        if context.assignedWorkoutTypes.contains(where: { $0.activity == activity }) {
            score += duplicateCategoryPenalty
        }
        if context.readiness == .low {
            if workoutType.loadClass == .high {
                score += highLoadReadinessPenalty
            }
            if workoutType.isRecoveryCompatible {
                score += recoveryFitScore
                reason = .supportsRecovery
            }
        }
        if workoutType == .upperBody && context.previousWorkout == .longRun {
            score += preferredAdjacencyScore
            reason = .preservesLegRecovery
        }

        let candidate = WorkoutCandidate(workoutType: workoutType, score: score, reason: reason)
        return WorkoutCandidateEvaluation(
            workoutType: workoutType,
            candidate: candidate,
            rejectionReason: nil
        )
    }

    static func diagnostics(for context: SchedulingContext) -> [SchedulingDiagnostic] {
        prepareAnchors(context: context).diagnostics
    }

    static func buildWeeklyAssignments(context: SchedulingContext) -> [ScheduledWorkoutAssignment] {
        let calendar = Calendar.current
        let preparation = prepareAnchors(context: context)
        var assignments = preparation.assignments
        var occupiedDays = preparation.occupiedDays
        var activeTrainingDays = preparation.activeTrainingDays
        guard !preparation.diagnostics.contains(.invalidContext) else {
            return assignments.sorted(by: assignmentOrder)
        }

        let dates = context.dates.sorted()
        let unavailable = context.unavailableWeekdays.union(context.profile.unavailableWeekdays)

        for date in dates {
            guard activeTrainingDays.count < context.profile.trainingDaysPerWeek else { break }

            let day = calendar.startOfDay(for: date)
            let weekday = DayOfWeek.from(date: date)
            guard !occupiedDays.contains(day),
                  !unavailable.contains(weekday.calendarWeekday) else {
                continue
            }

            let previousDay = calendar.date(byAdding: .day, value: -1, to: day)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day)
            let dayContext = SchedulingDayContext(
                date: date,
                weekday: weekday,
                profile: context.profile,
                plannedOrFixedWorkout: nil,
                previousWorkout: previousDay.flatMap { adjacentWorkout(on: $0, in: assignments) },
                nextWorkout: nextDay.flatMap { adjacentWorkout(on: $0, in: assignments) },
                readiness: context.readinessByWeekday[weekday] ?? .normal,
                assignedWorkoutTypes: assignments.map(\.workoutType),
                isCompletedProtected: false,
                isUnavailable: false,
                isTaperProtected: context.taperProtectedWeekdays.contains(weekday)
            )
            guard let candidate = weeklyCandidate(
                from: rankedCandidates(for: dayContext),
                profile: context.profile,
                assignedWorkoutTypes: assignments.map(\.workoutType)
            ),
                  candidate.workoutType != .rest,
                  candidate.score > 0 else {
                continue
            }

            assignments.append(ScheduledWorkoutAssignment(
                id: "scheduled-\(weekday.rawValue)-\(candidate.workoutType.rawValue)",
                weekday: weekday,
                date: date,
                workoutType: candidate.workoutType,
                reason: candidate.reason,
                isCompleted: false,
                isFixed: false
            ))
            occupiedDays.insert(day)
            activeTrainingDays.insert(day)
        }

        return assignments.sorted(by: assignmentOrder)
    }

    private static func weeklyCandidate(
        from candidates: [WorkoutCandidate],
        profile: TrainingProfile,
        assignedWorkoutTypes: [WorkoutType]
    ) -> WorkoutCandidate? {
        for role in [TrainingActivityRole.primary, .supporting, .optional] {
            if let candidate = candidates.first(where: { candidate in
                guard let activity = candidate.workoutType.activity,
                      let preference = profile.preference(for: activity),
                      preference.role == role else {
                    return false
                }
                let assigned = assignedWorkoutTypes.filter { $0.activity == activity }.count
                return assigned < preference.sessionsPerWeek
            }) {
                return candidate
            }
        }
        return candidates.first
    }

    private static func workoutTypes(for activity: TrainingActivity) -> [WorkoutType] {
        switch activity {
        case .running:
            return [.easyRun, .longRun, .tempoRun, .intervalRun, .hillRun, .recoveryRun]
        case .strength:
            return [.upperBody, .lowerBody, .fullBody]
        case .cycling:
            return [.cycling]
        case .swimming:
            return [.swimming]
        case .walking:
            return [.walking]
        case .hiking:
            return [.hiking]
        case .mobility:
            return [.stretchMobility, .yoga]
        }
    }

    private static func violatesLegRecovery(
        _ workoutType: WorkoutType,
        previous: WorkoutType?,
        next: WorkoutType?
    ) -> Bool {
        [previous, next]
            .compactMap { $0 }
            .contains { adjacencyConflict(workoutType, $0) }
    }

    private static func isProtectedRun(_ workoutType: WorkoutType) -> Bool {
        workoutType == .longRun || workoutType.isHighIntensity
    }

    private static func isHeavyStrength(_ workoutType: WorkoutType) -> Bool {
        workoutType == .lowerBody || workoutType == .fullBody
    }

    private static func adjacencyConflict(_ lhs: WorkoutType, _ rhs: WorkoutType) -> Bool {
        (isHeavyStrength(lhs) && isProtectedRun(rhs))
            || (isProtectedRun(lhs) && isHeavyStrength(rhs))
    }

    private struct AnchorPreparation {
        var assignments: [ScheduledWorkoutAssignment]
        var occupiedDays: Set<Date>
        var activeTrainingDays: Set<Date>
        var diagnostics: [SchedulingDiagnostic]
    }

    private static func prepareAnchors(context: SchedulingContext) -> AnchorPreparation {
        let calendar = Calendar.current
        let validDays = Set(context.dates.map { calendar.startOfDay(for: $0) })
        let outsideAnchors = (context.completedWorkouts + context.fixedPrimaryWorkouts)
            .filter { !validDays.contains(calendar.startOfDay(for: $0.date)) }
            .sorted(by: assignmentOrder)
        let outsideDiagnostics = outsideAnchors.map {
            SchedulingDiagnostic.anchorOutsideContext(assignmentID: $0.id)
        }
        let completed = context.completedWorkouts
            .filter { validDays.contains(calendar.startOfDay(for: $0.date)) }
            .sorted(by: assignmentOrder)

        guard isValid(context: context) else {
            return AnchorPreparation(
                assignments: completed,
                occupiedDays: [],
                activeTrainingDays: [],
                diagnostics: [.invalidContext] + outsideDiagnostics
            )
        }

        let unavailable = context.unavailableWeekdays.union(context.profile.unavailableWeekdays)
        var assignments = completed
        var occupiedDays = Set<Date>()
        var activeTrainingDays = Set<Date>()
        var diagnostics = outsideDiagnostics

        for assignment in completed {
            let day = calendar.startOfDay(for: assignment.date)
            let weekday = DayOfWeek.from(date: assignment.date)
            occupiedDays.insert(day)
            if assignment.workoutType != .rest && !activeTrainingDays.contains(day) {
                if activeTrainingDays.count >= context.profile.trainingDaysPerWeek {
                    diagnostics.append(.unavoidableCompletedConflict(
                        assignmentID: assignment.id,
                        reason: .trainingDayLimit
                    ))
                }
                activeTrainingDays.insert(day)
            }
            if unavailable.contains(weekday.calendarWeekday) {
                diagnostics.append(.unavoidableCompletedConflict(
                    assignmentID: assignment.id,
                    reason: .unavailableDay
                ))
            }
            if assignment.workoutType != .rest && !isSelected(assignment.workoutType, by: context.profile) {
                diagnostics.append(.unavoidableCompletedConflict(
                    assignmentID: assignment.id,
                    reason: .unselectedActivity
                ))
            }
            if let previousDay = calendar.date(byAdding: .day, value: -1, to: day),
               let previousWorkout = adjacentWorkout(on: previousDay, in: completed),
               adjacencyConflict(assignment.workoutType, previousWorkout) {
                diagnostics.append(.unavoidableCompletedConflict(
                    assignmentID: assignment.id,
                    reason: .lowerBodyRecoveryConflict
                ))
            }
        }

        let fixed = context.fixedPrimaryWorkouts
            .filter { validDays.contains(calendar.startOfDay(for: $0.date)) }
            .sorted(by: assignmentOrder)
        for assignment in fixed {
            let day = calendar.startOfDay(for: assignment.date)
            let weekday = DayOfWeek.from(date: assignment.date)
            if occupiedDays.contains(day) {
                diagnostics.append(.duplicateFixedSlot(assignmentID: assignment.id))
                continue
            }
            if unavailable.contains(weekday.calendarWeekday) {
                diagnostics.append(.rejectedFixedWorkout(
                    assignmentID: assignment.id,
                    reason: .unavailableDay
                ))
                continue
            }
            if assignment.workoutType != .rest && !isSelected(assignment.workoutType, by: context.profile) {
                diagnostics.append(.rejectedFixedWorkout(
                    assignmentID: assignment.id,
                    reason: .unselectedActivity
                ))
                continue
            }
            if assignment.workoutType != .rest
                && activeTrainingDays.count >= context.profile.trainingDaysPerWeek {
                diagnostics.append(.rejectedFixedWorkout(
                    assignmentID: assignment.id,
                    reason: .trainingDayLimit
                ))
                continue
            }

            let previousDay = calendar.date(byAdding: .day, value: -1, to: day)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day)
            let previous = previousDay.flatMap { adjacentWorkout(on: $0, in: assignments) }
            let next = nextDay.flatMap { adjacentWorkout(on: $0, in: assignments) }
            if violatesLegRecovery(assignment.workoutType, previous: previous, next: next) {
                diagnostics.append(.rejectedFixedWorkout(
                    assignmentID: assignment.id,
                    reason: .lowerBodyRecoveryConflict
                ))
                continue
            }

            assignments.append(assignment)
            occupiedDays.insert(day)
            if assignment.workoutType != .rest {
                activeTrainingDays.insert(day)
            }
        }

        return AnchorPreparation(
            assignments: assignments,
            occupiedDays: occupiedDays,
            activeTrainingDays: activeTrainingDays,
            diagnostics: diagnostics
        )
    }

    private static func isValid(context: SchedulingContext) -> Bool {
        guard context.dates.count == 7 else { return false }
        let calendar = Calendar.current
        let days = Set(context.dates.map { calendar.startOfDay(for: $0) })
        let weekdays = Set(context.dates.map { DayOfWeek.from(date: $0) })
        return days.count == 7 && weekdays.count == 7
    }

    private static func isSelected(_ workoutType: WorkoutType, by profile: TrainingProfile) -> Bool {
        guard let activity = workoutType.activity,
              let preference = profile.preference(for: activity) else {
            return false
        }
        return preference.sessionsPerWeek > 0
    }

    private static func adjacentWorkout(
        on day: Date,
        in assignments: [ScheduledWorkoutAssignment]
    ) -> WorkoutType? {
        let calendar = Calendar.current
        return assignments
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted(by: assignmentOrder)
            .first?
            .workoutType
    }

    private static func assignmentOrder(
        _ lhs: ScheduledWorkoutAssignment,
        _ rhs: ScheduledWorkoutAssignment
    ) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        if lhs.workoutType.rawValue != rhs.workoutType.rawValue {
            return lhs.workoutType.rawValue < rhs.workoutType.rawValue
        }
        return lhs.id < rhs.id
    }
}
