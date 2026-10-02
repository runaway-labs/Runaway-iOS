import SwiftUI

struct DigitalTwinMirrorCard: View {
    @State private var insight: TwinInsight?
    @State private var isLoading = true
    
    private var bg:   Color { AppTheme.Colors.DarkMode.cardBackground }
    private var accent: Color { AppTheme.Colors.DarkMode.accent }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label {
                    Text("DIGITAL TWIN MIRROR")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.5)
                } icon: {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(accent)
                }
                Spacer()
                if isLoading {
                    ProgressView().scaleEffect(0.7)
                }
            }
            
            if let insight = insight {
                VStack(alignment: .leading, spacing: 12) {
                    Text(insight.insight.message)
                        .font(AppTheme.Typography.headline)
                        .foregroundColor(.white)
                    
                    HStack(spacing: 20) {
                        statItem(label: "LOAD (ACWR)", value: String(format: "%.2f", insight.acwr), color: acwrColor(insight.acwr))
                        statItem(label: "HRV TREND", value: String(format: "%.0f%%", insight.hrvTrend * 100), color: hrvColor(insight.hrvTrend))
                        statItem(label: "READINESS", value: "\(insight.readiness)", color: readinessColor(insight.readiness))
                    }
                    
                    Divider().background(Color.white.opacity(0.1))
                    
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(accent)
                        Text(insight.insight.action)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                    }
                }
            } else if !isLoading {
                Text("Twin is calibrating. Sync your Health data to enable the mirror.")
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
            }
        }
        .padding()
        .background(bg)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .task {
            await load()
        }
    }
    
    private func load() async {
        do {
            insight = try await TwinEngineService.shared.fetchTwinInsights()
        } catch {
            #if DEBUG
            print("❌ TwinMirror: \(error)")
            #endif
        }
        isLoading = false
    }
    
    private func statItem(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .monospaced))
                .foregroundColor(color)
        }
    }
    
    private func acwrColor(_ val: Double) -> Color {
        if val > 1.5 { return .red }
        if val > 1.3 { return .orange }
        if val >= 0.8 { return .green }
        return .blue
    }
    
    private func hrvColor(_ val: Double) -> Color {
        if val >= 1.0 { return .green }
        if val >= 0.9 { return .orange }
        return .red
    }
    
    private func readinessColor(_ val: Int) -> Color {
        if val >= 80 { return .green }
        if val >= 60 { return .orange }
        return .red
    }
}
