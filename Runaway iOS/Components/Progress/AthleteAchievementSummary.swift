import SwiftUI

struct AthleteAchievementSummary: View {
    let athleteID: Int?
    @ObservedObject private var progress = TrainingProgressStore.shared
    @ObservedObject private var units = UnitPreferences.shared
    var body: some View {
        if let snapshot = progress.snapshot, snapshot.athleteID == athleteID, snapshot.isCurrent() {
            let divisor = units.distanceUnit == .kilometers ? 1000 : TrainingProgressSnapshot.metersPerMile
            let distance = snapshot.year.runningMeters / divisor
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("YOUR \(Calendar.current.component(.year, from: snapshot.yearStart).formatted(.number.grouping(.never)))")
                        .font(.system(.caption, design: .rounded, weight: .heavy)).tracking(2).foregroundStyle(TrainingProgressStyle.amber)
                    Spacer()
                    Image(systemName: "figure.run").font(.title2).foregroundStyle(TrainingProgressStyle.blue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(distance.formatted(.number.precision(.fractionLength(1))))
                        .font(.system(size: 56, weight: .bold, design: .rounded)).tracking(-2).foregroundStyle(.white)
                        .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                    Text("\(units.distanceUnit.abbreviation) run this year")
                        .font(.subheadline).foregroundStyle(TrainingProgressStyle.secondary)
                }
                HStack(alignment: .top, spacing: 20) {
                    stat("\(snapshot.year.runs)", "runs")
                    stat("\(snapshot.year.activeDays)", "active days")
                    stat(TrainingProgressStyle.duration(snapshot.year.seconds), "all training")
                }
                if snapshot.year.sessions > 0 {
                    Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
                    Label("\(snapshot.year.sessions) sessions in your story", systemImage: "checkmark.seal.fill")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(TrainingProgressStyle.mint)
                    if let next = [10.0, 25, 50, 100, 250, 500, 1000, 2000, 5000, 10000].first(where: { $0 > distance }) {
                        Text("\((next - distance).formatted(.number.precision(.fractionLength(1)))) \(units.distanceUnit.abbreviation) to \(Int(next)) this year")
                            .font(.caption).foregroundStyle(TrainingProgressStyle.secondary)
                    }
                }
            }
            .padding(22).background(TrainingProgressStyle.surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.10), lineWidth: 1))
        } else {
            Text(progress.isRefreshing ? "Gathering your year of training..." : "Sync your activities to see this year's progress.")
                .font(.subheadline).foregroundStyle(TrainingProgressStyle.secondary)
        }
    }
    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(.headline, design: .rounded, weight: .bold)).foregroundStyle(.white)
            Text(label).font(.caption).foregroundStyle(TrainingProgressStyle.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
