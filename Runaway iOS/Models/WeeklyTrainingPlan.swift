//
//  WeeklyTrainingPlan.swift
//  Runaway iOS
//
//  Models for AI-generated weekly training plans
//

import Foundation
import SwiftUI

// MARK: - Weekly Training Plan

struct WeeklyTrainingPlan: Codable, Identifiable {
    let id: String
    let athleteId: Int
    let weekStartDate: Date  // Sunday
    let weekEndDate: Date    // Saturday
    let workouts: [DailyWorkout]
    let weekNumber: Int?
    let totalMileage: Double
    let focusArea: String?
    let notes: String?
    let generatedAt: Date
    let goalId: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case athleteId = "athlete_id"
        case weekStartDate = "week_start_date"
        case weekEndDate = "week_end_date"
        case workouts
        case weekNumber = "week_number"
        case totalMileage = "total_mileage"
        case focusArea = "focus_area"
        case notes
        case generatedAt = "generated_at"
        case goalId = "goal_id"
    }

    var weekRangeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        let endFormatter = DateFormatter()
        if Calendar.current.component(.month, from: weekStartDate) == Calendar.current.component(.month, from: weekEndDate) {
            endFormatter.dateFormat = "d"
        } else {
            endFormatter.dateFormat = "MMM d"
        }
        return "\(formatter.string(from: weekStartDate)) - \(endFormatter.string(from: weekEndDate))"
    }

    var isCurrentWeek: Bool {
        contains(date: Date())
    }

    func contains(date: Date, calendar: Calendar = .current) -> Bool {
        let start = calendar.startOfDay(for: weekStartDate)
        let followingSunday = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: weekEndDate)
        ) ?? weekEndDate.addingTimeInterval(86_400)
        return date >= start && date < followingSunday
    }

    func workout(for date: Date) -> DailyWorkout? {
        let calendar = Calendar.current
        return workouts.first { workout in
            calendar.isDate(workout.date, inSameDayAs: date)
        }
    }

    func workout(for dayOfWeek: DayOfWeek) -> DailyWorkout? {
        workouts.first { $0.dayOfWeek == dayOfWeek }
    }
}

// MARK: - Daily Workout

struct DailyWorkout: Codable, Identifiable {
    let id: String
    let date: Date
    let dayOfWeek: DayOfWeek
    let workoutType: WorkoutType
    let title: String
    let description: String
    let duration: Int?  // minutes
    let distance: Double?  // miles
    let targetPace: String?
    let exercises: [Exercise]?
    let isCompleted: Bool
    let completedActivityId: Int?
    var acceptedPrescription: AcceptedTrainingPrescription? = nil
    var acceptedCompletion: AcceptedWorkoutCompletion? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case dayOfWeek = "day_of_week"
        case workoutType = "workout_type"
        case title
        case description
        case duration
        case distance
        case targetPace = "target_pace"
        case exercises
        case isCompleted = "is_completed"
        case completedActivityId = "completed_activity_id"
        case acceptedPrescription = "accepted_prescription"
        case acceptedCompletion = "accepted_completion"
    }

    var formattedDistance: String? {
        guard let distance = distance else { return nil }
        return String(format: "%.1f mi", distance)
    }

    var formattedDuration: String? {
        guard let duration = duration else { return nil }
        if duration >= 60 {
            let hours = duration / 60
            let mins = duration % 60
            return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
        }
        return "\(duration) min"
    }
}

// MARK: - Exercise (for strength workouts)

struct Exercise: Codable, Identifiable {
    let id: String
    let name: String
    let sets: Int?
    let reps: String?  // Can be "10" or "10-12" or "30 sec"
    let weight: String?  // Can be "bodyweight" or "135 lbs"
    let notes: String?

    init(id: String = UUID().uuidString, name: String, sets: Int? = nil, reps: String? = nil, weight: String? = nil, notes: String? = nil) {
        self.id = id
        self.name = name
        self.sets = sets
        self.reps = reps
        self.weight = weight
        self.notes = notes
    }
}

// MARK: - Day of Week

enum DayOfWeek: String, Codable, CaseIterable, Sendable {
    case sunday = "sunday"
    case monday = "monday"
    case tuesday = "tuesday"
    case wednesday = "wednesday"
    case thursday = "thursday"
    case friday = "friday"
    case saturday = "saturday"

    var shortName: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }

    var fullName: String {
        rawValue.capitalized
    }

    var calendarWeekday: Int {
        switch self {
        case .sunday: return 1
        case .monday: return 2
        case .tuesday: return 3
        case .wednesday: return 4
        case .thursday: return 5
        case .friday: return 6
        case .saturday: return 7
        }
    }

    static func from(date: Date) -> DayOfWeek {
        let weekday = Calendar.current.component(.weekday, from: date)
        return DayOfWeek.allCases.first { $0.calendarWeekday == weekday } ?? .sunday
    }
}

// MARK: - Workout Type

enum TrainingLoadClass: Int, Codable, Comparable, Sendable {
    case recovery
    case low
    case moderate
    case high

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum WorkoutType: String, Codable, CaseIterable, Sendable {
    case easyRun = "easy_run"
    case longRun = "long_run"
    case tempoRun = "tempo_run"
    case intervalRun = "interval_run"
    case hillRun = "hill_run"
    case recoveryRun = "recovery_run"
    case rest = "rest"
    case strengthTraining = "strength_training"
    case upperBody = "upper_body"
    case lowerBody = "lower_body"
    case fullBody = "full_body"
    case yoga = "yoga"
    case crossTraining = "cross_training"
    case cycling = "cycling"
    case swimming = "swimming"
    case walking = "walking"
    case hiking = "hiking"
    case stretchMobility = "stretch_mobility"

    var displayName: String {
        switch self {
        case .easyRun: return "Easy Run"
        case .longRun: return "Long Run"
        case .tempoRun: return "Tempo Run"
        case .intervalRun: return "Intervals"
        case .hillRun: return "Hill Workout"
        case .recoveryRun: return "Recovery Run"
        case .rest: return "Rest Day"
        case .strengthTraining: return "Strength"
        case .upperBody: return "Upper Body"
        case .lowerBody: return "Lower Body"
        case .fullBody: return "Full Body"
        case .yoga: return "Yoga"
        case .crossTraining: return "Cross Training"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        case .stretchMobility: return "Stretch & Mobility"
        }
    }

    var icon: String {
        switch self {
        case .easyRun, .recoveryRun: return "figure.run"
        case .longRun: return "figure.run.circle"
        case .tempoRun, .intervalRun: return "speedometer"
        case .hillRun: return "mountain.2"
        case .rest: return "moon.zzz.fill"
        case .strengthTraining, .upperBody, .lowerBody, .fullBody: return "dumbbell"
        case .yoga: return "figure.yoga"
        case .crossTraining: return "figure.mixed.cardio"
        case .cycling: return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .walking: return "figure.walk"
        case .hiking: return "figure.hiking"
        case .stretchMobility: return "figure.flexibility"
        }
    }

    var color: Color {
        switch self {
        case .easyRun, .recoveryRun: return .green
        case .longRun: return .blue
        case .tempoRun: return .orange
        case .intervalRun: return .red
        case .hillRun: return .brown
        case .rest: return .gray
        case .strengthTraining, .upperBody, .lowerBody, .fullBody: return .purple
        case .yoga, .stretchMobility: return .teal
        case .crossTraining: return .indigo
        case .cycling: return .cyan
        case .swimming: return .blue
        case .walking: return .mint
        case .hiking: return .brown
        }
    }

    var activity: TrainingActivity? {
        switch self {
        case .easyRun, .longRun, .tempoRun, .intervalRun, .hillRun, .recoveryRun:
            return .running
        case .rest:
            return nil
        case .strengthTraining, .upperBody, .lowerBody, .fullBody:
            return .strength
        case .yoga, .stretchMobility:
            return .mobility
        case .crossTraining:
            return nil
        case .cycling:
            return .cycling
        case .swimming:
            return .swimming
        case .walking:
            return .walking
        case .hiking:
            return .hiking
        }
    }

    var loadClass: TrainingLoadClass {
        switch self {
        case .rest, .yoga, .stretchMobility:
            return .recovery
        case .recoveryRun, .cycling, .swimming, .walking, .upperBody:
            return .low
        case .easyRun, .strengthTraining, .lowerBody, .fullBody, .crossTraining, .hiking:
            return .moderate
        case .longRun, .tempoRun, .intervalRun, .hillRun:
            return .high
        }
    }

    var isRecoveryCompatible: Bool {
        switch self {
        case .easyRun, .longRun, .tempoRun, .intervalRun, .hillRun:
            return false
        case .recoveryRun, .rest, .yoga, .walking, .stretchMobility:
            return true
        case .strengthTraining, .upperBody, .lowerBody, .fullBody, .crossTraining, .cycling, .swimming, .hiking:
            return false
        }
    }

    var isLowerBodyDemanding: Bool {
        switch self {
        case .easyRun, .longRun, .tempoRun, .intervalRun, .hillRun, .recoveryRun:
            return true
        case .rest, .strengthTraining, .upperBody, .yoga, .crossTraining, .swimming, .stretchMobility:
            return false
        case .lowerBody, .fullBody, .cycling, .walking, .hiking:
            return true
        }
    }

    var isHighIntensity: Bool {
        switch self {
        case .tempoRun, .intervalRun, .hillRun:
            return true
        case .easyRun, .longRun, .recoveryRun, .rest, .strengthTraining, .upperBody, .lowerBody, .fullBody, .yoga, .crossTraining, .cycling, .swimming, .walking, .hiking, .stretchMobility:
            return false
        }
    }

    var isRunning: Bool {
        switch self {
        case .easyRun, .longRun, .tempoRun, .intervalRun, .hillRun, .recoveryRun:
            return true
        case .rest, .strengthTraining, .upperBody, .lowerBody, .fullBody, .yoga, .crossTraining, .cycling, .swimming, .walking, .hiking, .stretchMobility:
            return false
        }
    }

    var isStrength: Bool {
        switch self {
        case .strengthTraining, .upperBody, .lowerBody, .fullBody:
            return true
        case .easyRun, .longRun, .tempoRun, .intervalRun, .hillRun, .recoveryRun, .rest, .yoga, .crossTraining, .cycling, .swimming, .walking, .hiking, .stretchMobility:
            return false
        }
    }
}

extension Activity {
    var isRunningWorkoutActivity: Bool {
        isCompatible(with: .easyRun)
    }

    func isCompatible(with workoutType: WorkoutType) -> Bool {
        let value = (type ?? name ?? "").lowercased()
        if value.contains("run") || value.contains("jog") { return workoutType.isRunning }
        if value.contains("ride") || value.contains("cycl") || value.contains("bike") {
            return workoutType == .cycling
        }
        if value.contains("swim") { return workoutType == .swimming }
        if value.contains("walk") { return workoutType == .walking }
        if value.contains("hike") { return workoutType == .hiking }
        if value.contains("strength") || value.contains("weight") || value.contains("workout") || value.contains("crossfit") {
            return workoutType.isStrength
        }
        if value.contains("yoga") || value.contains("mobility") || value.contains("stretch") {
            return workoutType == .yoga || workoutType == .stretchMobility
        }
        return false
    }
}

// MARK: - API Response

struct TrainingPlanAPIResponse: Codable {
    let success: Bool
    let plan: WeeklyTrainingPlan?
    let error: String?
}

// MARK: - Day Entry (merged planned workout + actual activity)

/// Represents a single day in the week, combining planned workout with actual activity
struct WeekDayEntry: Identifiable {
    let id: String
    let date: Date
    let dayOfWeek: DayOfWeek
    let plannedWorkout: DailyWorkout?
    let actualActivity: Activity?

    init(date: Date, dayOfWeek: DayOfWeek, plannedWorkout: DailyWorkout? = nil, actualActivity: Activity? = nil) {
        self.id = "\(dayOfWeek.rawValue)-\(date.timeIntervalSince1970)"
        self.date = date
        self.dayOfWeek = dayOfWeek
        self.plannedWorkout = plannedWorkout
        self.actualActivity = actualActivity
    }

    /// Whether this day has been completed with an actual activity
    var isCompleted: Bool {
        if let completion = plannedWorkout?.acceptedCompletion { return !completion.isPartial }
        return actualActivity != nil || plannedWorkout?.isCompleted == true
    }

    /// Whether this day is in the past (and should show as missed if no activity)
    var isPast: Bool {
        Calendar.current.compare(date, to: Date(), toGranularity: .day) == .orderedAscending
    }

    /// Whether this is today
    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    /// Whether this day is in the future
    var isFuture: Bool {
        Calendar.current.compare(date, to: Date(), toGranularity: .day) == .orderedDescending
    }

    /// Display title - actual activity name or planned workout title
    var displayTitle: String {
        if let activity = actualActivity {
            return activity.name ?? "Run"
        }
        return plannedWorkout?.title ?? "Rest Day"
    }

    /// Display distance in miles
    var displayDistance: Double? {
        if let activity = actualActivity, let distance = activity.distance {
            return distance * 0.000621371  // Convert meters to miles
        }
        return plannedWorkout?.distance
    }

    /// Formatted distance string
    var formattedDistance: String? {
        guard let distance = displayDistance else { return nil }
        return String(format: "%.1f mi", distance)
    }

    /// Display duration in minutes
    var displayDuration: Int? {
        if let completion = plannedWorkout?.acceptedCompletion { return Int(ceil(completion.elapsedSeconds / 60)) }
        if let activity = actualActivity, let elapsed = activity.elapsed_time {
            return Int(elapsed / 60)
        }
        return plannedWorkout?.duration
    }

    /// Formatted duration string
    var formattedDuration: String? {
        guard let duration = displayDuration else { return nil }
        if duration >= 60 {
            let hours = duration / 60
            let mins = duration % 60
            return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
        }
        return "\(duration) min"
    }

    /// Formatted pace from actual activity
    var formattedPace: String? {
        guard let activity = actualActivity,
              let speed = activity.average_speed, speed > 0 else { return nil }
        let minutesPerMile = (1609.34 / speed) / 60.0
        let minutes = Int(minutesPerMile)
        let seconds = Int((minutesPerMile - Double(minutes)) * 60)
        return String(format: "%d:%02d /mi", minutes, seconds)
    }

    /// Icon for the day
    var icon: String {
        if plannedWorkout?.acceptedCompletion?.isPartial == true { return "circle.lefthalf.filled" }
        if isCompleted { return "checkmark.circle.fill" }
        if actualActivity != nil {
            return "checkmark.circle.fill"
        }
        if let workout = plannedWorkout {
            return workout.workoutType.icon
        }
        return "bed.double"  // Rest day
    }

    /// Color for the day
    var iconColor: Color {
        if plannedWorkout?.acceptedCompletion?.isPartial == true { return .orange }
        if isCompleted { return .green }
        if actualActivity != nil {
            return .green
        }
        if isPast && plannedWorkout != nil {
            return .orange  // Missed workout
        }
        return plannedWorkout?.workoutType.color ?? .gray
    }

    /// Status text for the day
    var statusText: String? {
        if let completion = plannedWorkout?.acceptedCompletion { return completion.status }
        if plannedWorkout?.isCompleted == true { return "Completed" }
        if actualActivity != nil {
            return "Completed"
        }
        if isPast && plannedWorkout != nil {
            return "Missed"
        }
        if isToday {
            return "Today"
        }
        return nil
    }
}

// MARK: - WeeklyTrainingPlan Extension for Merging

extension WeeklyTrainingPlan {
    /// Merge the plan with actual activities to create a unified week view
    func mergedWithActivities(_ activities: [Activity]) -> [WeekDayEntry] {
        let calendar = Calendar.current
        var entries: [WeekDayEntry] = []

        // Create entries for each day of the week
        for day in DayOfWeek.allCases {
            // Calculate the date for this day of the week
            guard let dayDate = calendar.date(
                byAdding: .day,
                value: day.calendarWeekday - 1,
                to: weekStartDate
            ) else { continue }

            // Find planned workout for this day
            let plannedWorkout = workout(for: day)

            // Find actual activity for this day
            let actualActivity = activities.first { activity in
                guard let activityDate = activity.activity_date ?? activity.start_date else { return false }
                let activityDateObj = Date(timeIntervalSince1970: activityDate)
                guard calendar.isDate(activityDateObj, inSameDayAs: dayDate) else { return false }
                if let plannedWorkout, plannedWorkout.workoutType != .rest {
                    return activity.isCompatible(with: plannedWorkout.workoutType)
                }
                return activity.isRunningWorkoutActivity
            }

            let entry = WeekDayEntry(
                date: dayDate,
                dayOfWeek: day,
                plannedWorkout: plannedWorkout,
                actualActivity: actualActivity
            )
            entries.append(entry)
        }

        return entries
    }

    /// Calculate actual vs planned stats
    func weekStats(with activities: [Activity]) -> (plannedMiles: Double, actualMiles: Double, completedWorkouts: Int, plannedWorkouts: Int) {
        let runningActivities = activities.filter { activity in
            guard activity.isRunningWorkoutActivity,
                  let timestamp = activity.activity_date ?? activity.start_date else { return false }
            return contains(date: Date(timeIntervalSince1970: timestamp))
        }
        let plannedMiles = workouts.filter { $0.workoutType.isRunning }.compactMap(\.distance).reduce(0, +)
        let actualMiles = runningActivities.compactMap(\.distance).reduce(0, +) * 0.000621371
        let completedWorkouts = runningActivities.count
        let plannedWorkouts = workouts.filter { $0.workoutType.isRunning }.count

        return (plannedMiles, actualMiles, completedWorkouts, plannedWorkouts)
    }
}

struct WeeklyRunProgress: Equatable {
    let actualMiles: Double
    let completedRuns: Int

    static func activitiesOnly(
        _ activities: [Activity],
        weekStart: Date,
        calendar: Calendar = .current
    ) -> WeeklyRunProgress {
        let start = calendar.startOfDay(for: weekStart)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
        let runs = activities.filter { activity in
            guard activity.isRunningWorkoutActivity,
                  let timestamp = activity.activity_date ?? activity.start_date else { return false }
            let date = Date(timeIntervalSince1970: timestamp)
            return date >= start && date < end
        }
        return WeeklyRunProgress(
            actualMiles: runs.compactMap(\.distance).reduce(0, +) * 0.000621371,
            completedRuns: runs.count
        )
    }
}
