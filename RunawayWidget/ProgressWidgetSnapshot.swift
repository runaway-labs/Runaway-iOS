import Foundation


struct ProgressWidgetSnapshot: Sendable {
    struct Segment: Identifiable, Sendable {
        let kind: ProgressActivityKind
        let minutes: Double
        var id: String { kind.rawValue }
    }

    struct Day: Identifiable, Sendable {
        let index: Int
        let label: String
        let fullLabel: String
        let isToday: Bool
        let segments: [Segment]
        var id: Int { index }
        var minutes: Double { segments.reduce(0) { $0 + $1.minutes } }
    }

    let year: Int
    let annualDistance: Double
    let annualRuns: Int
    let weeklyDistance: Double
    let monthlyDistance: Double
    let weeklyGoal: Double?
    let monthlyGoal: Double?
    let goalWeeklyDistance: Double
    let goalMonthlyDistance: Double
    let unit: String
    let goalUnit: String
    let days: [Day]
    let hasAnnualData: Bool
    let hasWeeklyData: Bool
    let hasMonthlyData: Bool

    var activeDays: Int { days.filter { $0.minutes > 0 }.count }
    var trainingMinutes: Double { days.reduce(0) { $0 + $1.minutes } }
    var kinds: [ProgressActivityKind] {
        ProgressActivityKind.allCases.filter { kind in days.contains { $0.segments.contains { $0.kind == kind } } }
    }

    var accomplishment: String {
        if hasWeeklyData, let weeklyGoal, goalWeeklyDistance >= weeklyGoal { return "Weekly goal reached" }
        if activeDays > 1 { return "\(activeDays) active days this week" }
        if activeDays == 1 { return "One active day. You're building." }
        return "Make this week yours"
    }

    static func read(from defaults: UserDefaults?, at date: Date, calendar: Calendar = .current, selectedTypes: [String]? = nil) -> Self {
        if let owner = defaults?.object(forKey: TrainingProgressSnapshot.athleteKey) as? Int {
            guard owner > 0, let snapshot = TrainingProgressSnapshot.cached(in: defaults, athleteID: owner) else {
                return read(from: nil, at: date, calendar: calendar, selectedTypes: selectedTypes)
            }
            return fromShared(snapshot, defaults: defaults, at: date, calendar: calendar, selectedTypes: selectedTypes)
        }
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let dayStart = calendar.startOfDay(for: date)
        // The existing App Group arrays are explicitly Sunday through Saturday.
        let weekStart = calendar.date(byAdding: .day, value: 1 - calendar.component(.weekday, from: date), to: dayStart) ?? dayStart
        let storedWeek = defaults?.object(forKey: "widget_progress_week_start") as? Double
        let weekMatches = storedWeek.map { calendar.isDate(Date(timeIntervalSince1970: $0), inSameDayAs: weekStart) } ?? true
        let storedYear = defaults?.object(forKey: "widget_progress_year") as? Int
        let storedMonth = defaults?.object(forKey: "widget_progress_month") as? Int
        let yearMatches = storedYear.map { $0 == year } ?? true
        let monthMatches = yearMatches && (storedMonth.map { $0 == month } ?? true)

        let rawUnit = defaults?.string(forKey: "preferred_activity_distance_unit") ?? defaults?.string(forKey: "preferred_distance_unit") ?? "miles"
        let rawGoalUnit = defaults?.string(forKey: "goal_distance_unit") ?? rawUnit
        let metric = isMetric(rawUnit)
        let metricGoal = isMetric(rawGoalUnit)
        let scale = metric ? 1.609344 : 1
        let goalScale = metricGoal ? 1.609344 : 1
        let keys = ["sunArray", "monArray", "tueArray", "wedArray", "thuArray", "friArray", "satArray"]
        let labels = ["S", "M", "T", "W", "T", "F", "S"]
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let selection = selectedTypes.flatMap { $0.isEmpty ? nil : Set($0.map(ProgressActivityKind.init)) }
        var weeklyMiles = 0.0

        struct StoredActivity: Decodable {
            let type: String
            let distance: Double?
            let time: Double?
        }

        let days = keys.enumerated().map { index, key in
            var minutesByKind: [ProgressActivityKind: Double] = [:]
            if weekMatches {
                for json in defaults?.stringArray(forKey: key) ?? [] {
                    guard let data = json.data(using: .utf8), let activity = try? JSONDecoder().decode(StoredActivity.self, from: data) else { continue }
                    let kind = ProgressActivityKind(activity.type)
                    if kind == .run { weeklyMiles += nonnegative(activity.distance) }
                    let minutes = nonnegative(activity.time)
                    if minutes > 0, selection?.contains(kind) ?? true {
                        minutesByKind[kind, default: 0] += minutes
                    }
                }
            }
            return Day(index: index, label: labels[index], fullLabel: names[index], isToday: index + 1 == calendar.component(.weekday, from: date), segments: ProgressActivityKind.allCases.compactMap { kind in
                guard let minutes = minutesByKind[kind], minutes > 0 else { return nil }
                return Segment(kind: kind, minutes: minutes)
            })
        }

        let monthlyMiles = monthMatches ? nonnegative(defaults?.object(forKey: "monthlyMiles") as? Double) : 0
        return Self(
            year: year,
            annualDistance: (yearMatches ? nonnegative(defaults?.object(forKey: "miles") as? Double) : 0) * scale,
            annualRuns: yearMatches ? max(0, defaults?.integer(forKey: "runs") ?? 0) : 0,
            weeklyDistance: weeklyMiles * scale,
            monthlyDistance: monthlyMiles * scale,
            weeklyGoal: positive(defaults?.object(forKey: "weekly_goal_miles") as? Double).map { $0 * goalScale },
            monthlyGoal: positive(defaults?.object(forKey: "monthly_goal_miles") as? Double).map { $0 * goalScale },
            goalWeeklyDistance: weeklyMiles * goalScale,
            goalMonthlyDistance: monthlyMiles * goalScale,
            unit: metric ? "km" : "mi", goalUnit: metricGoal ? "km" : "mi", days: days,
            hasAnnualData: yearMatches && defaults?.object(forKey: "miles") != nil,
            hasWeeklyData: weekMatches && keys.contains { defaults?.object(forKey: $0) != nil },
            hasMonthlyData: monthMatches && defaults?.object(forKey: "monthlyMiles") != nil
        )
    }

    private static func fromShared(_ snapshot: TrainingProgressSnapshot, defaults: UserDefaults?, at date: Date, calendar: Calendar, selectedTypes: [String]?) -> Self {
        let unit = isMetric(defaults?.string(forKey: "preferred_activity_distance_unit") ?? "miles") ? "km" : "mi"
        let goalUnit = isMetric(defaults?.string(forKey: "goal_distance_unit") ?? unit) ? "km" : "mi"
        let divisor = unit == "km" ? 1000.0 : TrainingProgressSnapshot.metersPerMile
        let goalDivisor = goalUnit == "km" ? 1000.0 : TrainingProgressSnapshot.metersPerMile
        let zoneMatches = snapshot.timeZoneIdentifier == calendar.timeZone.identifier
        let yearMatches = zoneMatches && calendar.isDate(snapshot.yearStart, equalTo: date, toGranularity: .year)
        let monthMatches = zoneMatches && calendar.isDate(snapshot.monthStart, equalTo: date, toGranularity: .month)
        let weekStart = TrainingProgressPolicy.weekStart(for: date, calendar: calendar)
        let weekMatches = zoneMatches && snapshot.weekStart == weekStart
        let selected = selectedTypes.flatMap { $0.isEmpty ? nil : Set($0.map(ProgressActivityKind.init)) }
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let labels = ["S", "M", "T", "W", "T", "F", "S"]
        let days = (0..<7).map { index in
            let segments: [Segment] = weekMatches && snapshot.days.indices.contains(index)
                ? snapshot.days[index].segments.filter { selected?.contains($0.kind) ?? true }.map { Segment(kind: $0.kind, minutes: $0.seconds / 60) } : []
            return Day(index: index, label: labels[index], fullLabel: names[index], isToday: index + 1 == calendar.component(.weekday, from: date), segments: segments)
        }
        let weekMeters = weekMatches ? snapshot.week.runningMeters : 0
        let monthMeters = monthMatches ? snapshot.month.runningMeters : 0
        return Self(year: calendar.component(.year, from: date),
            annualDistance: yearMatches ? snapshot.year.runningMeters / divisor : 0,
            annualRuns: yearMatches ? snapshot.year.runs : 0,
            weeklyDistance: weekMeters / divisor, monthlyDistance: monthMeters / divisor,
            weeklyGoal: positive(defaults?.object(forKey: "weekly_goal_miles") as? Double).map { $0 * TrainingProgressSnapshot.metersPerMile / goalDivisor },
            monthlyGoal: positive(defaults?.object(forKey: "monthly_goal_miles") as? Double).map { $0 * TrainingProgressSnapshot.metersPerMile / goalDivisor },
            goalWeeklyDistance: weekMeters / goalDivisor, goalMonthlyDistance: monthMeters / goalDivisor,
            unit: unit, goalUnit: goalUnit, days: days,
            hasAnnualData: yearMatches, hasWeeklyData: weekMatches, hasMonthlyData: monthMatches)
    }
    
    private static func nonnegative(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }
        return max(0, value)
    }
    private static func positive(_ value: Double?) -> Double? {
        let value = nonnegative(value)
        return value > 0 ? value : nil
    }
    private static func isMetric(_ value: String) -> Bool {
        value.lowercased().contains("kilometer") || value.lowercased() == "km"
    }

    static let preview = Self(
        year: 2026, annualDistance: 428.6, annualRuns: 76, weeklyDistance: 12.4, monthlyDistance: 42.8,
        weeklyGoal: 20, monthlyGoal: 60, goalWeeklyDistance: 12.4, goalMonthlyDistance: 42.8, unit: "mi", goalUnit: "mi",
        days: [
            Day(index: 0, label: "S", fullLabel: "Sunday", isToday: false, segments: [Segment(kind: .run, minutes: 54)]),
            Day(index: 1, label: "M", fullLabel: "Monday", isToday: false, segments: [Segment(kind: .strength, minutes: 42)]),
            Day(index: 2, label: "T", fullLabel: "Tuesday", isToday: false, segments: [Segment(kind: .run, minutes: 38), Segment(kind: .walk, minutes: 18)]),
            Day(index: 3, label: "W", fullLabel: "Wednesday", isToday: false, segments: []),
            Day(index: 4, label: "T", fullLabel: "Thursday", isToday: false, segments: [Segment(kind: .run, minutes: 44)]),
            Day(index: 5, label: "F", fullLabel: "Friday", isToday: true, segments: [Segment(kind: .strength, minutes: 35)]),
            Day(index: 6, label: "S", fullLabel: "Saturday", isToday: false, segments: [])
        ], hasAnnualData: true, hasWeeklyData: true, hasMonthlyData: true
    )
}
