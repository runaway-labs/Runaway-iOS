import SwiftUI
import UIKit

struct TrainingProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: TrainingProfileEditorViewModel

    init(store: TrainingProfileStore) {
        self.init(route: TrainingProfileRoute(store: store))
    }

    init(route: TrainingProfileRoute) {
        _model = StateObject(wrappedValue: route.makeEditorModel())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        AppTheme.Colors.DarkMode.backgroundElevated,
                        AppTheme.Colors.DarkMode.background,
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
                        weeklyMixSummary

                        if !model.validationCopy.isEmpty {
                            validationRepairCard
                        }

                        ActivityMixEditor(model: model)
                        TrainingScheduleEditor(model: model)
                        saveButton
                    }
                    .padding(AppTheme.Spacing.xl)
                    .padding(.bottom, AppTheme.Spacing.xxxl)
                }
                .disabled(model.isEditorInteractionDisabled)
                .accessibilityHidden(model.isEditorInteractionDisabled)

                if model.isRegenerating {
                    regenerationOverlay
                }
            }
            .navigationTitle("Training Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(model.isRegenerating)
                }
            }
            .confirmationDialog(
                "When should your plan reflect this profile?",
                isPresented: $model.isPresentingRegenerationChoices,
                titleVisibility: .visible
            ) {
                Button("Update Next Week (Recommended)") {
                    Task { await model.regenerate(scope: .nextWeek) }
                }
                Button(model.currentWeekActionTitle) {
                    Task { await model.regenerate(scope: .remainingCurrentWeek) }
                }
                Button("Cancel", role: .cancel) {
                    model.cancelRegeneration()
                }
            } message: {
                Text("Your profile is saved. Completed workouts will stay protected.")
            }
            .alert(
                "Plan Update Failed",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.dismissError() } }
                )
            ) {
                if model.canRetry {
                    Button("Retry") {
                        Task { await model.retry() }
                    }
                }
                Button("Not Now", role: .cancel) {
                    model.dismissError()
                }
            } message: {
                Text(model.errorMessage ?? "Your saved profile is safe and your previous plan is unchanged.")
            }
            .onChange(of: model.shouldDismiss) { _, shouldDismiss in
                if shouldDismiss { dismiss() }
            }
            .interactiveDismissDisabled(model.isRegenerating)
        }
    }

    private var weeklyMixSummary: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            EyebrowLabel(text: "YOUR WEEK", color: AppTheme.Colors.warmAmber)
            Text(model.summary)
                .font(AppTheme.Typography.title)
                .foregroundColor(AppTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Shape the week you can repeat, then let Runaway handle the balance.")
                .font(AppTheme.Typography.subheadline)
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.xl)
        .background(AppTheme.Colors.DarkMode.cardBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.extraLarge))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.extraLarge)
                .stroke(AppTheme.Colors.warmAmber.opacity(0.18), lineWidth: 1)
        )
    }

    private var validationRepairCard: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            Image(systemName: "wand.and.stars")
                .foregroundColor(AppTheme.Colors.strideBlueLight)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("We’ll tidy this before saving")
                    .font(AppTheme.Typography.subheadlineBold)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                Text(model.validationCopy)
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Colors.strideBlue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                .stroke(AppTheme.Colors.strideBlue.opacity(0.24), lineWidth: 1)
        )
    }

    private var saveButton: some View {
        Button {
            model.save()
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                if model.isSaving {
                    ProgressView().tint(.black)
                }
                Text(model.isSaving ? "Saving Profile" : "Save Training Profile")
            }
            .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.touchTargetPreferred)
        }
        .primaryButton()
        .buttonStyle(.plain)
        .disabled(model.isSavingDisabled)
        .opacity(model.isSavingDisabled ? 0.7 : 1)
    }

    private var regenerationOverlay: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            ProgressView()
                .controlSize(.large)
                .tint(AppTheme.Colors.warmAmber)
            Text("Updating your plan")
                .font(AppTheme.Typography.title3)
                .foregroundColor(AppTheme.Colors.textPrimary)
            Text("Your previous plan stays in place until the new one is ready.")
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(AppTheme.Spacing.xxl)
        .frame(maxWidth: 300)
        .background(AppTheme.Colors.DarkMode.cardBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.extraLarge))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.extraLarge)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
        .padding(AppTheme.Spacing.xl)
        .background(Color.black.opacity(0.55).ignoresSafeArea())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Updating your training plan")
        .accessibilityValue("Your previous plan stays in place until the new plan is saved.")
        .accessibilityAddTraits(.updatesFrequently)
        .onAppear {
            UIAccessibility.post(
                notification: .announcement,
                argument: "Updating your training plan. Your previous plan stays in place until the new plan is saved."
            )
        }
    }
}

#Preview {
    TrainingProfileView(store: TrainingProfileStore())
        .preferredColorScheme(.dark)
}
