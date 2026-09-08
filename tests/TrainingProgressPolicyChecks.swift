import Foundation

@main
struct TrainingProgressPolicyChecks {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        func date(_ month: Int, _ day: Int, _ hour: Int = 12, year: Int = 2026) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
        }
        let now = date(9, 4)
        func activity(_ id: Int, _ kind: String, _ meters: Double, _ seconds: Double, _ day: Date, athlete: Int = 7) -> TrainingProgressActivity {
            TrainingProgressActivity(id: id, athleteID: athlete, name: kind, type: kind, date: day, meters: meters, seconds: seconds, polyline: "")
        }
        let mile = TrainingProgressSnapshot.metersPerMile
        let run = activity(1, "Run", 3 * mile, 1800, date(8, 30))
        let activities = [run, run, activity(2, "Weight Training", 0, 2700, date(9, 1)),
            activity(3, "GravelRide", 40_000, 3600, date(9, 2)),
            activity(4, "TrailRun", 2 * mile, 1500, date(9, 3)),
            activity(5, "Walk", 1609, 1200, date(9, 3)),
            activity(6, "Run", 1000, 600, date(9, 5)),
            activity(7, "Run", 2000, 1200, date(9, 1), athlete: 99),
            activity(8, "Run", 10 * mile, 5400, date(1, 4))]
        let snapshot = TrainingProgressPolicy.snapshot(activities: activities, athleteID: 7, at: now, calendar: calendar)
        var count = 0
        func check(_ condition: Bool, _ name: String) {
            guard condition else { fatalError("FAIL: \(name)") }
            count += 1
            print("PASS: \(name)")
        }
        func near(_ a: Double, _ b: Double) -> Bool { abs(a-b) < 0.00001 }
        check(near(snapshot.week.runningMeters, 5 * mile) && snapshot.week.runs == 2, "Only running contributes to running goals")
        check(snapshot.week.sessions == 5 && near(snapshot.week.seconds, 10_800), "Mixed sports count once; duplicate IDs do not inflate training")
        check(snapshot.week.activeDays == 4, "Active days are local dates, not streaks")
        check(near(snapshot.month.runningMeters, 2 * mile) && near(snapshot.year.runningMeters, 15 * mile), "Month and year use their own complete periods")
        check(snapshot.days.count == 7 && snapshot.weekStart == date(8, 30, 0), "Sunday through Saturday stays consistent across calendar settings")
        check(snapshot.days[2].segments.first?.kind == .strength, "Strength counts with zero distance")
        check(snapshot.isCurrent(at: now, calendar: calendar), "Current period is accepted")
        check(!snapshot.isCurrent(at: date(9, 6), calendar: calendar), "A new week never relabels the prior week")
        var otherZone = calendar; otherZone.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        check(!snapshot.isCurrent(at: now, calendar: otherZone), "Timezone changes require local-day reaggregation")
        check(TrainingProgressPolicy.clean(.nan) == 0 && TrainingProgressPolicy.clean(-2) == 0, "Non-finite and negative quantities cannot poison totals")
        let suite = "runaway.training-progress.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode(snapshot), forKey: TrainingProgressSnapshot.cacheKey)
        defaults.set(7, forKey: TrainingProgressSnapshot.athleteKey)
        defaults.set("miles", forKey: "preferred_activity_distance_unit")
        defaults.set("kilometers", forKey: "goal_distance_unit")
        defaults.set(20.0, forKey: "weekly_goal_miles")
        let widget = ProgressWidgetSnapshot.read(from: defaults, at: now, calendar: calendar)
        check(near(widget.weeklyDistance, 5) && widget.annualRuns == 3, "App and widget use the same canonical totals")
        check(widget.goalUnit == "km" && near(widget.goalWeeklyDistance, 8.04672), "Saved goal unit stays independent of activity display unit")
        let selected = ProgressWidgetSnapshot.read(from: defaults, at: now, calendar: calendar, selectedTypes: ["Strength"])
        check(near(selected.weeklyDistance, 5) && selected.trainingMinutes == 45, "Widget activity filter changes chart, never running goal totals")
        defaults.set(8, forKey: TrainingProgressSnapshot.athleteKey)
        let switched = ProgressWidgetSnapshot.read(from: defaults, at: now, calendar: calendar)
        check(!switched.hasAnnualData && switched.weeklyDistance == 0, "Account switch does not expose the prior athlete's totals")
        defaults.set(0, forKey: TrainingProgressSnapshot.athleteKey)
        check(!ProgressWidgetSnapshot.read(from: defaults, at: now, calendar: calendar).hasWeeklyData, "Signed-out widgets do not show cached private progress")
        let rollover = TrainingProgressPolicy.snapshot(activities: [activity(9, "Run", mile, 600, date(12, 31, year: 2025))], athleteID: 7, at: date(1, 1), calendar: calendar)
        check(rollover.week.runs == 1 && rollover.year.runs == 0, "New-year week keeps December sessions without adding them to the new year")
        print("\(count) canonical progress checks passed")
    }
}
