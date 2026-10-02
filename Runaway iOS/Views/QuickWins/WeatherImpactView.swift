//
//  WeatherImpactView.swift
//  Runaway iOS
//
//  Weather impact analysis detail view
//

import SwiftUI

struct WeatherImpactView: View {
    let weather: WeatherAnalysis
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Hero Card
                    WeatherHeroCard(weather: weather)

                    // Pace Impact Callout
                    PaceImpactCallout(weather: weather)

                    // Heat Acclimation Indicator
                    HeatAcclimationIndicator(weather: weather)

                    // Optimal Training Times
                    OptimalTrainingTimes(times: weather.optimalTrainingTimes)

                    // Recommendations
                    RecommendationsList(
                        recommendations: weather.recommendations,
                        icon: "lightbulb.fill",
                        iconColor: .yellow
                    )
                }
                .padding()
            }
            .adaptiveSurfaceTint()
            .navigationTitle("Weather Impact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(AppTheme.Colors.DarkMode.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.Colors.DarkMode.accent)
                    .darkSurfaceTint()
                }
            }
        }
        .darkSurfaceTint()
    }
}

// MARK: - Weather Hero Card

struct WeatherHeroCard: View {
    let weather: WeatherAnalysis

    var body: some View {
        VStack(spacing: 16) {
            // Impact Badge
            HStack {
                Image(systemName: "cloud.sun.fill")
                    .foregroundColor(impactColor)
                Text(weather.weatherImpactScore.capitalized + " Impact")
                    .font(.headline)
                    .foregroundColor(impactColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(impactColor.opacity(0.2))
            .cornerRadius(20)

            // 2x2 Metrics Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                WeatherMetricBox(
                    title: "Avg Temperature",
                    value: String(format: "%.1f°C", weather.averageTemperatureCelsius),
                    subtitle: "\(Int(weather.temperatureFahrenheit))°F",
                    icon: "thermometer",
                    color: .orange
                )

                WeatherMetricBox(
                    title: "Avg Humidity",
                    value: String(format: "%.1f%%", weather.averageHumidityPercent),
                    subtitle: "",
                    icon: "drop.fill",
                    color: .blue
                )

                WeatherMetricBox(
                    title: "Heat Stress Runs",
                    value: "\(weather.heatStressRuns)",
                    subtitle: "challenging",
                    icon: "flame.fill",
                    color: .red
                )

                WeatherMetricBox(
                    title: "Ideal Conditions",
                    value: "\(weather.idealConditionRuns)",
                    subtitle: "perfect",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var impactColor: Color {
        switch weather.weatherImpactScore {
        case "minimal": return .green
        case "moderate": return .orange
        case "significant": return .red
        case "severe": return .purple
        default: return .gray
        }
    }
}

struct WeatherMetricBox: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(value)
                .font(.title3)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

// MARK: - Pace Impact Callout

struct PaceImpactCallout: View {
    let weather: WeatherAnalysis

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speedometer")
                .font(.title2)
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("Pace Impact")
                    .font(.headline)

                Text("~\(Int(weather.paceDegradationSecondsPerMile))s/mile slower in heat")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }

            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Heat Acclimation Indicator

struct HeatAcclimationIndicator: View {
    let weather: WeatherAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Heat Acclimation")
                .font(.headline)

            HStack(spacing: 8) {
                // 3 dots for acclimation level
                ForEach(1...3, id: \.self) { index in
                    Circle()
                        .fill(index <= weather.acclimationDots ? Color.orange : Color.gray.opacity(0.3))
                        .frame(width: 12, height: 12)
                }

                Text(weather.heatAcclimationLevel.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.subheadline)
                    .foregroundColor(AppTheme.Colors.textSecondary)

                Spacer()
            }

            Text(acclimationDescription)
                .font(.caption)
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var acclimationDescription: String {
        switch weather.heatAcclimationLevel {
        case "none":
            return "Your body hasn't adapted to heat stress yet. Build heat tolerance gradually."
        case "developing":
            return "You're building heat tolerance. Continue consistent training in warm conditions."
        case "well-acclimated":
            return "Well adapted to heat stress. Performance degradation is minimal."
        default:
            return ""
        }
    }
}

// MARK: - Optimal Training Times

struct OptimalTrainingTimes: View {
    let times: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.blue)
                Text("Optimal Training Times")
                    .font(.headline)
            }

            ForEach(times, id: \.self) { timeRange in
                HStack {
                    Image(systemName: timeRange.contains("AM") || timeRange.contains("5:") || timeRange.contains("6:") || timeRange.contains("7:") ? "sunrise.fill" : "sunset.fill")
                        .foregroundColor(.orange)

                    Text(timeRange)
                        .font(.subheadline)

                    Spacer()
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Recommendations List

struct RecommendationsList: View {
    let recommendations: [String]
    let icon: String
    let iconColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                Text("Recommendations")
                    .font(.headline)
            }

            ForEach(Array(recommendations.enumerated()), id: \.offset) { index, recommendation in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "\(index + 1).circle.fill")
                        .foregroundColor(.blue)

                    Text(recommendation)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Preview

struct WeatherImpactView_Previews: PreviewProvider {
    static var previews: some View {
        WeatherImpactView(weather: QuickWinsResponse.mock.analyses.weatherContext!)
    }
}
