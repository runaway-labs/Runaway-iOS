import SwiftUI

struct BecomingLine: View {
    let snapshot: BecomingSnapshot
    let onExplore: (BecomingChoice) -> Void

    @State private var selectedChoice: BecomingChoice

    init(snapshot: BecomingSnapshot, onExplore: @escaping (BecomingChoice) -> Void) {
        self.snapshot = snapshot
        self.onExplore = onExplore
        _selectedChoice = State(initialValue: snapshot.recommendedChoice)
    }

    private var selectedPath: BecomingPath {
        snapshot.paths.first(where: { $0.choice == selectedChoice }) ?? snapshot.paths[0]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("THE BECOMING LINE")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(AppTheme.Colors.strideBlue)
                    Text(snapshot.headline)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(snapshot.detail)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.DarkMode.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "point.forward.to.point.capsulepath")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.strideBlue)
                    .padding(9)
                    .background(AppTheme.Colors.strideBlue.opacity(0.12), in: Circle())
            }

            HStack(spacing: 0) {
                ForEach(Array(snapshot.paths.enumerated()), id: \.element.id) { index, path in
                    Button {
                        withAnimation(.snappy(duration: 0.28)) {
                            selectedChoice = path.choice
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(nodeColor(for: path))
                                .frame(
                                    width: selectedChoice == path.choice ? 13 : 9,
                                    height: selectedChoice == path.choice ? 13 : 9
                                )
                                .overlay {
                                    if path.isRecommended {
                                        Circle().stroke(nodeColor(for: path).opacity(0.34), lineWidth: 5)
                                    }
                                }
                            Text(shortLabel(for: path.choice))
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(
                                    selectedChoice == path.choice
                                        ? Color.white
                                        : AppTheme.Colors.DarkMode.textTertiary
                                )
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)

                    if index < snapshot.paths.count - 1 {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        AppTheme.Colors.strideBlue.opacity(0.8),
                                        AppTheme.Colors.recoveryMint.opacity(0.5)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 2)
                            .offset(y: -8)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(selectedPath.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    if selectedPath.isRecommended {
                        Text("BEST PATH")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(AppTheme.Colors.recoveryMint)
                    }
                }
                Text(selectedPath.effect)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.DarkMode.textSecondary)
                Text(selectedPath.weekEffect)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.strideBlue)
            }
            .id(selectedPath.id)
            .transition(.opacity.combined(with: .move(edge: .bottom)))

            Button {
                onExplore(selectedPath.choice)
            } label: {
                HStack {
                    Text("Choose this path")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("Week adapts")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.DarkMode.textTertiary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(AppTheme.Colors.recoveryMint)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    AppTheme.Colors.recoveryMint.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Explore today's training paths")
            .accessibilityHint("Opens training choices that rebalance the remaining week.")
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.Colors.strideBlue.opacity(0.09),
                            AppTheme.Colors.recoveryMint.opacity(0.045),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTheme.Colors.strideBlue.opacity(0.18), lineWidth: 1)
        }
        .onChange(of: snapshot.recommendedChoice) { _, newValue in
            selectedChoice = newValue
        }
    }

    private func nodeColor(for path: BecomingPath) -> Color {
        if path.isRecommended { return AppTheme.Colors.recoveryMint }
        if path.choice == .recover { return AppTheme.Colors.strideBlue }
        return AppTheme.Colors.DarkMode.textTertiary
    }

    private func shortLabel(for choice: BecomingChoice) -> String {
        switch choice {
        case .planned: return "PLAN"
        case .easier: return "EASIER"
        case .alternate: return "SWAP"
        case .recover: return "RECOVER"
        }
    }
}
