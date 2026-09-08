import SwiftUI

struct TrainingActivityChart: View {
    let days: [TrainingProgressSnapshot.Day]
    let today: Date
    private var peak: Double { max(60, days.map(\.seconds).max() ?? 60) }
    private var kinds: [ProgressActivityKind] {
        ProgressActivityKind.allCases.filter { kind in days.contains { $0.segments.contains { $0.kind == kind } } }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(days) { day in
                    VStack(spacing: 8) {
                        VStack(spacing: 2) {
                            Spacer(minLength: 0)
                            ForEach(day.segments.reversed()) { segment in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(TrainingProgressStyle.color(segment.kind))
                                    .frame(height: max(3, segment.seconds / peak * 76))
                            }
                            if day.segments.isEmpty {
                                Capsule().fill(.white.opacity(0.10)).frame(height: 3)
                            }
                        }.frame(height: 90)
                        Text(day.date, format: .dateTime.weekday(.narrow))
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .foregroundStyle(Calendar.current.isDate(day.date, inSameDayAs: today) ? .white : TrainingProgressStyle.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide)))
                    .accessibilityValue(day.segments.isEmpty ? "No recorded training" : day.segments.map { "\($0.kind.title), \(TrainingProgressStyle.duration($0.seconds))" }.joined(separator: ", "))
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(kinds, id: \.self) { kind in
                    Label(kind.title, systemImage: kind.symbol)
                        .font(.caption2).foregroundStyle(TrainingProgressStyle.color(kind))
                }
            }
            Text("Training time across all activities")
                .font(.caption2).foregroundStyle(TrainingProgressStyle.secondary)
        }
    }
}
