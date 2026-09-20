import Foundation

struct AcceptedWorkoutCompletion: Codable, Equatable {
    let resultID: UUID
    let completedAt: Date
    let elapsedSeconds: Double
    let isPartial: Bool
    var status: String { isPartial ? "Partial session" : "Completed" }
}

enum AcceptedWorkoutCompletionProjection {
    /// Derived status only. The original prescription and stored actual result stay intact.
    static func applying(_ results: [TrainingSessionResult], to plan: WeeklyTrainingPlan) throws -> WeeklyTrainingPlan? {
        guard results.allSatisfy({ $0.isValid && $0.reference.athleteID == plan.athleteId }),
              Set(results.map { $0.reference.id }).count == results.count else {
            throw AcceptedPrescriptionCompletionPolicy.Failure.stalePlan
        }
        var changed = false
        let workouts = try plan.workouts.map { workout -> DailyWorkout in
            guard workout.acceptedPrescription != nil else { return workout }
            let reference = try AcceptedPrescriptionCompletionPolicy.reference(for: workout, athleteID: plan.athleteId)
            guard let result = results.first(where: { $0.reference == reference }),
                  result.completedAt >= reference.generatedAt,
                  result.completedAt >= Calendar.current.startOfDay(for: workout.date) else { return workout }
            let completion = AcceptedWorkoutCompletion(resultID: result.id, completedAt: result.completedAt,
                elapsedSeconds: result.elapsedSeconds, isPartial: result.isPartial)
            guard completion != workout.acceptedCompletion || workout.isCompleted != !result.isPartial else { return workout }
            var updated = DailyWorkout(id: workout.id, date: workout.date, dayOfWeek: workout.dayOfWeek,
                workoutType: workout.workoutType, title: workout.title, description: workout.description,
                duration: workout.duration, distance: workout.distance, targetPace: workout.targetPace,
                exercises: workout.exercises, isCompleted: !result.isPartial, completedActivityId: workout.completedActivityId)
            updated.acceptedPrescription = workout.acceptedPrescription
            updated.acceptedCompletion = completion
            changed = true
            return updated
        }
        return changed ? AcceptedPrescriptionPlanPolicy.replacingWorkouts(in: plan, with: workouts, generatedAt: Date()) : nil
    }
}

extension DataManager {
    /// Replays the status projection after a crash between result storage and cache update.
    func refreshAcceptedWorkoutCompletions() throws {
        guard UserSession.shared.isReady, let athleteID = UserSession.shared.userId,
              let plan = currentWeeklyPlan, plan.athleteId == athleteID,
              plan.workouts.contains(where: { $0.acceptedPrescription != nil }) else { return }
        let results = try ProtectedTrainingRepository(activeAthleteID: {
            UserSession.shared.isReady ? UserSession.shared.userId : nil
        }).sessionResults(athleteID: athleteID)
        if let updated = try AcceptedWorkoutCompletionProjection.applying(results, to: plan) {
            try updateCurrentWeeklyPlan(updated)
        }
    }
}
