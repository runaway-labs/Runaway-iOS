import SwiftUI

extension TrainingGoalMetric {
    var editorTitle: String {
        switch self {
        case .racePerformance: return "Race performance"
        case .weeklyRunningDistance: return "Weekly running distance"
        case .weeklyRunningDuration: return "Weekly running time"
        case .strengthPerformance: return "Strength performance"
        case .bodyweightRepetitions: return "Bodyweight repetitions"
        }
    }
}

enum TrainingExerciseCatalog {
    static let entries: [(id: String, title: String)] = [
        ("barbell-back-squat", "Barbell back squat"),
        ("barbell-deadlift", "Conventional barbell deadlift"),
        ("barbell-bench-press", "Barbell bench press"),
        ("dumbbell-bench-press", "Dumbbell bench press"),
        ("dumbbell-row", "Dumbbell row"),
        ("barbell-overhead-press", "Barbell overhead press"),
        ("pull-up", "Pull-up"), ("push-up", "Push-up"),
        ("machine-leg-press", "Machine leg press"),
        ("machine-lat-pulldown", "Machine lat pulldown")
    ]

    static func title(_ id: String) -> String { entries.first { $0.id == id }?.title ?? id }
}

struct TrainingGoalEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var goal: AthleteTrainingGoal
    @State private var issues: [TrainingProfileIssue] = []
    let onApply: (AthleteTrainingGoal) -> Void

    init(goal: AthleteTrainingGoal, onApply: @escaping (AthleteTrainingGoal) -> Void) {
        _goal = State(initialValue: goal)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Goal name", text: $goal.title)
                    Picker("Priority", selection: $goal.priority) {
                        Text("Equal priority").tag(GoalPriority.equalPrimary)
                        Text("Supporting").tag(GoalPriority.supporting)
                    }
                    Toggle("Active goal", isOn: $goal.isActive)
                } footer: {
                    Text("Running and strength can both be equal priority. Neither is automatically demoted.")
                }
                Section("Target: what you want to achieve") {
                    PerformanceMeasurementFields(measurement: $goal.target, metric: goal.metric,
                        distanceUnit: goal.enteredDistanceUnit, massUnit: goal.enteredLoadUnit)
                    Toggle("Set a target date", isOn: Binding(
                        get: { goal.deadlineLocalDate != nil },
                        set: { goal.deadlineLocalDate = $0 ? Self.localDate(Date()) : nil }))
                    if goal.deadlineLocalDate != nil {
                        DatePicker("Target date", selection: Binding(
                            get: { Self.calendarDate(goal.deadlineLocalDate) },
                            set: { goal.deadlineLocalDate = Self.localDate($0) }), displayedComponents: .date)
                    }
                }
                Section {
                    Toggle("I have a measured baseline", isOn: Binding(
                        get: { goal.baseline != nil },
                        set: { enabled in
                            goal.baseline = enabled ? GoalMeasurement(
                                exerciseID: goal.target.exerciseID, loadConvention: goal.target.loadConvention) : nil
                            goal.baselineMeasuredAt = enabled ? Date() : nil
                            goal.baselineSource = enabled ? .userEntered : nil
                        }))
                    if goal.baseline != nil {
                        PerformanceMeasurementFields(measurement: Binding(
                            get: { goal.baseline ?? GoalMeasurement() },
                            set: { goal.baseline = $0; goal.baselineSource = .userEntered }),
                            metric: goal.metric, distanceUnit: goal.enteredDistanceUnit, massUnit: goal.enteredLoadUnit)
                        DatePicker("Measured on", selection: Binding(
                            get: { goal.baselineMeasuredAt ?? Date() },
                            set: { goal.baselineMeasuredAt = $0; goal.baselineSource = .userEntered }),
                            in: ...Date(), displayedComponents: .date)
                    }
                } header: { Text("Current ability: what you have actually done") }
                  footer: { Text("Leave unknown performance blank. A target is not evidence of current ability. No maximal test is required.") }
                if !issues.isEmpty {
                    Section("Before applying") {
                        ForEach(issues) { issue in Text(issue.message).foregroundStyle(.red) }
                    }
                }
                Section {
                    Text("Apply updates your draft. Save profile on the previous screen to keep the changes.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(goal.metric.editorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .tint(.teal)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        issues = goal.validationIssues(field: "goal")
                        if issues.isEmpty { onApply(goal); dismiss() }
                    }
                }
            }
        }
    }

    private static func dateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }
    private static func localDate(_ date: Date) -> String { dateFormatter().string(from: date) }
    private static func calendarDate(_ value: String?) -> Date {
        value.flatMap { dateFormatter().date(from: $0) } ?? Date()
    }
}

struct PerformanceMeasurementFields: View {
    @Binding var measurement: GoalMeasurement
    let metric: TrainingGoalMetric
    let distanceUnit: TrainingDistanceUnit
    let massUnit: TrainingMassUnit

    var body: some View {
        if metric == .racePerformance || metric == .weeklyRunningDistance {
            TextField("Distance (\(distanceUnit == .miles ? "mi" : "km"))",
                value: number(\.distanceMeters, factor: distanceUnit == .miles ? 1609.344 : 1000), format: .number)
                .keyboardType(.decimalPad)
        }
        if metric == .racePerformance || metric == .weeklyRunningDuration {
            TextField("Elapsed time (minutes)", value: number(\.durationSeconds, factor: 60), format: .number)
                .keyboardType(.decimalPad)
        }
        if metric.discipline == .strength {
            Picker("Exercise variant", selection: Binding(
                get: { measurement.exerciseID ?? "" }, set: { measurement.exerciseID = $0.isEmpty ? nil : $0 })) {
                Text("Choose exercise").tag("")
                ForEach(TrainingExerciseCatalog.entries, id: \.id) { item in Text(item.title).tag(item.id) }
                if let id = measurement.exerciseID, !TrainingExerciseCatalog.entries.contains(where: { $0.id == id }) {
                    Text(id).tag(id)
                }
            }
            if metric == .strengthPerformance {
                Picker("Load convention", selection: Binding(
                    get: { measurement.loadConvention ?? .total }, set: { measurement.loadConvention = $0 })) {
                    Text("Total external load").tag(LoadConvention.total)
                    Text("Per hand").tag(LoadConvention.perHand)
                    Text("Machine setting").tag(LoadConvention.machine)
                }
                TextField("Load (\(massUnit == .pounds ? "lb" : "kg"))",
                    value: number(\.loadKilograms, factor: massUnit == .pounds ? 0.45359237 : 1), format: .number)
                    .keyboardType(.decimalPad)
            }
            TextField("Repetitions", value: $measurement.repetitions, format: .number).keyboardType(.numberPad)
            TextField("Sets (optional)", value: $measurement.sets, format: .number).keyboardType(.numberPad)
        }
    }

    private func number(_ key: WritableKeyPath<GoalMeasurement, Double?>, factor: Double) -> Binding<Double?> {
        Binding(get: { measurement[keyPath: key].map { $0 / factor } },
                set: { measurement[keyPath: key] = $0.map { $0 * factor } })
    }
}
