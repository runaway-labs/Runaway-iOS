import SwiftUI

struct StrengthRecommendationSettingsView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: AthleteTrainingProfileEditorModel

    init(athleteID: Int) {
        _model = StateObject(wrappedValue: AthleteTrainingProfileEditorModel(athleteID: athleteID))
    }

    private var colors: (background: Color, card: Color, primary: Color, secondary: Color) {
        if themeManager.isDarkMode {
            return (
                AppTheme.Colors.DarkMode.background,
                AppTheme.Colors.DarkMode.cardBackground,
                AppTheme.Colors.DarkMode.textPrimary,
                AppTheme.Colors.DarkMode.textSecondary
            )
        }
        return (
            AppTheme.Colors.LightMode.background,
            AppTheme.Colors.LightMode.cardBackground,
            AppTheme.Colors.LightMode.textPrimary,
            AppTheme.Colors.LightMode.textSecondary
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                        introduction
                        suggestionCard
                        zoneSection

                        if let error = model.errorMessage {
                            Text(error)
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.error)
                                .accessibilityLabel("Save error: \(error)")
                        }
                    }
                    .padding(AppTheme.Spacing.md)
                }
            }
            .navigationTitle("Strength recommendations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isSaving ? "Saving..." : "Save") { model.save() }
                        .disabled(!model.loaded || model.isSaving)
                }
            }
            .task { model.load() }
            .onChange(of: model.receipt) { _, receipt in
                if receipt != nil { dismiss() }
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text("Shape what your coach can suggest")
                .font(AppTheme.Typography.title2)
                .foregroundStyle(colors.primary)
            Text("These preferences apply anywhere Runaway builds a strength workout.")
                .font(AppTheme.Typography.body)
                .foregroundStyle(colors.secondary)
        }
    }

    private var suggestionCard: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "sparkles")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.warmAmber)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text("Strength focus suggestions")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(colors.primary)
                Text("Highlight up to two zones based on your goals and recent work.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(colors.secondary)
            }

            Spacer(minLength: AppTheme.Spacing.sm)

            Toggle("", isOn: Binding(
                get: { model.draft.resolvedStrengthRecommendations.suggestionsEnabled },
                set: model.setStrengthSuggestionsEnabled
            ))
            .labelsHidden()
            .tint(AppTheme.Colors.warmAmber)
            .accessibilityLabel("Strength focus suggestions")
        }
        .padding(AppTheme.Spacing.md)
        .background(colors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var zoneSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("AVAILABLE TRAINING ZONES")
                .font(AppTheme.Typography.caption)
                .fontWeight(.bold)
                .tracking(1.2)
                .foregroundStyle(colors.secondary)

            VStack(spacing: 0) {
                ForEach(Array(StrengthZone.allCases.enumerated()), id: \.element) { index, zone in
                    zoneRow(zone)
                    if index < StrengthZone.allCases.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .background(colors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Text("Turn off any zone Runaway should not suggest or include. You never need to provide a reason.")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(colors.secondary)
                .padding(.horizontal, AppTheme.Spacing.xs)

            if model.draft.resolvedStrengthRecommendations.availableZones.isEmpty {
                Label(
                    "All zones are off. Runaway will not build strength workouts until at least one is available.",
                    systemImage: "hand.raised.fill"
                )
                .font(AppTheme.Typography.caption)
                .foregroundStyle(colors.secondary)
                .padding(AppTheme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.Colors.warmAmber.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func zoneRow(_ zone: StrengthZone) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: icon(for: zone))
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.warmAmber)
                .frame(width: 36, height: 36)
                .background(AppTheme.Colors.warmAmber.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            Text(zone.rawValue.capitalized)
                .font(AppTheme.Typography.body)
                .foregroundStyle(colors.primary)

            Spacer()

            Toggle("", isOn: Binding(
                get: { model.draft.resolvedStrengthRecommendations.availableZones.contains(zone) },
                set: { model.setStrengthZone(zone, available: $0) }
            ))
            .labelsHidden()
            .tint(AppTheme.Colors.warmAmber)
            .accessibilityLabel("Allow \(zone.rawValue) workouts")
        }
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    private func icon(for zone: StrengthZone) -> String {
        switch zone {
        case .chest: return "figure.strengthtraining.traditional"
        case .back: return "figure.flexibility"
        case .shoulders: return "figure.arms.open"
        case .arms: return "dumbbell.fill"
        case .legs: return "figure.run"
        case .core: return "figure.core.training"
        }
    }
}
