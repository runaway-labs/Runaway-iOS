import Foundation

struct CoachWeekBoardPresentation: Equatable {
    enum Status: String, Equatable, Hashable {
        case recommended, committed, completed, partial, upcoming, rest, missed

        var label: String {
            switch self {
            case .recommended: "Recommended"
            case .committed: "Committed"
            case .completed: "Completed"
            case .partial: "Partial"
            case .upcoming: "Upcoming"
            case .rest: "Rest"
            case .missed: "Missed"
            }
        }
    }

    enum Action: Equatable, Hashable {
        case commit, change, viewWorkout, reviewResult

        var label: String {
            switch self {
            case .commit: "Commit"
            case .change: "Change"
            case .viewWorkout: "View workout"
            case .reviewResult: "Review result"
            }
        }
    }

    struct Day: Identifiable, Equatable {
        let id: String
        let workoutID: String
        let date: Date
        let weekday: String
        let dayNumber: String
        let title: String
        let modality: WorkoutType
        let dose: String
        let status: Status
        let actions: [Action]
        let adaptationDecisionID: UUID?
        let isToday: Bool
    }

    let weekRange: String
    let completedSessionCount: Int
    let plannedSessionCount: Int
    let plannedMinutes: Int
    let weeklyFocus: String
    let days: [Day]

    static func make(
        plan: WeeklyTrainingPlan,
        activities: [Activity],
        recentDecision: CoachDecision?,
        now: Date = Date(),
        calendar: Calendar = .current,
        distanceFormatter: (Double) -> String = { UnitFormatter.formatMiles($0) }
    ) -> Self {
        let workouts = plan.workouts.sorted { $0.date < $1.date }
        let days = workouts.map { workout in
            let isToday = calendar.isDate(workout.date, inSameDayAs: now)
            let state = status(for: workout, activities: activities, now: now, calendar: calendar)
            let decisionID = recentDecision?.changes.contains(where: { $0.workoutID == workout.id }) == true
                ? recentDecision?.id
                : nil
            return Day(
                id: workout.id, workoutID: workout.id, date: workout.date,
                weekday: workout.date.formatted(.dateTime.weekday(.abbreviated)).uppercased(),
                dayNumber: workout.date.formatted(.dateTime.day()),
                title: workout.title, modality: workout.workoutType,
                dose: dose(for: workout, distanceFormatter: distanceFormatter),
                status: state, actions: actions(for: state, isToday: isToday),
                adaptationDecisionID: decisionID, isToday: isToday
            )
        }
        let training = workouts.filter { $0.workoutType != .rest }
        return Self(
            weekRange: weekRange(workouts: workouts),
            completedSessionCount: days.filter { $0.status == .completed }.count,
            plannedSessionCount: training.count,
            plannedMinutes: training.compactMap(\.duration).reduce(0, +),
            weeklyFocus: weeklyFocus(workouts: training),
            days: days
        )
    }

    private static func status(
        for workout: DailyWorkout,
        activities: [Activity],
        now: Date,
        calendar: Calendar
    ) -> Status {
        if workout.acceptedCompletion?.isPartial == true { return .partial }
        if workout.commitment != nil {
            switch CommittedWorkoutCompletionPolicy.status(
                workout: workout,
                evidence: activities,
                calendar: calendar
            ) {
            case .complete: return .completed
            case .partial: return .partial
            case .notCompleted: break
            }
        }
        if workout.acceptedCompletion != nil || workout.isCompleted { return .completed }
        if workout.workoutType == .rest { return .rest }
        if calendar.isDate(workout.date, inSameDayAs: now) {
            guard let commitment = workout.commitment,
                  (try? WorkoutPrescriptionFingerprint.make(workout)) == commitment.prescriptionFingerprint else {
                return .recommended
            }
            return .committed
        }
        return workout.date < calendar.startOfDay(for: now) ? .missed : .upcoming
    }

    private static func actions(for status: Status, isToday: Bool) -> [Action] {
        switch (status, isToday) {
        case (.recommended, true): [.commit, .change]
        case (.committed, true): [.viewWorkout, .change]
        case (.completed, _), (.partial, _): [.reviewResult]
        case (.rest, true): [.viewWorkout, .change]
        default: [.viewWorkout]
        }
    }

    private static func dose(for workout: DailyWorkout, distanceFormatter: (Double) -> String) -> String {
        if workout.workoutType == .rest { return "Recovery is part of the plan" }
        var pieces: [String] = []
        if let duration = workout.formattedDuration { pieces.append(duration) }
        if let distance = workout.distance,
           workout.workoutType.isRunning || workout.workoutType == .walking ||
            workout.workoutType == .cycling || workout.workoutType == .swimming {
            pieces.append(distanceFormatter(distance))
        }
        if let count = workout.exercises?.count, count > 0 {
            pieces.append("\(count) exercise\(count == 1 ? "" : "s")")
        }
        if workout.workoutType.isRunning, let pace = workout.displayTargetPace, !pace.isEmpty {
            pieces.append(pace)
        }
        return pieces.isEmpty ? "Prescription details unavailable" : pieces.joined(separator: " · ")
    }

    private static func weekRange(workouts: [DailyWorkout]) -> String {
        guard let first = workouts.first?.date, let last = workouts.last?.date else { return "This week" }
        return "\(first.formatted(.dateTime.month(.abbreviated).day()))–\(last.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private static func weeklyFocus(workouts: [DailyWorkout]) -> String {
        let runs = workouts.filter { $0.workoutType.isRunning }.count
        let strength = workouts.filter { $0.workoutType.isStrength }.count
        let other = workouts.count - runs - strength
        var pieces: [String] = []
        if runs > 0 { pieces.append("\(runs) run\(runs == 1 ? "" : "s")") }
        if strength > 0 { pieces.append("\(strength) strength session\(strength == 1 ? "" : "s")") }
        if other > 0 { pieces.append("\(other) cross-training session\(other == 1 ? "" : "s")") }
        return pieces.isEmpty ? "Recovery week" : pieces.joined(separator: " · ")
    }
}
