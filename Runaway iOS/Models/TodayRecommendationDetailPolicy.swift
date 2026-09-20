import Foundation

enum TodayRecommendationDetailPolicy {
    static func workout(
        recommendation: TodayRecommendation,
        plannedWorkout: DailyWorkout?,
        date: Date
    ) -> DailyWorkout? {
        guard let type = recommendation.workoutType else { return nil }
        if recommendation.directive == .proceed,
           let plannedWorkout,
           plannedWorkout.workoutType == type,
           Calendar.current.isDate(plannedWorkout.date, inSameDayAs: date) {
            return plannedWorkout
        }
        let day = Calendar.current.startOfDay(for: date)
        return DailyWorkout(
            id: "recommendation-\(Int(day.timeIntervalSince1970))-\(type.rawValue)",
            date: day, dayOfWeek: DayOfWeek.from(date: day), workoutType: type,
            title: recommendation.title, description: recommendation.detail,
            duration: nil, distance: nil, targetPace: nil, exercises: nil,
            isCompleted: false, completedActivityId: nil
        )
    }
}
