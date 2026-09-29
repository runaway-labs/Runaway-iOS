import SwiftUI

struct ManualRaceSheet: View {
    @Environment(\.dismiss) private var dismiss

    let existingRace: AthleteRace?
    let onSaved: (AthleteRace) -> Void

    @State private var raceName = ""
    @State private var raceDate = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var selectedDistance: RaceDistance = .halfMarathon
    @State private var selectedDistanceUnit: DistanceUnit
    @State private var customDistance = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(existingRace: AthleteRace? = nil, onSaved: @escaping (AthleteRace) -> Void) {
        self.existingRace = existingRace
        self.onSaved = onSaved
        let initialUnit = existingRace?.resolvedDistanceUnit(
            fallback: UnitPreferences.shared.distanceUnit
        ) ?? UnitPreferences.shared.distanceUnit
        _selectedDistanceUnit = State(initialValue: initialUnit)

        if let edit = existingRace.flatMap({ ManualRaceEdit(race: $0, fallbackUnit: initialUnit) }) {
            let distance = RaceDistance.matching(miles: edit.draft.distanceMiles)
            _raceName = State(initialValue: edit.draft.name)
            _raceDate = State(initialValue: edit.draft.date)
            _selectedDistance = State(initialValue: distance)
            _customDistance = State(
                initialValue: distance == .custom
                    ? distanceValue(fromMiles: edit.draft.distanceMiles, unit: initialUnit)
                        .formatted(.number.precision(.fractionLength(0...2)))
                    : ""
            )
        }
    }

    private var existingEdit: ManualRaceEdit? {
        existingRace.flatMap { ManualRaceEdit(race: $0) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [AppTheme.Colors.backgroundElevated, AppTheme.Colors.background],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        intro
                        raceDetails
                        saveButton

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(AppTheme.Typography.footnote)
                                .foregroundStyle(AppTheme.Colors.error)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(existingEdit == nil ? "Target Race" : "Edit Race")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var intro: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "flag.checkered.2.crossed")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.infoBlueLight)
                .frame(width: 48, height: 48)
                .background(AppTheme.Colors.infoBackground, in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 5) {
                Text("Give the plan a finish line")
                    .font(AppTheme.Typography.title3)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("Your race date and distance shape weekly volume, long runs, and taper timing.")
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
    }

    private var raceDetails: some View {
        VStack(alignment: .leading, spacing: 18) {
            fieldLabel("Race name")
            TextField("Chicago Half Marathon", text: $raceName)
                .textInputAutocapitalization(.words)
                .padding(14)
                .background(AppTheme.Colors.surfaceBackground, in: RoundedRectangle(cornerRadius: 12))

            fieldLabel("Distance")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(RaceDistance.allCases) { distance in
                    Button {
                        selectedDistance = distance
                    } label: {
                        Text(distance.title)
                            .font(AppTheme.Typography.footnoteBold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(selectedDistance == distance ? Color.white : AppTheme.Colors.textSecondary)
                            .background(
                                selectedDistance == distance ? AppTheme.Colors.infoBlue : AppTheme.Colors.surfaceBackground,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if selectedDistance == .custom {
                TextField(selectedDistanceUnit.displayName, text: $customDistance)
                    .keyboardType(.decimalPad)
                    .padding(14)
                    .background(AppTheme.Colors.surfaceBackground, in: RoundedRectangle(cornerRadius: 12))
            }

            fieldLabel("Race date")
            DatePicker(
                "Race date",
                selection: $raceDate,
                in: (Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())...,
                displayedComponents: .date
            )
            .labelsHidden()
            .tint(AppTheme.Colors.infoBlueLight)
        }
        .padding(18)
        .background(AppTheme.Colors.cardBackground, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppTheme.Colors.infoBlue.opacity(0.18)))
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            HStack {
                if isSaving { ProgressView().tint(.white) }
                Text(isSaving ? "Saving race..." : (existingEdit == nil ? "Set target race" : "Save changes"))
                    .font(AppTheme.Typography.bodyBold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(.white)
            .background(AppTheme.Colors.infoBlue, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(!draft.isValid || isSaving)
        .opacity(draft.isValid ? 1 : 0.45)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(AppTheme.Colors.textTertiary)
    }

    private var draft: ManualRaceDraft {
        let savedUnit = selectedDistance.preferredUnit ?? selectedDistanceUnit
        let customMiles = Double(customDistance).map { distanceMiles(from: $0, unit: savedUnit) } ?? 0
        return ManualRaceDraft(
            name: raceName,
            distanceMiles: selectedDistance.miles ?? customMiles,
            distanceUnit: savedUnit,
            date: raceDate
        )
    }

    private func distanceValue(fromMiles miles: Double, unit: DistanceUnit) -> Double {
        unit == .kilometers ? miles * 1.609344 : miles
    }

    private func distanceMiles(from value: Double, unit: DistanceUnit) -> Double {
        unit == .kilometers ? value / 1.609344 : value
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let race: AthleteRace
                if let edit = existingEdit {
                    race = try await GoalService.updateManualRace(raceID: edit.raceID, draft: draft)
                } else {
                    race = try await GoalService.createManualRace(draft)
                }
                await MainActor.run {
                    onSaved(race)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}

private enum RaceDistance: String, CaseIterable, Identifiable {
    case fiveK, tenK, halfMarathon, marathon, fiftyK, custom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .fiveK: return "5K"
        case .tenK: return "10K"
        case .halfMarathon: return "Half"
        case .marathon: return "Marathon"
        case .fiftyK: return "50K"
        case .custom: return "Custom"
        }
    }
    var miles: Double? {
        switch self {
        case .fiveK: return 3.10686
        case .tenK: return 6.21371
        case .halfMarathon: return 13.1094
        case .marathon: return 26.2188
        case .fiftyK: return 31.0686
        case .custom: return nil
        }
    }

    var preferredUnit: DistanceUnit? {
        switch self {
        case .fiveK, .tenK, .fiftyK: return .kilometers
        case .halfMarathon, .marathon, .custom: return nil
        }
    }

    static func matching(miles: Double) -> RaceDistance {
        allCases.first { distance in
            guard let presetMiles = distance.miles else { return false }
            return abs(presetMiles - miles) < 0.05
        } ?? .custom
    }
}
