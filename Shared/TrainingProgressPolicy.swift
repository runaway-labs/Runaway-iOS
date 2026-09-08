import Foundation

/// Pure calendar/aggregation rules shared by the app and its widgets. Inputs use
/// meters and elapsed seconds; conversion belongs at the presentation boundary.
enum TrainingProgressPolicy {
    static func weekStart(for date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1 - calendar.component(.weekday, from: date), to: day) ?? day
    }

    static func clean(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }

    static func unique(_ activities: [TrainingProgressActivity], athleteID: Int, through now: Date) -> [TrainingProgressActivity] {
        var seen = Set<Int>()
        return activities.filter {
            $0.athleteID == athleteID && $0.date <= now
                && (clean($0.seconds) > 0 || clean($0.meters) > 0)
                && seen.insert($0.id).inserted
        }
    }

    static func totals(_ activities: [TrainingProgressActivity], calendar: Calendar = .current) -> TrainingProgressSnapshot.Totals {
        var result = TrainingProgressSnapshot.Totals()
        var days = Set<Date>()
        for activity in activities {
            result.sessions += 1
            result.seconds += clean(activity.seconds)
            result.distanceMeters += clean(activity.meters)
            if activity.kind == .run {
                result.runs += 1
                result.runningMeters += clean(activity.meters)
            }
            days.insert(calendar.startOfDay(for: activity.date))
        }
        result.activeDays = days.count
        return result
    }

    static func snapshot(activities: [TrainingProgressActivity], athleteID: Int, at now: Date = Date(), calendar: Calendar = .current) -> TrainingProgressSnapshot {
        let weekStart = weekStart(for: now, calendar: calendar)
        let monthStart = calendar.dateInterval(of: .month, for: now)!.start
        let yearStart = calendar.dateInterval(of: .year, for: now)!.start
        let activities = unique(activities, athleteID: athleteID, through: now)
        let week = activities.filter { $0.date >= weekStart }
        let days = (0..<7).map { index in
            let date = calendar.date(byAdding: .day, value: index, to: weekStart)!
            let daily = week.filter { calendar.isDate($0.date, inSameDayAs: date) }
            return TrainingProgressSnapshot.Day(date: date, segments: ProgressActivityKind.allCases.compactMap { kind in
                let seconds = daily.filter { $0.kind == kind }.reduce(0) { $0 + clean($1.seconds) }
                return seconds > 0 ? TrainingProgressSnapshot.Segment(kind: kind, seconds: seconds) : nil
            })
        }
        return TrainingProgressSnapshot(
            athleteID: athleteID, weekStart: weekStart, monthStart: monthStart, yearStart: yearStart,
            timeZoneIdentifier: calendar.timeZone.identifier, refreshedAt: now,
            week: totals(week, calendar: calendar),
            month: totals(activities.filter { $0.date >= monthStart }, calendar: calendar),
            year: totals(activities.filter { $0.date >= yearStart }, calendar: calendar), days: days
        )
    }
}
