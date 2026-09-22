//
//  MainView.swift
//  Runaway iOS
//

import SwiftUI
import WidgetKit
import Supabase

enum RunawayTab: Int, CaseIterable {
    case today
    case plan
    case activities
    case you

    var title: String {
        switch self {
        case .today: "Today"
        case .activities: "Activities"
        case .plan: "Plan"
        case .you: "You"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max.fill"
        case .activities: "figure.run"
        case .plan: "calendar.badge.clock"
        case .you: "person.crop.circle"
        }
    }
}

struct MainView: View {
    @Environment(UserSession.self) var userSession
    @Environment(RealtimeService.self) var realtimeService
    @Environment(DataManager.self) var dataManager
    @Environment(AppRouter.self) private var router
    @State var selectedTab = RunawayTab.today
    @State var isDataReady: Bool = false
    @State private var workoutPromptRoute: WorkoutPromptRoute?
    @ObservedObject private var promptReadiness = ReadinessService.shared
    @EnvironmentObject private var trainingProfileStore: TrainingProfileStore

    private var promptPublication: WorkoutPromptPublication? {
        guard let id = userSession.userId, !dataManager.isLoadingActivities else { return nil }
        return WorkoutPromptPublication.make(
            athleteID: id, plans: [dataManager.currentWeeklyPlan, dataManager.pendingNextWeekPlan].compactMap { $0 },
            profile: trainingProfileStore.profile, activities: dataManager.activities,
            readinessScore: promptReadiness.todaysReadiness?.score
        )
    }

    private var backgroundColor: Color {
        AppTheme.Colors.adaptiveBackground
    }

    var body: some View {
        if isDataReady {
            TabView(selection: $selectedTab) {
                Tab(RunawayTab.today.title, systemImage: RunawayTab.today.systemImage, value: RunawayTab.today) {
                    NavigationStack(path: Bindable(router).path) {
                        TrainingView {
                            selectedTab = .activities
                        }
                            .navigationDestination(for: AppRouter.Route.self) { route in
                                router.destination(for: route)
                            }
                    }
                }

                Tab(RunawayTab.plan.title, systemImage: RunawayTab.plan.systemImage, value: RunawayTab.plan) {
                    NavigationStack(path: Bindable(router).path) {
                        PlanView()
                            .navigationDestination(for: AppRouter.Route.self) { route in
                                router.destination(for: route)
                            }
                    }
                }

                Tab(RunawayTab.activities.title, systemImage: RunawayTab.activities.systemImage, value: RunawayTab.activities) {
                    NavigationStack(path: Bindable(router).path) {
                        ActivitiesView()
                            .navigationDestination(for: AppRouter.Route.self) { route in
                                router.destination(for: route)
                            }
                    }
                }

                Tab(RunawayTab.you.title, systemImage: RunawayTab.you.systemImage, value: RunawayTab.you) {
                    NavigationStack(path: Bindable(router).path) {
                        profileContent
                            .navigationDestination(for: AppRouter.Route.self) { route in
                                router.destination(for: route)
                            }
                    }
                }
            }
            .tint(AppTheme.Colors.warmAmber)
            .ignoresSafeArea(.keyboard)
            .animation(.easeInOut(duration: 0.2), value: selectedTab)
            .onChange(of: selectedTab) { oldTab, newTab in
                router.popToRoot()
                AnalyticsService.shared.track(.tabSelected, category: .navigation, properties: [
                    "tab_name": newTab.title,
                    "tab_index": newTab.rawValue,
                    "previous_tab": oldTab.title
                ])
            }
            .task {
                await loadInitialData()
                realtimeService.startRealtimeSubscription()
            }
            .task(id: PushNotificationService.shared.pendingActivityID) {
                guard let id = PushNotificationService.shared.takePendingActivityID() else { return }
                router.popToRoot()
                router.navigate(to: .activityDetail(id))
            }
            .task(id: PushNotificationService.shared.pendingCoachRoute?.id) {
                guard let route = PushNotificationService.shared.takePendingCoachRoute() else { return }
                router.popToRoot()
                router.navigate(to: .coachDecision(route.decisionID))
            }
            .task(id: PushNotificationService.shared.coachCommandRevision) {
                processCoachNotificationCommands()
            }
            .task(id: "\(promptPublication?.signature ?? "loading")-\(WorkoutPromptService.shared.syncRevision)") {
                if let publication = promptPublication { await WorkoutPromptService.shared.publish(publication) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                WorkoutPromptService.shared.requestSync()
            }
            .task(id: PushNotificationService.shared.pendingWorkoutRoute) {
                guard let route = PushNotificationService.shared.takePendingWorkoutRoute() else { return }
                workoutPromptRoute = route
            }
            .sheet(item: $workoutPromptRoute) { route in
                WorkoutPromptDeliveryView(route: route) {
                    workoutPromptRoute = nil
                    selectedTab = .today
                    router.popToRoot()
                    WorkoutPromptService.shared.requestSync()
                }
            }
        } else {
            ZStack {
                backgroundColor.ignoresSafeArea()

                VStack(spacing: AppTheme.Spacing.xl) {
                    VStack(spacing: AppTheme.Spacing.md) {
                        Image("LaunchLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                    }

                    VStack(spacing: AppTheme.Spacing.lg) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.Colors.accent))

                        VStack(spacing: AppTheme.Spacing.sm) {
                            Text("Loading your data...")
                                .font(AppTheme.Typography.headline)
                                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

                            Text("Syncing activities and performance metrics")
                                .font(AppTheme.Typography.body)
                                .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(AppTheme.Spacing.xl)
            }
            .task {
                await loadInitialData()
            }
        }
    }

    // MARK: - Profile Content

    @ViewBuilder
    private var profileContent: some View {
        Group {
            if let athlete = dataManager.athlete, let stats = dataManager.stats {
                AthleteView(athlete: athlete, stats: stats)
                    .navigationTitle("You")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: { router.navigate(to: .settings) }) {
                                Image(systemName: "gearshape.fill")
                                    .foregroundColor(AppTheme.Colors.accent)
                            }
                        }
                    }
            } else if dataManager.isLoadingAthlete {
                VStack(spacing: AppTheme.Spacing.md) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.Colors.accent))
                    Text("Loading your profile...")
                        .font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(backgroundColor)
                .navigationTitle("You")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { router.navigate(to: .settings) }) {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(AppTheme.Colors.accent)
                        }
                    }
                }
            } else {
                ProfileLoadingErrorView(onRetry: {
                    Task {
                        if let userId = userSession.userId {
                            await dataManager.loadAllData(for: userId)
                        }
                    }
                })
                .navigationTitle("You")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { router.navigate(to: .settings) }) {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(AppTheme.Colors.accent)
                        }
                    }
                }
            }
        }
    }
}

extension MainView {
    @MainActor
    private func processCoachNotificationCommands() {
        guard let athleteID = userSession.userId else { return }
        let repository = ProtectedTrainingRepository(activeAthleteID: { userSession.userId })
        let ledger = CoachDecisionLedger(repository: repository, athleteID: athleteID)
        let model = CoachActivityViewModel(ledger: ledger, currentPlan: { dataManager.currentWeeklyPlan },
            activate: { plan, expected in
                guard let current = dataManager.currentWeeklyPlan,
                      try CoachDecisionLedger.fingerprint(of: current) == expected else {
                    throw ProtectedTrainingRepository.RepositoryError.staleCoachDecision
                }
                try dataManager.updateCurrentWeeklyPlan(plan)
            })
        for command in PushNotificationService.shared.takePendingCoachCommands() {
            switch command.actionIdentifier {
            case "RUNAWAY_COACH_ACCEPT": try? model.accept(command.route.decisionID)
            case "RUNAWAY_COACH_KEEP": try? model.keepOriginal(command.route.decisionID)
            case "RUNAWAY_COACH_UNDO": _ = try? model.undo(command.route.decisionID)
            default: break
            }
            router.popToRoot()
            router.navigate(to: .coachDecision(command.route.decisionID))
        }
    }

    private func loadInitialData() async {
        guard let authId = userSession.currentUser?.id else {
            isDataReady = true
            return
        }

        do {
            let user = try await UserService.getUserByAuthId(authId: authId)
            await MainActor.run {
                userSession.setProfile(user)
                NotificationCenter.default.post(name: NSNotification.Name("UserDidLogin"), object: nil)
            }
            await dataManager.loadAllData(for: user.userId)
            await MainActor.run { isDataReady = true }
        } catch {
            await MainActor.run { isDataReady = true }
        }
    }
}

// MARK: - Profile Loading Error View

private struct ProfileLoadingErrorView: View {
    let onRetry: () -> Void
    @State private var isRetrying = false

    var body: some View {
        ZStack {
            (AppTheme.Colors.adaptiveBackground).ignoresSafeArea()

            VStack(spacing: AppTheme.Spacing.lg) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 50))
                    .foregroundColor(.orange)

                Text("Couldn't load profile")
                    .font(AppTheme.Typography.headline)
                    .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

                Text("Please check your connection and try again")
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
                    .multilineTextAlignment(.center)

                Button(action: {
                    isRetrying = true
                    onRetry()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { isRetrying = false }
                }) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        if isRetrying {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(isRetrying ? "Loading..." : "Try Again")
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, AppTheme.Spacing.xl)
                    .padding(.vertical, AppTheme.Spacing.md)
                    .background(AppTheme.Colors.accent)
                    .cornerRadius(AppTheme.CornerRadius.medium)
                }
                .disabled(isRetrying)
            }
            .padding(AppTheme.Spacing.xl)
        }
    }
}
