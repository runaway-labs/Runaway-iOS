import SwiftUI

struct StrengthZoneIcon: View {
    let zone: StrengthZone
    let selected: Bool

    var body: some View {
        Image(assetName)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundStyle(selected ? AppTheme.Colors.pine : TrainingProgressStyle.amber)
            .accessibilityHidden(true)
    }

    private var assetName: String {
        zone.rawValue.capitalized
    }
}
