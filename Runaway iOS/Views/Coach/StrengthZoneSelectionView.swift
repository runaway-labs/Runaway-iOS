import SwiftUI

struct StrengthZoneSelectionView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let recommendations: [StrengthZoneRecommendation]
    let selection: Set<StrengthZone>
    let errorMessage: String?
    let onToggle: (StrengthZone) -> Void
    let onBuild: (Int) -> Void
    @State private var duration = 45

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Choose your focus")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("Pick one or more zones. Runaway will build the movements, sets, and recovery around them.")
                    .font(.subheadline)
                    .foregroundStyle(TrainingProgressStyle.secondary)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(recommendations) { recommendation in
                    zoneTile(recommendation)
                }
            }

            Stepper("\(duration) min", value: $duration, in: 20...90, step: 5)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .padding(14)
                .background(TrainingProgressStyle.surface, in: RoundedRectangle(cornerRadius: 16))

            if selection.isEmpty {
                Text("Choose at least one focus zone.")
                    .font(.caption)
                    .foregroundStyle(TrainingProgressStyle.secondary)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(TrainingProgressStyle.amber)
            }

            Button { onBuild(duration) } label: {
                Text("Build my workout · \(selection.count) zones")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.black)
            .background(
                (selection.isEmpty ? TrainingProgressStyle.secondary : TrainingProgressStyle.amber),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .disabled(selection.isEmpty)
        }
    }

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }

    private func zoneTile(_ recommendation: StrengthZoneRecommendation) -> some View {
        let selected = selection.contains(recommendation.zone)
        return Button { onToggle(recommendation.zone) } label: {
            StrengthZoneTile(
                recommendation: recommendation,
                selected: selected,
                context: contextLabel(recommendation)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(recommendation.zone.rawValue.capitalized)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint("Double tap to \(selected ? "remove" : "add") this focus zone")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func contextLabel(_ value: StrengthZoneRecommendation) -> String? {
        if value.reasons.isEmpty { return nil }
        switch value.context {
        case .trainedYesterday: return "Worked yesterday"
        case .daysAgo(let days): return "\(days)d since focused"
        case .lowVolume: return "Light work recently"
        case .recovered: return "Ready for focus"
        case .noRecentData: return "Limited recent history"
        }
    }
}

private struct StrengthZoneTile: View {
    let recommendation: StrengthZoneRecommendation
    let selected: Bool
    let context: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                StrengthZoneIcon(zone: recommendation.zone, selected: selected)
                    .frame(width: 44, height: 44)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.black)
                    .opacity(selected ? 1 : 0)
            }
            Text(recommendation.zone.rawValue.capitalized).font(.headline)
            Text("COACH PICK")
                .font(.caption2.bold())
                .tracking(0.8)
                .opacity(recommendation.isCoachPick ? 1 : 0)
            Text(context ?? " ")
                .font(.caption)
                .foregroundStyle(selected ? Color.black.opacity(0.7) : TrainingProgressStyle.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .padding(14)
        .foregroundStyle(selected ? Color.black : Color.white)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(TrainingProgressStyle.amber)
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(TrainingProgressStyle.surface)
            }
        }
    }
}
