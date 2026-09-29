//
//  OnboardingStepViews.swift
//  Runaway iOS
//
//  Created by Claude on 1/12/26.
//

import SwiftUI

// MARK: - Welcome View

struct OnboardingWelcomeView: View {
    let onContinue: () -> Void

    @State private var showContent = false

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // Logo/Icon
            VStack(spacing: 16) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 100))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(showContent ? 1 : 0.5)
                    .opacity(showContent ? 1 : 0)

                Text("Welcome to Runaway")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .opacity(showContent ? 1 : 0)
            }

            // Tagline
            Text("Track your runs, crush your goals,\nand become the runner you want to be.")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .opacity(showContent ? 1 : 0)

            Spacer()

            // Features preview
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "chart.line.uptrend.xyaxis", title: "Private Insights", description: "On-device guidance for your training")
                FeatureRow(icon: "flame.fill", title: "Daily Commitments", description: "Build habits that stick")
                FeatureRow(icon: "person.fill.checkmark", title: "Personal Coach", description: "Guidance tailored to you")
            }
            .padding(.horizontal, 32)
            .opacity(showContent ? 1 : 0)

            Spacer()

            // Continue button
            Button(action: onContinue) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
            .opacity(showContent ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                showContent = true
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Profile Setup View

struct OnboardingProfileSetupView: View {
    @Binding var firstName: String
    @Binding var lastName: String
    let onContinue: () -> Void

    @FocusState private var focusedField: Field?

    enum Field {
        case firstName, lastName
    }

    private var isValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "person.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.blue)

                Text("What's your name?")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("This helps personalize your experience")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)

            // Form fields
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("First Name")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("Enter your first name", text: $firstName)
                        .font(.body)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        .focused($focusedField, equals: .firstName)
                        .textContentType(.givenName)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .lastName
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Last Name (Optional)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("Enter your last name", text: $lastName)
                        .font(.body)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        .focused($focusedField, equals: .lastName)
                        .textContentType(.familyName)
                        .submitLabel(.done)
                        .onSubmit {
                            if isValid {
                                onContinue()
                            }
                        }
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Continue button
            Button(action: onContinue) {
                Text("Continue")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isValid ? Color.blue : Color.gray)
                    .cornerRadius(16)
            }
            .disabled(!isValid)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .onAppear {
            focusedField = .firstName
        }
    }
}

// MARK: - Goals Setup View

struct OnboardingGoalsPresentation: Equatable {
    let usesVerticalScroll = true
    let respectsSafeArea = true
    let dismissesKeyboardInteractively = true
    let keepsContinueReachableAtAccessibilitySizes = true
    let continueMinimumTargetSize = AppTheme.Layout.touchTargetMinimum
}

struct OnboardingGoalsSetupView: View {
    @Binding var primaryGoal: OnboardingPrimaryGoal
    @Binding var weeklyGoal: Double
    @Binding var monthlyGoal: Double
    let isNavigationDisabled: Bool
    let onContinue: () -> Void

    @State private var weeklyGoalText: String = ""
    @State private var monthlyGoalText: String = ""
    private let presentation = OnboardingGoalsPresentation()

    // Preset options for weekly goals
    private let weeklyPresets: [(label: String, value: Double)] = [
        ("10 mi", 10),
        ("15 mi", 15),
        ("20 mi", 20),
        ("25 mi", 25),
        ("30 mi", 30),
        ("40 mi", 40)
    ]

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 50))
                    .foregroundColor(.green)

                Text("Set Your Goals")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("What distance do you want to run each week?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)

            VStack(alignment: .leading, spacing: 12) {
                Text("Primary goal")
                    .font(.headline)

                ForEach([OnboardingPrimaryGoal.race, .running], id: \.rawValue) { goal in
                    Button {
                        primaryGoal = goal
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: primaryGoal == goal ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(primaryGoal == goal ? AppTheme.Colors.warmAmber : .secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(goal.displayName)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text(goal.detail)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.touchTargetMinimum, alignment: .leading)
                        .padding(.horizontal, 14)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(goal.displayName)
                    .accessibilityValue(primaryGoal == goal ? "Selected" : "Not selected")
                }
            }
            .padding(.horizontal, 24)

            // Weekly goal presets
            VStack(alignment: .leading, spacing: 12) {
                Text("Weekly Goal")
                    .font(.headline)
                    .padding(.horizontal, 24)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(weeklyPresets, id: \.value) { preset in
                            GoalPresetButton(
                                label: preset.label,
                                isSelected: weeklyGoal == preset.value,
                                action: {
                                    weeklyGoal = preset.value
                                    // Auto-calculate monthly as 4x weekly
                                    monthlyGoal = preset.value * 4
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }

            // Custom input
            VStack(alignment: .leading, spacing: 8) {
                Text("Or enter custom goals")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 24)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Weekly")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            TextField("20", text: $weeklyGoalText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.center)
                                .frame(width: 60)
                                .padding(.vertical, 12)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                                .onChange(of: weeklyGoalText) { _, newValue in
                                    if let value = Double(newValue), value > 0 {
                                        weeklyGoal = value
                                    }
                                }

                            Text("mi")
                                .foregroundColor(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Monthly")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            TextField("80", text: $monthlyGoalText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.center)
                                .frame(width: 60)
                                .padding(.vertical, 12)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                                .onChange(of: monthlyGoalText) { _, newValue in
                                    if let value = Double(newValue), value > 0 {
                                        monthlyGoal = value
                                    }
                                }

                            Text("mi")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }

            // Summary
            VStack(spacing: 8) {
                Text("Your targets")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 32) {
                    VStack {
                        Text("\(Int(weeklyGoal))")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.blue)
                        Text("mi/week")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack {
                        Text("\(Int(monthlyGoal))")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                        Text("mi/month")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
            .padding(.horizontal, 24)

            // Continue button
            Button(action: onContinue) {
                Text("Continue")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: presentation.continueMinimumTargetSize)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(16)
            }
            .disabled(isNavigationDisabled)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaPadding(.bottom, 8)
        .onAppear {
            weeklyGoalText = weeklyGoal > 0 ? String(format: "%.0f", weeklyGoal) : ""
            monthlyGoalText = monthlyGoal > 0 ? String(format: "%.0f", monthlyGoal) : ""
        }
    }
}

private struct GoalPresetButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? Color.blue : Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.clear : Color.gray.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Experience Assessment View

struct OnboardingExperienceView: View {
    @Binding var selectedLevel: ExperienceLevel
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "figure.run")
                    .font(.system(size: 50))
                    .foregroundColor(.blue)

                Text("What's your running experience?")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("This helps us personalize your experience")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)

            // Options
            VStack(spacing: 12) {
                ForEach(ExperienceLevel.allCases.filter { $0 != .skip }, id: \.self) { level in
                    ExperienceLevelCard(
                        level: level,
                        isSelected: selectedLevel == level,
                        onSelect: { selectedLevel = level }
                    )
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(16)
                }

                Button(action: onSkip) {
                    Text("Skip for now")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

struct ExperienceLevelCard: View {
    let level: ExperienceLevel
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                Image(systemName: level.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : level.color)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(isSelected ? level.color : level.color.opacity(0.1))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(level.displayName)
                        .font(.headline)
                        .foregroundColor(isSelected ? .white : .primary)

                    Text(level.description)
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)

                    if !level.weeklyMilesRange.isEmpty {
                        Text(level.weeklyMilesRange)
                            .font(.caption2)
                            .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? level.color : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.clear : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Movement Test View
// NOTE: Cadence assessment removed (recording stack removed). Onboarding step skipped.

struct OnboardingMovementTestView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void
    let onResult: (MovementTestResult) -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)

                Text("You're Almost Set")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Runaway will analyze your running data from Strava and HealthKit to personalize your experience.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.top, 60)

            Spacer()

            Button(action: onContinue) {
                Text("Continue")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Location Permission View

struct OnboardingLocationView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void
    let onPermissionResult: (Bool) -> Void

    @State private var permissionGranted = false

    var body: some View {
        VStack(spacing: 24) {
            // Map preview placeholder
            ZStack {
                // Background gradient to simulate map
                LinearGradient(
                    colors: [Color.green.opacity(0.3), Color.blue.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Grid pattern to simulate streets
                VStack(spacing: 20) {
                    ForEach(0..<4, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.white.opacity(0.5))
                            .frame(height: 2)
                    }
                }

                HStack(spacing: 30) {
                    ForEach(0..<5, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.white.opacity(0.5))
                            .frame(width: 2)
                    }
                }

                // Route line
                Path { path in
                    path.move(to: CGPoint(x: 50, y: 150))
                    path.addCurve(
                        to: CGPoint(x: 300, y: 50),
                        control1: CGPoint(x: 100, y: 100),
                        control2: CGPoint(x: 200, y: 80)
                    )
                }
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))

                // Location pin
                VStack(spacing: 0) {
                    Image(systemName: "location.fill")
                        .font(.title)
                        .foregroundColor(.blue)
                    Circle()
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: 20, height: 10)
                }
                .offset(x: 50, y: -20)
            }
            .frame(height: 200)
            .cornerRadius(20)
            .padding(.horizontal)
            .padding(.top)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                    .padding(.horizontal)
                    .padding(.top)
            )

            // Header
            VStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)

                Text("Track Your Routes")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Enable location to map your runs and discover popular routes nearby")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Benefits
            VStack(alignment: .leading, spacing: 12) {
                OnboardingBenefitRow(icon: "map.fill", text: "See your run routes on a map")
                OnboardingBenefitRow(icon: "figure.run", text: "Track pace and distance accurately")
                OnboardingBenefitRow(icon: "star.fill", text: "Discover popular running routes")
            }
            .padding(.horizontal, 32)

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                Button(action: requestLocationPermission) {
                    HStack {
                        Image(systemName: "location.fill")
                        Text("Enable Location")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(16)
                }

                Button(action: {
                    onPermissionResult(false)
                    onSkip()
                }) {
                    Text("Maybe later")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    private func requestLocationPermission() {
        LocationManager.shared.requestLocationPermission()

        // Check result after a moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let granted = LocationManager.shared.authorizationStatus == .authorizedWhenInUse ||
                         LocationManager.shared.authorizationStatus == .authorizedAlways
            permissionGranted = granted
            onPermissionResult(granted)
            onContinue()
        }
    }
}

struct OnboardingBenefitRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Coach Selection View

struct OnboardingCoachSelectionView: View {
    @Binding var selectedPersonality: CoachPersonality
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "person.fill.questionmark")
                    .font(.system(size: 50))
                    .foregroundColor(.purple)

                Text("Choose Your Coach Style")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("How do you like to receive feedback?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)

            // Options
            VStack(spacing: 16) {
                ForEach(CoachPersonality.allCases, id: \.self) { personality in
                    CoachPersonalityCard(
                        personality: personality,
                        isSelected: selectedPersonality == personality,
                        onSelect: { selectedPersonality = personality }
                    )
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Continue button
            Button(action: onContinue) {
                Text("Continue")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

struct CoachPersonalityCard: View {
    let personality: CoachPersonality
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: personality.icon)
                        .font(.title2)
                        .foregroundColor(isSelected ? .white : personality.color)

                    Text(personality.displayName)
                        .font(.headline)
                        .foregroundColor(isSelected ? .white : .primary)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.white)
                    }
                }

                Text(personality.description)
                    .font(.subheadline)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)

                // Sample message
                Text(personality.sampleMessage)
                    .font(.caption)
                    .italic()
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                    .padding(.top, 4)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? personality.color : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.clear : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Completion View

struct OnboardingCompletionView: View {
    let experienceLevel: ExperienceLevel
    let coachPersonality: CoachPersonality
    let onComplete: () -> Void

    @State private var showContent = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Success animation
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
                    .scaleEffect(showContent ? 1 : 0.5)

                Text("You're All Set!")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Your personalized running experience is ready")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(showContent ? 1 : 0)

            // Summary
            VStack(spacing: 16) {
                SummaryRow(
                    icon: experienceLevel.icon,
                    title: "Experience",
                    value: experienceLevel.displayName,
                    color: experienceLevel.color
                )

                SummaryRow(
                    icon: coachPersonality.icon,
                    title: "Coach Style",
                    value: coachPersonality.displayName,
                    color: coachPersonality.color
                )
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemBackground))
            )
            .padding(.horizontal, 32)
            .opacity(showContent ? 1 : 0)

            Spacer()

            // Start button
            Button(action: onComplete) {
                Text("Start Running")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
            .opacity(showContent ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                showContent = true
            }
        }
    }
}

struct SummaryRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 30)

            Text(title)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Runner Mindset Step

struct RunnerMindsetStepView: View {
    let onContinue: (String, [String]) -> Void
    let onSkip: () -> Void

    @State private var whyIRun: String = ""
    @State private var selectedValues: [String] = []

    private let presetValues = AppConstants.Mindset.coreValuePresets

    private var canContinue: Bool {
        whyIRun.trimmingCharacters(in: .whitespaces).count >= 10 && !selectedValues.isEmpty
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Spacer().frame(height: 8)

                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your Running Mindset")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("Understanding why you run helps your AI coach support you better.")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(.secondary)
                    }

                    // WHY I RUN
                    VStack(alignment: .leading, spacing: 10) {
                        Text("WHY I RUN")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                            .kerning(1.2)

                        ZStack(alignment: .topLeading) {
                            if whyIRun.isEmpty {
                                Text("I run to clear my head and feel strong")
                                    .font(.system(size: 15, design: .rounded))
                                    .foregroundColor(Color(.tertiaryLabel))
                                    .padding(.horizontal, 12)
                                    .padding(.top, 12)
                            }
                            TextEditor(text: $whyIRun)
                                .font(.system(size: 15, design: .rounded))
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .frame(minHeight: 100)
                                .onChange(of: whyIRun) { _, newValue in
                                    if newValue.count > 200 {
                                        whyIRun = String(newValue.prefix(200))
                                    }
                                }
                        }
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Text("\(whyIRun.count)/200")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    // WHAT MATTERS MOST
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("WHAT MATTERS MOST")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                                .kerning(1.2)
                            Spacer()
                            Text("Pick up to 3")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        OnboardingChipGrid(
                            values: presetValues,
                            selected: $selectedValues,
                            maxSelected: 3
                        )
                    }

                    // Continue button
                    Button {
                        onContinue(
                            whyIRun.trimmingCharacters(in: .whitespaces),
                            selectedValues
                        )
                    } label: {
                        Text("Continue")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(canContinue ? AppTheme.Colors.strideLime : AppTheme.Colors.strideLime.opacity(0.3))
                            .foregroundColor(AppTheme.Colors.pine)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!canContinue)

                    // Skip link
                    Button {
                        onSkip()
                    } label: {
                        Text("Skip for now")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }

                    Spacer().frame(height: 20)
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

// MARK: - Onboarding Chip Grid

private struct OnboardingChipGrid: View {
    let values: [String]
    @Binding var selected: [String]
    let maxSelected: Int

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(values, id: \.self) { value in
                let isSelected = selected.contains(value)
                Button {
                    toggleValue(value)
                } label: {
                    Text(isSelected ? "✓ \(value)" : value)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular, design: .rounded))
                        .foregroundColor(isSelected ? Color.accentColor : Color(.secondaryLabel))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(isSelected
                            ? Color.accentColor.opacity(0.12)
                            : Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(
                                isSelected ? Color.accentColor : Color(.separator),
                                lineWidth: 1
                            )
                        )
                }
            }
        }
    }

    private func toggleValue(_ value: String) {
        if let index = selected.firstIndex(of: value) {
            selected.remove(at: index)
        } else if selected.count < maxSelected {
            selected.append(value)
        } else {
            selected.removeFirst()
            selected.append(value)
        }
    }
}

// MARK: - Training Profile Steps

struct OnboardingActivityMixView: View {
    @ObservedObject var model: TrainingProfileEditorViewModel
    let onBack: () -> Void
    let onContinue: () -> Void
    let isNavigationDisabled: Bool

    private var canContinue: Bool {
        model.draft.validated().profile.primaryActivity != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                onboardingTrainingHeader(
                    eyebrow: "TRAINING INTENT",
                    title: "How do you want to train?",
                    detail: "Pick the activities that belong in your week. You can change the role and frequency as soon as you select one."
                )

                ActivityMixEditor(model: model)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    EyebrowLabel(text: "YOUR WEEK", color: AppTheme.Colors.warmAmber)
                    Text(model.summary)
                        .font(AppTheme.Typography.title3)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(AppTheme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.Colors.DarkMode.cardBackgroundElevated)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large))

                onboardingTrainingNavigation(
                    onBack: onBack,
                    onContinue: onContinue,
                    continueLabel: "Continue to training schedule",
                    isContinueDisabled: !canContinue || isNavigationDisabled
                )
            }
            .padding(AppTheme.Spacing.xl)
            .padding(.bottom, AppTheme.Spacing.xxl)
        }
        .background(AppTheme.Colors.DarkMode.background)
    }
}

struct OnboardingTrainingScheduleView: View {
    @ObservedObject var model: TrainingProfileEditorViewModel
    let onBack: () -> Void
    let onContinue: () -> Void
    let isNavigationDisabled: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                onboardingTrainingHeader(
                    eyebrow: "WEEKLY RHYTHM",
                    title: "Shape a week you can repeat",
                    detail: "Start with the simple version, then mark the days that genuinely cannot work."
                )

                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    EyebrowLabel(text: "PLAN SUMMARY", color: AppTheme.Colors.warmAmber)
                    Text(model.summary)
                        .font(AppTheme.Typography.title3)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Runaway will balance this mix across your available days.")
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                .padding(AppTheme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.Colors.DarkMode.cardBackgroundElevated)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large))

                TrainingScheduleEditor(model: model)

                if model.controlPresentation.showsStrengthControls {
                    StrengthTrainingDetailsEditor(model: model)
                }

                onboardingTrainingNavigation(
                    onBack: onBack,
                    onContinue: onContinue,
                    continueLabel: "Continue onboarding",
                    isContinueDisabled: model.draft.validated().profile.primaryActivity == nil || isNavigationDisabled
                )
            }
            .padding(AppTheme.Spacing.xl)
            .padding(.bottom, AppTheme.Spacing.xxl)
        }
        .background(AppTheme.Colors.DarkMode.background)
    }
}

private func onboardingTrainingHeader(
    eyebrow: String,
    title: String,
    detail: String
) -> some View {
    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
        EyebrowLabel(text: eyebrow, color: AppTheme.Colors.warmAmber)
        Text(title)
            .font(AppTheme.Typography.title)
            .foregroundColor(AppTheme.Colors.textPrimary)
        Text(detail)
            .font(AppTheme.Typography.subheadline)
            .foregroundColor(AppTheme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct OnboardingTrainingNavigationPresentation: Equatable {
    let backLabel = "Back"
    let continueLabel: String
    let minimumTargetSize = AppTheme.Layout.touchTargetMinimum
}

private func onboardingTrainingNavigation(
    onBack: @escaping () -> Void,
    onContinue: @escaping () -> Void,
    continueLabel: String,
    isContinueDisabled: Bool
) -> some View {
    let presentation = OnboardingTrainingNavigationPresentation(continueLabel: continueLabel)
    return HStack(spacing: AppTheme.Spacing.md) {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .frame(width: presentation.minimumTargetSize, height: AppTheme.Layout.touchTargetPreferred)
        }
        .buttonStyle(.plain)
        .foregroundColor(AppTheme.Colors.textSecondary)
        .accessibilityLabel(presentation.backLabel)

        Button(action: onContinue) {
            Text("Continue")
                .font(AppTheme.Typography.bodyBold)
                .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.touchTargetPreferred)
        }
        .primaryButton()
        .buttonStyle(.plain)
        .disabled(isContinueDisabled)
        .opacity(isContinueDisabled ? 0.6 : 1)
        .accessibilityLabel(presentation.continueLabel)
    }
}

// MARK: - Previews

#Preview("Welcome") {
    OnboardingWelcomeView(onContinue: {})
}

#Preview("Experience") {
    OnboardingExperienceView(
        selectedLevel: .constant(.intermediate),
        onContinue: {},
        onSkip: {}
    )
}

#Preview("Coach Selection") {
    OnboardingCoachSelectionView(
        selectedPersonality: .constant(.balanced),
        onContinue: {}
    )
}

#Preview("Completion") {
    OnboardingCompletionView(
        experienceLevel: .intermediate,
        coachPersonality: .balanced,
        onComplete: {}
    )
}

#Preview("Runner Mindset") {
    RunnerMindsetStepView(onContinue: { _, _ in }, onSkip: {})
}
