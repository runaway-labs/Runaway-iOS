import SwiftUI

struct TrainingSessionResultView: View {
    let reference: TrainingSessionResult.Reference
    let acceptedWorkout: DailyWorkout?
    let existingResult: TrainingSessionResult?
    @Environment(DataManager.self) private var dataManager
    @Environment(\.dismiss) private var dismiss
    @State private var resultID = UUID()
    @State private var completedAt = Date()
    @State private var elapsedMinutes: Double?
    @State private var effort: Int?
    @State private var bodyState: ReflectionBodyState?
    @State private var confirmed = false
    @State private var drafts: [EntryDraft]
    @State private var alertText: String?
    @State private var saved = false

    private struct EntryDraft: Identifiable {
        let id: String
        var skipped = false
        var minutes: Double?
        var reps: Int?
        var load: Double?
        var assistance: Double?
        var reserve: Double?
    }

    init(
        reference: TrainingSessionResult.Reference,
        acceptedWorkout: DailyWorkout? = nil,
        existingResult: TrainingSessionResult? = nil
    ) {
        self.reference = reference
        self.acceptedWorkout = acceptedWorkout
        self.existingResult = existingResult
        let factor = reference.massUnit == .pounds ? 1 / 0.45359237 : 1
        _resultID = State(initialValue: existingResult?.id ?? UUID())
        _completedAt = State(initialValue: existingResult?.completedAt ?? Date())
        _elapsedMinutes = State(initialValue: existingResult.map { $0.elapsedSeconds / 60 })
        _effort = State(initialValue: existingResult?.perceivedEffort)
        _bodyState = State(initialValue: existingResult?.bodyState)
        _drafts = State(initialValue: reference.items.map { item in
            let entry = existingResult?.entries.first(where: { $0.itemID == item.id })
            return EntryDraft(id: item.id, skipped: entry?.skipped ?? false,
                minutes: entry?.seconds.map { $0 / 60 } ?? item.durationSeconds.map { $0 / 60 },
                reps: entry?.repetitions,
                load: entry?.loadKilograms.map { $0 * factor } ?? item.loadKilograms.map { $0 * factor },
                assistance: entry?.assistanceKilograms.map { $0 * factor } ?? item.assistanceKilograms.map { $0 * factor },
                reserve: entry?.repsInReserve)
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(reference.goalTitle).font(.headline)
                    Text(acceptedWorkout == nil
                        ? "Record work you actually completed, using this session as a reference. Review the shown values and edit differences. This does not mark Next Up complete."
                        : "This record is linked to your accepted workout. Review its exact prescription, enter actual work and mark skipped blocks honestly. Plan and Next Up will show Completed or Partial session based on what you record.")
                    Text("Use the shown exercise variants. Skip exercises you did not perform; do not record substitutions under the original exercise name.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("When and how long") {
                    DatePicker("Completed", selection: $completedAt, in: ...Date())
                    numberField("Actual total minutes", value: $elapsedMinutes)
                    Text("Include warm-up, cooldown, rest and setup. Reference duration: \(reference.prescribedSeconds / 60) min \(reference.prescribedSeconds % 60) sec. Enter your actual elapsed time.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach($drafts) { $draft in
                    if let item = reference.items.first(where: { $0.id == draft.id }) {
                        Section(item.title) {
                            Toggle("Skipped", isOn: $draft.skipped)
                            if !draft.skipped {
                                if item.kind == .strength {
                                    if let reps = item.prescribedRepetitions {
                                        Text("Accepted prescription: \(reps) reps")
                                            .font(.caption).foregroundStyle(.secondary)
                                    } else if let reps = item.repetitions {
                                        Text("Reference: \(reps.lowerBound)-\(reps.upperBound) reps")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    TextField("Actual reps", value: $draft.reps, format: .number)
                                        .keyboardType(.numberPad)
                                    if item.convention == .bodyweight {
                                        Text("Bodyweight exercise")
                                        numberField("Assistance (\(massLabel), optional)", value: $draft.assistance)
                                    } else {
                                        numberField("Actual load (\(massLabel) \(item.convention == .perHand ? "per hand" : "total"))", value: $draft.load)
                                    }
                                    numberField("Reps left in reserve", value: $draft.reserve)
                                    Button("Copy values to this exercise's other sets") { copyValues(from: draft.id) }
                                        .font(.caption)
                                    Text("Copies reps, load and effort, including the other side. Use only when those sets really matched.")
                                        .font(.caption).foregroundStyle(.secondary)
                                } else {
                                    numberField("Actual minutes", value: $draft.minutes)
                                }
                            }
                        }
                    }
                }
                Section("How it felt") {
                    Picker("Whole-session effort", selection: $effort) {
                        Text("Choose effort").tag(Optional<Int>.none)
                        ForEach(1...10, id: \.self) { Text("\($0) / 10").tag(Optional($0)) }
                    }
                    Picker("Body response", selection: $bodyState) {
                        Text("Choose response").tag(Optional<ReflectionBodyState>.none)
                        ForEach(ReflectionBodyState.allCases, id: \.self) {
                            Text($0.rawValue.capitalized).tag(Optional($0))
                        }
                    }
                    Text("Effort and discomfort are your reports, not estimates from the plan.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Toggle("These values describe work I actually completed", isOn: $confirmed)
                    Button(existingResult == nil ? "Confirm and save completed work" : "Save corrected values") { save() }
                        .disabled(!confirmed || result == nil || saved)
                        .accessibilityIdentifier("saveCompletedTrainingSession")
                    Text("Enter actual reps, load and reps in reserve for each performed set, answer how it felt, and check the total time. Results stay on this iPhone and support fresh progression proposals. Accepted workouts update their completion status, not the rest of the week's prescription or your widgets and notifications.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(existingResult == nil ? "Record completed work" : "Edit completed work")
            .navigationBarTitleDisplayMode(.inline)
            .tint(AppTheme.Colors.strideBlue)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onReceive(NotificationCenter.default.publisher(for: .trainingSessionInvalidated)) { _ in dismiss() }
            .alert(saved ? "Session saved" : "Could not save", isPresented: Binding(
                get: { alertText != nil }, set: { if !$0 { alertText = nil } }
            )) {
                Button("OK") { if saved { dismiss() } }
            } message: { Text(alertText ?? "") }
        }
    }

    private var massLabel: String { reference.massUnit == .pounds ? "lb" : "kg" }

    private func numberField(_ label: String, value: Binding<Double?>) -> some View {
        TextField(label, value: value, format: .number.precision(.fractionLength(0...3)))
            .keyboardType(.decimalPad)
    }

    private var result: TrainingSessionResult? {
        guard let elapsedMinutes, let effort, let bodyState else { return nil }
        let factor = reference.massUnit == .pounds ? 0.45359237 : 1
        let entries = drafts.map { draft in
            TrainingSessionResult.Entry(itemID: draft.id, skipped: draft.skipped,
                seconds: draft.skipped ? nil : draft.minutes.map { $0 * 60 },
                repetitions: draft.skipped ? nil : draft.reps,
                loadKilograms: draft.skipped ? nil : draft.load.map { $0 * factor },
                assistanceKilograms: draft.skipped ? nil : draft.assistance.map { $0 * factor },
                repsInReserve: draft.skipped ? nil : draft.reserve)
        }
        let value = TrainingSessionResult(id: resultID, reference: reference, completedAt: completedAt,
            recordedAt: existingResult?.recordedAt ?? Date(), elapsedSeconds: elapsedMinutes * 60,
            perceivedEffort: effort, bodyState: bodyState, entries: entries)
        if let acceptedWorkout {
            guard completedAt >= Calendar.current.startOfDay(for: acceptedWorkout.date),
                  completedAt >= reference.generatedAt else { return nil }
        }
        return value.isValid ? value : nil
    }

    private func copyValues(from id: String) {
        guard let source = drafts.first(where: { $0.id == id }),
              let exercise = reference.items.first(where: { $0.id == id })?.exerciseID else { return }
        let ids = Set(reference.items.filter { $0.exerciseID == exercise }.map(\.id))
        for index in drafts.indices where drafts[index].id != id && ids.contains(drafts[index].id) && !drafts[index].skipped {
            drafts[index].reps = source.reps
            drafts[index].load = source.load
            drafts[index].assistance = source.assistance
            drafts[index].reserve = source.reserve
        }
    }

    private func save() {
        guard confirmed, let result, !saved else { return }
        do {
            if let acceptedWorkout {
                guard UserSession.shared.isReady, UserSession.shared.userId == reference.athleteID else {
                    throw AcceptedPrescriptionCompletionPolicy.Failure.stalePlan
                }
                try AcceptedPrescriptionCompletionPolicy.validate(result, workout: acceptedWorkout,
                    currentPlan: dataManager.currentWeeklyPlan, athleteID: reference.athleteID, now: Date())
            }
            let repository = ProtectedTrainingRepository(activeAthleteID: {
                UserSession.shared.isReady ? UserSession.shared.userId : nil
            })
            if let existingResult {
                try repository.replaceSessionResult(result, replacing: existingResult, athleteID: reference.athleteID)
            } else {
                try repository.appendSessionResult(result, athleteID: reference.athleteID)
            }
            saved = true
            if acceptedWorkout != nil {
                // Updating the presenting plan here can rebuild the open form.
                // The presenting panel refreshes status after this sheet closes.
                alertText = "Actual work saved. Close this confirmation to update Plan and Next Up to \(result.isPartial ? "Partial session" : "Completed"). The rest of your week is unchanged."
            } else {
                alertText = "Actual work saved on this iPhone\(result.isPartial ? " as a partial session" : ""). Review it in Completed session records. Your live plan has not changed."
            }
        } catch { alertText = error.localizedDescription }
    }
}

struct TrainingSessionHistoryView: View {
    let athleteID: Int
    @Environment(DataManager.self) private var dataManager
    @Environment(\.dismiss) private var dismiss
    @State private var results: [TrainingSessionResult] = []
    @State private var observations: [TrainingObservation] = []
    @State private var error: String?
    @State private var editingResult: TrainingSessionResult?

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.secondary) }
                if results.isEmpty && error == nil { Text("No completed-session records yet.") }
                ForEach(results) { result in
                    DisclosureGroup {
                        Text(result.isPartial ? "Partial session" : "Recorded session")
                        Text("\((result.elapsedSeconds / 60).formatted()) min elapsed; effort \(result.perceivedEffort)/10; body: \(result.bodyState.rawValue)")
                        ForEach(result.reference.items) { item in
                            if let entry = result.entries.first(where: { $0.itemID == item.id }) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).font(.subheadline.bold())
                                    Text(summary(entry, item: item, unit: result.reference.massUnit))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button("Edit recorded values") { editingResult = result }
                        ForEach(matchingRuns(for: result)) { observation in
                            Button {
                                link(observation, to: result)
                            } label: {
                                Label(linkLabel(observation), systemImage: "link")
                            }
                        }
                        if result.reference.items.contains(where: { $0.kind == .running })
                            && matchingRuns(for: result).isEmpty {
                            Text("No unlinked synced run was found for this day.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(result.reference.goalTitle)
                            Text(result.completedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Completed session records")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { loadResults() }
            .sheet(item: $editingResult, onDismiss: {
                loadResults()
                try? dataManager.refreshAcceptedWorkoutCompletions()
            }) { result in
                TrainingSessionResultView(reference: result.reference, existingResult: result)
            }
            .onReceive(NotificationCenter.default.publisher(for: .trainingSessionInvalidated)) { _ in
                results = []; dismiss()
            }
        }
    }

    private func loadResults() {
        do {
            results = try ProtectedTrainingRepository(activeAthleteID: {
                UserSession.shared.isReady ? UserSession.shared.userId : nil
            }).sessionResults(athleteID: athleteID)
            observations = try ProtectedTrainingRepository(activeAthleteID: {
                UserSession.shared.isReady ? UserSession.shared.userId : nil
            }).currentObservations(athleteID: athleteID)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func matchingRuns(for result: TrainingSessionResult) -> [TrainingObservation] {
        guard result.reference.items.contains(where: { $0.kind == .running }) else { return [] }
        return observations.filter { observation in
            guard observation.source == .importedActivity, observation.sessionID == nil,
                  case .run = observation.value else { return false }
            return Calendar.current.isDate(observation.measuredAt, inSameDayAs: result.completedAt)
        }
    }

    private func link(_ observation: TrainingObservation, to result: TrainingSessionResult) {
        do {
            let repository = ProtectedTrainingRepository(activeAthleteID: {
                UserSession.shared.isReady ? UserSession.shared.userId : nil
            })
            try repository.linkObservation(observation.id, toSessionResult: result.id, athleteID: athleteID)
            loadResults()
        } catch { self.error = error.localizedDescription }
    }

    private func linkLabel(_ observation: TrainingObservation) -> String {
        guard case let .run(distance, seconds, _) = observation.value else { return "Link synced run" }
        let distanceText = UnitFormatter.formatDistance(distance, decimals: 1, includeUnit: true)
        return "Link synced run · \(distanceText) · \(Int((seconds / 60).rounded())) min"
    }

    private func summary(_ entry: TrainingSessionResult.Entry, item: TrainingSessionResult.Item,
                         unit: TrainingMassUnit) -> String {
        if entry.skipped { return "Skipped" }
        if let seconds = entry.seconds { return "\((seconds / 60).formatted()) min" }
        let factor = unit == .pounds ? 1 / 0.45359237 : 1
        let label = unit == .pounds ? "lb" : "kg"
        var text = "\(entry.repetitions ?? 0) reps"
        if let load = entry.loadKilograms {
            text += ", \((load * factor).formatted(.number.precision(.fractionLength(0...2)))) \(label) \(item.convention == .perHand ? "per hand" : "total")"
        } else if let assistance = entry.assistanceKilograms {
            text += ", \((assistance * factor).formatted(.number.precision(.fractionLength(0...2)))) \(label) assistance"
        } else { text += ", bodyweight" }
        if let reserve = entry.repsInReserve { text += ", \(reserve.formatted()) reps in reserve" }
        return text
    }
}
