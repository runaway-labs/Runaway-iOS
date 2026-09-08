import SwiftUI

struct TrainingGoalRing: View {
    let title: String
    let meters: Double
    let goalMeters: Double?
    let unit: String
    let color: Color
    private var goal: Double? {
        guard let goalMeters, goalMeters.isFinite, goalMeters > 0 else { return nil }
        return goalMeters
    }
    private var progress: Double { goal.map { min(1, TrainingProgressPolicy.clean(meters) / $0) } ?? 0 }
    private var distance: String {
        let divisor = unit == "km" ? 1000 : TrainingProgressSnapshot.metersPerMile
        guard let goal else { return "Set a goal" }
        return String(format: "%.1f / %.0f %@", meters / divisor, goal / divisor, unit)
    }
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(.white.opacity(0.10), lineWidth: 4)
                Circle().trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                if progress >= 1 { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(color) }
                else { Text(goal == nil ? "--" : "\(Int(progress * 100))%").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.white) }
            }.frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(.caption2, design: .rounded, weight: .heavy)).tracking(1).foregroundStyle(color)
                Text(distance).font(.caption).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title.lowercased()) running goal")
        .accessibilityValue(goal == nil ? "No goal set" : "\(distance), \(Int(progress * 100)) percent complete")
    }
}
