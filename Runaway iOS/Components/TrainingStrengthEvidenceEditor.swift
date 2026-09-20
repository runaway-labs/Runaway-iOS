import SwiftUI

/// Records one actual set, not a prescribed load or a whole completed workout.
struct TrainingStrengthEvidenceEditor: View {
    @Environment(\.dismiss) private var dismiss
    let athleteID: Int
    let onSave: (TrainingObservation) throws -> Void
    @State private var exercise = ""
    @State private var convention = LoadConvention.total
    @State private var equipment = ""
    @State private var repetitions: Int?
    @State private var load: Double?
    @State private var assistance: Double?
    @State private var effort: Double?
    @State private var measuredAt = Date()
    @State private var errorMessage: String?
    @State private var submission = ManualStrengthEvidenceDraft()
    private let metric = UnitPreferences.shared.isMetric

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Exercise", selection: $exercise) {
                        Text("Choose exercise").tag("")
                        ForEach(TrainingExerciseCatalog.entries, id: \.id) { item in Text(item.title).tag(item.id) }
                    }
                    Picker("How was the load measured?", selection: $convention) {
                        Text("Total external load").tag(LoadConvention.total)
                        Text("Per hand").tag(LoadConvention.perHand)
                        Text("Machine setting").tag(LoadConvention.machine)
                        Text("Bodyweight").tag(LoadConvention.bodyweight)
                    }
                    TextField("Actual repetitions", value: $repetitions, format: .number).keyboardType(.numberPad)
                    if convention == .bodyweight {
                        TextField("Assistance (\(metric ? "kg" : "lb"), optional)", value: $assistance, format: .number)
                            .keyboardType(.decimalPad)
                    } else {
                        TextField("Actual load (\(metric ? "kg" : "lb"))", value: $load, format: .number)
                            .keyboardType(.decimalPad)
                    }
                    if convention == .machine || (convention == .bodyweight && assistance != nil) {
                        TextField("Equipment identifier, e.g. gym leg press 1", text: $equipment)
                    }
                    TextField("Reps left in reserve (optional, 0 = none)", value: $effort, format: .number)
                        .keyboardType(.decimalPad)
                    DatePicker("Performed", selection: $measuredAt, in: ...Date())
                } footer: {
                    Text("Enter a set you actually performed. Machine settings and per-hand loads are not interchangeable. Leave effort blank if you do not know.")
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
                Section {
                    Text("Save set writes this evidence immediately to your protected local history. It does not mark a planned workout complete.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Record an actual set")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.teal)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save set", action: save) }
            }
        }
    }

    private func save() {
        let factor = metric ? 1.0 : 0.45359237
        let trimmedEquipment = equipment.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = TrainingObservationValue.strengthSet(exerciseID: exercise,
            equipmentID: trimmedEquipment.isEmpty ? nil : trimmedEquipment,
            repetitions: repetitions ?? 0,
            externalLoadKilograms: convention == .bodyweight ? nil : load.map { $0 * factor },
            assistanceKilograms: convention == .bodyweight ? assistance.map { $0 * factor } : nil,
            convention: convention,
            effort: effort.map { TrainingEffortObservation(scale: .repetitionsInReserve, value: $0) })
        guard value.isValid else {
            errorMessage = "Choose an exercise and enter positive reps and load. Machines require an equipment identifier. Reps in reserve must be zero or more."
            return
        }
        do {
            let record = try submission.observation(athleteID: athleteID, measuredAt: measuredAt, value: value)
            try onSave(record)
            dismiss()
        }
        catch { errorMessage = error.localizedDescription }
    }
}
