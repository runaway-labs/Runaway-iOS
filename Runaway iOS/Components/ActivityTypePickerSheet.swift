//
//  ActivityTypePickerSheet.swift
//  Runaway iOS
//
//  Reusable activity type picker that loads from database
//

import SwiftUI

// MARK: - Activity Type with Icon

extension ActivityType {
    /// SF Symbol icon for this activity type
    var icon: String {
        switch name.lowercased() {
        case "run": return "figure.run"
        case "ride", "bike", "cycling": return "figure.outdoor.cycle"
        case "walk": return "figure.walk"
        case "hike": return "figure.hiking"
        case "swim": return "figure.pool.swim"
        case "workout", "weight training", "weighttraining": return "dumbbell.fill"
        case "yoga": return "figure.mind.and.body"
        case "elliptical": return "figure.elliptical"
        case "rowing": return "figure.rower"
        case "stair stepper": return "figure.stair.stepper"
        case "crossfit": return "figure.cross.training"
        case "pilates": return "figure.pilates"
        case "tennis": return "tennis.racket"
        case "golf": return "figure.golf"
        case "soccer", "football": return "soccerball"
        case "basketball": return "basketball.fill"
        case "skiing": return "figure.skiing.downhill"
        case "snowboarding": return "figure.snowboarding"
        case "surfing": return "figure.surfing"
        case "rock climbing": return "figure.climbing"
        case "other": return "figure.mixed.cardio"
        default: return "figure.mixed.cardio"
        }
    }
}

// MARK: - Activity Type Picker Sheet

struct ActivityTypePickerSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedTypeName: String
    let title: String
    let subtitle: String?
    let onSelect: ((ActivityType) -> Void)?

    @State private var activityTypes: [ActivityType] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    init(
        selectedTypeName: Binding<String>,
        title: String = "Select Activity Type",
        subtitle: String? = nil,
        onSelect: ((ActivityType) -> Void)? = nil
    ) {
        self._selectedTypeName = selectedTypeName
        self.title = title
        self.subtitle = subtitle
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationView {
            VStack(spacing: AppTheme.Spacing.lg) {
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                        .padding(.top, AppTheme.Spacing.md)
                }

                if isLoading {
                    Spacer()
                    ProgressView("Loading activity types...")
                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                    Spacer()
                } else if let error = errorMessage {
                    Spacer()
                    VStack(spacing: AppTheme.Spacing.md) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .font(AppTheme.Typography.body)
                            .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await loadActivityTypes() }
                        }
                        .foregroundColor(AppTheme.Colors.accent)
                    }
                    .padding()
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: AppTheme.Spacing.sm) {
                            ForEach(activityTypes) { activityType in
                                ActivityTypeRow(
                                    activityType: activityType,
                                    isSelected: selectedTypeName.lowercased() == activityType.name.lowercased()
                                ) {
                                    selectedTypeName = activityType.name
                                    onSelect?(activityType)
                                    dismiss()
                                }
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.md)
                    }
                }
            }
            .adaptiveSurfaceTint()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.Colors.DarkMode.accent)
                    .darkSurfaceTint()
                }
            }
        }
        .darkSurfaceTint()
        .task {
            await loadActivityTypes()
        }
    }

    private func loadActivityTypes() async {
        isLoading = true
        errorMessage = nil

        do {
            activityTypes = try await ActivityTypeService.getAllActivityTypes()
            isLoading = false
        } catch {
            errorMessage = "Failed to load activity types: \(error.localizedDescription)"
            isLoading = false
        }
    }
}

// MARK: - Activity Type Row

struct ActivityTypeRow: View {
    let activityType: ActivityType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(isSelected ?
                              AppTheme.Colors.accent.opacity(0.2) :
                              AppTheme.Colors.textTertiary.opacity(0.1))
                        .frame(width: 44, height: 44)

                    Image(systemName: activityType.icon)
                        .foregroundColor(isSelected ?
                                        AppTheme.Colors.accent :
                                        AppTheme.Colors.adaptiveTextSecondary)
                        .font(.title3)
                }

                Text(activityType.name)
                    .font(AppTheme.Typography.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppTheme.Colors.accent)
                        .font(.title3)
                } else {
                    Circle()
                        .stroke(AppTheme.Colors.textTertiary.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(AppTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                    .fill(isSelected ?
                          AppTheme.Colors.accent.opacity(0.05) :
                          Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                    .stroke(isSelected ?
                           AppTheme.Colors.accent.opacity(0.3) :
                           AppTheme.Colors.textTertiary.opacity(0.2), lineWidth: 1)
            )
            .contentShape(Rectangle()) // Make entire row tappable
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    ActivityTypePickerSheet(
        selectedTypeName: .constant("Run"),
        title: "Select Activity",
        subtitle: "Choose your activity type"
    )
}
