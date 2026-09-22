//
//  Router.swift
//  Runaway iOS
//
//  Centralized navigation router for app-wide navigation management
//

import SwiftUI

@Observable
class AppRouter {
    var path = NavigationPath()

    // MARK: - Route Definitions

    enum Route: Hashable {
        case activityDetail(Int)
        case activityList
        case settings
        case accountInfo
        case commitmentSetup
        case goalManagement
        case awards
        case coachActivity
        case coachDecision(UUID)
    }

    // MARK: - Navigation Methods

    func navigate(to route: Route) { path.append(route) }
    func pop() { guard !path.isEmpty else { return }; path.removeLast() }
    func popToRoot() { path.removeLast(path.count) }
    func pop(count: Int) { guard count > 0, count <= path.count else { return }; path.removeLast(count) }
    func replace(with route: Route) { if !path.isEmpty { path.removeLast() }; path.append(route) }

    var isAtRoot: Bool { path.isEmpty }
    var depth: Int { path.count }

    // MARK: - Deep Linking

    static func deepLinkRoute(for url: URL) -> Route? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return nil
        }

        switch components.path {
        case "/activity":
            if let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
               let activityId = Int(id) {
                return .activityDetail(activityId)
            }
            return .activityList
        case "/settings":
            return .settings
        case "/commitment":
            return .commitmentSetup
        case "/goals":
            return .goalManagement
        case "/awards", "/achievements":
            return .awards
        default:
            return nil
        }
    }

    func handleDeepLink(_ url: URL) {
        guard let route = Self.deepLinkRoute(for: url) else { return }
        navigate(to: route)
    }
}

// MARK: - Destination Builder

extension AppRouter {
    @ViewBuilder
    func destination(for route: Route) -> some View {
        switch route {
        case .activityDetail(let activityId):
            RoutedActivityDetailView(activityId: activityId)

        case .activityList:
            ActivitiesView()

        case .settings:
            SettingsView()

        case .accountInfo:
            AccountInformationView()

        case .commitmentSetup:
            PerformanceCoachDecisionRouteView()

        case .goalManagement:
            GoalSettingsView()

        case .awards:
            AwardsView()
        case .coachActivity:
            CoachActivityRouteView()
        case .coachDecision(let id):
            CoachDecisionRouteView(decisionID: id)
        }
    }
}

private struct PerformanceCoachDecisionRouteView: View {
    @Environment(DataManager.self) private var dataManager
    @EnvironmentObject private var trainingProfileStore: TrainingProfileStore

    var body: some View {
        if let plan = dataManager.currentWeeklyPlan,
           let workout = plan.workouts.first(where: { Calendar.current.isDateInToday($0.date) }) {
            TodayWorkoutDecisionSheet(
                plan: plan,
                profile: trainingProfileStore.profile,
                recommendedWorkout: workout,
                startChoosing: true
            )
        } else {
            ContentUnavailableView(
                "No workout to review",
                systemImage: "figure.run.circle",
                description: Text("Open Today after your training plan is ready.")
            )
            .navigationTitle("Performance Coach")
        }
    }
}

private struct CoachActivityRouteView: View {
    @Environment(UserSession.self) private var session
    var body: some View { if let id = session.userId { CoachActivityView(athleteID: id) } else { ContentUnavailableView("Sign in required", systemImage: "lock") } }
}
private struct CoachDecisionRouteView: View {
    @Environment(UserSession.self) private var session
    let decisionID: UUID
    var body: some View { if let id = session.userId { CoachDecisionDetailView(athleteID: id, decisionID: decisionID) } else { ContentUnavailableView("Sign in required", systemImage: "lock") } }
}

private struct RoutedActivityDetailView: View {
    @Environment(DataManager.self) private var dataManager
    @Environment(UserSession.self) private var userSession
    @State private var fetchedActivity: Activity?
    @State private var isLoading = true
    let activityId: Int

    var body: some View {
        Group {
        if let activity = fetchedActivity ?? dataManager.activities.first(where: { $0.id == activityId }),
           activity.athlete_id == userSession.userId {
            ActivityDetailView(
                activity: LocalActivity(
                    id: activity.id,
                    name: activity.name ?? "Activity",
                    type: activity.type ?? "",
                    summary_polyline: activity.summary_polyline ?? "",
                    distance: activity.distance ?? 0,
                    start_date: (activity.activity_date ?? activity.start_date).map(Date.init(timeIntervalSince1970:)),
                    elapsed_time: activity.elapsed_time ?? 0
                )
            )
        } else if isLoading {
            ProgressView("Loading activity...")
        } else {
            ContentUnavailableView(
                "Activity unavailable",
                systemImage: "figure.run.circle",
                description: Text("This activity may have been removed, or your connection is unavailable.")
            )
            .navigationTitle("Activity")
        }
        }
        .task(id: activityId) { await loadActivity() }
        .refreshable { await loadActivity() }
    }

    private func loadActivity() async {
        isLoading = true
        defer { isLoading = false }
        fetchedActivity = try? await ActivityService.getActivityById(id: activityId)
    }
}

// MARK: - View Extension

extension View {
    func withAppRouter(_ router: AppRouter) -> some View {
        self
            .navigationDestination(for: AppRouter.Route.self) { route in
                router.destination(for: route)
            }
            .environment(router)
    }
}
