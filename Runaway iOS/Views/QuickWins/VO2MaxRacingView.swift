//
//  VO2MaxRacingView.swift
//  Runaway iOS
//
//  VO2 Max estimation and race predictions view
//

import SwiftUI

struct VO2MaxRacingView: View {
    let vo2max: VO2MaxEstimate
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // VO2 Max Hero Card
                    VO2MaxHeroCard(vo2max: vo2max)

                    // Fitness Level Progress Bar
                    FitnessLevelProgressBar(vo2max: vo2max)

                    // vVO2 Max Training Card (if available)
                    if let vvo2MaxPace = vo2max.vvo2MaxPace {
                        VVO2MaxTrainingCard(pace: vvo2MaxPace)
                    }

                    // Race Predictions List
                    RacePredictionsList(predictions: vo2max.racePredictions)

                    // Recommendations
                    RecommendationsList(
                        recommendations: vo2max.recommendations,
                        icon: "chart.line.uptrend.xyaxis",
                        iconColor: .blue
                    )
                }
                .padding()
            }
            .tint(AppTheme.Colors.accent)
            .navigationTitle("VO2 Max & Racing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.Colors.LightMode.accent)
                }
            }
        }
        .tint(AppTheme.Colors.LightMode.accent)
    }
}

// MARK: - VO2 Max Hero Card

struct VO2MaxHeroCard: View {
    let vo2max: VO2MaxEstimate

    var body: some View {
        VStack(spacing: 16) {
            // Large VO2 Max Number
            Text(String(format: "%.1f", vo2max.vo2Max))
                .font(.system(size: 60, weight: .bold))
                .foregroundColor(fitnessColor)

            Text("ml/kg/min")
                .font(.subheadline)
                .foregroundColor(AppTheme.Colors.textSecondary)

            // Fitness Level Badge
            Text(vo2max.fitnessLevelDisplay)
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(fitnessColor)
                .cornerRadius(20)

            // Data Quality
            HStack(spacing: 4) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(.green)
                Text("Data Quality: \(Int(vo2max.dataQualityScore * 100))%")
                    .font(.caption)
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [fitnessColor.opacity(0.3), fitnessColor.opacity(0.1)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
    }

    private var fitnessColor: Color {
        switch vo2max.fitnessLevel {
        case "elite": return .purple
        case "excellent": return .blue
        case "good": return .green
        case "average": return .orange
        default: return .gray
        }
    }
}

// MARK: - Fitness Level Progress Bar

struct FitnessLevelProgressBar: View {
    let vo2max: VO2MaxEstimate

    // VO2 Max ranges (example values, adjust based on age/gender)
    let ranges: [(String, Double, Color)] = [
        ("Below Avg", 35, .gray),
        ("Average", 42, .orange),
        ("Good", 52, .green),
        ("Excellent", 58, .blue),
        ("Elite", 70, .purple)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fitness Level")
                .font(.headline)

            // Rainbow gradient bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background gradient
                    LinearGradient(
                        gradient: Gradient(colors: ranges.map { $0.2 }),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 8)
                    .cornerRadius(4)

                    // Current position marker
                    Circle()
                        .fill(currentColor)
                        .frame(width: 16, height: 16)
                        .offset(x: calculatePosition(width: geometry.size.width) - 8)
                }
            }
            .frame(height: 16)

            // Labels
            HStack {
                ForEach(ranges, id: \.0) { range in
                    Text(range.0)
                        .font(.caption2)
                        .foregroundColor(range.0 == vo2max.fitnessLevelDisplay ? currentColor : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func calculatePosition(width: Double) -> Double {
        let minVO2 = 30.0
        let maxVO2 = 70.0
        let normalizedValue = min(max(vo2max.vo2Max, minVO2), maxVO2)
        return ((normalizedValue - minVO2) / (maxVO2 - minVO2)) * width
    }

    private var currentColor: Color {
        switch vo2max.fitnessLevel {
        case "elite": return .purple
        case "excellent": return .blue
        case "good": return .green
        case "average": return .orange
        default: return .gray
        }
    }
}

// MARK: - vVO2 Max Training Card

struct VVO2MaxTrainingCard: View {
    let pace: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "bolt.fill")
                .font(.title)
                .foregroundColor(.red)

            VStack(alignment: .leading, spacing: 4) {
                Text("Interval Training Target")
                    .font(.headline)
                    .foregroundColor(.white)

                Text(pace + " /km pace")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }

            Spacer()
        }
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [.red, .orange]),
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(12)
    }
}

// MARK: - Race Predictions List

struct RacePredictionsList: View {
    let predictions: [RacePrediction]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Race Predictions")
                .font(.headline)

            if predictions.isEmpty {
                Text("Complete more runs to get race predictions")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(predictions) { prediction in
                    RacePredictionCard(prediction: prediction)
                }
            }
        }
    }
}

struct RacePredictionCard: View {
    let prediction: RacePrediction

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(prediction.distance)
                        .font(.headline)
                    Text(String(format: "%.2f km", prediction.distanceKm))
                        .font(.caption)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(prediction.predictedTime)
                        .font(.title3)
                        .fontWeight(.bold)
                    Text(prediction.pacePerMile + " /mi")
                        .font(.caption)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }

            // Confidence Bar
            HStack(spacing: 8) {
                Text("Confidence:")
                    .font(.caption)
                    .foregroundColor(AppTheme.Colors.textSecondary)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(confidenceColor)
                            .frame(width: geometry.size.width * CGFloat(prediction.confidenceValue), height: 4)
                    }
                }
                .frame(height: 4)

                Text(prediction.confidence.capitalized)
                    .font(.caption)
                    .foregroundColor(confidenceColor)
                    .frame(width: 60, alignment: .trailing)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var confidenceColor: Color {
        switch prediction.confidence {
        case "high": return .green
        case "medium": return .orange
        case "low": return .red
        default: return .gray
        }
    }
}

// MARK: - Preview

struct VO2MaxRacingView_Previews: PreviewProvider {
    static var previews: some View {
        VO2MaxRacingView(vo2max: QuickWinsResponse.mock.analyses.vo2maxEstimate!)
    }
}
