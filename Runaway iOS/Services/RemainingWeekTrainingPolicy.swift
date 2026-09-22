import Foundation

/// Read-only conflict review of tomorrow through Saturday. It does not rewrite
/// a plan or claim future readiness. Inputs must come from one validated account.
enum RemainingWeekTrainingPolicy {
    static let version = "remaining-week-review-v1"
    enum State { case preserved, needsAvailability, unavailable, timeConflict, reviewRecovery, scheduled, open }
    struct DayReview: Identifiable {
        let date: Date
        let title: String
        let state: State
        let reason: String
        var id: Date { date }
    }

    struct RebalancedResult {
        let workouts: [DailyWorkout]
        let changes: [TodayWorkoutDecisionPreview.Change]
        let warnings: [TodayWorkoutDecisionPreview.Warning]
    }

    static func rebalancedPlan(
        replacingTodayWith replacement: DailyWorkout,
        in plan: WeeklyTrainingPlan,
        on date: Date,
        calendar: Calendar = .current
    ) -> RebalancedResult {
        let today = calendar.startOfDay(for: date)
        guard let originalIndex = plan.workouts.firstIndex(where: {
            calendar.isDate($0.date, inSameDayAs: today)
        }) else {
            return RebalancedResult(workouts: plan.workouts, changes: [], warnings: [])
        }
        let original = plan.workouts[originalIndex]
        var workouts = plan.workouts
        var changes: [TodayWorkoutDecisionPreview.Change] = []
        var warnings: [TodayWorkoutDecisionPreview.Warning] = []

        let displacesGoalCriticalRun = original.workoutType == .longRun
            || original.workoutType == .tempoRun
            || original.workoutType == .intervalRun
            || original.workoutType == .hillRun
        if displacesGoalCriticalRun && replacement.workoutType != original.workoutType,
           let destination = workouts.indices.first(where: { index in
               let candidate = workouts[index]
               return candidate.date > today && !candidate.isCompleted
                   && candidate.commitment == nil && candidate.workoutType == .rest
           }) {
            let target = workouts[destination]
            workouts[destination] = movedCopy(original, to: target.date, dayOfWeek: target.dayOfWeek)
            changes.append(.init(
                id: "move-\(original.id)", kind: .moved,
                title: "\(original.title) moves to \(target.dayOfWeek.fullName)",
                detail: "Goal-critical work stays in the week instead of disappearing."
            ))
            warnings.append(.goalCriticalWorkoutMoved)
        }

        workouts[originalIndex] = replacement
        return RebalancedResult(
            workouts: workouts.sorted { $0.date < $1.date },
            changes: changes,
            warnings: warnings
        )
    }

    private static func movedCopy(_ workout: DailyWorkout, to date: Date, dayOfWeek: DayOfWeek) -> DailyWorkout {
        DailyWorkout(
            id: "\(workout.id)-moved-\(Int(date.timeIntervalSince1970))",
            date: date, dayOfWeek: dayOfWeek, workoutType: workout.workoutType,
            title: workout.title, description: workout.description,
            duration: workout.duration, distance: workout.distance,
            targetPace: workout.displayTargetPace, exercises: workout.exercises,
            isCompleted: false, completedActivityId: nil,
            acceptedPrescription: workout.acceptedPrescription,
            acceptedCompletion: nil, commitment: nil
        )
    }

    static func review(workouts: [DailyWorkout], results: [TrainingSessionResult],
                       availability: [TrainingDayAvailability], on date: Date,
                       calendar: Calendar = .current) -> [DayReview] {
        guard date.timeIntervalSince1970.isFinite else { return [] }
        let today = calendar.startOfDay(for: date)
        let remainingDays = 7 - calendar.component(.weekday, from: today)
        guard remainingDays > 0 else { return [] }
        let actual = results.filter { $0.isValid && $0.completedAt <= date && $0.recordedAt <= date }
        return (1...remainingDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return nil }
            let planned = workouts.first { calendar.isDate($0.date, inSameDayAs: day) }
            let title = planned?.title ?? "Unassigned training time"
            let available = availability.first { $0.weekday == calendar.component(.weekday, from: day) }
            let chosen = planned.map {
                $0.description.hasPrefix("Chosen for today") || $0.description.hasPrefix("Adjusted for today's readiness")
            } ?? false
            let protected = chosen || planned?.workoutType == .rest || planned?.isCompleted == true
            func answer(_ state: State, _ reason: String) -> DayReview {
                DayReview(date: day, title: title, state: protected ? .preserved : state,
                    reason: protected ? "Your recorded session, rest day or explicit choice stays unchanged. " + reason : reason)
            }
            if planned?.workoutType == .rest || planned?.isCompleted == true {
                return answer(.preserved, "No catch-up work has been added.")
            }
            guard let available else {
                return answer(.needsAvailability, "Set available time for this weekday before fitting a session.")
            }
            guard available.availableMinutes > 0 else {
                return answer(.unavailable, "This weekday is marked unavailable. Resolve the conflict explicitly rather than silently scheduling training.")
            }
            if let duration = planned?.duration, duration > available.availableMinutes {
                return answer(.timeConflict, "The planned \(duration) minutes exceed your \(available.availableMinutes)-minute availability. Review a shorter session or change available time.")
            }
            let previousActual = actual.filter { calendar.isDate($0.completedAt, inSameDayAs: yesterday) }
            let previousPlan = workouts.first {
                calendar.isDate($0.date, inSameDayAs: yesterday)
                    && ($0.isCompleted || calendar.startOfDay(for: $0.date) > today)
            }
            let demanding = planned?.workoutType.isLowerBodyDemanding == true || planned?.workoutType.isStrength == true
            let actualStrength = previousActual.contains { result in
                result.entries.contains { entry in
                    !entry.skipped && result.reference.items.contains { $0.id == entry.itemID && $0.kind == .strength }
                }
            }
            let flaggedReport = previousActual.contains { $0.bodyState != .good || $0.perceivedEffort >= 7 }
            let reservedDemand = previousPlan.map {
                $0.workoutType.loadClass == .high || $0.workoutType == .fullBody
                    || $0.workoutType == .lowerBody || $0.workoutType == .strengthTraining
            } ?? false
            if flaggedReport || (demanding && (actualStrength || reservedDemand)) {
                return answer(.reviewRecovery,
                    "Review recovery and spacing after the previous day's recorded effort or reserved demanding work. Missed past plans are not counted as completed load. Nothing has been moved automatically.")
            }
            if planned != nil {
                return answer(.scheduled, "The existing session fits the stated time budget. This is not a clearance to train; check that day's recovery before proceeding.")
            }
            return answer(.open, "\(available.availableMinutes) minutes available. No missed workout has been carried forward as debt; choose a goal-aligned session after the recovery review.")
        }
    }

    /// Produces only conservative, measurable adaptations. Other events remain
    /// no-ops until a deterministic domain policy supplies a candidate plan.
    static func candidatePlan(for event: CoachEvent, in plan: WeeklyTrainingPlan,
                              calendar: Calendar = .current) -> WeeklyTrainingPlan {
        let reduction: Double
        switch event.payload {
        case .readinessChanged(let score) where (score ?? 100) < 45:
            reduction = 0.7
        case .weatherChanged(_, let severity) where severity >= 0.75:
            reduction = 0.8
        default:
            return plan
        }
        guard let target = plan.workouts
            .filter({ !$0.isCompleted && $0.workoutType != .rest && $0.date >= calendar.startOfDay(for: event.occurredAt) })
            .sorted(by: { $0.date < $1.date }).first else { return plan }
        let workouts = plan.workouts.map { workout -> DailyWorkout in
            guard workout.id == target.id else { return workout }
            return DailyWorkout(
                id: workout.id, date: workout.date, dayOfWeek: workout.dayOfWeek,
                workoutType: workout.workoutType,
                title: "Adjusted " + workout.title,
                description: "Reduced from the protected plan after new recovery or weather evidence.",
                duration: workout.duration.map { max(10, Int((Double($0) * reduction).rounded())) },
                distance: workout.distance.map { $0 * reduction }, targetPace: workout.targetPace,
                exercises: workout.exercises, isCompleted: workout.isCompleted,
                completedActivityId: workout.completedActivityId,
                acceptedPrescription: workout.acceptedPrescription,
                acceptedCompletion: workout.acceptedCompletion,
                commitment: workout.commitment
            )
        }
        return AcceptedPrescriptionPlanPolicy.replacingWorkouts(
            in: plan, with: workouts, generatedAt: event.receivedAt
        )
    }
}
