//
//  CompactCommitmentCard.swift
//  Runaway iOS
//
//  Condensed commitment card for Activities tab - single row layout
//

import SwiftUI

struct CompactCommitmentCard: View {
    @Environment(DataManager.self) var dataManager
    @State private var viewModel = CommitmentCardViewModel()
    @State private var showingFullCommitment = false
    @State private var showingActivityPicker = false
    @State private var selectedActivityName = ""

    @ObservedObject private var goalStore = DailyGoalStore.shared

    private var backgroundColor: Color {
        // Slightly lighter/elevated background to stand out from activity cards
        AppTheme.Colors.adaptiveSurfaceBackground
    }

    private var accentTint: Color {
        AppTheme.Colors.accent.opacity(0.08)
    }

    private var textPrimary: Color {
        AppTheme.Colors.adaptiveTextPrimary
    }

    private var textSecondary: Color {
        AppTheme.Colors.adaptiveTextSecondary
    }

    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: AppTheme.Spacing.md) {
                // Status icon
                statusIcon

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    if let commitment = dataManager.todaysCommitment {
                        if commitment.isFulfilled {
                            fulfilledContent(commitment)
                        } else {
                            activeContent(commitment)
                        }
                    } else {
                        noCommitmentContent
                    }
                }

                Spacer()

                // Loading or action indicator
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(textSecondary)
                }
            }
            .padding(AppTheme.Spacing.md)
            .background(
                ZStack {
                    backgroundColor
                    accentTint // Subtle accent overlay to stand out
                }
            )
            .cornerRadius(AppTheme.CornerRadius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                    .stroke(AppTheme.Colors.accent.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(viewModel.isLoading)
        .sheet(isPresented: $showingFullCommitment) {
            NavigationView {
                FullCommitmentSheet()
                    .environment(dataManager)
            }
        }
        .sheet(isPresented: $showingActivityPicker) {
            ActivityTypePickerSheet(
                selectedTypeName: $selectedActivityName,
                title: "Set Today's Commitment",
                subtitle: "What activity will you commit to today?",
                onSelect: { activityType in
                    createCommitment(for: activityType.name)
                }
            )
        }
    }

    // MARK: - Actions

    private func handleTap() {
        if dataManager.todaysCommitment != nil {
            // Has commitment - show full sheet for viewing/editing
            showingFullCommitment = true
        } else {
            // No commitment - go directly to activity picker
            showingActivityPicker = true
        }
    }

    private func createCommitment(for activityName: String) {
        let activityType = CommitmentCardViewModel.commitmentActivityType(for: activityName)
        Task {
            await viewModel.createCommitment(activityType)
        }
    }

    // MARK: - Status Icon

    @ViewBuilder
    private var statusIcon: some View {
        if let commitment = dataManager.todaysCommitment {
            if commitment.isFulfilled {
                // Completed - green checkmark
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.success.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppTheme.Colors.success)
                }
            } else {
                // Active - activity icon with accent
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.accent.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: commitment.activityType.icon)
                        .font(.system(size: 18))
                        .foregroundColor(AppTheme.Colors.accent)
                }
            }
        } else {
            // No commitment - plus icon
            ZStack {
                Circle()
                    .stroke(textSecondary.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 40, height: 40)

                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(textSecondary)
            }
        }
    }

    // MARK: - Content Views

    @ViewBuilder
    private func fulfilledContent(_ commitment: DailyCommitment) -> some View {
        Text("Commitment Complete!")
            .font(AppTheme.Typography.body)
            .fontWeight(.semibold)
            .foregroundColor(AppTheme.Colors.success)

        Text("\(commitment.activityType.displayName) done today")
            .font(AppTheme.Typography.caption)
            .foregroundColor(textSecondary)
    }

    @ViewBuilder
    private func activeContent(_ commitment: DailyCommitment) -> some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Text("Today:")
                .font(AppTheme.Typography.body)
                .foregroundColor(textSecondary)

            Text(commitment.activityType.displayName)
                .font(AppTheme.Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(textPrimary)

            // Show goal if set
            if let goal = goalStore.todaysGoal {
                Text("•")
                    .foregroundColor(textSecondary)
                Text(goal.type == .distance ? "\(Int(goal.value)) mi" : "\(Int(goal.value)) min")
                    .font(AppTheme.Typography.body)
                    .fontWeight(.medium)
                    .foregroundColor(AppTheme.Colors.accent)
            }
        }

        if commitment.timeRemainingToday > 0 {
            Text(commitment.timeRemainingText)
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.accent)
        } else {
            Text("Commitment expired")
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.error)
        }
    }

    @ViewBuilder
    private var noCommitmentContent: some View {
        Text("Set today's commitment")
            .font(AppTheme.Typography.body)
            .fontWeight(.medium)
            .foregroundColor(textPrimary)

        Text("Tap to commit to an activity")
            .font(AppTheme.Typography.caption)
            .foregroundColor(textSecondary)
    }
}

// MARK: - Full Commitment Sheet

struct FullCommitmentSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(DataManager.self) var dataManager

    @State private var viewModel = CommitmentCardViewModel()
    @ObservedObject private var goalStore = DailyGoalStore.shared

    @State private var showingActivityPicker = false
    @State private var showingDeleteConfirmation = false
    @State private var selectedActivityName = ""
    @State private var showGoalSection = false
    @State private var selectedGoalType: GoalType? = nil
    @State private var goalValue: String = ""

    enum GoalType: String {
        case distance, time
    }

    private var backgroundColor: Color {
        AppTheme.Colors.adaptiveBackground
    }

    private var textPrimary: Color {
        AppTheme.Colors.adaptiveTextPrimary
    }

    private var textSecondary: Color {
        AppTheme.Colors.adaptiveTextSecondary
    }

    private var commitment: DailyCommitment? {
        dataManager.todaysCommitment
    }

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                if let commitment = commitment {
                    if commitment.isFulfilled {
                        fulfilledView(commitment)
                    } else {
                        activeCommitmentView(commitment)
                    }
                } else {
                    noCommitmentView
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
                    .fontWeight(.medium)
                    .foregroundColor(AppTheme.Colors.accent)
            }
        }
        .sheet(isPresented: $showingActivityPicker) {
            ActivityTypePickerSheet(
                selectedTypeName: $selectedActivityName,
                title: "Change Activity",
                subtitle: nil,
                onSelect: { activityType in
                    updateCommitment(to: activityType.name)
                }
            )
        }
        .background {
            Color.clear
                .alert("Remove Commitment?", isPresented: $showingDeleteConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Remove", role: .destructive) {
                        deleteCommitment()
                    }
                } message: {
                    Text("You can set a new one anytime.")
                }
                .adaptiveSurfaceTint()
        }
    }

    // MARK: - Active Commitment View

    @ViewBuilder
    private func activeCommitmentView(_ commitment: DailyCommitment) -> some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Spacer()
                .frame(height: 40)

            // Hero Icon
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.accent.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: commitment.activityType.icon)
                    .font(.system(size: 44))
                    .foregroundColor(AppTheme.Colors.accent)
            }

            // Main Message
            VStack(spacing: AppTheme.Spacing.sm) {
                Text("You're committed to")
                    .font(.title3)
                    .foregroundColor(textSecondary)

                Text(commitment.activityType.displayName)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(textPrimary)

                Text("today")
                    .font(.title3)
                    .foregroundColor(textSecondary)
            }

            // Time Remaining
            if commitment.timeRemainingToday > 0 {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text(commitment.timeRemainingText)
                        .font(.subheadline)
                }
                .foregroundColor(textSecondary)
                .padding(.top, AppTheme.Spacing.sm)
            }

            Spacer()

            // Goal Section (Optional)
            goalSection(for: commitment)

            Spacer()

            // Actions
            VStack(spacing: AppTheme.Spacing.md) {
                // Change Activity
                Button(action: {
                    selectedActivityName = commitment.activityType.displayName
                    showingActivityPicker = true
                }) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Change activity")
                    }
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(AppTheme.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.md)
                    .background(AppTheme.Colors.accent.opacity(0.1))
                    .cornerRadius(AppTheme.CornerRadius.medium)
                }

                // Remove
                Button(action: { showingDeleteConfirmation = true }) {
                    Text("Remove commitment")
                        .font(.subheadline)
                        .foregroundColor(textSecondary)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.xl)
            .disabled(viewModel.isLoading)
            .opacity(viewModel.isLoading ? 0.5 : 1)
        }
    }

    // MARK: - Goal Section

    @ViewBuilder
    private func goalSection(for commitment: DailyCommitment) -> some View {
        let supportsGoal = commitment.activityType.supportsDistanceGoal || commitment.activityType.supportsTimeGoal

        if supportsGoal {
            VStack(spacing: AppTheme.Spacing.md) {
                if let goal = goalStore.todaysGoal {
                    // Show saved goal
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: goal.type == .distance ? "ruler" : "timer")
                            .foregroundColor(AppTheme.Colors.accent)

                        Text("Goal:")
                            .font(.subheadline)
                            .foregroundColor(textSecondary)

                        Text(goal.type == .distance ? "\(Int(goal.value)) mi" : "\(Int(goal.value)) min")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(textPrimary)

                        Spacer()

                        Button(action: {
                            withAnimation { goalStore.clearGoal() }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.body)
                                .foregroundColor(textSecondary.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, AppTheme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                            .fill(AppTheme.Colors.accent.opacity(0.1))
                    )
                } else if !showGoalSection {
                    Button(action: { withAnimation { showGoalSection = true } }) {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Image(systemName: "target")
                                .foregroundColor(AppTheme.Colors.accent)
                            Text("Set a goal?")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(textPrimary)
                            Text("Optional")
                                .font(.caption)
                                .foregroundColor(textSecondary)
                        }
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.vertical, AppTheme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                                .stroke(textSecondary.opacity(0.2), lineWidth: 1)
                        )
                    }
                } else {
                    goalInputView(for: commitment)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
        }
    }

    @ViewBuilder
    private func goalInputView(for commitment: DailyCommitment) -> some View {
        VStack(spacing: AppTheme.Spacing.md) {
            HStack {
                Text("Today's Goal")
                    .font(.headline)
                    .foregroundColor(textPrimary)
                Spacer()
                Button(action: {
                    withAnimation {
                        selectedGoalType = nil
                        goalValue = ""
                        showGoalSection = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(textSecondary)
                }
            }

            if let goalType = selectedGoalType {
                // Show input for selected goal type
                VStack(spacing: AppTheme.Spacing.sm) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        TextField(goalType == .distance ? "0" : "0", text: $goalValue)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(textPrimary)
                            .multilineTextAlignment(.center)
                            .frame(width: 80)

                        Text(goalType == .distance ? "miles" : "min")
                            .font(.title3)
                            .foregroundColor(textSecondary)
                    }

                    HStack(spacing: AppTheme.Spacing.md) {
                        Button(action: {
                            withAnimation { selectedGoalType = nil }
                            goalValue = ""
                        }) {
                            Text("Cancel")
                                .font(.subheadline)
                                .foregroundColor(textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppTheme.Spacing.sm)
                        }

                        Button(action: {
                            if let value = Double(goalValue), value > 0 {
                                goalStore.setGoal(type: goalType, value: value)
                                withAnimation {
                                    selectedGoalType = nil
                                    goalValue = ""
                                    showGoalSection = false
                                }
                            }
                        }) {
                            Text("Set Goal")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(AppTheme.Colors.pine)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppTheme.Spacing.sm)
                                .background(AppTheme.Colors.strideLime)
                                .cornerRadius(AppTheme.CornerRadius.small)
                        }
                    }
                }
            } else {
                // Show goal type options
                HStack(spacing: AppTheme.Spacing.md) {
                    if commitment.activityType.supportsDistanceGoal {
                        GoalOptionButton(
                            icon: "ruler",
                            label: "Distance",
                            sublabel: goalDistanceLabel(for: commitment.activityType),
                            action: { withAnimation { selectedGoalType = .distance } }
                        )
                    }

                    if commitment.activityType.supportsTimeGoal {
                        GoalOptionButton(
                            icon: "timer",
                            label: "Time",
                            sublabel: goalTimeLabel(for: commitment.activityType),
                            action: { withAnimation { selectedGoalType = .time } }
                        )
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                .fill(AppTheme.Colors.adaptiveCardBackground)
        )
    }

    private func goalDistanceLabel(for activityType: CommitmentActivityType) -> String {
        switch activityType {
        case .run: return "e.g. 3 miles"
        case .walk: return "e.g. 2 miles"
        default: return "Set distance"
        }
    }

    private func goalTimeLabel(for activityType: CommitmentActivityType) -> String {
        switch activityType {
        case .run: return "e.g. 30 min"
        case .walk: return "e.g. 45 min"
        case .yoga: return "e.g. 20 min"
        case .workout: return "e.g. 45 min"
        }
    }

    // MARK: - Fulfilled View

    @ViewBuilder
    private func fulfilledView(_ commitment: DailyCommitment) -> some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Spacer()

            // Hero Icon
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.success.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(AppTheme.Colors.success)
            }

            // Message
            VStack(spacing: AppTheme.Spacing.sm) {
                Text("Done! 🎉")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(textPrimary)

                Text("You completed your \(commitment.activityType.displayName.lowercased())")
                    .font(.title3)
                    .foregroundColor(textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
            Spacer()
        }
    }

    // MARK: - No Commitment View

    @ViewBuilder
    private var noCommitmentView: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Spacer()

            Image(systemName: "plus.circle")
                .font(.system(size: 60))
                .foregroundColor(textSecondary.opacity(0.5))

            Text("No commitment set")
                .font(.title2)
                .foregroundColor(textSecondary)

            Spacer()
        }
    }

    // MARK: - Actions

    private func updateCommitment(to activityName: String) {
        let activityType = CommitmentCardViewModel.commitmentActivityType(for: activityName)
        Task {
            await viewModel.updateCommitment(to: activityType)
        }
    }

    private func deleteCommitment() {
        Task {
            await viewModel.deleteCommitment()
            if viewModel.errorMessage == nil {
                dismiss()
            }
        }
    }
}

// MARK: - Goal Option Button

private struct GoalOptionButton: View {
    let icon: String
    let label: String
    let sublabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(AppTheme.Colors.accent)

                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

                Text(sublabel)
                    .font(.caption)
                    .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(AppTheme.Colors.accent.opacity(0.08))
            .cornerRadius(AppTheme.CornerRadius.medium)
        }
    }
}

// MARK: - CommitmentActivityType Extensions

extension CommitmentActivityType {
    var supportsDistanceGoal: Bool {
        switch self {
        case .run, .walk: return true
        case .yoga, .workout: return false
        }
    }

    var supportsTimeGoal: Bool {
        return true // All activities support time goals
    }
}

// MARK: - Daily Goal Store

class DailyGoalStore: ObservableObject {
    static let shared = DailyGoalStore()

    private let userDefaults = UserDefaults.standard
    private let goalTypeKey = "dailyGoal_type"
    private let goalValueKey = "dailyGoal_value"
    private let goalDateKey = "dailyGoal_date"

    @Published var todaysGoal: (type: FullCommitmentSheet.GoalType, value: Double)?

    private init() {
        loadGoal()
    }

    func setGoal(type: FullCommitmentSheet.GoalType, value: Double) {
        userDefaults.set(type.rawValue, forKey: goalTypeKey)
        userDefaults.set(value, forKey: goalValueKey)
        userDefaults.set(Date().startOfDay, forKey: goalDateKey)

        todaysGoal = (type: type, value: value)
    }

    func clearGoal() {
        userDefaults.removeObject(forKey: goalTypeKey)
        userDefaults.removeObject(forKey: goalValueKey)
        userDefaults.removeObject(forKey: goalDateKey)

        todaysGoal = nil
    }

    private func loadGoal() {
        // Check if goal was set today
        guard let savedDate = userDefaults.object(forKey: goalDateKey) as? Date,
              Calendar.current.isDate(savedDate, inSameDayAs: Date()) else {
            // Goal is from a previous day - clear it
            clearGoal()
            return
        }

        guard let typeRaw = userDefaults.string(forKey: goalTypeKey),
              let type = FullCommitmentSheet.GoalType(rawValue: typeRaw) else {
            return
        }

        let value = userDefaults.double(forKey: goalValueKey)
        if value > 0 {
            todaysGoal = (type: type, value: value)
        }
    }
}

private extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
}

#Preview("With Active Commitment") {
    CompactCommitmentCard()
        .padding()
        .background(Color.gray.opacity(0.1))
        .environment(DataManager.shared)
}

#Preview("No Commitment") {
    CompactCommitmentCard()
        .padding()
        .background(Color.gray.opacity(0.1))
        .environment(DataManager.shared)
}
