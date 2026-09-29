import SwiftUI

@MainActor
struct WorkoutReflectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: WorkoutReflectionViewModel

    let activityTitle: String
    let onSave: (WorkoutReflectionFormSnapshot) -> Void

    init(
        activityTitle: String,
        onSave: @escaping (WorkoutReflectionFormSnapshot) -> Void
    ) {
        self.activityTitle = activityTitle
        _viewModel = StateObject(wrappedValue: WorkoutReflectionViewModel())
        self.onSave = onSave
    }

    init(
        activityTitle: String,
        viewModel: WorkoutReflectionViewModel,
        onSave: @escaping (WorkoutReflectionFormSnapshot) -> Void
    ) {
        self.activityTitle = activityTitle
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxxl) {
                    header
                    effortSection
                    choiceSection(
                        title: "How does your body feel?",
                        choices: ReflectionBodyChoice.allCases,
                        selection: $viewModel.bodyStatus
                    )
                    choiceSection(
                        title: "How are you leaving the run?",
                        choices: ReflectionMoodChoice.allCases,
                        selection: $viewModel.mood
                    )
                    conditionsSection
                    noteSection
                }
                .padding(.horizontal, AppTheme.Spacing.xl)
                .padding(.vertical, AppTheme.Spacing.xxl)
            }
            .background(AppTheme.Colors.DarkMode.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                saveButton
                    .padding(.horizontal, AppTheme.Spacing.xl)
                    .padding(.vertical, AppTheme.Spacing.md)
                    .background(AppTheme.Colors.DarkMode.background)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Later") { dismiss() }
                        .foregroundStyle(AppTheme.Colors.DarkMode.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            EyebrowLabel(text: "POST-RUN CHECK-IN", color: AppTheme.Colors.warmAmber)
            Text("How did that feel?")
                .font(AppTheme.Typography.largeTitle)
                .foregroundStyle(AppTheme.Colors.DarkMode.textPrimary)
            Text(activityTitle)
                .font(AppTheme.Typography.subheadline)
                .foregroundStyle(AppTheme.Colors.DarkMode.textTertiary)
                .lineLimit(1)
        }
    }

    private var effortSection: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            VStack(spacing: 0) {
                Text("\(Int(viewModel.effort.rounded()))")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.Colors.warmAmber)
                    .contentTransition(.numericText())
                Text("EFFORT / 10")
                    .font(AppTheme.Typography.caption)
                    .tracking(1.6)
                    .foregroundStyle(AppTheme.Colors.DarkMode.textSecondary)
            }

            Slider(value: $viewModel.effort, in: 1...10, step: 1)
                .tint(AppTheme.Colors.strideLime)
                .accessibilityLabel("Effort")
                .accessibilityValue("\(Int(viewModel.effort.rounded())) out of 10")

            HStack {
                Text("Easy")
                Spacer()
                Text("All out")
            }
            .font(AppTheme.Typography.caption2)
            .foregroundStyle(AppTheme.Colors.DarkMode.textTertiary)
        }
        .padding(AppTheme.Spacing.xl)
        .background(AppTheme.Colors.DarkMode.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.extraLarge))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.extraLarge)
                .stroke(AppTheme.Colors.warmAmber.opacity(0.16), lineWidth: 1)
        }
    }

    private func choiceSection<Choice: Identifiable & Equatable & CaseIterable>(
        title: String,
        choices: Choice.AllCases,
        selection: Binding<Choice?>
    ) -> some View where Choice.AllCases: RandomAccessCollection, Choice: ReflectionChoicePresenting {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            sectionTitle(title)
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(choices) { choice in
                    ReflectionChoiceButton(
                        label: choice.label,
                        symbol: choice.symbol,
                        isSelected: selection.wrappedValue == choice
                    ) {
                        selection.wrappedValue = choice
                    }
                }
            }
        }
    }

    private var conditionsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            sectionTitle("Anything shape the run?")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: AppTheme.Spacing.sm)], spacing: AppTheme.Spacing.sm) {
                ForEach(ReflectionConditionChoice.allCases) { condition in
                    Button {
                        viewModel.toggleCondition(condition)
                    } label: {
                        Text(condition.label)
                            .font(AppTheme.Typography.subheadlineBold)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(viewModel.selectedConditions.contains(condition)
                                ? AppTheme.Colors.amberLight
                                : AppTheme.Colors.DarkMode.textSecondary)
                            .background(viewModel.selectedConditions.contains(condition)
                                ? AppTheme.Colors.warmAmber.opacity(0.14)
                                : AppTheme.Colors.DarkMode.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
                            .overlay {
                                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                                    .stroke(viewModel.selectedConditions.contains(condition)
                                        ? AppTheme.Colors.warmAmber.opacity(0.32)
                                        : AppTheme.Colors.Semantic.border, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                sectionTitle("One thing to remember")
                Spacer()
                Text("\(viewModel.noteCharactersRemaining)")
                    .font(AppTheme.Typography.caption2)
                    .foregroundStyle(AppTheme.Colors.DarkMode.textTertiary)
                    .monospacedDigit()
            }

            TextEditor(text: $viewModel.note)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.DarkMode.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(AppTheme.Spacing.md)
                .frame(minHeight: 112)
                .background(AppTheme.Colors.DarkMode.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                        .stroke(AppTheme.Colors.Semantic.border, lineWidth: 1)
                }
                .accessibilityLabel("Optional reflection note")
        }
    }

    private var saveButton: some View {
        Button {
            guard let snapshot = viewModel.snapshot() else { return }
            onSave(snapshot)
            dismiss()
        } label: {
            Text("Save reflection")
                .font(AppTheme.Typography.headline)
                .foregroundStyle(Color(red: 0.10, green: 0.05, blue: 0))
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(viewModel.canSubmit
                    ? AppTheme.Colors.warmAmber
                    : AppTheme.Colors.DarkMode.surfaceBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large))
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSubmit)
        .accessibilityHint(viewModel.canSubmit ? "Saves this post-run reflection" : "Choose body and mood first")
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(AppTheme.Typography.title3)
            .foregroundStyle(AppTheme.Colors.DarkMode.textPrimary)
    }
}

private protocol ReflectionChoicePresenting {
    var label: String { get }
    var symbol: String { get }
}

extension ReflectionBodyChoice: ReflectionChoicePresenting {}
extension ReflectionMoodChoice: ReflectionChoicePresenting {}

private struct ReflectionChoiceButton: View {
    let label: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                Text(label)
                    .font(AppTheme.Typography.subheadlineBold)
            }
            .foregroundStyle(isSelected ? AppTheme.Colors.amberLight : AppTheme.Colors.DarkMode.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(isSelected ? AppTheme.Colors.warmAmber.opacity(0.14) : AppTheme.Colors.DarkMode.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                    .stroke(isSelected ? AppTheme.Colors.warmAmber.opacity(0.32) : AppTheme.Colors.Semantic.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
