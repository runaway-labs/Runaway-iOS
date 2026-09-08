import SwiftUI

struct PersonalBestCollection: View {
    let records: [SupportedPersonalBest]
    let isLoading: Bool
    let hasError: Bool
    let onRetry: () -> Void
    let onOpen: (LocalActivity) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("EFFORTS TO REMEMBER").font(.system(.caption, design: .rounded, weight: .heavy)).tracking(1.2)
                    .foregroundStyle(TrainingProgressStyle.amber)
                Spacer()
                if isLoading { ProgressView().tint(TrainingProgressStyle.amber) }
            }
            if hasError {
                Button("Couldn't load your records. Retry", action: onRetry).frame(minHeight: 44)
            } else if records.isEmpty && !isLoading {
                Text("Your next benchmark is out there.")
                    .font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                Text("Saved bests appear here when a recorded run or exact-distance split supports the result. Estimated efforts stay out of your record collection.")
                    .font(.caption).foregroundStyle(TrainingProgressStyle.secondary)
            }
            ForEach(records) { supported in
                Button { onOpen(supported.activity) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "medal.fill").font(.title2).foregroundStyle(TrainingProgressStyle.amber)
                            .frame(width: 44, height: 48)
                            .background(TrainingProgressStyle.amber.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(PRDistance.allCases.first { $0.label == supported.record.distanceLabel }?.displayName ?? supported.record.distanceLabel)
                                .font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                            Text(supported.record.achievedAt, format: .dateTime.month(.abbreviated).day().year())
                                .font(.caption).foregroundStyle(TrainingProgressStyle.secondary)
                        }
                        Spacer(minLength: 4)
                        Text(supported.record.formattedTime).font(.system(.headline, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(TrainingProgressStyle.secondary)
                    }.frame(minHeight: 60).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if !records.isEmpty {
                Text("Verified saved bests. Tap an effort to open its source activity.")
                    .font(.caption2).foregroundStyle(TrainingProgressStyle.secondary)
            }
        }.padding(18).background(TrainingProgressStyle.surface, in: RoundedRectangle(cornerRadius: 22))
    }
}
