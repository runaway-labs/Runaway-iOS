import SwiftUI

struct AthleteTrainingProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UserSession.self) private var session
    @Environment(DataManager.self) private var dataManager
    @StateObject private var model: AthleteTrainingProfileEditorModel
    @State private var editingGoal: AthleteTrainingGoal?
    @State private var showingStrengthSet = false
    @State private var showingBenchmarks = false
    @State private var confirmingImport = false
    @State private var sessionPreview: TrainingSessionPreviewSnapshot?
    @State private var previewError: String?

    init(athleteID: Int) {
        _model = StateObject(wrappedValue: AthleteTrainingProfileEditorModel(athleteID: athleteID))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("BUILT AROUND WHO YOU'RE BECOMING")
                            .font(AppTheme.Typography.caption).foregroundStyle(.teal)
                        Text("One profile.\nA smarter training week.")
                            .font(AppTheme.Typography.title)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Choose the outcomes that matter. Runaway turns them into measurable running, strength, and recovery decisions.")
                            .font(AppTheme.Typography.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }.padding(.vertical, 8)
                    Label("Protected on device · Synced securely", systemImage: "lock.shield")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Outcomes guide the plan. Benchmarks improve precision, but they are optional and never replace what you are training to become.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if model.loaded {
                    outcomesSection
                    benchmarksSection
                    availabilitySection
                    equipmentSection
                    bodySection
                    evidenceSection
                    Section {
                        Button {
                            do { sessionPreview = try model.sessionPreview() }
                            catch { previewError = error.localizedDescription }
                        } label: {
                            Label("Preview sessions", systemImage: "list.bullet.rectangle")
                        }
                        .disabled(model.isImporting || model.isSaving)
                        .accessibilityIdentifier("previewGoalSessions")
                    } footer: {
                        Text("Review running and strength options, then use Compare with Next Up to inspect progression and accept a future session. Browsing or saving your profile does not change the plan automatically.")
                    }
                    Section {
                        Button(model.isSaving ? "Saving & syncing..." : "Save Training Profile") { model.save() }
                            .font(.headline)
                            .disabled(model.isSaving)
                    } footer: {
                        Text("Profile edits remain a draft until saved. Imported runs and recorded sets are saved separately when you confirm those actions.")
                    }
                } else if model.errorMessage == nil {
                    ProgressView("Opening training profile")
                }
                if let error = model.errorMessage {
                    Section("Needs attention") {
                        Text(error).foregroundStyle(.red)
                        if !model.loaded { Button("Try opening again") { model.load() } }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let receipt = model.receipt {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.teal)
                            .accessibilityHidden(true)
                        Text(receipt)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Dismiss") { model.receipt = nil }
                            .font(.subheadline.weight(.semibold))
                            .accessibilityLabel("Dismiss save confirmation")
                    }
                    .padding()
                    .background(.regularMaterial)
                }
            }
            .scrollContentBackground(.hidden)
            .background(LinearGradient(colors: [AppTheme.Colors.adaptiveBackground,
                Color.teal.opacity(0.07)], startPoint: .top, endPoint: .bottom))
            .tint(.teal)
            .navigationTitle("Training Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task { model.load() }
            .onReceive(NotificationCenter.default.publisher(for: .trainingSessionInvalidated)) { _ in
                editingGoal = nil
                showingStrengthSet = false
                sessionPreview = nil
                previewError = nil
                dismiss()
            }
            .sheet(item: $editingGoal) { goal in
                TrainingGoalEditor(goal: goal) { updated in
                    guard model.loaded else { return }
                    if let index = model.draft.goals.firstIndex(where: { $0.id == updated.id }) {
                        model.draft.goals[index] = updated
                    } else { model.draft.goals.append(updated) }
                }
            }
            .sheet(isPresented: $showingStrengthSet) {
                TrainingStrengthEvidenceEditor(athleteID: model.athleteID, onSave: model.record)
            }
            .sheet(item: $sessionPreview) { snapshot in
                CompleteGoalSessionPreviewView(snapshot: snapshot).safeAreaInset(edge: .bottom) { GoalDailyShadowComparisonEntry(snapshot: snapshot) }
            }
            .alert("Cannot preview yet", isPresented: Binding(
                get: { previewError != nil }, set: { if !$0 { previewError = nil } })) {
                Button("OK", role: .cancel) { previewError = nil }
            } message: {
                Text(previewError ?? "Save your profile and try again.")
            }
            .confirmationDialog("Import completed runs?", isPresented: $confirmingImport, titleVisibility: .visible) {
                Button("Import loaded runs") { model.importRuns(dataManager.activities) }
            } message: {
                Text("Uses activities currently loaded for this account. Walks, planned sessions, missing measurements, and unowned records are excluded. Existing corrections are preserved. This saves evidence immediately.")
            }
        }
    }

    private var outcomesSection: some View {
        Section {
            ForEach(AthleteOutcome.allCases, id: \.self) { outcome in
                Button { toggle(outcome) } label: {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: outcome.systemImage)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(isSelected(outcome) ? Color.orange : Color.secondary)
                            .frame(width: 34, height: 34)
                            .background((isSelected(outcome) ? Color.orange : Color.secondary).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(outcome.title).font(.headline).foregroundStyle(.primary)
                            Text(outcome.detail).font(.subheadline).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: isSelected(outcome) ? "checkmark.circle.fill" : "circle")
                            .font(.title3).foregroundStyle(isSelected(outcome) ? Color.teal : Color.secondary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let message = model.draft.outcomeValidationMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.orange)
            }
        } header: { Text("Your outcomes") }
          footer: { Text("Choose at least one. These outcomes share priority; recovery and recent work determine the right session each day.") }
    }

    private var benchmarksSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showingBenchmarks) {
                if model.draft.goals.isEmpty {
                    Text("No benchmarks yet. Runaway can still build your plan from completed activities.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.draft.goals) { goal in
                    Button { editingGoal = goal } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(goal.title).foregroundStyle(.primary)
                            Text(goalSummary(goal)).font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Menu("Add optional benchmark", systemImage: "plus.circle") {
                    ForEach(TrainingGoalMetric.allCases, id: \.self) { metric in
                        Button(metric.editorTitle) { addGoal(metric) }
                    }
                }
            } label: {
                Label("Performance benchmarks", systemImage: "chart.line.uptrend.xyaxis")
            }
        } footer: {
            Text("Benchmarks help Runaway choose starting paces, repetitions, and loads. They are supporting evidence, not separate goals you must pursue.")
        }
    }

    private var availabilitySection: some View {
        Section {
            ForEach($model.draft.availability) { $day in
                VStack(alignment: .leading, spacing: 8) {
                    Stepper("\(Calendar.current.weekdaySymbols[day.weekday - 1]): \(day.availableMinutes) min",
                        value: Binding(get: { day.availableMinutes }, set: {
                            day.availableMinutes = $0
                            if $0 == 0 { day.allowsTwoSessions = false }
                        }), in: 0...1440, step: 15)
                    if day.availableMinutes > 0 {
                        Toggle("Allow two sessions", isOn: $day.allowsTwoSessions).font(.subheadline)
                    }
                }
            }
        } header: { Text("Weekly rhythm") }
          footer: { Text("Set the time you can realistically train. Zero means unavailable. Two sessions share the day's total time budget and are always opt-in.") }
    }

    private var equipmentSection: some View {
        Section("Equipment & limitations") {
            ForEach([StrengthEquipment.bodyweight, .dumbbells, .fullGym], id: \.self) { item in
                Toggle(item == .bodyweight ? "Bodyweight" : item == .dumbbells ? "Dumbbells" : "Full gym",
                    isOn: Binding(get: { model.draft.equipment.contains(item) }, set: { selected in
                        model.draft.equipment.removeAll { $0 == item || $0 == .unspecified }
                        if selected { model.draft.equipment.append(item) }
                    }))
            }
            TextField("Limitations or movements to avoid (optional)", text: $model.draft.reportedLimitations, axis: .vertical)
                .lineLimit(2...5)
        }
    }

    private var bodySection: some View {
        Section {
            TextField("Weight (\(weightUnit == .pounds ? "lb" : "kg"), optional)",
                value: bodyNumber(\.weightKilograms, factor: weightUnit == .pounds ? 0.45359237 : 1, weight: true), format: .number)
                .keyboardType(.decimalPad)
            if model.draft.bodyMeasurements?.weightKilograms != nil {
                DatePicker("Weight measured", selection: bodyDate(weight: true), in: ...Date(), displayedComponents: .date)
            }
            TextField("Height (\(heightUnit == .inches ? "in" : "cm"), optional)",
                value: bodyNumber(\.heightCentimeters, factor: heightUnit == .inches ? 2.54 : 1, weight: false), format: .number)
                .keyboardType(.decimalPad)
            if model.draft.bodyMeasurements?.heightCentimeters != nil {
                DatePicker("Height measured", selection: bodyDate(weight: false), in: ...Date(), displayedComponents: .date)
            }
        } header: { Text("Optional measurements") }
          footer: { Text("These are dated, self-reported measurements, not estimates. They are not required to set a performance goal.") }
    }

    private var evidenceSection: some View {
        Section {
            Text("\(model.observations.count) current performance records")
                .font(.headline)
            Button { confirmingImport = true } label: {
                Label(model.isImporting ? "Importing runs..." : "Import completed runs", systemImage: "arrow.down.circle")
            }.disabled(model.isImporting || dataManager.isLoadingActivities)
            Button { showingStrengthSet = true } label: {
                Label("Record an actual strength set", systemImage: "plus.circle")
            }.disabled(model.isImporting)
            ForEach(Array(model.observations.suffix(8).reversed())) { record in
                VStack(alignment: .leading, spacing: 4) {
                    Text(evidenceSummary(record)).font(.subheadline)
                    Text(record.measuredAt, format: .dateTime.month(.abbreviated).day().year())
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: { Text("Completed performance") }
          footer: { Text("Only actual evidence belongs here. Imported running time is elapsed time, not moving time. Imported runs do not automatically establish race fitness, and an activity summary cannot supply lifting sets or weights.") }
    }

    private func addGoal(_ metric: TrainingGoalMetric) {
        var target = GoalMeasurement()
        if metric.discipline == .strength {
            target.loadConvention = metric == .bodyweightRepetitions ? .bodyweight : .total
        }
        var goal = AthleteTrainingGoal(title: metric.editorTitle, metric: metric, target: target)
        goal.enteredDistanceUnit = UnitPreferences.shared.isMetric ? .kilometers : .miles
        goal.enteredLoadUnit = UnitPreferences.shared.isMetric ? .kilograms : .pounds
        editingGoal = goal
    }

    private func isSelected(_ outcome: AthleteOutcome) -> Bool {
        model.draft.resolvedOutcomes.contains(outcome)
    }

    private func toggle(_ outcome: AthleteOutcome) {
        var selected = model.draft.resolvedOutcomes
        if let index = selected.firstIndex(of: outcome) {
            selected.remove(at: index)
        } else {
            selected.append(outcome)
        }
        model.draft.outcomes = AthleteOutcome.allCases.filter(selected.contains)
    }

    private func goalSummary(_ goal: AthleteTrainingGoal) -> String {
        let target = goal.target
        var parts: [String] = []
        if let meters = target.distanceMeters {
            parts.append(UnitFormatter.formatDistance(meters,
                unit: goal.enteredDistanceUnit == .miles ? .miles : .kilometers))
        }
        if let seconds = target.durationSeconds { parts.append(String(format: "%.1f min", seconds / 60)) }
        if let exercise = target.exerciseID { parts.append(TrainingExerciseCatalog.title(exercise)) }
        if let reps = target.repetitions { parts.append("\(reps) reps") }
        if let kg = target.loadKilograms {
            parts.append(String(format: "%.1f %@", goal.enteredLoadUnit == .pounds ? kg / 0.45359237 : kg,
                goal.enteredLoadUnit == .pounds ? "lb" : "kg"))
        }
        if let date = goal.deadlineLocalDate { parts.append("by \(date)") }
        return parts.joined(separator: " / ")
    }

    private func evidenceSummary(_ record: TrainingObservation) -> String {
        switch record.value {
        case .run(let meters, let seconds, _):
            return "Run: \(UnitFormatter.formatDistance(meters)), \(String(format: "%.1f", seconds / 60)) min"
        case .strengthSet(let exercise, _, let reps, let load, let assistance, let convention, _):
            let kg = load ?? assistance
            let mass = kg.map { String(format: "%.1f %@", UnitPreferences.shared.isMetric ? $0 : $0 / 0.45359237,
                                       UnitPreferences.shared.isMetric ? "kg" : "lb") }
            let qualifier = assistance != nil ? "assistance" : convention == .perHand ? "per hand" : convention == .machine ? "machine" : "total"
            return "\(TrainingExerciseCatalog.title(exercise)): \(reps) reps" + (mass.map { ", \($0) \(qualifier)" } ?? ", bodyweight")
        case .bodyWeight: return "Body weight measurement"
        case .height: return "Height measurement"
        }
    }

    private var weightUnit: TrainingMassUnit { model.draft.bodyMeasurements?.enteredWeightUnit ?? .pounds }
    private var heightUnit: TrainingHeightUnit { model.draft.bodyMeasurements?.enteredHeightUnit ?? .inches }

    private func bodyNumber(_ key: WritableKeyPath<TrainingBodyMeasurements, Double?>,
                            factor: Double, weight: Bool) -> Binding<Double?> {
        Binding(get: { model.draft.bodyMeasurements?[keyPath: key].map { $0 / factor } }, set: { value in
            var body = model.draft.bodyMeasurements ?? TrainingBodyMeasurements()
            body[keyPath: key] = value.map { $0 * factor }
            if weight {
                body.weightMeasuredAt = value == nil ? nil : Date()
                body.weightSource = value == nil ? nil : .userEntered
            } else {
                body.heightMeasuredAt = value == nil ? nil : Date()
                body.heightSource = value == nil ? nil : .userEntered
            }
            model.draft.bodyMeasurements = body
        })
    }

    private func bodyDate(weight: Bool) -> Binding<Date> {
        Binding(get: {
            (weight ? model.draft.bodyMeasurements?.weightMeasuredAt : model.draft.bodyMeasurements?.heightMeasuredAt) ?? Date()
        }, set: { date in
            guard var body = model.draft.bodyMeasurements else { return }
            if weight { body.weightMeasuredAt = date; body.weightSource = .userEntered }
            else { body.heightMeasuredAt = date; body.heightSource = .userEntered }
            model.draft.bodyMeasurements = body
        })
    }
}
