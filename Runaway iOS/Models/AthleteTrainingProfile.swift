import Foundation

enum TrainingDiscipline: String, Codable, CaseIterable {
    case running, strength
}

enum GoalPriority: String, Codable, CaseIterable {
    case equalPrimary, supporting
}

enum TrainingGoalMetric: String, Codable, CaseIterable {
    case racePerformance, weeklyRunningDistance, weeklyRunningDuration
    case strengthPerformance, bodyweightRepetitions

    var discipline: TrainingDiscipline {
        switch self {
        case .racePerformance, .weeklyRunningDistance, .weeklyRunningDuration: return .running
        case .strengthPerformance, .bodyweightRepetitions: return .strength
        }
    }
}

enum LoadConvention: String, Codable, CaseIterable {
    case total, perHand, machine, bodyweight
}

enum TrainingDistanceUnit: String, Codable { case miles, kilometers }
enum TrainingMassUnit: String, Codable { case pounds, kilograms }
enum TrainingHeightUnit: String, Codable { case inches, centimeters }
enum TrainingEvidenceSource: String, Codable { case userEntered, healthKit, importedActivity }

struct TrainingProfileIssue: Equatable, Identifiable {
    let field: String
    let message: String
    var id: String { field + ":" + message }
}

struct GoalMeasurement: Codable, Equatable {
    var distanceMeters: Double?
    var durationSeconds: Double?
    var loadKilograms: Double?
    var repetitions: Int?
    var exerciseID: String?
    var loadConvention: LoadConvention?
    var sets: Int?
    var reportedEffort: Double?
}

struct AthleteTrainingGoal: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var metric: TrainingGoalMetric
    var priority: GoalPriority = .equalPrimary
    var baseline: GoalMeasurement?
    var baselineMeasuredAt: Date?
    var baselineSource: TrainingEvidenceSource?
    var target: GoalMeasurement
    var deadlineLocalDate: String?
    var sourceRaceID: Int?
    var enteredDistanceUnit: TrainingDistanceUnit = .miles
    var enteredLoadUnit: TrainingMassUnit = .pounds
    var isActive = true

    var discipline: TrainingDiscipline { metric.discipline }

    func validationIssues(field: String) -> [TrainingProfileIssue] {
        var issues: [TrainingProfileIssue] = []
        func issue(_ suffix: String, _ message: String) {
            issues.append(TrainingProfileIssue(field: field + "." + suffix, message: message))
        }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issue("title", "Give this goal a name.")
        }
        if let deadlineLocalDate, !Self.isValidLocalDate(deadlineLocalDate) {
            issue("deadline", "Choose a valid calendar date.")
        }
        if let sourceRaceID, sourceRaceID <= 0 || discipline != .running {
            issue("sourceRaceID", "Only a running goal can link to a valid race.")
        }
        if baseline != nil && (baselineMeasuredAt == nil || baselineSource == nil) {
            issue("baseline", "Record when and how this performance was measured.")
        }
        if baseline == nil && (baselineMeasuredAt != nil || baselineSource != nil) {
            issue("baseline", "Add the observed performance or clear its date and source.")
        }
        for (name, value) in [("target", Optional(target)), ("baseline", baseline)] {
            guard let value else { continue }
            func invalid(_ message: String) { issue(name, message) }
            let quantities = [value.distanceMeters, value.durationSeconds, value.loadKilograms]
            if quantities.compactMap({ $0 }).contains(where: { !$0.isFinite || $0 <= 0 }) {
                invalid("Measurements must be finite and greater than zero.")
            }
            if let reps = value.repetitions, reps <= 0 { invalid("Repetitions must be greater than zero.") }
            if let sets = value.sets, sets <= 0 { invalid("Sets must be greater than zero.") }
            if let effort = value.reportedEffort, !effort.isFinite || !(1...10).contains(effort) {
                invalid("Reported effort must be between 1 and 10.")
            }
            switch metric {
            case .racePerformance:
                if value.distanceMeters == nil || value.durationSeconds == nil {
                    invalid("Race performance needs both distance and elapsed time.")
                }
            case .weeklyRunningDistance:
                if value.distanceMeters == nil { invalid("Enter a weekly running distance.") }
                if value.durationSeconds != nil { invalid("Use a separate goal for weekly running time.") }
            case .weeklyRunningDuration:
                if value.durationSeconds == nil { invalid("Enter a weekly running duration.") }
                if value.distanceMeters != nil { invalid("Use a separate goal for weekly running distance.") }
            case .strengthPerformance, .bodyweightRepetitions:
                if value.exerciseID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                    invalid("Choose a specific exercise and variant.")
                }
                if value.repetitions == nil { invalid("Enter the repetition target.") }
                if value.loadConvention == nil { invalid("Specify how the load is measured.") }
                if metric == .bodyweightRepetitions {
                    if value.loadConvention != .bodyweight || value.loadKilograms != nil {
                        invalid("Bodyweight repetition goals must use bodyweight without an external load.")
                    }
                } else if value.loadConvention == .bodyweight || value.loadKilograms == nil {
                    invalid("A loaded strength goal needs an external load and its convention.")
                }
                if value.distanceMeters != nil || value.durationSeconds != nil {
                    invalid("Keep running measurements separate from strength performance.")
                }
            }
            if discipline == .running && (value.loadKilograms != nil || value.loadConvention != nil
                || value.exerciseID != nil || value.repetitions != nil || value.sets != nil) {
                invalid("Keep strength measurements separate from running performance.")
            }
        }
        if let baseline, discipline == .strength,
           baseline.exerciseID != target.exerciseID || baseline.loadConvention != target.loadConvention {
            issue("baseline", "Baseline and target must use the same exercise variant and load convention.")
        }
        return issues
    }

    static func isValidLocalDate(_ value: String) -> Bool {
        guard value.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else { return false }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }
}

struct TrainingDayAvailability: Codable, Equatable, Identifiable {
    var weekday: Int
    var availableMinutes: Int
    var allowsTwoSessions = false
    var id: Int { weekday }
}

struct TrainingBodyMeasurements: Codable, Equatable {
    var heightCentimeters: Double?
    var heightMeasuredAt: Date?
    var heightSource: TrainingEvidenceSource?
    var enteredHeightUnit: TrainingHeightUnit = .inches
    var weightKilograms: Double?
    var weightMeasuredAt: Date?
    var weightSource: TrainingEvidenceSource?
    var enteredWeightUnit: TrainingMassUnit = .pounds
}

struct AthleteTrainingProfile: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion = Self.currentSchemaVersion
    var athleteID: Int
    var revision = UUID()
    var updatedAt = Date()
    var goals: [AthleteTrainingGoal] = []
    var availability: [TrainingDayAvailability] = []
    var equipment: [StrengthEquipment] = []
    var reportedLimitations: String = ""
    var bodyMeasurements: TrainingBodyMeasurements?

    var equalPriorityDisciplines: Set<TrainingDiscipline> {
        Set(goals.filter { $0.isActive && $0.priority == .equalPrimary }.map(\.discipline))
    }

    var needsGoalSetup: Bool { !goals.contains(where: \.isActive) }

    func validationIssues() -> [TrainingProfileIssue] {
        var issues: [TrainingProfileIssue] = []
        func issue(_ field: String, _ message: String) {
            issues.append(TrainingProfileIssue(field: field, message: message))
        }
        if schemaVersion != Self.currentSchemaVersion { issue("schemaVersion", "This profile version is not supported.") }
        if athleteID <= 0 { issue("athleteID", "Sign in to save your training profile.") }
        if Set(goals.map(\.id)).count != goals.count { issue("goals", "Goal identifiers must be unique.") }
        let raceIDs = goals.compactMap(\.sourceRaceID)
        if Set(raceIDs).count != raceIDs.count { issue("goals", "A race is already linked to another goal.") }
        for goal in goals { issues += goal.validationIssues(field: "goals.\(goal.id.uuidString)") }
        if Set(availability.map(\.weekday)).count != availability.count {
            issue("availability", "Each weekday needs only one availability entry.")
        }
        for day in availability {
            if !(1...7).contains(day.weekday) || !(0...1440).contains(day.availableMinutes) {
                issue("availability", "Choose a valid weekday and a time budget from 0 to 1440 minutes.")
            }
            if day.availableMinutes == 0 && day.allowsTwoSessions {
                issue("availability", "An unavailable day cannot allow two sessions.")
            }
        }
        if let body = bodyMeasurements {
            for (field, value, measuredAt, source) in [
                ("height", body.heightCentimeters, body.heightMeasuredAt, body.heightSource),
                ("weight", body.weightKilograms, body.weightMeasuredAt, body.weightSource)
            ] {
                if let value {
                    if !value.isFinite || value <= 0 { issue(field, "Enter a positive, finite measurement.") }
                    if measuredAt == nil || source == nil { issue(field, "Include the measurement date and source.") }
                } else if measuredAt != nil || source != nil {
                    issue(field, "Add the measurement or clear its date and source.")
                }
            }
        }
        return issues
    }
}
