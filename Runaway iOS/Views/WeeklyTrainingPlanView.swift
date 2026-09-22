//
//  WeeklyTrainingPlanView.swift
//  Runaway iOS
//
//  Weekly training plan view showing Sun-Sat workouts
//

import SwiftUI

@MainActor
struct WeeklyTrainingPlanSurface {
    let dataManager: DataManager
    let trainingProfileStore: TrainingProfileStore

    var currentPlan: WeeklyTrainingPlan? { dataManager.currentWeeklyPlan }

    func load() async {
        await dataManager.loadCurrentWeeklyPlan(profile: trainingProfileStore.profile)
    }

    func generateInitialCurrentWeek() async throws -> WeeklyTrainingPlan {
        try await dataManager.generateTrainingPlan(
            profile: trainingProfileStore.profile,
            scope: .initialCurrentWeek
        )
    }
}

struct WeeklyTrainingPlanView: View {
    @Environment(DataManager.self) var dataManager
    @EnvironmentObject private var trainingProfileStore: TrainingProfileStore
    @State private var isLoading = false
    @State private var isGenerating = false
    @State private var selectedWorkout: DailyWorkout?
    @State private var errorMessage: String?

    private var surface: WeeklyTrainingPlanSurface {
        WeeklyTrainingPlanSurface(
            dataManager: dataManager,
            trainingProfileStore: trainingProfileStore
        )
    }

    private var weeklyPlan: WeeklyTrainingPlan? { surface.currentPlan }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Week Header
                weekHeader

                if isLoading {
                    loadingView
                } else if let plan = weeklyPlan {
                    // Weekly Stats Summary
                    weekSummaryCard(plan: plan)

                    // Daily Workouts
                    ForEach(DayOfWeek.allCases, id: \.self) { day in
                        if let workout = plan.workout(for: day) {
                            WorkoutDayCard(workout: workout) {
                                selectedWorkout = workout
                            }
                        }
                    }
                } else {
                    // No plan - show generate button
                    noPlanView
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding()
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Training Plan")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selectedWorkout) { workout in
            WorkoutDetailSheet(workout: workout)
        }
        .task {
            await loadPlan()
        }
    }

    // MARK: - Subviews

    private var weekHeader: some View {
        VStack(spacing: 8) {
            if let plan = weeklyPlan {
                Text(plan.weekRangeString)
                    .font(.title2)
                    .fontWeight(.bold)

                if plan.isCurrentWeek {
                    Text("This Week")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                }
            } else {
                Text("This Week's Plan")
                    .font(.title2)
                    .fontWeight(.bold)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func weekSummaryCard(plan: WeeklyTrainingPlan) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text("Week Overview")
                    .font(.headline)
                Spacer()
                if let focus = plan.focusArea {
                    Text(focus)
                        .font(.caption)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
            }

            HStack(spacing: 20) {
                StatPill(title: "Total Miles", value: String(format: "%.1f", plan.totalMileage), icon: "figure.run")
                StatPill(title: "Workouts", value: "\(plan.workouts.count)", icon: "calendar")
                StatPill(title: "Run Days", value: "\(plan.workouts.filter { $0.workoutType.isRunning }.count)", icon: "shoe")
                StatPill(title: "Strength", value: "\(plan.workouts.filter { $0.workoutType.isStrength }.count)", icon: "dumbbell")
            }

            if let notes = plan.notes {
                Text(notes)
                    .font(.subheadline)
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading plan...")
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(60)
    }

    private var noPlanView: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.blue.opacity(0.6))

            Text("No Training Plan Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Generate a personalized weekly plan based on your goals. Includes running, strength training, and active recovery.")
                .font(.subheadline)
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: {
                Task { await generatePlan() }
            }) {
                HStack {
                    if isGenerating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isGenerating ? "Generating..." : "Generate Plan")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }
            .disabled(isGenerating)
            .padding(.horizontal)
        }
        .padding(40)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }

    // MARK: - Actions

    private func loadPlan() async {
        isLoading = true
        errorMessage = nil
        await surface.load()
        isLoading = false
    }

    private func generatePlan() async {
        isGenerating = true
        errorMessage = nil

        do {
            _ = try await surface.generateInitialCurrentWeek()
        } catch {
            errorMessage = error.localizedDescription
        }

        isGenerating = false
    }
}

// MARK: - Workout Day Card

struct WorkoutDayCard: View {
    let workout: DailyWorkout
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Day indicator
                VStack {
                    Text(workout.dayOfWeek.shortName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    Text(dayNumber)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(isToday ? .white : .primary)
                }
                .frame(width: 50, height: 50)
                .background(isToday ? Color.blue : Color(.systemGray6))
                .cornerRadius(12)

                // Workout info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: workout.workoutType.icon)
                            .foregroundColor(workout.workoutType.color)
                        Text(workout.title)
                            .font(.headline)
                            .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
                    }

                    HStack(spacing: 12) {
                        if let distance = workout.formattedDistance {
                            Label(distance, systemImage: "ruler")
                                .font(.caption)
                                .foregroundColor(AppTheme.Colors.textSecondary)
                        }
                        if let duration = workout.formattedDuration {
                            Label(duration, systemImage: "clock")
                                .font(.caption)
                                .foregroundColor(AppTheme.Colors.textSecondary)
                        }
                        if let pace = workout.displayTargetPace {
                            Label(pace, systemImage: "speedometer")
                                .font(.caption)
                                .foregroundColor(AppTheme.Colors.textSecondary)
                        }
                    }
                }

                Spacer()

                // Completion indicator
                if workout.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(workout.date)
    }

    private var dayNumber: String {
        let day = Calendar.current.component(.day, from: workout.date)
        return "\(day)"
    }
}

// MARK: - Stat Pill

struct StatPill: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.blue)
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            Text(title)
                .font(.caption2)
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Workout Detail Sheet

struct WorkoutDetailSheet: View {
    let workout: DailyWorkout
    var whyToday: String? = nil
    var recommendationOnly: Bool = false
    var recommendationExplanation: TodayRecommendationExplanation? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: workout.workoutType.icon)
                                .font(.title)
                                .foregroundColor(workout.workoutType.color)
                            Text(workout.workoutType.displayName)
                                .font(.caption)
                                .foregroundColor(AppTheme.Colors.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(workout.workoutType.color.opacity(0.1))
                                .cornerRadius(8)
                        }

                        Text(workout.title)
                            .font(.title)
                            .fontWeight(.bold)

                        Text(workout.dayOfWeek.fullName + ", " + formattedDate)
                            .font(.subheadline)
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }

                    if recommendationOnly {
                        Label("Recommendation, not yet scheduled", systemImage: "info.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Use Performance Coach on Today to choose this session, review its exact dose and see how the week adapts before committing.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Workout Details
                    HStack(spacing: 20) {
                        if let distance = workout.distance {
                            DetailBox(title: "Distance", value: UnitFormatter.formatDistance(distance * 1609.344, decimals: 1, includeUnit: true))
                        }
                        if let duration = workout.duration {
                            DetailBox(title: "Duration", value: "\(duration) min")
                        }
                        if let effort = AcceptedPrescriptionCompletionPolicy.effortLabel(for: workout) {
                            DetailBox(title: "Effort", value: effort)
                        } else if let pace = workout.displayTargetPace {
                            DetailBox(title: "Pace", value: pace)
                        }
                    }

                    if let recommendationExplanation {
                        TodayRecommendationExplanationView(explanation: recommendationExplanation)
                    } else if let whyToday, !whyToday.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Why today", systemImage: "lightbulb")
                                .font(.headline)
                            Text(whyToday)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.headline)
                        Text(workout.displayDescription)
                            .font(.body)
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }

                    if !recommendationOnly {
                        if workout.acceptedPrescription != nil {
                            AcceptedWorkoutCompletionPanel(workout: workout)
                        }
                        NativeWorkoutContextCard(workout: workout)
                    }

                    // Exercises (for strength workouts)
                    if let exercises = workout.exercises, !exercises.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Exercises")
                                .font(.headline)

                            ForEach(exercises) { exercise in
                                ExerciseRow(exercise: exercise)
                            }
                        }
                    } else if workout.workoutType.isStrength {
                        Label("This session has no exercise breakdown yet. It has not been personalized into a complete strength workout.", systemImage: "info.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: workout.date)
    }
}

struct TodayRecommendationExplanationView: View {
    let explanation: TodayRecommendationExplanation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Why this workout?", systemImage: "lightbulb")
                .font(.headline)
            Text(explanation.recommendation.reason ?? explanation.recommendation.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup("See decision details") {
                VStack(alignment: .leading, spacing: 18) {
                    explanationRow("Selection rule", detail: explanation.didRankAlternatives
                        ? "Next Up ranked activity-mix candidates using scheduling and readiness rules. The reason above describes the selected candidate; it is not a complete goal-based prescription."
                        : "Next Up kept the planned session or your explicit choice. It did not rank alternatives for this decision.")

                    explanationRow("Readiness input", detail: explanation.readinessScore.map {
                        "\($0)/100 was supplied to Next Up. This is not a new readiness calculation."
                    } ?? "No readiness score was supplied. This is not confirmation that you are recovered or ready for hard training.")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recorded context: previous 7 days").font(.subheadline.bold())
                        if explanation.completedWorkouts.isEmpty {
                            Text("No classified completed sessions were supplied. Missing records are not proof that you rested.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(explanation.completedWorkouts, id: \.id) { workout in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workout.workoutType.displayName)
                                    Text(workout.date, format: .dateTime.month(.abbreviated).day())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Text("Missed plans are not completed workload. These are the records available to the decision, not a claim that every session determined today's choice.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    explanationRow("Upcoming plan", detail: upcomingDetail)
                    explanationRow("Activity mix used", detail: explanation.trainingMix.isEmpty
                        ? "No positive weekly activity targets were supplied."
                        : explanation.trainingMix.joined(separator: "\n"))
                    explanationRow("Not connected yet", detail: "Targets in Goals & Current Ability and its session previews do not yet drive Next Up. Your existing activity mix still drives this recommendation.")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Evaluated \(explanation.evaluatedAt.formatted(date: .abbreviated, time: .shortened))")
                        Text("Recomputed from currently available inputs, not a saved historical decision. Weather guidance is shown separately.")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            }
            .tint(AppTheme.Colors.strideBlue)
        }
        .accessibilityIdentifier("whyThisWorkoutExplanation")
    }

    private var upcomingDetail: String {
        let tomorrow = explanation.nextPlannedWorkout.map {
            "Tomorrow's planned \($0.displayName.lowercased()) is available as an adjacent-session constraint."
        } ?? "No planned session for tomorrow was supplied."
        return "\(tomorrow) \(explanation.reservedFutureSessionCount) future planned sessions reserve activity-mix slots; they are not completed workload."
    }

    private func explanationRow(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            Text(detail).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Detail Box

struct DetailBox: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            Text(title)
                .font(.caption)
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Exercise Row

struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let weight = exercise.weight, !weight.isEmpty {
                    Text(weight)
                        .font(.subheadline)
                }

                if let notes = exercise.notes {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }

            Spacer()

            if let sets = exercise.sets, let reps = exercise.reps {
                Text("\(sets) x \(reps)")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.Colors.textSecondary)
            } else if let reps = exercise.reps {
                Text(reps)
                    .font(.subheadline)
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

#Preview {
    NavigationView {
        WeeklyTrainingPlanView()
            .environment(DataManager.shared)
    }
}
