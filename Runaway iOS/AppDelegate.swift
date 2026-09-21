//
//  AppDelegate.swift
//  Runaway iOS
//
//  Created by Jack Rudelic on 3/27/25.
//
import SwiftUI
import UserNotifications
import Supabase

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        UNUserNotificationCenter.current().delegate = self

        Task { await PushNotificationService.shared.activate() }

        // If the user logs in after the token was already received, save it then
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("UserDidLogin"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                PushNotificationService.shared.resumeRegistration()
            }
        }

        return true
    }

    // Called by iOS when APNs issues a device token (or rotates it)
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        #if DEBUG
        print("📱 APNs device token: \(String(token.prefix(20)))...")
        #endif
        PushNotificationService.shared.receiveToken(token)
        PushNotificationService.shared.scheduleSynchronization()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushNotificationService.shared.registrationFailed(error)
        #if DEBUG
        print("❌ APNs registration failed: \(error)")
        #endif
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        Task { await PushNotificationService.shared.activate() }
    }

    // Handle silent background notifications (e.g. new activity sync trigger)
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if let syncType = userInfo["sync_type"] as? String, syncType == "new_activity" {
            Task {
                await DataManager.shared.refreshActivities()
                await MainActor.run { completionHandler(.newData) }
            }
        } else if let syncType = userInfo["sync_type"] as? String, syncType == "coach_event" {
            Task { @MainActor in
                guard let athleteID = UserSession.shared.userId else {
                    completionHandler(.noData)
                    return
                }
                do {
                    let saved = try CoachEventService.persistRemotePayload(userInfo, athleteID: athleteID)
                    if saved,
                       let event = CoachEvent.remoteScheduledCheckIn(
                           from: userInfo,
                           authenticatedAthleteID: athleteID
                       ) {
                        await DataManager.shared.loadCurrentWeeklyPlan()
                        if let workout = DataManager.shared.currentWeeklyPlan?.workout(
                            for: DayOfWeek.from(date: Date())
                        ), !workout.isCompleted {
                            try await PushNotificationService.shared.presentScheduledCoachRecommendation(
                                for: workout,
                                eventID: event.id
                            )
                        }
                    }
                    completionHandler(saved ? .newData : .noData)
                } catch {
                    completionHandler(.failed)
                }
            }
        } else {
            completionHandler(.noData)
        }
    }

    // Show notification banner even when app is foregrounded
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            if response.actionIdentifier != UNNotificationDefaultActionIdentifier,
               response.actionIdentifier != UNNotificationDismissActionIdentifier {
                PushNotificationService.shared.enqueueCoachAction(userInfo, actionIdentifier: response.actionIdentifier)
            }
            PushNotificationService.shared.receiveNotification(userInfo)
        }
        #if DEBUG
        print("🔔 Notification tapped: \(userInfo)")
        #endif
        completionHandler()
    }

}
