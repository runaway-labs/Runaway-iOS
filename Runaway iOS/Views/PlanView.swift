//
//  PlanView.swift
//  Runaway iOS
//
//  Weekly schedule and race planning.
//

import SwiftUI

// MARK: - Plan Section Enum

enum PlanSection: String, CaseIterable {
    case weeklySchedule = "Weekly Schedule"
    case races = "Races"
}

struct PlanView: View {
    @Environment(DataManager.self) var dataManager
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject private var trainingProfileStore: TrainingProfileStore
    @StateObject private var viewModel = PlanViewModel()
    @ObservedObject private var unitPreferences = UnitPreferences.shared
    @State private var selectedSection: PlanSection = .weeklySchedule
    @State private var showingWorkoutDetail: DailyWorkout?
    @State private var decisionWorkout: DailyWorkout?
    @State private var decisionStartsWithChoices = false
    @State private var showingTrainingGuidelines = false
    @State private var showingGoalSettings = false
    @State private var showingManualRace = false
    @State private var editingManualRace: AthleteRace?
    @State private var allGoals: [AthleteRace] = []
    @State private var isLoadingGoals = false
    @State private var lastRefreshError: String? = nil
    @State private var coachDecision: CoachDecision?
    @Environment(AppRouter.self) private var router
    private var bg:   Color { AppTheme.Colors.DarkMode.background }
    private var card: Color { AppTheme.Colors.DarkMode.cardBackground }
    private var pri:  Color { AppTheme.Colors.DarkMode.textPrimary }
    private var sec:  Color { AppTheme.Colors.DarkMode.textSecondary }

    private var upcomingRaces: [AthleteRace] {
        allGoals.filter { $0.isUpcoming }
    }

    private var pastRaces: [AthleteRace] {
        allGoals.filter { !$0.isUpcoming }.reversed()
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selectedSection) {
                ForEach(PlanSection.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, AppTheme.Spacing.sm)

            switch selectedSection {
            case .weeklySchedule: weeklyScheduleContent
            case .races: racesContent
            }
        }
        .background {
            LinearGradient(
                colors: [AppTheme.Colors.DarkMode.backgroundElevated, bg],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .ignoresSafeArea()
        }
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { showingTrainingGuidelines = true } label: {
                    Image(systemName: "info.circle")
                        .foregroundColor(AppTheme.Colors.accent)
                }
            }
        }
        .sheet(item: $showingWorkoutDetail) { PlanWorkoutDetailSheet(workout: $0) }
        .sheet(item: $decisionWorkout) { workout in
            if let plan = dataManager.currentWeeklyPlan {
                TodayWorkoutDecisionSheet(
                    plan: plan,
                    profile: trainingProfileStore.profile,
                    recommendedWorkout: workout,
                    startChoosing: decisionStartsWithChoices
                )
            }
        }
        .sheet(isPresented: $showingTrainingGuidelines) { TrainingGuidelinesSheet() }
        .sheet(isPresented: $showingGoalSettings, onDismiss: {
            Task { await loadAll() }
        }) {
            GoalSettingsView()
        }
        .sheet(isPresented: $showingManualRace, onDismiss: {
            Task { await loadAll() }
        }) {
            ManualRaceSheet { _ in
                Task { await loadAll() }
            }
        }
        .sheet(item: $editingManualRace, onDismiss: {
            Task { await loadAll() }
        }) { race in
            ManualRaceSheet(existingRace: race) { _ in
                Task { await loadAll() }
            }
        }
        .task(id: dataManager.athlete?.id) { allGoals = []; await loadAll() }
        .task(id: dataManager.currentWeeklyPlan?.generatedAt) { loadCoachDecision() }
        .onChange(of: dataManager.currentWeeklyPlan?.generatedAt) { _, _ in
            viewModel.currentPlan = dataManager.currentWeeklyPlan
            viewModel.displayedPlan = dataManager.currentWeeklyPlan
        }
    }

    // MARK: - Load

    private func loadAll() async {
        await viewModel.loadPlan()
        isLoadingGoals = true
        lastRefreshError = nil
        do {
            let races = try await GoalService.getAllRaces()
            #if DEBUG
            print("🔍 PlanView: Refresh fetched \(races.count) races")
            #endif
            allGoals = races
        } catch {
            #if DEBUG
            print("❌ PlanView: Refresh failed: \(error)")
            #endif
            lastRefreshError = error.localizedDescription
        }
        isLoadingGoals = false
    }

    private func loadCoachDecision() {
        guard let athleteID = dataManager.athlete?.id else { coachDecision = nil; return }
        let repository = ProtectedTrainingRepository(activeAthleteID: { UserSession.shared.userId })
        let ledger = CoachDecisionLedger(repository: repository, athleteID: athleteID)
        coachDecision = try? ledger.decisions().reversed().first {
            $0.state == .proposed || ($0.state == .applied && Date().timeIntervalSince($0.createdAt) < 172_800)
        }
    }

    private func handleWeekBoardAction(_ action: CoachWeekBoard.UserAction) {
        func workout(_ id: String) -> DailyWorkout? {
            dataManager.currentWeeklyPlan?.workouts.first { $0.id == id }
        }
        switch action {
        case .commit(let id):
            decisionStartsWithChoices = false
            decisionWorkout = workout(id)
        case .change(let id):
            decisionStartsWithChoices = true
            decisionWorkout = workout(id)
        case .viewWorkout(let id), .reviewResult(let id):
            showingWorkoutDetail = workout(id)
        case .reviewCoachDecision(let id):
            router.navigate(to: .coachDecision(id))
        }
    }

    // MARK: - Weekly Schedule

    @ViewBuilder
    private var weeklyScheduleContent: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                if let coachDecision {
                    CoachChangeBanner(decision: coachDecision) {
                        router.navigate(to: .coachDecision(coachDecision.id))
                    }
                }

                if viewModel.isLoading && viewModel.displayedPlan == nil {
                    LoadingPlanView()
                } else if let plan = viewModel.displayedPlan {
                    CoachWeekBoard(
                        presentation: CoachWeekBoardPresentation.make(
                            plan: plan,
                            activities: dataManager.activities,
                            recentDecision: coachDecision,
                            distanceFormatter: { UnitFormatter.formatMiles($0) }
                        ),
                        focusTitle: plan.focusArea,
                        focusDescription: plan.focusArea.map(focusExplanation),
                        isRegenerating: viewModel.isGenerating,
                        onRegenerate: { Task { await viewModel.regeneratePlan() } },
                        onAction: handleWeekBoardAction
                    )

                    if let baseline = viewModel.trainingBaseline {
                        BaselineTransparencyCard(baseline: baseline)
                    }

                    if let insights = viewModel.adaptiveInsights {
                        AdaptiveInsightsCard(insights: insights)
                    }

                    TrainingPrinciplesCard()

                } else {
                    NoPlanView(
                        baseline: viewModel.trainingBaseline,
                        onGenerate: { Task { await viewModel.generatePlan() } },
                        isGenerating: viewModel.isGenerating
                    )
                }
            }
            .padding()
        }
        .refreshable { await loadAll() }
    }

    private func focusExplanation(_ focus: String) -> String {
        let normalized = focus.lowercased()
        if normalized.contains("base") {
            return "Build durable weekly volume and consistency before race-specific work."
        }
        if normalized.contains("build") {
            return "Increase useful training load while protecting recovery between hard days."
        }
        if normalized.contains("peak") {
            return "Sharpen race-specific fitness while holding onto the strength already built."
        }
        if normalized.contains("taper") {
            return "Reduce fatigue while preserving speed and readiness for race day."
        }
        if normalized.contains("recover") {
            return "Absorb recent work with lower stress before the next progression."
        }
        return "This is the coach's main priority when balancing the sessions below."
    }

    // MARK: - Races

    @ViewBuilder
    private var racesContent: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                sectionHeader("UPCOMING RACES")

                if isLoadingGoals && allGoals.isEmpty {
                    ProgressView()
                        .tint(AppTheme.Colors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.xxl)
                } else if upcomingRaces.isEmpty {
                    NoRaceCard { showingManualRace = true }
                } else {
                    RaceCarousel(
                        races: upcomingRaces,
                        onEdit: { editingManualRace = $0 }
                    )

                    Button { showingManualRace = true } label: {
                        Label("Add another race", systemImage: "plus.circle.fill")
                            .font(AppTheme.Typography.subheadline)
                            .foregroundColor(AppTheme.Colors.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppTheme.Spacing.sm)
                    }
                }

                sectionHeader("PAST RACES")

                if pastRaces.isEmpty {
                    VStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 28))
                            .foregroundColor(sec.opacity(0.7))
                        Text("Completed races will collect here.")
                            .font(AppTheme.Typography.body)
                            .foregroundColor(sec)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.xl)
                } else {
                    ForEach(pastRaces) { race in
                        PastRaceRow(race: race)
                    }
                }

                if let lastRefreshError {
                    Text(lastRefreshError)
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(.red.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .refreshable { await loadAll() }
    }

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(sec)
                .tracking(0.8)
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Race Carousel

struct RaceCarousel: View {
    let races: [AthleteRace]
    let onEdit: (AthleteRace) -> Void
    @State private var currentIndex = 0

    var body: some View {
        VStack(spacing: 8) {
            TabView(selection: $currentIndex) {
                ForEach(Array(races.enumerated()), id: \.element.id) { index, race in
                    NextRaceCard(
                        race: race,
                        index: index,
                        total: races.count,
                        onEdit: ManualRaceEdit(race: race) == nil ? nil : { onEdit(race) }
                    )
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 228)

            if races.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<races.count, id: \.self) { i in
                        Capsule()
                            .fill(i == currentIndex ? AppTheme.Colors.accent : Color.white.opacity(0.2))
                            .frame(width: i == currentIndex ? 18 : 6, height: 6)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentIndex)
                            .onTapGesture { currentIndex = i }
                    }
                }
            }
        }
    }
}

// MARK: - Next Race Card

struct NextRaceCard: View {
    let race: AthleteRace
    let index: Int
    let total: Int
    let onEdit: (() -> Void)?
    @State private var showingCourseRecon = false
    @State private var raceWeather: RaceWeatherSnapshot?

    private var daysUntil: Int {
        guard let d = race.parsedDate else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: d).day ?? 0)
    }

    private var raceDate: String {
        guard let d = race.parsedDate else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: d)
    }

    private var urgencyColor: Color {
        if daysUntil == 0  { return .red }
        if daysUntil <= 7  { return .orange }
        return AppTheme.Colors.accent
    }

    private var cardLabel: String {
        total > 1 ? "RACE \(index + 1) OF \(total)" : "NEXT RACE"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(urgencyColor)
                .frame(height: 3)
                .cornerRadius(2)
                .padding(.bottom, 16)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(cardLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                        .tracking(1.2)

                    Text(race.raceName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
                        .lineLimit(2)

                    if let distLabel = race.primaryDistanceLabel(
                        fallback: UnitPreferences.shared.distanceUnit
                    ) {
                        Text(distLabel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(urgencyColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(urgencyColor.opacity(0.15))
                            .cornerRadius(6)

                        if let equivalent = race.convertedDistanceLabel(
                            fallback: UnitPreferences.shared.distanceUnit
                        ) {
                            Text(equivalent)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.Colors.DarkMode.textTertiary)
                        }
                    }

                    if let loc = race.locationString {
                        Label(loc, systemImage: "mappin")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                    }

                    Text(raceDate)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)

                    if race.runsignupRaceId != nil {
                        Button { showingCourseRecon = true } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "mountain.2.fill")
                                Text("Scout Course")
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(urgencyColor)
                            .cornerRadius(20)
                        }
                        .padding(.top, 8)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if let onEdit {
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
                                .frame(width: 32, height: 32)
                                .background(Color.white.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit \(race.raceName)")
                        .padding(.bottom, 2)
                    }

                    Text("\(daysUntil)")
                        .font(.system(size: 44, weight: .heavy))
                        .foregroundColor(urgencyColor)
                        .monospacedDigit()
                    Text(daysUntil == 1 ? "day to go" : "days to go")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                }
            }

            if daysUntil <= 14 && daysUntil > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill").font(.system(size: 11))
                    Text(daysUntil <= 7 ? "Race week — final prep" : "Two weeks out — taper time")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(urgencyColor)
                .padding(.top, 12)
            }

            if let raceWeather {
                HStack(spacing: 8) {
                    Image(systemName: raceWeather.symbolName)
                        .foregroundColor(AppTheme.Colors.strideBlueLight)
                    Text("Race-day outlook")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
                    Spacer(minLength: 8)
                    Text(raceWeatherSummary(raceWeather))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                }
                .padding(.top, 10)
            }
        }
        .padding(16)
        .background(AppTheme.Colors.DarkMode.cardBackground)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .sheet(isPresented: $showingCourseRecon) {
            CourseReconView(race: race)
        }
        .task(id: race.raceDate) {
            raceWeather = await NativeTrainingContextService.shared.raceForecast(for: race)
        }
    }


    private func raceWeatherSummary(_ weather: RaceWeatherSnapshot) -> String {
        let usesMetric = UnitPreferences.shared.distanceUnit == .kilometers
        let temperatureUnit: UnitTemperature = usesMetric ? .celsius : .fahrenheit
        let high = Measurement(value: weather.highCelsius, unit: UnitTemperature.celsius)
            .converted(to: temperatureUnit).value.rounded()
        let low = Measurement(value: weather.lowCelsius, unit: UnitTemperature.celsius)
            .converted(to: temperatureUnit).value.rounded()
        let rain = Int((weather.precipitationChance * 100).rounded())
        return "H \(Int(high))° · L \(Int(low))° · \(rain)% rain"
    }
}

// MARK: - No Race Card

struct NoRaceCard: View {
    let onAddGoal: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "flag.checkered.2.crossed")
                .font(.system(size: 36))
                .foregroundColor(AppTheme.Colors.accent.opacity(0.7))
            Text("No upcoming race set")
                .font(AppTheme.Typography.headline)
                .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
            Text("Add a target race to shape weekly volume, long runs, and taper timing.")
                .font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                .multilineTextAlignment(.center)
            Button(action: onAddGoal) {
                Label("Set target race", systemImage: "plus")
                    .font(AppTheme.Typography.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.Colors.strideBlue)
            .foregroundStyle(Color.white)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(AppTheme.Colors.DarkMode.cardBackground)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}

// MARK: - Past Race Row

struct PastRaceRow: View {
    let race: AthleteRace

    private var raceDate: String {
        guard let d = race.parsedDate else { return race.raceDate ?? "" }
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: d)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 16))
                .foregroundColor(AppTheme.Colors.DarkMode.textSecondary.opacity(0.5))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(race.raceName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
                HStack(spacing: 6) {
                    Text(raceDate)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                    if let loc = race.locationString {
                        Text("·")
                            .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                        Text(loc)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                    }
                }
            }

            Spacer()
        }
        .padding(14)
        .background(AppTheme.Colors.DarkMode.cardBackground)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}

// MARK: - Plan Header Card

struct PlanHeaderCard: View {
    @ObservedObject private var unitPreferences = UnitPreferences.shared
    let plan: WeeklyTrainingPlan
    let insights: AdaptiveInsights?
    let onRegenerate: () -> Void
    let isRegenerating: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.weekRangeString)
                        .font(AppTheme.Typography.headline)
                        .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
                    if let focus = plan.focusArea {
                        Text(focus)
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(AppTheme.Colors.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(AppTheme.Colors.accent.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                Spacer()
                Button(action: onRegenerate) {
                    if isRegenerating {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 16, weight: .medium))
                    }
                }
                .foregroundColor(AppTheme.Colors.accent)
                .disabled(isRegenerating)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Regenerate remaining training plan")
            }

            Divider()

            HStack(spacing: AppTheme.Spacing.xl) {
                PlanStatItem(title: "Planned",
                             value: UnitFormatter.formatMiles(plan.totalMileage),
                             icon: "target")
                PlanStatItem(title: "Completed", value: "\(PlanProgressPresentation(plan: plan).completedSessions)/\(PlanProgressPresentation(plan: plan).scheduledSessions)", icon: "checkmark.circle", valueColor: TrainingProgressStyle.mint)
                PlanStatItem(title: "Workouts",
                             value: "\(plan.workouts.filter { $0.workoutType != .rest }.count)",
                             icon: "figure.run")
            }
        }
        .padding()
        .background(AppTheme.Colors.DarkMode.cardBackground)
        .cornerRadius(AppTheme.CornerRadius.large)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}

struct PlanStatItem: View {
    let title: String
    let value: String
    let icon: String
    var valueColor: Color = AppTheme.Colors.DarkMode.textPrimary

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(AppTheme.Colors.accent)
            Text(value)
                .font(AppTheme.Typography.headline)
                .foregroundColor(valueColor)
            Text(title)
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Week Overview Section

struct WeekOverviewSection: View {
    let plan: WeeklyTrainingPlan
    let activities: [Activity]
    let onWorkoutTap: (DailyWorkout) -> Void

    var weekEntries: [WeekDayEntry] { plan.mergedWithActivities(activities) }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("This Week")
                .font(AppTheme.Typography.headline)
                .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
            VStack(spacing: AppTheme.Spacing.sm) {
                ForEach(weekEntries) { entry in
                    PlanWeekDayRow(entry: entry, onTap: {
                        if let w = entry.plannedWorkout { onWorkoutTap(w) }
                    })
                }
            }
        }
        .padding()
        .background(AppTheme.Colors.DarkMode.cardBackground)
        .cornerRadius(AppTheme.CornerRadius.large)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}

struct PlanWeekDayRow: View {
    let entry: WeekDayEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.md) {
                Text(entry.dayOfWeek.shortName)
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(entry.isToday ? AppTheme.Colors.accent : AppTheme.Colors.DarkMode.textSecondary)
                    .frame(width: 35, alignment: .leading)
                Image(systemName: entry.icon)
                    .font(.system(size: 16))
                    .foregroundColor(entry.iconColor)
                    .frame(width: 24)
                Text(entry.displayTitle)
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
                    .lineLimit(1)
                Spacer()
                if let d = entry.formattedDistance {
                    Text(d).font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                } else if let s = entry.statusText {
                    Text(s).font(AppTheme.Typography.caption)
                        .foregroundColor(entry.isCompleted ? .green : .orange)
                }
            }
            .padding(.vertical, AppTheme.Spacing.sm)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .background(entry.isToday ? AppTheme.Colors.accent.opacity(0.05) : Color.clear)
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(entry.plannedWorkout == nil)
    }
}

// MARK: - Adaptive Insights Card

struct AdaptiveInsightsCard: View {
    let insights: AdaptiveInsights

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Image(systemName: "brain").foregroundColor(AppTheme.Colors.accent)
                Text("Adaptive Insights").font(AppTheme.Typography.headline)
                    .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
            }
            if insights.hasWarnings {
                ForEach(insights.spikeWarnings, id: \.self) { w in
                    HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange).font(.system(size: 14))
                        Text(w).font(AppTheme.Typography.body)
                            .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
                    }
                    .padding(AppTheme.Spacing.sm)
                    .background(Color.orange.opacity(0.1)).cornerRadius(8)
                }
            }
            ForEach(insights.recommendations.prefix(3), id: \.self) { r in
                HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow).font(.system(size: 14))
                    Text(r).font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                }
            }
        }
        .padding()
        .background(AppTheme.Colors.DarkMode.cardBackground)
        .cornerRadius(AppTheme.CornerRadius.large)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}

// MARK: - Baseline Transparency Card

struct BaselineTransparencyCard: View {
    let baseline: TrainingBaseline
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis").foregroundColor(AppTheme.Colors.accent)
                    Text("Your Training Baseline").font(AppTheme.Typography.headline)
                        .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                HStack(spacing: AppTheme.Spacing.lg) {
                    BaselineStatPill(label: "Prior 4 Weeks",
                                     value: "\(UnitFormatter.formatMiles(baseline.averageWeeklyMileage))/wk",
                                     icon: "calendar")
                    BaselineStatPill(label: "Runs/Week", value: "\(baseline.runsPerWeek)", icon: "figure.run")
                    BaselineStatPill(label: "Easy Pace", value: formatPace(baseline.averageEasyPace), icon: "speedometer")
                }

                Divider()
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text("How the algorithm uses this:")
                        .font(AppTheme.Typography.subheadline)
                        .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
                    BaselineExplanationRow(text: "Your prior 4-week average (\(UnitFormatter.formatMiles(baseline.averageWeeklyMileage))) sets your training baseline (current week excluded)")
                    BaselineExplanationRow(text: "Long runs are capped at 30% of weekly distance")
                    BaselineExplanationRow(text: "Build weeks increase progressively from your baseline")
                    if baseline.longestRecentRun > 0 {
                        BaselineExplanationRow(text: "Your longest recent run: \(UnitFormatter.formatMiles(baseline.longestRecentRun))")
                    }
                    if !baseline.weeklyMileages.isEmpty {
                        Text("Prior 4 weeks (most recent first):")
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                            .padding(.top, AppTheme.Spacing.xs)
                        HStack(spacing: AppTheme.Spacing.sm) {
                            ForEach(Array(baseline.weeklyMileages.enumerated().reversed()), id: \.offset) { i, m in
                                VStack(spacing: 2) {
                                    Text(UnitFormatter.formatMiles(m, decimals: 1, includeUnit: false)).font(AppTheme.Typography.caption)
                                        .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
                                    Text("W\(4 - i)").font(.system(size: 10))
                                        .foregroundColor(AppTheme.Colors.DarkMode.textTertiary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(AppTheme.Colors.DarkMode.cardBackground)
        .cornerRadius(AppTheme.CornerRadius.large)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    private func formatPace(_ pace: Double) -> String {
        UnitFormatter.formatPace(minutesPerMile: pace)
    }
}

struct BaselineStatPill: View {
    let label: String; let value: String; let icon: String
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(AppTheme.Colors.accent)
            Text(value).font(AppTheme.Typography.subheadline).fontWeight(.semibold)
                .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
            Text(label).font(.system(size: 10))
                .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct BaselineExplanationRow: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            Image(systemName: "info.circle").font(.system(size: 12)).foregroundColor(AppTheme.Colors.accent)
            Text(text).font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
        }
    }
}

// MARK: - Training Principles Card

struct TrainingPrinciplesCard: View {
    @State private var isExpanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "book.fill").foregroundColor(AppTheme.Colors.accent)
                    Text("Training Science").font(AppTheme.Typography.headline)
                        .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            if isExpanded {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    PrincipleRow(icon: "heart.fill", title: "Lactate Threshold",
                                 description: "Correlates 0.91 with marathon time - more predictive than VO2 max (0.63)")
                    PrincipleRow(icon: "exclamationmark.shield.fill", title: "Injury Prevention",
                                 description: "Single-session spikes are the key predictor. 30%+ increase = 64% higher risk.")
                    PrincipleRow(icon: "arrow.up.right", title: "Progressive Overload",
                                 description: "20-25% weekly increases below 30mpw, 10-15% above. Step-back every 3-4 weeks.")
                    PrincipleRow(icon: "clock.fill", title: "Long Run Limits",
                                 description: "20-30% of weekly mileage, max 2.5-3 hours. Beyond this, recovery costs outweigh benefits.")
                }
            }
        }
        .padding()
        .background(AppTheme.Colors.DarkMode.cardBackground)
        .cornerRadius(AppTheme.CornerRadius.large)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}

struct PrincipleRow: View {
    let icon: String; let title: String; let description: String
    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            Image(systemName: icon).foregroundColor(AppTheme.Colors.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppTheme.Typography.subheadline)
                    .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
                Text(description).font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
            }
        }
    }
}

// MARK: - No Plan / Loading / Workout Detail (unchanged logic, dark-only colors)

struct NoPlanView: View {
    let baseline: TrainingBaseline?
    let onGenerate: () -> Void
    let isGenerating: Bool
    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Spacer()
            Image(systemName: "calendar.badge.plus").font(.system(size: 80))
                .foregroundColor(AppTheme.Colors.accent)
            VStack(spacing: AppTheme.Spacing.sm) {
                Text("No Training Plan").font(AppTheme.Typography.title)
                    .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
                Text("Generate an adaptive plan based on your recent training and goals.")
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let b = baseline {
                HStack(spacing: AppTheme.Spacing.xl) {
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", b.averageWeeklyMileage)).font(AppTheme.Typography.headline)
                            .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
                        Text("mi/week avg").font(.system(size: 10))
                            .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                    }
                    VStack(spacing: 2) {
                        Text("\(b.runsPerWeek)").font(AppTheme.Typography.headline)
                            .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
                        Text("runs/week").font(.system(size: 10))
                            .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                    }
                }
                .padding()
                .background(AppTheme.Colors.accent.opacity(0.05))
                .cornerRadius(AppTheme.CornerRadius.medium)
            }
            Button(action: onGenerate) {
                HStack {
                    if isGenerating {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .black)).scaleEffect(0.8)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isGenerating ? "Generating..." : "Generate Plan")
                }
                .font(AppTheme.Typography.headline)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding()
                .background(AppTheme.Colors.accent)
                .cornerRadius(AppTheme.CornerRadius.medium)
            }
            .disabled(isGenerating)
            Spacer()
        }
        .padding(AppTheme.Spacing.xl)
    }
}

struct LoadingPlanView: View {
    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            ProgressView().scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.Colors.accent))
            Text("Loading your plan...").font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Spacing.xxl)
    }
}

struct PlanWorkoutDetailSheet: View {
    let workout: DailyWorkout
    var body: some View {
        WorkoutDetailSheet(workout: workout)
    }
}

struct DetailRow: View {
    let label: String; let value: String
    var body: some View {
        HStack {
            Text(label).font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
            Spacer()
            Text(value).font(AppTheme.Typography.headline)
                .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
        }
    }
}

struct TrainingGuidelinesSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text("Evidence-Based Training").font(AppTheme.Typography.title)
                            .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
                        Text("Guidelines backed by exercise physiology research")
                            .font(AppTheme.Typography.body)
                            .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                    }
                    GuidelinesSection(title: "Marathon Training Mileage", icon: "figure.run") { MileageTable() }
                    GuidelinesSection(title: "Long Run Constraints", icon: "clock") {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            GuidelineRow(label: "% of weekly mileage", value: "20-30%")
                            GuidelineRow(label: "Maximum duration", value: "2.5-3 hours")
                            GuidelineRow(label: "At 10:00/mi pace", value: "~18 miles max")
                            GuidelineRow(label: "At 8:00/mi pace", value: "~22 miles max")
                        }
                    }
                    GuidelinesSection(title: "Weekly Progression", icon: "arrow.up.right") {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            GuidelineRow(label: "Under 30 mi/week", value: "+20-25%")
                            GuidelineRow(label: "Over 30 mi/week", value: "+10-15%")
                            GuidelineRow(label: "Step-back frequency", value: "Every 3-4 weeks")
                            GuidelineRow(label: "Step-back reduction", value: "-20-40%")
                        }
                    }
                }
                .padding()
            }
            .background(AppTheme.Colors.DarkMode.background)
            .navigationTitle("Training Guidelines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct GuidelinesSection<Content: View>: View {
    let title: String; let icon: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: icon).foregroundColor(AppTheme.Colors.accent).font(.system(size: 18))
                Text(title).font(AppTheme.Typography.headline)
                    .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
            }
            content
        }
        .padding()
        .background(AppTheme.Colors.DarkMode.cardBackground)
        .cornerRadius(AppTheme.CornerRadius.large)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}

struct MileageTable: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Level").font(AppTheme.Typography.caption).fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Weekly").font(AppTheme.Typography.caption).fontWeight(.semibold)
                    .frame(width: 80, alignment: .trailing)
                Text("Long Run").font(AppTheme.Typography.caption).fontWeight(.semibold)
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.vertical, AppTheme.Spacing.sm)
            .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
            Divider()
            MileageTableRow(level: "Beginner", weekly: "25-35 mi", longRun: "16-20 mi")
            MileageTableRow(level: "Intermediate", weekly: "35-50 mi", longRun: "18-22 mi")
            MileageTableRow(level: "Competitive", weekly: "50-70 mi", longRun: "20-23 mi")
            MileageTableRow(level: "Elite", weekly: "70-120+ mi", longRun: "22-26 mi")
        }
    }
}

struct MileageTableRow: View {
    let level: String; let weekly: String; let longRun: String
    var body: some View {
        HStack {
            Text(level).font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(weekly).font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                .frame(width: 80, alignment: .trailing)
            Text(longRun).font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, AppTheme.Spacing.sm)
    }
}

struct GuidelineRow: View {
    let label: String; let value: String
    var body: some View {
        HStack {
            Text(label).font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
            Spacer()
            Text(value).font(AppTheme.Typography.body).fontWeight(.medium)
                .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
        }
    }
}

// MARK: - Preview

struct PlanView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PlanView()
                .environment(DataManager.shared)
        }
    }
}
