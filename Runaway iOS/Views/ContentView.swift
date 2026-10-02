//
//  ContentView.swift
//  Runaway iOS
//
//  Created by Jack Rudelic on 2/18/25.
//

import SwiftUI

struct ContentView: View {
    @Environment(UserSession.self) var userSession
    @StateObject private var foundationModels = FoundationModelsService.shared

    var body: some View {
        switch foundationModels.availabilityState {
        case .checking:
            LoaderView()
        case .available:
            accountContent
        case .deviceNotEligible:
            IntelligenceRequirementView(
                icon: "iphone.gen3.slash",
                title: "A newer iPhone is required",
                message: "Runaway uses Apple's on-device model and requires hardware that supports Apple Intelligence.",
                canRetry: false,
                retry: foundationModels.checkAvailability
            )
        case .appleIntelligenceNotEnabled:
            IntelligenceRequirementView(
                icon: "apple.intelligence",
                title: "Turn on Apple Intelligence",
                message: "Open Settings, choose Apple Intelligence & Siri, and turn on Apple Intelligence. Then return here and check again.",
                canRetry: true,
                retry: foundationModels.checkAvailability
            )
        case .modelNotReady:
            IntelligenceRequirementView(
                icon: "arrow.down.circle",
                title: "Apple's model is getting ready",
                message: "Keep your iPhone connected to Wi-Fi and power while the on-device model finishes downloading.",
                canRetry: true,
                retry: foundationModels.checkAvailability
            )
        case .unavailable:
            IntelligenceRequirementView(
                icon: "exclamationmark.triangle",
                title: "On-device intelligence is unavailable",
                message: "Runaway couldn't access Apple's local model. Check Apple Intelligence in Settings and try again.",
                canRetry: true,
                retry: foundationModels.checkAvailability
            )
        }
    }

    @ViewBuilder
    private var accountContent: some View {
        if userSession.isCheckingAuth || userSession.isCheckingOnboarding {
            LoaderView()
        } else if let setupError = userSession.setupError {
            SessionSetupErrorView(message: setupError) {
                Task { await userSession.retrySetup() }
            }
        } else if userSession.isReady {
            if userSession.hasCompletedOnboarding {
                MainView()
            } else {
                OnboardingContainerView()
            }
        } else if userSession.isAuthenticated {
            LoaderView()
        } else {
            LoginView()
        }
    }
}

private struct IntelligenceRequirementView: View {
    let icon: String
    let title: String
    let message: String
    let canRetry: Bool
    let retry: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.Colors.DarkMode.background, Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: AppTheme.Spacing.lg) {
                Image(systemName: icon)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.warmAmber)
                    .accessibilityHidden(true)
                Text(title)
                    .font(AppTheme.Typography.title)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.DarkMode.textSecondary)
                    .multilineTextAlignment(.center)
                if canRetry {
                    Button("Check Again", action: retry)
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.pine)
                        .frame(minHeight: 44)
                        .padding(.horizontal, AppTheme.Spacing.xl)
                        .background(AppTheme.Colors.strideLime)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large))
                        .buttonStyle(.plain)
                }
            }
            .padding(AppTheme.Spacing.xl)
        }
        .preferredColorScheme(.dark)
    }
}

private struct SessionSetupErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(AppTheme.Colors.warning)
                .accessibilityHidden(true)
            Text("Account setup paused")
                .font(AppTheme.Typography.title)
            Text(message)
                .font(AppTheme.Typography.body)
                .multilineTextAlignment(.center)
            Button("Try Again", action: retry)
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.pine)
                .frame(minHeight: 44)
                .padding(.horizontal, AppTheme.Spacing.xl)
                .background(AppTheme.Colors.strideLime)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large))
                .buttonStyle(.plain)
                .accessibilityHint("Retries secure account setup")
        }
        .padding(AppTheme.Spacing.xl)
        .accessibilityElement(children: .contain)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environment(UserSession.shared)
    }
}
