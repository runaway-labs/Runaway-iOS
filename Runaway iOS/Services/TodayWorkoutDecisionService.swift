import Foundation

enum TodayWorkoutDecisionService {
    static func preview(
        draft: TodayWorkoutDraft,
        currentPlan: WeeklyTrainingPlan,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> TodayWorkoutDecisionPreview {
        guard draft.validationIssues.isEmpty else { throw TodayWorkoutDecisionError.invalidDraft }
        let day = calendar.startOfDay(for: now)
        guard let original = currentPlan.workouts.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) else {
            throw TodayWorkoutDecisionError.unavailableDay
        }
        guard !original.isCompleted, original.completedActivityId == nil else {
            throw TodayWorkoutDecisionError.completedWorkout
        }

        let base = copy(
            draft.workout,
            id: original.id,
            date: original.date,
            dayOfWeek: original.dayOfWeek,
            commitment: nil
        )
        let fingerprint = try WorkoutPrescriptionFingerprint.make(base)
        let committed = copy(
            base,
            commitment: WorkoutCommitment(
                committedAt: now,
                source: draft.source,
                prescriptionFingerprint: fingerprint,
                originalWorkoutID: original.id
            )
        )
        let rebalanced = RemainingWeekTrainingPolicy.rebalancedPlan(
            replacingTodayWith: committed,
            in: currentPlan,
            on: day,
            calendar: calendar
        )
        let proposed = AcceptedPrescriptionPlanPolicy.replacingWorkouts(
            in: currentPlan,
            with: rebalanced.workouts,
            generatedAt: now
        )
        let revision = try AcceptedPrescriptionPlanPolicy.fingerprint(currentPlan)
        let replacement = TodayWorkoutDecisionPreview.Change(
            id: "replace-\(original.id)", kind: .replaced,
            title: "Today: \(original.title) → \(committed.title)",
            detail: "Your remaining week is rebalanced around this exact prescription."
        )
        return TodayWorkoutDecisionPreview(
            id: UUID(), originalPlanRevision: revision, originalPlan: currentPlan,
            proposedPlan: proposed, committedWorkoutID: committed.id,
            changes: [replacement] + rebalanced.changes,
            warnings: rebalanced.warnings, createdAt: now
        )
    }

    static func commit(
        preview: TodayWorkoutDecisionPreview,
        currentPlan: WeeklyTrainingPlan
    ) throws -> WeeklyTrainingPlan {
        guard currentPlan.id == preview.originalPlan.id,
              currentPlan.athleteId == preview.originalPlan.athleteId,
              try AcceptedPrescriptionPlanPolicy.fingerprint(currentPlan) == preview.originalPlanRevision else {
            throw TodayWorkoutDecisionError.stalePlan
        }
        guard let committed = preview.proposedPlan.workouts.first(where: { $0.id == preview.committedWorkoutID }),
              let commitment = committed.commitment,
              try WorkoutPrescriptionFingerprint.make(committed) == commitment.prescriptionFingerprint else {
            throw TodayWorkoutDecisionError.invalidCommitment
        }
        return preview.proposedPlan
    }

    static func commitPublishedRecommendation(
        prescriptionFingerprint: String,
        currentPlan: WeeklyTrainingPlan,
        now: Date = Date()
    ) throws -> WeeklyTrainingPlan {
        guard let workout = currentPlan.workouts.first(where: { Calendar.current.isDate($0.date, inSameDayAs: now) }),
              !workout.isCompleted,
              workout.acceptedCompletion == nil else {
            throw TodayWorkoutDecisionError.completedWorkout
        }
        let currentFingerprint = try WorkoutPrescriptionFingerprint.make(workout)
        guard currentFingerprint == prescriptionFingerprint else {
            throw TodayWorkoutDecisionError.stalePlan
        }
        if workout.commitment?.prescriptionFingerprint == currentFingerprint {
            return currentPlan
        }

        var committed = DailyWorkout(
            id: workout.id, date: workout.date, dayOfWeek: workout.dayOfWeek,
            workoutType: workout.workoutType, title: workout.title, description: workout.description,
            duration: workout.duration, distance: workout.distance, targetPace: workout.targetPace,
            exercises: workout.exercises, isCompleted: workout.isCompleted,
            completedActivityId: workout.completedActivityId
        )
        committed.acceptedPrescription = workout.acceptedPrescription
        committed.acceptedCompletion = workout.acceptedCompletion
        committed.commitment = WorkoutCommitment(
            committedAt: now,
            source: .recommendation,
            prescriptionFingerprint: currentFingerprint,
            originalWorkoutID: workout.id
        )
        let workouts = currentPlan.workouts.map { $0.id == workout.id ? committed : $0 }
        return AcceptedPrescriptionPlanPolicy.replacingWorkouts(
            in: currentPlan,
            with: workouts,
            generatedAt: now
        )
    }

    private static func copy(
        _ workout: DailyWorkout,
        id: String? = nil,
        date: Date? = nil,
        dayOfWeek: DayOfWeek? = nil,
        commitment: WorkoutCommitment?
    ) -> DailyWorkout {
        DailyWorkout(
            id: id ?? workout.id, date: date ?? workout.date,
            dayOfWeek: dayOfWeek ?? workout.dayOfWeek, workoutType: workout.workoutType,
            title: workout.title, description: workout.description,
            duration: workout.duration, distance: workout.distance,
            targetPace: workout.displayTargetPace, exercises: workout.exercises,
            isCompleted: false, completedActivityId: nil,
            acceptedPrescription: workout.acceptedPrescription,
            acceptedCompletion: nil, commitment: commitment
        )
    }
}

extension Notification.Name {
    static let workoutCommitmentDidChange = Notification.Name("workoutCommitmentDidChange")
}
