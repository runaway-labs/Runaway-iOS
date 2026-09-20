import Foundation
import CryptoKit

struct WorkoutPromptSchedule: Codable, Equatable, Identifiable {
    var id = UUID()
    var hour = 7
    var minute = 0
    var weekdays = [1, 2, 3, 4, 5, 6, 7]

    var time: Date {
        get { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date() }
        set {
            hour = Calendar.current.component(.hour, from: newValue)
            minute = Calendar.current.component(.minute, from: newValue)
        }
    }
}

struct WorkoutPromptSettings: Codable, Equatable {
    var athlete_id: Int
    var enabled = false
    var hour = 7
    var minute = 0
    var weekdays = [1, 2, 3, 4, 5, 6, 7]
    var timezone = TimeZone.current.identifier
    var show_workout_name = false
    var schedules: [WorkoutPromptSchedule]?

    var effectiveSchedules: [WorkoutPromptSchedule] {
        schedules ?? [WorkoutPromptSchedule(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            hour: hour, minute: minute, weekdays: weekdays)]
    }

    var scheduleValidationMessage: String? {
        let entries = effectiveSchedules
        guard (1...12).contains(entries.count) else { return "Choose between 1 and 12 notification times." }
        guard Set(entries.map(\.id)).count == entries.count else { return "Each notification needs its own entry." }
        var slots = Set<Int>()
        for entry in entries {
            guard (0...23).contains(entry.hour), (0...59).contains(entry.minute),
                  !entry.weekdays.isEmpty, entry.weekdays.allSatisfy({ (1...7).contains($0) }) else {
                return "Choose a valid time and at least one day for each notification."
            }
            for day in Set(entry.weekdays) {
                guard slots.insert(day * 1440 + entry.hour * 60 + entry.minute).inserted else {
                    return "Two notifications have the same time on an overlapping day. Change the time or days."
                }
            }
        }
        return nil
    }
}

struct WorkoutPromptRoute: Identifiable, Equatable {
    let id: UUID
    let athleteID: Int

    init?(userInfo: [AnyHashable: Any]) {
        guard let value = userInfo["workout_delivery_id"] as? String,
              let id = UUID(uuidString: value),
              let athlete = userInfo["athlete_id"] as? String,
              let athleteID = Int(athlete), athleteID > 0 else { return nil }
        self.id = id
        self.athleteID = athleteID
    }
}

struct WorkoutPromptContent: Codable {
    let workout: DailyWorkout
    let whyToday: String
    let recommendationOnly: Bool
}

struct WorkoutPromptItem: Encodable {
    let day: String
    let workout_json: String
    let title: String
    let completed: Bool
}

struct WorkoutPromptActivity: Encodable {
    let id: Int
    let activity_type_id: Int?
    let activity_date: Double?
    let distance: Double?
    let elapsed_time: Double?

    init(_ activity: Activity) {
        id = activity.id
        activity_type_id = activity.activity_type_id
        activity_date = activity.activity_date ?? activity.start_date
        distance = activity.distance
        elapsed_time = activity.elapsed_time
    }
}

struct WorkoutPromptPublication: Encodable {
    let p_athlete: Int
    let p_items: [WorkoutPromptItem]
    let p_activities: [WorkoutPromptActivity]

    var signature: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let bytes = try? encoder.encode(self) else { return "invalid" }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    static func make(
        athleteID: Int, plans: [WeeklyTrainingPlan], profile: TrainingProfile,
        activities: [Activity], readinessScore: Int?, now: Date = Date()
    ) -> WorkoutPromptPublication {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let planned = plans.flatMap(\.workouts)
        let todayPlan = planned.first { calendar.isDate($0.date, inSameDayAs: now) }
        let context = TodayRecommendationContextBuilder.build(
            date: now, profile: profile, plannedWorkout: todayPlan,
            planWorkouts: planned, activities: activities, readinessScore: readinessScore
        )
        let recommendation = TodayRecommendationPolicy.recommendation(
            plannedWorkout: todayPlan, profile: profile,
            recentCompletedWorkouts: context.recentCompletedWorkouts,
            readinessScore: readinessScore, schedulingContext: context.schedulingContext
        )
        let recommended = TodayRecommendationDetailPolicy.workout(
            recommendation: recommendation, plannedWorkout: todayPlan, date: now
        )
        var contents: [WorkoutPromptContent] = []
        if let recommended {
            contents.append(WorkoutPromptContent(
                workout: recommended, whyToday: recommendation.reason ?? recommendation.detail,
                recommendationOnly: recommended.id != todayPlan?.id
            ))
        }
        let end = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        contents += planned.filter { $0.date > today && $0.date <= end && !calendar.isDate($0.date, inSameDayAs: now) }
            .sorted { $0.date < $1.date }
            .map { WorkoutPromptContent(workout: $0,
                whyToday: "From your training plan. Check today's recovery before starting; you can adjust the session and rebalance your week.",
                recommendationOnly: false) }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        var seen = Set<String>()
        let items = contents.compactMap { content -> WorkoutPromptItem? in
            let day = formatter.string(from: content.workout.date)
            guard seen.insert(day).inserted,
                  let data = try? encoder.encode(content),
                  let json = String(data: data, encoding: .utf8) else { return nil }
            let matching = calendar.isDate(content.workout.date, inSameDayAs: now) ? (todayPlan ?? content.workout) : content.workout
            let completed = matching.isCompleted || TodayActivityCompletionPolicy.completedActivity(
                for: matching, among: activities, on: matching.date
            ) != nil
            return WorkoutPromptItem(day: day, workout_json: json,
                title: content.workout.workoutType.displayName, completed: completed)
        }
        return WorkoutPromptPublication(p_athlete: athleteID, p_items: Array(items.prefix(8)),
            p_activities: activities.sorted { $0.id < $1.id }.prefix(2000).map(WorkoutPromptActivity.init))
    }
}

struct WorkoutPromptDelivery: Decodable {
    let id: UUID
    let athlete_id: Int
    let day: String
    let sent_revision: UUID?
    let revision: UUID?
    let workout_json: String?
    let completed: Bool
    let fresh: Bool?
    let is_today: Bool
    let timezone: String

    var content: WorkoutPromptContent? {
        guard let workout_json, let data = workout_json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WorkoutPromptContent.self, from: data)
    }
}
