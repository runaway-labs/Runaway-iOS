//
//  ActivityCommitmentCard.swift
//  Runaway iOS
//
//  Created by Jack Rudelic on 9/16/25.
//

import SwiftUI
import Combine

// MARK: - Activity Commitment Card

struct ActivityCommitmentCard: View {
    @Environment(DataManager.self) var dataManager
    @State private var viewModel = CommitmentCardViewModel()
    @State private var selectedActivityType: CommitmentActivityType = .run
    @State private var showingCommitmentPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // Header with days counter
            HStack {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("Activity Tracker")
                        .font(AppTheme.Typography.headline)
                        .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

                    Text(dataManager.daysSinceLastActivityText)
                        .font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                }

                Spacer()

                // Activity streak icon
                if dataManager.daysSinceLastActivity == 0 {
                    Image(systemName: "flame.fill")
                        .foregroundColor(AppTheme.Colors.accent)
                        .font(AppTheme.Typography.title2)
                } else if dataManager.daysSinceLastActivity > 0 {
                    Image(systemName: "clock.fill")
                        .foregroundColor(AppTheme.Colors.accent)
                        .font(AppTheme.Typography.title2)
                }
            }

            Divider()
                .background(AppTheme.Colors.textTertiary.opacity(0.3))

            // Commitment section
            if let commitment = dataManager.todaysCommitment {
                if commitment.isFulfilled {
                    // Fulfilled commitment
                    FulfilledCommitmentView(commitment: commitment)
                } else if commitment.isMicroCommitment {
                    // Active micro-commitment
                    MicroCommitmentCard(
                        commitment: commitment,
                        onComplete: completeMicroCommitment
                    )
                } else {
                    // Active commitment with countdown
                    ActiveCommitmentView(commitment: commitment)
                }
            } else {
                // No commitment - show commitment picker
                NoCommitmentView(
                    selectedActivityType: $selectedActivityType,
                    showingCommitmentPicker: $showingCommitmentPicker,
                    onCommitmentCreated: createCommitment
                )
                .environment(CommitmentManager.shared)
            }

            // Error message
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.error)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, AppTheme.Spacing.xs)
                    .background(AppTheme.Colors.error.opacity(0.1))
                    .cornerRadius(AppTheme.CornerRadius.small)
            }

            // Success message
            if viewModel.showingSuccess {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppTheme.Colors.success)
                    Text("Commitment created!")
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.success)
                }
                .padding(.horizontal, AppTheme.Spacing.sm)
                .padding(.vertical, AppTheme.Spacing.xs)
                .background(AppTheme.Colors.success.opacity(AppTheme.Opacity.light))
                .cornerRadius(AppTheme.CornerRadius.small)
            }

        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.adaptiveCardBackground)
        .cornerRadius(AppTheme.CornerRadius.medium)
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        .task {
            // Refresh commitment data on appear
            await dataManager.refreshTodaysCommitment()
        }
        .refreshable {
            await dataManager.refreshTodaysCommitment()
        }
    }

    private func createCommitment() {
        showingCommitmentPicker = false
        Task {
            await viewModel.createCommitment(selectedActivityType)
        }
    }

    private func completeMicroCommitment() {
        Task {
            await viewModel.completeMicroCommitment()
        }
    }
}

// MARK: - No Commitment View

struct NoCommitmentView: View {
    @Environment(CommitmentManager.self) var commitmentManager
    @Binding var selectedActivityType: CommitmentActivityType
    @Binding var showingCommitmentPicker: Bool
    let onCommitmentCreated: () -> Void

    @State private var showMicroCommitmentSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Today's Commitment")
                .font(AppTheme.Typography.headline)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

            HStack {
                Text("I commit to:")
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)

                Spacer()

                Picker("Activity Type", selection: $selectedActivityType) {
                    ForEach(CommitmentActivityType.allCases, id: \.self) { activityType in
                        HStack {
                            Image(systemName: activityType.icon)
                            Text(activityType.displayName)
                        }
                        .tag(activityType)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .accentColor(AppTheme.Colors.accent)
            }

            Button(action: onCommitmentCreated) {
                HStack {
                    Spacer()
                    Text("Set Commitment")
                        .font(AppTheme.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(AppTheme.Colors.pine)
                    Spacer()
                }
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(AppTheme.Colors.strideLime)
                .cornerRadius(AppTheme.CornerRadius.small)
            }

            // Micro-commitment option
            if commitmentManager.shouldOfferMicroCommitment {
                VStack(spacing: AppTheme.Spacing.xs) {
                    Divider()
                        .padding(.vertical, AppTheme.Spacing.xs)

                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(.cyan)
                            .font(.caption)

                        Text("Need to start smaller?")
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)

                        Spacer()

                        Button(action: { showMicroCommitmentSheet = true }) {
                            Text("Try a micro-commitment")
                                .font(AppTheme.Typography.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.cyan)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showMicroCommitmentSheet) {
            MicroCommitmentSelector { type in
                Task {
                    try? await commitmentManager.createMicroCommitment(type)
                }
            }
        }
    }
}

// MARK: - Active Commitment View

struct ActiveCommitmentView: View {
    @Environment(DataManager.self) var dataManager
    @State private var viewModel = CommitmentCardViewModel()
    let initialCommitment: DailyCommitment
    @State private var currentTime = Date()
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var selectedActivityType: CommitmentActivityType

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// Use dataManager's commitment if available, fallback to initial
    private var commitment: DailyCommitment {
        dataManager.todaysCommitment ?? initialCommitment
    }

    init(commitment: DailyCommitment) {
        self.initialCommitment = commitment
        _selectedActivityType = State(initialValue: commitment.activityType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Text("Today's Commitment")
                    .font(AppTheme.Typography.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

                Spacer()

                Text("Active")
                    .font(AppTheme.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.Colors.pine)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, 2)
                    .background(AppTheme.Colors.strideLime)
                    .cornerRadius(AppTheme.CornerRadius.small)
            }

            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: commitment.activityType.icon)
                    .foregroundColor(AppTheme.Colors.accent)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(commitment.activityType.displayName)
                        .font(AppTheme.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

                    if commitment.timeRemainingToday > 0 {
                        Text(commitment.timeRemainingText)
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                    } else {
                        Text("Commitment expired")
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(AppTheme.Colors.error)
                    }
                }

                Spacer()

                // Progress ring
                CommitmentProgressRing(timeRemaining: commitment.timeRemainingToday)
            }

            // Edit/Delete controls
            HStack(spacing: AppTheme.Spacing.sm) {
                Button(action: { showingEditSheet = true }) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Image(systemName: "pencil")
                        Text("Edit")
                    }
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.accent)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, AppTheme.Spacing.xs)
                    .background(AppTheme.Colors.accent.opacity(0.1))
                    .cornerRadius(AppTheme.CornerRadius.small)
                }
                .disabled(viewModel.isLoading)

                Button(action: { showingDeleteConfirmation = true }) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Image(systemName: "trash")
                        Text("Remove")
                    }
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.error)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, AppTheme.Spacing.xs)
                    .background(AppTheme.Colors.error.opacity(0.1))
                    .cornerRadius(AppTheme.CornerRadius.small)
                }
                .disabled(viewModel.isLoading)

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.top, AppTheme.Spacing.xs)

            // Error message
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.error)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, AppTheme.Spacing.xs)
                    .background(AppTheme.Colors.error.opacity(0.1))
                    .cornerRadius(AppTheme.CornerRadius.small)
            }
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
        .sheet(isPresented: $showingEditSheet) {
            EditCommitmentSheet(
                selectedType: $selectedActivityType,
                currentType: commitment.activityType,
                onSave: updateCommitment
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
                    Text("Are you sure you want to remove today's commitment? You can set a new one afterward.")
                }
                .adaptiveSurfaceTint()
        }
        .onChange(of: dataManager.todaysCommitment?.activityType) { _, newType in
            // Sync selectedActivityType when commitment changes externally
            if let newType = newType, newType != selectedActivityType {
                selectedActivityType = newType
            }
        }
    }

    private func updateCommitment() {
        guard selectedActivityType != commitment.activityType else {
            showingEditSheet = false
            return
        }

        Task {
            await viewModel.updateCommitment(to: selectedActivityType)
            if viewModel.errorMessage == nil {
                showingEditSheet = false
            } else {
                selectedActivityType = commitment.activityType
            }
        }
    }

    private func deleteCommitment() {
        Task {
            await viewModel.deleteCommitment()
        }
    }
}

// MARK: - Fulfilled Commitment View

struct FulfilledCommitmentView: View {
    let commitment: DailyCommitment

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // Celebration header
            HStack {
                Text(commitment.isMicroCommitment ? "Micro-Commitment Done!" : "Commitment Completed")
                    .font(AppTheme.Typography.headline)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.Colors.success)

                Spacer()

                Image(systemName: commitment.isMicroCommitment ? "sparkles" : "party.popper.fill")
                    .foregroundColor(commitment.isMicroCommitment ? .cyan : AppTheme.Colors.accent)
                    .font(AppTheme.Typography.title2)
            }

            // Main celebration message
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text(commitment.isMicroCommitment ? "Great start! ✨" : "LET'S GO! 🔥")
                    .font(.title2)
                    .fontWeight(.heavy)
                    .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

                if commitment.isMicroCommitment, let microType = commitment.microCommitmentType {
                    Text(microType.completionMessage)
                        .font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                } else {
                    Text("You crushed your \(commitment.displayTitle.lowercased()) commitment today!")
                        .font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                }
            }

            // Activity details
            HStack(spacing: AppTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill((commitment.isMicroCommitment ? Color.cyan : AppTheme.Colors.success).opacity(AppTheme.Opacity.medium))
                        .frame(width: 50, height: 50)

                    Image(systemName: commitment.displayIcon)
                        .foregroundColor(commitment.isMicroCommitment ? .cyan : AppTheme.Colors.success)
                        .font(AppTheme.Typography.title2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(commitment.displayTitle)
                        .font(AppTheme.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

                    if let fulfilledTime = commitment.fulfilledAtAsDate {
                        Text("Completed at \(fulfilledTime, formatter: timeFormatter)")
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                    } else {
                        Text("Completed today")
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                    }
                }

                Spacer()

                // Big checkmark with animation effect
                ZStack {
                    Circle()
                        .fill(commitment.isMicroCommitment ? Color.cyan : AppTheme.Colors.success)
                        .frame(width: 40, height: 40)

                    Image(systemName: "checkmark")
                        .foregroundColor(.black)
                        .font(AppTheme.Typography.title3)
                        .fontWeight(.bold)
                }
            }

            // Motivational footer
            HStack {
                Spacer()
                Text(commitment.isMicroCommitment ? "Small steps lead to big wins! 💫" : "Keep the momentum going! 💪")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(commitment.isMicroCommitment ? .cyan : AppTheme.Colors.accent)
                    .italic()
                Spacer()
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(
            LinearGradient(
                colors: [
                    (commitment.isMicroCommitment ? Color.cyan : AppTheme.Colors.success).opacity(AppTheme.Opacity.light),
                    (commitment.isMicroCommitment ? Color.cyan : AppTheme.Colors.success).opacity(AppTheme.Opacity.veryLight)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                .stroke((commitment.isMicroCommitment ? Color.cyan : AppTheme.Colors.success).opacity(AppTheme.Opacity.strong), lineWidth: 1)
        )
        .cornerRadius(AppTheme.CornerRadius.medium)
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
}

// MARK: - Commitment Progress Ring

struct CommitmentProgressRing: View {
    let timeRemaining: TimeInterval

    private var progress: Double {
        let totalSecondsInDay: TimeInterval = 24 * 60 * 60
        let elapsed = totalSecondsInDay - timeRemaining
        return min(max(elapsed / totalSecondsInDay, 0), 1)
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(AppTheme.Colors.textTertiary.opacity(AppTheme.Opacity.medium), lineWidth: 3)
                .frame(width: 32, height: 32)

            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    timeRemaining > 0 ? AppTheme.Colors.accent : AppTheme.Colors.error,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 32, height: 32)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)

            // Center indicator
            Circle()
                .fill(timeRemaining > 0 ? AppTheme.Colors.accent : AppTheme.Colors.error)
                .frame(width: 8, height: 8)
        }
    }
}

// MARK: - Edit Commitment Sheet

struct EditCommitmentSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedType: CommitmentActivityType
    let currentType: CommitmentActivityType
    let onSave: () -> Void

    @State private var activityTypes: [ActivityType] = []
    @State private var isLoading = true
    @State private var selectedTypeName: String = ""

    var body: some View {
        NavigationView {
            VStack(spacing: AppTheme.Spacing.lg) {
                Text("Change your commitment type")
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                    .padding(.top, AppTheme.Spacing.md)

                if isLoading {
                    Spacer()
                    ProgressView("Loading activity types...")
                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: AppTheme.Spacing.sm) {
                            ForEach(activityTypes) { activityType in
                                Button(action: {
                                    selectedTypeName = activityType.name
                                    // Map to CommitmentActivityType enum
                                    selectedType = mapToCommitmentType(activityType.name)
                                }) {
                                    HStack(spacing: AppTheme.Spacing.md) {
                                        ZStack {
                                            Circle()
                                                .fill(selectedTypeName.lowercased() == activityType.name.lowercased() ?
                                                      AppTheme.Colors.accent.opacity(0.2) :
                                                      AppTheme.Colors.textTertiary.opacity(0.1))
                                                .frame(width: 44, height: 44)

                                            Image(systemName: activityType.icon)
                                                .foregroundColor(selectedTypeName.lowercased() == activityType.name.lowercased() ?
                                                                AppTheme.Colors.accent :
                                                                AppTheme.Colors.adaptiveTextSecondary)
                                                .font(.title3)
                                        }

                                        Text(activityType.name)
                                            .font(AppTheme.Typography.body)
                                            .fontWeight(selectedTypeName.lowercased() == activityType.name.lowercased() ? .semibold : .regular)
                                            .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

                                        Spacer()

                                        if selectedTypeName.lowercased() == activityType.name.lowercased() {
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
                                            .fill(selectedTypeName.lowercased() == activityType.name.lowercased() ?
                                                  AppTheme.Colors.accent.opacity(0.05) :
                                                  Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                                            .stroke(selectedTypeName.lowercased() == activityType.name.lowercased() ?
                                                   AppTheme.Colors.accent.opacity(0.3) :
                                                   AppTheme.Colors.textTertiary.opacity(0.2), lineWidth: 1)
                                    )
                                    .contentShape(Rectangle()) // Make entire row tappable
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.md)
                    }
                }

                Button(action: onSave) {
                    HStack {
                        Spacer()
                        Text("Save Changes")
                            .font(AppTheme.Typography.body)
                            .fontWeight(.semibold)
                            .foregroundColor(AppTheme.Colors.pine)
                        Spacer()
                    }
                    .padding(.vertical, AppTheme.Spacing.md)
                    .background(AppTheme.Colors.strideLime)
                    .cornerRadius(AppTheme.CornerRadius.medium)
                }
                .disabled(selectedType == currentType)
                .opacity(selectedType == currentType ? 0.5 : 1.0)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.lg)
            }
            .adaptiveSurfaceTint()
            .navigationTitle("Edit Commitment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(AppTheme.Colors.DarkMode.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        selectedType = currentType
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
        .onAppear {
            selectedTypeName = currentType.displayName
        }
    }

    private func loadActivityTypes() async {
        do {
            activityTypes = try await ActivityTypeService.getAllActivityTypes()
            isLoading = false
        } catch {
            #if DEBUG
            print("Failed to load activity types: \(error)")
            #endif
            isLoading = false
        }
    }

    /// Map activity type name to CommitmentActivityType enum
    private func mapToCommitmentType(_ name: String) -> CommitmentActivityType {
        CommitmentCardViewModel.commitmentActivityType(for: name)
    }
}
