import SwiftUI

struct TrainingProfileControlPresentation: Equatable {
    let showsStrengthControls: Bool
    let minimumTargetSize: CGFloat

    func activitySelectionLabel(for activity: TrainingActivity) -> String {
        "Select \(activity.displayName)"
    }
}

@MainActor
final class TrainingProfileEditorViewModel: ObservableObject {
    typealias PlanGenerator = @MainActor (
        TrainingProfile,
        PlanRegenerationScope,
        WeeklyTrainingPlan?
    ) async throws -> WeeklyTrainingPlan
    typealias CurrentPlanProvider = @MainActor () -> WeeklyTrainingPlan?

    let trainingProfileStore: TrainingProfileStore

    @Published var draft: TrainingProfile
    @Published private(set) var isSaving = false
    @Published private(set) var isRegenerating = false
    @Published var isPresentingRegenerationChoices = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var shouldDismiss = false

    var onDraftChangeAcknowledged: (@MainActor (TrainingProfile) -> Void)?

    private var originalProfile: TrainingProfile
    private var retryScope: PlanRegenerationScope?
    private var preservedRegenerationInput: WeeklyTrainingPlan?
    private let currentPlan: CurrentPlanProvider
    private let generatePlan: PlanGenerator

    init(
        store: TrainingProfileStore,
        currentPlan: @escaping CurrentPlanProvider = { DataManager.shared.currentWeeklyPlan },
        generatePlan: @escaping PlanGenerator = { profile, scope, regenerationInput in
            try await DataManager.shared.generateTrainingPlan(
                profile: profile,
                scope: scope,
                regenerationInput: regenerationInput
            )
        }
    ) {
        trainingProfileStore = store
        originalProfile = store.profile
        draft = store.profile
        self.currentPlan = currentPlan
        self.generatePlan = generatePlan
    }

    convenience init(
        store: TrainingProfileStore,
        generatePlan: @escaping @MainActor (
            TrainingProfile,
            PlanRegenerationScope
        ) async throws -> WeeklyTrainingPlan
    ) {
        self.init(store: store, generatePlan: { profile, scope, _ in
            try await generatePlan(profile, scope)
        })
    }

    var summary: String {
        let mix = TrainingActivity.allCases.compactMap { activity -> String? in
            guard let preference = draft.preference(for: activity),
                  preference.sessionsPerWeek > 0 else { return nil }
            return activity.sessionSummary(count: preference.sessionsPerWeek)
        }.joined(separator: " + ")
        let week = mix.isEmpty ? "No weekly sessions" : mix
        return "\(week), long run \(TrainingProfileWeekday.name(for: draft.preferredLongRunWeekday))"
    }

    var showsStrengthDetails: Bool {
        controlPresentation.showsStrengthControls
    }

    var controlPresentation: TrainingProfileControlPresentation {
        TrainingProfileControlPresentation(
            showsStrengthControls: isSelected(.strength),
            minimumTargetSize: AppTheme.Layout.touchTargetMinimum
        )
    }

    var validationCopy: String {
        draft.validated().repairReasons.joined(separator: " ")
    }

    var canRetry: Bool {
        retryScope != nil
    }

    var currentWeekActionTitle: String {
        (preservedRegenerationInput ?? currentPlan()) == nil
            ? "Create This Week"
            : "Rebalance This Week"
    }

    var isEditorInteractionDisabled: Bool {
        isRegenerating
    }

    var isSavingDisabled: Bool {
        isSaving || isRegenerating
    }

    func isSelected(_ activity: TrainingActivity) -> Bool {
        draft.preference(for: activity) != nil
    }

    func canRemove(_ activity: TrainingActivity) -> Bool {
        guard let preference = draft.preference(for: activity) else { return false }
        return preference.role != .primary
            || draft.activities.filter { $0.role == .primary }.count > 1
    }

    func role(for activity: TrainingActivity) -> TrainingActivityRole? {
        draft.preference(for: activity)?.role
    }

    func sessions(for activity: TrainingActivity) -> Int {
        draft.preference(for: activity)?.sessionsPerWeek ?? 0
    }

    func setActivity(_ activity: TrainingActivity, selected: Bool) {
        var updated = draft
        if selected {
            guard updated.preference(for: activity) == nil else { return }
            let role: TrainingActivityRole = updated.primaryActivity == nil ? .primary : .supporting
            updated.activities.append(
                TrainingActivityPreference(activity: activity, role: role, sessionsPerWeek: 1)
            )
            let requestedSessions = updated.activities.reduce(0) { $0 + $1.sessionsPerWeek }
            updated.trainingDaysPerWeek = min(7, max(updated.trainingDaysPerWeek, requestedSessions))
        } else {
            guard canRemove(activity) else { return }
            updated.activities.removeAll { $0.activity == activity }
        }
        acknowledge(updated)
    }

    func setRole(_ role: TrainingActivityRole, for activity: TrainingActivity) {
        var updated = draft
        guard let index = updated.activities.firstIndex(where: { $0.activity == activity }) else { return }
        if updated.activities[index].role == .primary,
           role != .primary,
           updated.activities.filter({ $0.role == .primary }).count == 1 {
            return
        }
        if role == .primary {
            for candidate in updated.activities.indices where updated.activities[candidate].role == .primary {
                updated.activities[candidate].role = .supporting
            }
        }
        updated.activities[index].role = role
        acknowledge(updated)
    }

    func setSessions(_ sessions: Int, for activity: TrainingActivity) {
        var updated = draft
        guard let index = updated.activities.firstIndex(where: { $0.activity == activity }) else { return }
        updated.activities[index].sessionsPerWeek = min(7, max(0, sessions))
        acknowledge(updated)
    }

    func setTrainingDays(_ days: Int) {
        var updated = draft
        updated.trainingDaysPerWeek = min(7, max(1, days))
        acknowledge(updated)
    }

    func setLongRunWeekday(_ weekday: Int) {
        var updated = draft
        updated.preferredLongRunWeekday = min(7, max(1, weekday))
        acknowledge(updated)
    }

    func setUnavailable(_ unavailable: Bool, weekday: Int) {
        var updated = draft
        if unavailable {
            updated.unavailableWeekdays.insert(weekday)
        } else {
            updated.unavailableWeekdays.remove(weekday)
        }
        acknowledge(updated)
    }

    func setStrengthEquipment(_ equipment: StrengthEquipment) {
        var updated = draft
        updated.strengthEquipment = equipment
        acknowledge(updated)
    }

    func setStrengthExperience(_ experience: TrainingExperience) {
        var updated = draft
        updated.strengthExperience = experience
        acknowledge(updated)
    }

    private func acknowledge(_ updated: TrainingProfile) {
        draft = updated
        onDraftChangeAcknowledged?(updated)
    }

    func save() {
        isSaving = true
        defer { isSaving = false }

        let validation = draft.validated()
        guard validation.profile.fingerprint != originalProfile.fingerprint else {
            do {
                try trainingProfileStore.save(validation.profile)
                draft = validation.profile
                originalProfile = validation.profile
                shouldDismiss = true
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        do {
            preservedRegenerationInput = currentPlan()
            try trainingProfileStore.save(validation.profile)
            draft = validation.profile
            originalProfile = validation.profile
            isPresentingRegenerationChoices = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func regenerate(scope: PlanRegenerationScope) async {
        await Task.yield()
        isPresentingRegenerationChoices = false
        isRegenerating = true
        errorMessage = nil
        let regenerationInput = preservedRegenerationInput ?? currentPlan()
        preservedRegenerationInput = regenerationInput
        let generationScope: PlanRegenerationScope
        if case .remainingCurrentWeek = scope, regenerationInput == nil {
            generationScope = .initialCurrentWeek
        } else {
            generationScope = scope
        }
        retryScope = generationScope
        defer { isRegenerating = false }

        do {
            _ = try await generatePlan(
                trainingProfileStore.profile,
                generationScope,
                regenerationInput
            )
            retryScope = nil
            preservedRegenerationInput = nil
            shouldDismiss = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func retry() async {
        guard let retryScope else { return }
        await regenerate(scope: retryScope)
    }

    func cancelRegeneration() {
        isPresentingRegenerationChoices = false
        shouldDismiss = true
    }

    func dismissError() {
        errorMessage = nil
    }
}

@MainActor
struct TrainingProfileRoute {
    let store: TrainingProfileStore

    func makeEditorModel(
        currentPlan: @escaping TrainingProfileEditorViewModel.CurrentPlanProvider = {
            DataManager.shared.currentWeeklyPlan
        },
        generatePlan: @escaping TrainingProfileEditorViewModel.PlanGenerator = {
            profile,
            scope,
            regenerationInput in
            try await DataManager.shared.generateTrainingPlan(
                profile: profile,
                scope: scope,
                regenerationInput: regenerationInput
            )
        }
    ) -> TrainingProfileEditorViewModel {
        TrainingProfileEditorViewModel(
            store: store,
            currentPlan: currentPlan,
            generatePlan: generatePlan
        )
    }
}

struct ActivityMixEditor: View {
    @ObservedObject var model: TrainingProfileEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            EyebrowLabel(text: "ACTIVITY MIX")

            VStack(spacing: 0) {
                ForEach(Array(TrainingActivity.allCases.enumerated()), id: \.element.id) { index, activity in
                    if index > 0 {
                        Divider()
                            .background(Color.white.opacity(0.06))
                            .padding(.leading, 60)
                    }
                    TrainingActivityRow(model: model, activity: activity)
                }
            }
            .background(AppTheme.Colors.DarkMode.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                    .stroke(Color.white.opacity(0.07), lineWidth: AppTheme.BorderWidth.regular)
            )

            if model.controlPresentation.showsStrengthControls {
                StrengthTrainingDetailsEditor(model: model)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.showsStrengthDetails)
    }
}

struct TrainingScheduleEditor: View {
    @ObservedObject var model: TrainingProfileEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            EyebrowLabel(text: "SCHEDULE")

            VStack(spacing: AppTheme.Spacing.md) {
                Stepper(
                    value: Binding(
                        get: { model.draft.trainingDaysPerWeek },
                        set: model.setTrainingDays
                    ),
                    in: 1...7
                ) {
                    TrainingProfileValueRow(
                        title: "Training days",
                        value: "\(model.draft.trainingDaysPerWeek) per week"
                    )
                }

                Divider().background(Color.white.opacity(0.06))

                HStack {
                    Text("Long-run day")
                        .font(AppTheme.Typography.bodyMedium)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                    Spacer()
                    Picker(
                        "Long-run day",
                        selection: Binding(
                            get: { model.draft.preferredLongRunWeekday },
                            set: model.setLongRunWeekday
                        )
                    ) {
                        ForEach(TrainingProfileWeekday.all) { weekday in
                            Text(weekday.name).tag(weekday.id)
                        }
                    }
                    .labelsHidden()
                    .tint(AppTheme.Colors.warmAmber)
                }
                .frame(minHeight: AppTheme.Layout.touchTargetMinimum)

                Divider().background(Color.white.opacity(0.06))

                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text("Unavailable days")
                        .font(AppTheme.Typography.bodyMedium)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            ForEach(TrainingProfileWeekday.all) { weekday in
                                let unavailable = model.draft.unavailableWeekdays.contains(weekday.id)
                                Button {
                                    model.setUnavailable(!unavailable, weekday: weekday.id)
                                } label: {
                                    Text(weekday.shortName)
                                        .font(AppTheme.Typography.caption)
                                        .foregroundColor(unavailable ? .white : AppTheme.Colors.textSecondary)
                                        .frame(minWidth: 44, minHeight: AppTheme.Layout.touchTargetMinimum)
                                        .background(
                                            unavailable
                                                ? AppTheme.Colors.strideBlue.opacity(0.32)
                                                : AppTheme.Colors.DarkMode.surfaceBackground
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small)
                                                .stroke(
                                                    unavailable
                                                        ? AppTheme.Colors.strideBlue.opacity(0.7)
                                                        : Color.white.opacity(0.06),
                                                    lineWidth: 1
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(weekday.name) unavailable")
                                .accessibilityValue(unavailable ? "Yes" : "No")
                            }
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.lg)
            .background(AppTheme.Colors.DarkMode.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                    .stroke(Color.white.opacity(0.07), lineWidth: AppTheme.BorderWidth.regular)
            )
        }
    }
}

private struct TrainingActivityRow: View {
    @ObservedObject var model: TrainingProfileEditorViewModel
    let activity: TrainingActivity

    var body: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Toggle(
                isOn: Binding(
                    get: { model.isSelected(activity) },
                    set: { model.setActivity(activity, selected: $0) }
                )
            ) {
                HStack(spacing: AppTheme.Spacing.md) {
                    ActivityTypeDisc(activityType: activity.discActivityType)
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        Text(activity.displayName)
                            .font(AppTheme.Typography.bodyBold)
                            .foregroundColor(AppTheme.Colors.textPrimary)
                        Text(activity.supportingCopy)
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(AppTheme.Colors.textTertiary)
                    }
                }
            }
            .tint(activity.tint)
            .disabled(model.isSelected(activity) && !model.canRemove(activity))
            .frame(minHeight: AppTheme.Layout.touchTargetMinimum)
            .accessibilityLabel(model.controlPresentation.activitySelectionLabel(for: activity))

            if model.isSelected(activity) {
                HStack(spacing: AppTheme.Spacing.md) {
                    Picker(
                        "Role",
                        selection: Binding(
                            get: { model.role(for: activity) ?? .supporting },
                            set: { model.setRole($0, for: activity) }
                        )
                    ) {
                        ForEach(TrainingActivityRole.allCases, id: \.self) { role in
                            Text(role.displayName).tag(role)
                        }
                    }
                    .tint(activity.tint)

                    Spacer(minLength: 0)

                    Stepper(
                        value: Binding(
                            get: { model.sessions(for: activity) },
                            set: { model.setSessions($0, for: activity) }
                        ),
                        in: 0...7
                    ) {
                        Text("\(model.sessions(for: activity))/week")
                            .font(AppTheme.Typography.subheadlineBold)
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .monospacedDigit()
                    }
                    .fixedSize()
                }
                .padding(.leading, 56)
                .frame(minHeight: AppTheme.Layout.touchTargetMinimum)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(
            model.isSelected(activity)
                ? activity.tint.opacity(0.055)
                : Color.clear
        )
    }
}

struct StrengthTrainingDetailsEditor: View {
    @ObservedObject var model: TrainingProfileEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "dumbbell.fill")
                    .foregroundColor(AppTheme.Colors.strideBlue)
                Text("Strength setup")
                    .font(AppTheme.Typography.title3)
                    .foregroundColor(AppTheme.Colors.textPrimary)
            }

            HStack {
                Text("Equipment")
                    .foregroundColor(AppTheme.Colors.textSecondary)
                Spacer()
                Picker(
                    "Equipment",
                    selection: Binding(
                        get: { model.draft.strengthEquipment },
                        set: { model.setStrengthEquipment($0) }
                    )
                ) {
                    ForEach(StrengthEquipment.allCases, id: \.self) { equipment in
                        Text(equipment.displayName).tag(equipment)
                    }
                }
                .labelsHidden()
                .tint(AppTheme.Colors.strideBlueLight)
            }
            .frame(minHeight: AppTheme.Layout.touchTargetMinimum)

            HStack {
                Text("Experience")
                    .foregroundColor(AppTheme.Colors.textSecondary)
                Spacer()
                Picker(
                    "Experience",
                    selection: Binding(
                        get: { model.draft.strengthExperience },
                        set: { model.setStrengthExperience($0) }
                    )
                ) {
                    ForEach(TrainingExperience.allCases, id: \.self) { experience in
                        Text(experience.displayName).tag(experience)
                    }
                }
                .labelsHidden()
                .tint(AppTheme.Colors.strideBlueLight)
            }
            .frame(minHeight: AppTheme.Layout.touchTargetMinimum)
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppTheme.Colors.DarkMode.cardBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                .stroke(AppTheme.Colors.strideBlue.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct TrainingProfileValueRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(title)
                .font(AppTheme.Typography.bodyMedium)
                .foregroundColor(AppTheme.Colors.textPrimary)
            Text(value)
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.textTertiary)
                .monospacedDigit()
        }
    }
}

struct TrainingProfileWeekday: Identifiable {
    let id: Int
    let name: String
    let shortName: String

    static let all = [
        TrainingProfileWeekday(id: 1, name: "Sunday", shortName: "Sun"),
        TrainingProfileWeekday(id: 2, name: "Monday", shortName: "Mon"),
        TrainingProfileWeekday(id: 3, name: "Tuesday", shortName: "Tue"),
        TrainingProfileWeekday(id: 4, name: "Wednesday", shortName: "Wed"),
        TrainingProfileWeekday(id: 5, name: "Thursday", shortName: "Thu"),
        TrainingProfileWeekday(id: 6, name: "Friday", shortName: "Fri"),
        TrainingProfileWeekday(id: 7, name: "Saturday", shortName: "Sat"),
    ]

    static func name(for id: Int) -> String {
        all.first(where: { $0.id == id })?.name ?? "Sunday"
    }
}

private extension TrainingActivity {
    var displayName: String {
        switch self {
        case .running: return "Running"
        case .strength: return "Strength"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        case .mobility: return "Mobility"
        }
    }

    var supportingCopy: String {
        switch self {
        case .running: return "Mileage, quality work and the long run"
        case .strength: return "Durability and force production"
        case .cycling: return "Aerobic volume without extra impact"
        case .swimming: return "Low-impact aerobic conditioning"
        case .walking: return "Gentle volume and active recovery"
        case .hiking: return "Time on feet and climbing strength"
        case .mobility: return "Range of motion and recovery"
        }
    }

    var discActivityType: String {
        switch self {
        case .running: return "run"
        case .strength: return "weight training"
        case .cycling: return "cycling"
        case .swimming: return "swimming"
        case .walking: return "walk"
        case .hiking: return "hike"
        case .mobility: return "yoga"
        }
    }

    var tint: Color {
        switch self {
        case .running:
            return AppTheme.Colors.warmAmber
        case .strength, .cycling, .swimming:
            return AppTheme.Colors.strideBlue
        case .walking, .hiking, .mobility:
            return AppTheme.Colors.recoveryMint
        }
    }

    func sessionSummary(count: Int) -> String {
        let singular: String
        let plural: String
        switch self {
        case .running: (singular, plural) = ("run", "runs")
        case .strength: (singular, plural) = ("strength session", "strength sessions")
        case .cycling: (singular, plural) = ("ride", "rides")
        case .swimming: (singular, plural) = ("swim", "swims")
        case .walking: (singular, plural) = ("walk", "walks")
        case .hiking: (singular, plural) = ("hike", "hikes")
        case .mobility: (singular, plural) = ("mobility session", "mobility sessions")
        }
        return "\(count) \(count == 1 ? singular : plural)"
    }
}

private extension TrainingActivityRole {
    var displayName: String {
        switch self {
        case .primary: return "Primary"
        case .supporting: return "Supporting"
        case .optional: return "Optional"
        }
    }
}

private extension StrengthEquipment {
    var displayName: String {
        switch self {
        case .bodyweight: return "Bodyweight"
        case .dumbbells: return "Dumbbells"
        case .fullGym: return "Full gym"
        case .unspecified: return "Not sure"
        }
    }
}

private extension TrainingExperience {
    var displayName: String {
        rawValue.capitalized
    }
}
