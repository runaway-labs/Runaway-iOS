//
//  ReadinessComponents.swift
//  Runaway iOS
//
//  UI components for displaying daily readiness scores
//

import SwiftUI

// MARK: - Readiness Gauge

/// Circular gauge showing readiness score
struct ReadinessGauge: View {
    let score: Int
    let level: DailyReadinessLevel
    let size: CGFloat

    init(score: Int, level: DailyReadinessLevel? = nil, size: CGFloat = 120) {
        self.score = score
        self.level = level ?? DailyReadinessLevel.from(score: score)
        self.size = size
    }

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: size * 0.1)

            // Progress arc
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(
                    Color(hex: level.color),
                    style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.8), value: score)

            // Score text
            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.system(size: size * 0.35, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: level.color))

                Text(level.rawValue)
                    .font(.system(size: size * 0.12, weight: .medium))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Readiness Card

/// Card displaying readiness score with factors
struct ReadinessCard: View {
    let readiness: DailyReadiness
    var onTap: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today's Readiness")
                            .font(.headline)
                            .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

                        Text(readiness.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }

                    Spacer()

                    Image(systemName: readiness.level.systemImageName)
                        .font(.title2)
                        .foregroundColor(Color(hex: readiness.level.color))
                }

                // Gauge
                ReadinessGauge(score: readiness.score, level: readiness.level, size: 100)
                    .padding(.vertical, 8)

                // Factors grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(readiness.factors) { factor in
                        FactorPill(factor: factor)
                    }
                }

            // Recommendation
            Text(readiness.recommendation)
                .font(.subheadline)
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .onTapGesture {
            onTap?()
        }
    }
}

// MARK: - Factor Pill

/// Small pill showing individual readiness factor
struct FactorPill: View {
    let factor: ReadinessFactor

    var body: some View {
        HStack(spacing: 8) {
            // Score indicator
            ZStack {
                Circle()
                    .fill(scoreColor.opacity(0.2))
                    .frame(width: 32, height: 32)

                Text("\(factor.score)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(scoreColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(factor.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

                HStack(spacing: 4) {
                    if !factor.value.isEmpty {
                        Text(factor.value)
                            .font(.caption2)
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }

                    if let change = factor.change {
                        Text(change)
                            .font(.caption2)
                            .foregroundColor(Color(hex: factor.trend.color))
                    }
                }
            }

            Spacer()

            Image(systemName: factor.trend.systemImageName)
                .font(.caption)
                .foregroundColor(Color(hex: factor.trend.color))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    private var scoreColor: Color {
        if factor.score >= 70 { return .green }
        if factor.score >= 50 { return .yellow }
        return .red
    }
}

// MARK: - Compact Readiness View

/// Smaller readiness display for list items
struct CompactReadinessView: View {
    let readiness: DailyReadiness

    var body: some View {
        HStack(spacing: 12) {
            // Small gauge
            ReadinessGauge(score: readiness.score, level: readiness.level, size: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text("Readiness: \(readiness.level.rawValue)")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(readiness.recommendation)
                    .font(.caption)
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Readiness Section for Training View

/// Section showing readiness in the Training tab
struct ReadinessSection: View {
    @StateObject private var readinessService = ReadinessService.shared
    @State private var showingFullReadiness = false
    @State private var errorMessage: String?
    @State private var isRequestingAuth = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Label("Daily Readiness", systemImage: "heart.circle.fill")
                    .font(.headline)
                    .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

                Spacer()

                if readinessService.isCalculating || isRequestingAuth {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            // Content
            if let readiness = readinessService.todaysReadiness {
                CompactReadinessView(readiness: readiness)
                    .onTapGesture {
                        showingFullReadiness = true
                    }
            } else if !HealthKitManager.isHealthKitAvailable {
                HealthKitUnavailableView()
            } else if let error = errorMessage {
                ReadinessErrorView(message: error) {
                    errorMessage = nil
                    await calculateReadiness()
                }
            } else {
                NoReadinessDataView {
                    await calculateReadiness()
                }
            }
        }
        .sheet(isPresented: $showingFullReadiness) {
            if let readiness = readinessService.todaysReadiness {
                ReadinessDetailView(readiness: readiness)
            }
        }
        .task {
            await readinessService.refreshIfNeeded()
        }
    }

    private func calculateReadiness() async {
        errorMessage = nil
        isRequestingAuth = true

        do {
            // First ensure HealthKit is authorized
            let isAuthorized = HealthKitManager.shared.isAuthorized
            if !isAuthorized {
                // Request authorization
                let granted = await HealthKitManager.shared.requestAuthorization()
                if !granted {
                    isRequestingAuth = false
                    errorMessage = "HealthKit access required. Please enable in Settings > Privacy > Health."
                    return
                }
            }

            isRequestingAuth = false

            // Now calculate readiness
            _ = try await readinessService.calculateTodaysReadiness()
        } catch {
            isRequestingAuth = false
            errorMessage = error.localizedDescription
            #if DEBUG
            print("❌ Readiness calculation failed: \(error)")
            #endif
        }
    }
}

// MARK: - Readiness Detail View

/// Full-screen view showing detailed readiness info
struct ReadinessDetailView: View {
    let readiness: DailyReadiness
    @Environment(\.dismiss) private var dismiss
    @StateObject private var readinessService = ReadinessService.shared
    @State private var isRecalibrating = false
    @State private var recalibrationError: String?
    @State private var lastRecalibratedAt: Date?

    private var currentReadiness: DailyReadiness {
        readinessService.todaysReadiness ?? readiness
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Large gauge
                    ReadinessGauge(score: currentReadiness.score, level: currentReadiness.level, size: 180)
                        .padding(.top, 20)

                    // Recommendation card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Today's Recommendation")
                            .font(.subheadline)
                            .foregroundColor(AppTheme.Colors.textSecondary)

                        Text(currentReadiness.recommendation)
                            .font(.body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(hex: currentReadiness.level.color).opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Factors breakdown
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Contributing Factors")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(currentReadiness.factors) { factor in
                            FactorDetailRow(factor: factor)
                        }
                    }

                    VStack(spacing: 8) {
                        Button {
                            Task { await recalibrateReadiness() }
                        } label: {
                            HStack(spacing: 8) {
                                if isRecalibrating {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text(isRecalibrating ? "Recalibrating..." : "Recalibrate readiness")
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRecalibrating)
                        .accessibilityHint("Rechecks HealthKit, running load, and recovery data without using the cached score")

                        if let lastRecalibratedAt {
                            Text("Updated \(lastRecalibratedAt.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundColor(AppTheme.Colors.textSecondary)
                        }

                        if let recalibrationError {
                            Text(recalibrationError)
                                .font(.caption)
                                .foregroundStyle(AppTheme.Colors.error)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 40)
            }
            .navigationTitle("Readiness Details")
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

    @MainActor
    private func recalibrateReadiness() async {
        isRecalibrating = true
        recalibrationError = nil
        defer { isRecalibrating = false }

        do {
            _ = try await readinessService.calculateTodaysReadiness()
            lastRecalibratedAt = Date()
        } catch {
            recalibrationError = "Couldn’t recalibrate right now. Your previous score is still available."
        }
    }
}

// MARK: - Factor Detail Row

struct FactorDetailRow: View {
    let factor: ReadinessFactor

    var body: some View {
        HStack(spacing: 16) {
            // Score ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                    .frame(width: 50, height: 50)

                Circle()
                    .trim(from: 0, to: CGFloat(factor.score) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(-90))

                Text("\(factor.score)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(factor.name)
                    .font(.headline)

                HStack(spacing: 8) {
                    if !factor.value.isEmpty {
                        Text(factor.value)
                            .font(.subheadline)
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }

                    if let change = factor.change {
                        HStack(spacing: 2) {
                            Image(systemName: factor.trend.systemImageName)
                            Text(change)
                        }
                        .font(.caption)
                        .foregroundColor(Color(hex: factor.trend.color))
                    }
                }
            }

            Spacer()

            Text("\(Int(factor.weight * 100))%")
                .font(.caption)
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private var scoreColor: Color {
        if factor.score >= 70 { return .green }
        if factor.score >= 50 { return .yellow }
        return .red
    }
}

// MARK: - Helper Views

struct HealthKitUnavailableView: View {
    var body: some View {
        HStack {
            Image(systemName: "heart.slash")
                .foregroundColor(AppTheme.Colors.textSecondary)

            Text("HealthKit not available on this device")
                .font(.subheadline)
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct NoReadinessDataView: View {
    let onCalculate: () async -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.square")
                .font(.largeTitle)
                .foregroundColor(AppTheme.Colors.textSecondary)

            Text("No readiness data yet")
                .font(.subheadline)
                .foregroundColor(AppTheme.Colors.textSecondary)

            Text("Calculate your daily readiness score based on sleep, HRV, resting heart rate, and training load.")
                .font(.caption)
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await onCalculate()
                }
            } label: {
                Text("Calculate Readiness")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct ReadinessErrorView: View {
    let message: String
    let onRetry: () async -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)

            Text("Unable to calculate readiness")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

            Text(message)
                .font(.caption)
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await onRetry()
                }
            } label: {
                Text("Try Again")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Readiness Banner (Color-coded, glanceable)

struct ReadinessBanner: View {
    var compact = false
    @StateObject private var readinessService = ReadinessService.shared
    @State private var showingDetail = false

    var body: some View {
        Button(action: { showingDetail = true }) {
            HStack(spacing: 16) {
                // ── Ring gauge ─────────────────────────────────────────────
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 5)
                        .frame(width: compact ? 42 : 64, height: compact ? 42 : 64)
                    Circle()
                        .trim(from: 0, to: ringProgress)
                        .stroke(readinessColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: compact ? 42 : 64, height: compact ? 42 : 64)
                        .rotationEffect(.degrees(-90))
                    if let score = readinessService.todaysReadiness?.score {
                        VStack(spacing: 0) {
                            Text("\(score)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .monospacedDigit()
                            Text("%")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AppTheme.Colors.DarkMode.textTertiary)
                        }
                    } else if readinessService.isCalculating {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "questionmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.Colors.DarkMode.textTertiary)
                    }
                }

                // ── Text stack ─────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 4) {
                    EyebrowLabel(text: "READINESS · \(readinessLevelLabel)", color: readinessColor)
                    Text(readinessHeadline)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text(compact ? "Tap for recovery details" : readinessSubtext)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(AppTheme.Colors.DarkMode.textTertiary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.Colors.DarkMode.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(compact ? Color.white.opacity(0.03) : readinessColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium + 2))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium + 2)
                    .stroke(compact ? Color.white.opacity(0.07) : readinessColor.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            if let readiness = readinessService.todaysReadiness {
                ReadinessDetailView(readiness: readiness)
            } else {
                ReadinessCalculationSheet()
            }
        }
        .task {
            await readinessService.refreshIfNeeded()
        }
    }

    private var ringProgress: CGFloat {
        guard let score = readinessService.todaysReadiness?.score else { return 0 }
        return CGFloat(score) / 100.0
    }

    private var readinessColor: Color {
        guard let readiness = readinessService.todaysReadiness else { return .gray }
        switch readiness.level {
        case .optimal: return AppTheme.Colors.success
        case .good: return Color(red: 0.5, green: 0.8, blue: 0.1)
        case .moderate: return .yellow
        case .low: return .orange
        case .poor: return .red
        }
    }

    private var readinessLevelLabel: String {
        guard let readiness = readinessService.todaysReadiness else { return "UNKNOWN" }
        switch readiness.level {
        case .optimal: return "OPTIMAL"
        case .good: return "GOOD"
        case .moderate: return "MODERATE"
        case .low: return "LOW"
        case .poor: return "POOR"
        }
    }

    private var readinessHeadline: String {
        guard let readiness = readinessService.todaysReadiness else { return "Tap to calculate" }
        return TodayRecommendationPolicy.recommendation(readinessScore: readiness.score).title
    }

    private var readinessSubtext: String {
        guard let score = readinessService.todaysReadiness?.score else { return "Analyze your recovery" }
        return "Score \(score) · Tap for full breakdown"
    }
}

// MARK: - Readiness Calculation Sheet

struct ReadinessCalculationSheet: View {
    @StateObject private var readinessService = ReadinessService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 60))
                    .foregroundColor(AppTheme.Colors.accent)

                Text("Calculate Your Readiness")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("We'll analyze your sleep, HRV, resting heart rate, and training load to determine how ready you are to train today.")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }

                Button {
                    Task {
                        await calculateReadiness()
                    }
                } label: {
                    HStack {
                        if readinessService.isCalculating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "waveform.path.ecg")
                        }
                        Text(readinessService.isCalculating ? "Calculating..." : "Calculate Now")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(AppTheme.Colors.accent)
                    .cornerRadius(12)
                }
                .disabled(readinessService.isCalculating)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 40)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func calculateReadiness() async {
        errorMessage = nil
        do {
            _ = try await readinessService.calculateTodaysReadiness()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ReadinessGauge(score: 78, size: 120)

        ReadinessCard(readiness: DailyReadiness(
            athleteId: 1,
            date: Date(),
            score: 78,
            factors: [
                ReadinessFactor(id: "sleep", name: "Sleep", score: 85, weight: 0.30, value: "7h 32m", change: nil, trend: .stable),
                ReadinessFactor(id: "hrv", name: "HRV", score: 72, weight: 0.25, value: "45ms", change: "+5%", trend: .improving),
                ReadinessFactor(id: "resting_hr", name: "Resting HR", score: 80, weight: 0.20, value: "52 bpm", change: "-2 bpm", trend: .improving),
                ReadinessFactor(id: "training_load", name: "Training Load", score: 75, weight: 0.25, value: "Optimal", change: nil, trend: .stable)
            ]
        ))
        .padding(.horizontal)
    }
    .padding()
}
