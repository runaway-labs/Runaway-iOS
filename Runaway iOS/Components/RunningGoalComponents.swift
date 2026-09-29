//
//  RunningGoalComponents.swift
//  Runaway iOS
//
//  Created by Jack Rudelic on 6/28/25.
//

import SwiftUI
import Charts

// MARK: - Main Goal Card Component
struct RunningGoalCard: View {
    @State private var showingGoalInput = false
    @State private var currentGoal: RunningGoal?
    @State private var goalAnalysis: GoalAnalysis?
    @State private var isLoadingGoal = false
    @State private var errorMessage: String?
    
    let activities: [Activity]
    let goalReadiness: GoalReadiness?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Running Goal")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

                Spacer()

                if isLoadingGoal {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button(action: {
                        showingGoalInput = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: currentGoal == nil ? "plus.circle.fill" : "pencil.circle.fill")
                            Text(currentGoal == nil ? "Set Goal" : "Edit")
                        }
                        .font(.subheadline)
                        .foregroundColor(AppTheme.Colors.accent)
                    }
                }
            }
            
            // Error Message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(AppTheme.Colors.error)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppTheme.Colors.error.opacity(0.1))
                    .cornerRadius(8)
            }
            
            if let goal = currentGoal, let analysis = goalAnalysis {
                // Goal Overview
                GoalOverviewSection(goal: goal, analysis: analysis)
                
                // Goal Readiness Assessment
                if let goalReadiness = goalReadiness {
                    GoalReadinessCompactCard(goalReadiness: goalReadiness)
                } else {
                    // Fallback to progress chart if no readiness data
                    GoalProgressChart(analysis: analysis)
                }
            } else if !isLoadingGoal {
                // Empty State
                GoalEmptyState()
            }
        }
        .padding()
        .background(AppTheme.Colors.adaptiveCardBackground)
        .cornerRadius(AppTheme.CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        .sheet(isPresented: $showingGoalInput) {
            GoalInputSheet(currentGoal: currentGoal) { newGoal in
                if let goal = newGoal {
                    currentGoal = goal
                    Task {
                        await generateAnalysis(for: goal)
                    }
                }
            }
        }
        .onAppear {
            loadActiveGoal()
        }
        .refreshable {
            await refreshGoal()
        }
    }
    
    private func loadActiveGoal() {
        isLoadingGoal = true
        errorMessage = nil
        
        Task {
            do {
                // Get the most recent active goal (any type)
                let activeGoals = try await GoalService.getActiveGoals()
                let mostRecentGoal = activeGoals.first
                
                await MainActor.run {
                    currentGoal = mostRecentGoal
                    isLoadingGoal = false
                }
                
                if let goal = mostRecentGoal {
                    await generateAnalysis(for: goal)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load goal: \(error.localizedDescription)"
                    isLoadingGoal = false
                }
                #if DEBUG
                print("❌ Error loading goal: \(error)")
                #endif
            }
        }
    }
    
    private func generateAnalysis(for goal: RunningGoal) async {
        // Simple local analysis based on current progress
        let currentProgress = goal.currentProgress
        let projectedCompletion = min(currentProgress * 100 / max(goal.weeksRemaining, 1), 100)
        let isOnTrack = projectedCompletion >= 80

        let analysis = GoalAnalysis(
            goal: goal,
            currentProgress: currentProgress,
            projectedCompletion: projectedCompletion,
            isOnTrack: isOnTrack,
            recommendations: [],
            progressPoints: []
        )

        await MainActor.run {
            goalAnalysis = analysis
        }
    }
    
    @MainActor
    private func refreshGoal() async {
        guard let currentGoalId = currentGoal?.id else {
            loadActiveGoal()
            return
        }
        
        do {
            let refreshedGoal = try await GoalService.getGoalById(currentGoalId)
            currentGoal = refreshedGoal
            
            if let goal = refreshedGoal {
                await generateAnalysis(for: goal)
            }
        } catch {
            errorMessage = "Failed to refresh goal: \(error.localizedDescription)"
            #if DEBUG
            print("❌ Error refreshing goal: \(error)")
            #endif
        }
    }
}

// MARK: - Goal Overview Section
struct GoalOverviewSection: View {
    let goal: RunningGoal
    let analysis: GoalAnalysis
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.title)
                        .font(.headline)
                        .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

                    Text(goal.formattedTarget())
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(AppTheme.Colors.accent)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(goal.daysRemaining) days left")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)

                    Text(analysis.trackingStatus.description)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.2))
                        .cornerRadius(8)
                }
            }

            // Progress Bar
            ProgressView(value: analysis.progressPercentage / 100.0)
                .progressViewStyle(LinearProgressViewStyle(tint: statusColor))
                .scaleEffect(x: 1, y: 2, anchor: .center)

            Text("\(Int(analysis.progressPercentage))% Complete")
                .font(.caption)
                .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
        }
    }
    
    private var statusColor: Color {
        switch analysis.trackingStatus {
        case .onTrack: return AppTheme.Colors.success
        case .slightlyBehind: return AppTheme.Colors.warning
        case .significantlyBehind: return AppTheme.Colors.error
        }
    }
}

// MARK: - Progress Chart
struct GoalProgressChart: View {
    let analysis: GoalAnalysis
    
    private var currentProgress: Double {
        analysis.progressPoints.first?.actualProgress ?? 0
    }
    
    private var targetProgress: Double {
        analysis.progressPoints.first?.targetProgress ?? 0
    }
    
    private var progressColor: Color {
        let ratio = currentProgress / max(targetProgress, 0.01)
        if ratio >= 1.0 { return AppTheme.Colors.success }
        if ratio >= 0.8 { return AppTheme.Colors.accent }
        if ratio >= 0.6 { return AppTheme.Colors.warning }
        return AppTheme.Colors.error
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Progress Overview")
                .font(.headline)
                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
            
            ZStack {
                // Background circle
                Circle()
                    .stroke(AppTheme.Colors.textTertiary.opacity(AppTheme.Opacity.medium), lineWidth: 20)
                    .frame(width: 160, height: 160)

                // Target progress ring (outer)
                Circle()
                    .trim(from: 0, to: targetProgress)
                    .stroke(
                        AppTheme.Colors.textSecondary.opacity(AppTheme.Opacity.strong),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                
                // Actual progress ring (inner)
                Circle()
                    .trim(from: 0, to: currentProgress)
                    .stroke(
                        LinearGradient(
                            colors: [progressColor.opacity(0.7), progressColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1.0), value: currentProgress)
                
                // Center content
                VStack(spacing: 4) {
                    Text("\(Int(currentProgress * 100))%")
                        .font(AppTheme.Typography.numberMedium)
                        .foregroundColor(progressColor)

                    Text("Complete")
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            
            // Progress details
            VStack(spacing: 8) {
                HStack {
                    Circle()
                        .fill(progressColor)
                        .frame(width: 12, height: 12)
                    Text("Current Progress")
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
                    Spacer()
                    Text("\(Int(currentProgress * 100))%")
                        .font(AppTheme.Typography.caption.weight(.semibold))
                        .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
                }

                HStack {
                    Circle()
                        .fill(AppTheme.Colors.textSecondary.opacity(AppTheme.Opacity.strong))
                        .frame(width: 12, height: 12)
                    Text("Target Progress")
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                    Spacer()
                    Text("\(Int(targetProgress * 100))%")
                        .font(AppTheme.Typography.caption.weight(.semibold))
                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                }

                if currentProgress > 0 && targetProgress > 0 {
                    let ratio = currentProgress / targetProgress
                    let statusText = ratio >= 1.0 ? "Ahead of Target" : ratio >= 0.8 ? "On Track" : "Behind Target"
                    let statusColor = ratio >= 1.0 ? AppTheme.Colors.success : ratio >= 0.8 ? AppTheme.Colors.accent : AppTheme.Colors.warning

                    HStack {
                        Image(systemName: ratio >= 1.0 ? "checkmark.circle.fill" : ratio >= 0.8 ? "clock.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(statusColor)
                            .font(AppTheme.Typography.caption)
                        Text(statusText)
                            .font(AppTheme.Typography.caption.weight(.medium))
                            .foregroundColor(statusColor)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding()
        .background(AppTheme.Colors.adaptiveCardBackground)
        .cornerRadius(AppTheme.CornerRadius.large)
    }
}

// MARK: - Empty State
struct GoalEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "target")
                .font(.system(size: 40))
                .foregroundColor(AppTheme.Colors.accent)
            
            VStack(spacing: 8) {
                Text("Set Your Running Goal")
                    .font(.headline)
                    .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

                Text("Get AI-powered training recommendations based on your performance data")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Goal Input Sheet
struct GoalInputSheet: View {
    @Environment(\.presentationMode) var presentationMode
    
    let currentGoal: RunningGoal?
    let onSave: (RunningGoal?) -> Void
    
    @State private var selectedType: GoalType = .distance
    @State private var targetValue: String = ""
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var goalTitle: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isMetric: Bool = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Goal Details")) {
                    TextField("Goal Title", text: $goalTitle)
                        .placeholder("e.g., 'Run a 10K'", when: goalTitle.isEmpty)
                    
                    Picker("Goal Type", selection: $selectedType) {
                        ForEach(GoalType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    // Unit toggle for distance and pace goals
                    if selectedType == .distance || selectedType == .pace {
                        HStack {
                            Text("Units")
                            Spacer()
                            Picker("Units", selection: $isMetric) {
                                Text(selectedType == .distance ? "Miles" : "Miles/Min").tag(false)
                                Text(selectedType == .distance ? "Kilometers" : "Km/Min").tag(true)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .frame(width: 180)
                        }
                        .onChange(of: isMetric) { _, newValue in
                            convertTargetValue(toMetric: newValue)
                        }
                    }
                    
                    HStack {
                        TextField("Target", text: $targetValue)
                            .keyboardType(.decimalPad)
                        
                        Text(selectedType.unit(isMetric: isMetric))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                    
                    DatePicker("Deadline", selection: $deadline, displayedComponents: .date)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(AppTheme.Colors.error)
                            .font(AppTheme.Typography.caption)
                    }
                }
            }
            .tint(AppTheme.Colors.accent)
            .navigationTitle(currentGoal == nil ? "Set Running Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(AppTheme.Colors.LightMode.accent)
                    .disabled(isSaving)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(AppTheme.Colors.LightMode.accent)
                    } else {
                        Button("Save") {
                            saveGoal()
                        }
                        .foregroundColor(AppTheme.Colors.LightMode.accent)
                        .disabled(!isValidInput)
                    }
                }
            }
        }
        .tint(AppTheme.Colors.LightMode.accent)
        .onAppear {
            loadCurrentGoal()
        }
    }
    
    private var isValidInput: Bool {
        !goalTitle.isEmpty && 
        !targetValue.isEmpty && 
        Double(targetValue) != nil &&
        deadline > Date() &&
        !isSaving
    }
    
    private func loadCurrentGoal() {
        if let goal = currentGoal {
            goalTitle = goal.title
            selectedType = goal.type
            targetValue = String(goal.targetValue)
            deadline = goal.deadline
        }
    }
    
    private func saveGoal() {
        guard let value = getTargetValueInMiles() else { return }
        
        isSaving = true
        errorMessage = nil
        
        Task {
            do {
                let goal: RunningGoal
                
                if let existingGoal = currentGoal {
                    // Update existing goal
                    let updatedGoal = RunningGoal(
                        id: existingGoal.id,
                        athleteId: existingGoal.athleteId,
                        type: selectedType,
                        targetValue: value,
                        deadline: deadline,
                        createdDate: existingGoal.createdDate,
                        updatedDate: existingGoal.updatedDate,
                        title: goalTitle,
                        isActive: existingGoal.isActive,
                        isCompleted: existingGoal.isCompleted,
                        currentProgress: existingGoal.currentProgress,
                        completedDate: existingGoal.completedDate
                    )
                    goal = try await GoalService.updateGoal(updatedGoal)
                } else {
                    // Create new goal
                    // First deactivate any existing goals of the same type
                    try await GoalService.deactivateGoalsOfType(selectedType)
                    
                    // Create the new goal
                    let newGoal = RunningGoal(
                        type: selectedType,
                        targetValue: value,
                        deadline: deadline,
                        title: goalTitle
                    )
                    goal = try await GoalService.createGoal(newGoal)
                }
                
                await MainActor.run {
                    onSave(goal)
                    presentationMode.wrappedValue.dismiss()
                }
                
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to save goal: \(error.localizedDescription)"
                    isSaving = false
                }
                #if DEBUG
                print("❌ Error saving goal: \(error)")
                #endif
            }
        }
    }
    
    private func convertTargetValue(toMetric: Bool) {
        guard !targetValue.isEmpty, let currentValue = Double(targetValue) else { return }
        
        if selectedType == .distance {
            if toMetric {
                // Convert miles to km
                let kmValue = currentValue * 1.60934
                targetValue = String(format: "%.1f", kmValue)
            } else {
                // Convert km to miles
                let milesValue = currentValue / 1.60934
                targetValue = String(format: "%.1f", milesValue)
            }
        } else if selectedType == .pace {
            if toMetric {
                // Convert min/mile to min/km (pace gets faster in km)
                let kmPace = currentValue / 1.60934
                targetValue = String(format: "%.2f", kmPace)
            } else {
                // Convert min/km to min/mile (pace gets slower in miles)
                let milePace = currentValue * 1.60934
                targetValue = String(format: "%.2f", milePace)
            }
        }
    }
    
    private func getTargetValueInMiles() -> Double? {
        guard let value = Double(targetValue) else { return nil }
        
        if selectedType == .distance && isMetric {
            // Convert km to miles for storage
            return value / 1.60934
        } else if selectedType == .pace && isMetric {
            // Convert min/km to min/mile for storage
            return value * 1.60934
        }
        
        return value // Already in miles or not distance/pace
    }
}

// MARK: - Helper Extensions
extension View {
    func placeholder(_ text: String, when shouldShow: Bool) -> some View {
        ZStack(alignment: .leading) {
            if shouldShow {
                Text(text)
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            self
        }
    }
}

// MARK: - Goal Readiness Compact Card
struct GoalReadinessCompactCard: View {
    let goalReadiness: GoalReadiness
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Goal Readiness")
                    .font(.headline)
                    .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
                
                Spacer()
                
                // Overall Score Badge
                Text("\(Int(goalReadiness.overallScore))%")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(getScoreColor(goalReadiness.overallScore))
                    .cornerRadius(8)
            }
            
            // Quick readiness indicators
            HStack(spacing: 16) {
                ReadinessIndicator(
                    title: "Fitness",
                    level: goalReadiness.fitnessLevel,
                    icon: "heart.fill"
                )
                
                ReadinessIndicator(
                    title: "Volume",
                    level: goalReadiness.volumePreparation,
                    icon: "speedometer"
                )
                
                ReadinessIndicator(
                    title: "Time",
                    level: goalReadiness.timeToGoal,
                    icon: "clock.fill"
                )
                
                ReadinessIndicator(
                    title: "Experience",
                    level: goalReadiness.experienceLevel,
                    icon: "star.fill"
                )
            }
            
            // Key recommendation
            if !goalReadiness.recommendations.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(AppTheme.Colors.accent)
                        .font(AppTheme.Typography.caption)
                        .padding(.top, 1)

                    Text(goalReadiness.recommendations.first ?? "")
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
                        .lineLimit(2)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(AppTheme.Colors.adaptiveCardBackground)
        .cornerRadius(AppTheme.CornerRadius.large)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }

    private func getScoreColor(_ score: Double) -> Color {
        switch score {
        case 80...: return AppTheme.Colors.success
        case 60..<80: return AppTheme.Colors.accent
        case 40..<60: return AppTheme.Colors.warning
        default: return AppTheme.Colors.error
        }
    }
}

struct ReadinessIndicator: View {
    let title: String
    let level: ReadinessLevel
    let icon: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(getLevelColor(level))
                .font(AppTheme.Typography.caption)
            
            Text(title)
                .font(AppTheme.Typography.caption2)
                .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                .lineLimit(1)
            
            Circle()
                .fill(getLevelColor(level))
                .frame(width: 8, height: 8)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func getLevelColor(_ level: ReadinessLevel) -> Color {
        switch level {
        case .excellent: return AppTheme.Colors.success
        case .good: return AppTheme.Colors.accent
        case .fair: return AppTheme.Colors.warning
        case .poor: return AppTheme.Colors.error
        }
    }
}
