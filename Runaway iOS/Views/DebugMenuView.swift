//
//  DebugMenuView.swift
//  Runaway iOS
//
//  Created by Assistant on 9/28/25.
//

import SwiftUI
import UserNotifications

struct DebugMenuView: View {
    @State private var realtimeService = RealtimeService.shared
    @State private var showingBackgroundMonitor = false
    @State private var apnsToken: String = "Not registered"
    @State private var notificationStatus: String = "Unknown"
    @State private var showingTokenCopied = false

    var body: some View {
        List {
            // MARK: - Notification Testing Section
            Section("Push Notifications") {
                // APNs Token display
                VStack(alignment: .leading, spacing: 8) {
                    Text("APNs Token")
                        .font(.headline)
                    Text(apnsToken)
                        .font(.caption)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .lineLimit(3)

                    Button("Copy Token") {
                        UIPasteboard.general.string = apnsToken
                        showingTokenCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showingTokenCopied = false
                        }
                    }
                    .foregroundColor(AppTheme.Colors.accent)

                    if showingTokenCopied {
                        Text("Copied!")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }

                HStack {
                    Text("Permission Status")
                        .font(.headline)
                    Spacer()
                    Text(notificationStatus)
                        .foregroundColor(notificationStatus == "Authorized" ? .green : .orange)
                }

                Button("Test Local Notification (3s delay)") {
                    scheduleTestNotification()
                }
                .foregroundColor(AppTheme.Colors.accent)

                Button("Test Activity Sync Notification") {
                    simulateActivitySyncNotification()
                }
                .foregroundColor(AppTheme.Colors.accent)

                Button("Request Notification Permission") {
                    requestNotificationPermission()
                }
                .foregroundColor(.orange)
            }

            Section("Realtime Services") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Connection Status")
                            .font(.headline)
                        Text(realtimeService.isConnected ? "Connected" : "Disconnected")
                            .foregroundColor(realtimeService.isConnected ? .green : .red)
                    }
                    Spacer()
                    Circle()
                        .fill(realtimeService.isConnected ? .green : .red)
                        .frame(width: 12, height: 12)
                }
                
                HStack {
                    Text("Health Status")
                        .font(.headline)
                    Spacer()
                    Text(healthStatusText)
                        .foregroundColor(healthColor)
                }
                
                if let lastUpdate = realtimeService.lastUpdateTime {
                    HStack {
                        Text("Last Update")
                            .font(.headline)
                        Spacer()
                        Text(lastUpdate.formatted(.dateTime.hour().minute().second()))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                }
                
                Button("View Background Task Monitor") {
                    showingBackgroundMonitor = true
                }
                .foregroundColor(.blue)
            }
            
            Section("Quick Actions") {
                Button("Restart Realtime Connection") {
                    realtimeService.startRealtimeSubscription()
                }
                
                Button("Refresh Widget") {
                    realtimeService.refreshWidget()
                }
                
                Button("Force Data Refresh") {
                    Task {
                        await DataManager.shared.refreshAllData()
                    }
                }
            }
        }
        .adaptiveSurfaceTint()
        .navigationTitle("Debug Menu")
        .sheet(isPresented: $showingBackgroundMonitor) {
            BackgroundTaskMonitorView()
        }
        .darkSurfaceTint()
        .onAppear {
            loadAPNsToken()
            checkNotificationStatus()
        }
    }

    // MARK: - Notification Testing Functions

    private func loadAPNsToken() {
        // Read the token we saved to the athletes table — stored in UserDefaults by AppDelegate
        if let token = UserDefaults.standard.string(forKey: "apns_device_token") {
            apnsToken = token
        } else {
            apnsToken = "Not yet registered (launch app on real device)"
        }
    }

    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized:
                    notificationStatus = "Authorized"
                case .denied:
                    notificationStatus = "Denied"
                case .notDetermined:
                    notificationStatus = "Not Determined"
                case .provisional:
                    notificationStatus = "Provisional"
                case .ephemeral:
                    notificationStatus = "Ephemeral"
                @unknown default:
                    notificationStatus = "Unknown"
                }
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    notificationStatus = "Authorized"
                    #if DEBUG
                    print("✅ Notification permission granted")
                    #endif
                } else if let error = error {
                    #if DEBUG
                    print("❌ Notification permission error: \(error)")
                    #endif
                } else {
                    notificationStatus = "Denied"
                    #if DEBUG
                    print("❌ Notification permission denied")
                    #endif
                }
            }
        }
    }

    private func scheduleTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Test Notification"
        content.body = "This is a test notification from Runaway iOS debug menu."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                #if DEBUG
                print("❌ Failed to schedule notification: \(error)")
                #endif
            } else {
                #if DEBUG
                print("✅ Test notification scheduled (3 second delay)")
                #endif
            }
        }
    }

    private func simulateActivitySyncNotification() {
        #if DEBUG
        print("🔄 Simulating activity sync notification...")
        #endif

        // Simulate the background sync that would happen from a push notification
        Task {
            await DataManager.shared.refreshActivities()
            #if DEBUG
            print("✅ Activity sync completed (simulated)")
            #endif

            // Also show a local notification to confirm it worked
            let content = UNMutableNotificationContent()
            content.title = "Activity Sync Complete"
            content.body = "Background activity refresh triggered successfully."
            content.sound = .default

            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private var healthStatusText: String {
        switch realtimeService.connectionHealth {
        case .healthy: return "Healthy"
        case .degraded: return "Degraded"
        case .disconnected: return "Disconnected"
        case .unknown: return "Unknown"
        }
    }
    
    private var healthColor: Color {
        switch realtimeService.connectionHealth {
        case .healthy: return .green
        case .degraded: return .orange
        case .disconnected: return .red
        case .unknown: return .gray
        }
    }
}

#Preview {
    NavigationView {
        DebugMenuView()
    }
}