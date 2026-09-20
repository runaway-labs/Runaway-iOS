import SwiftUI

struct CoachChangeBanner: View {
    let decision: CoachDecision
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: decision.state == .proposed ? "checklist" : "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(statusColor)
                    .frame(width: 42, height: 42).background(statusColor.opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(decision.state == .proposed ? "Your call" : "Week adjusted")
                        .font(AppTheme.Typography.headline).foregroundStyle(AppTheme.Colors.adaptiveTextPrimary)
                    Text(summary).font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.adaptiveTextSecondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.Colors.adaptiveTextSecondary)
            }
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.Colors.adaptiveCardBackground, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large))
            .overlay(alignment: .leading) { Capsule().fill(statusColor).frame(width: 3).padding(.vertical, AppTheme.Spacing.sm) }
        }.buttonStyle(.plain).accessibilityLabel(summary)
    }
    private var statusColor: Color { decision.state == .proposed ? AppTheme.Colors.warmAmber : AppTheme.Colors.success }
    private var summary: String {
        guard let first = decision.changes.first else { return "Review the latest coaching decision." }
        return first.after + (decision.changes.count > 1 ? " and \(decision.changes.count - 1) more. Tap to see why." : ". Tap to see why.")
    }
}
