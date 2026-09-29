//
//  EmailVerificationPendingView.swift
//  Runaway iOS
//
//  Shown after signup while waiting for email verification
//

import SwiftUI
import Supabase

struct EmailVerificationPendingView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(UserSession.self) var userSession
    @Environment(\.dismiss) private var dismiss

    let email: String
    let onResendEmail: () async -> Void
    let onBackToSignIn: () -> Void

    @State private var isResending = false
    @State private var showResendSuccess = false
    @State private var showVerificationError = false
    @State private var verificationErrorMessage = ""
    @State private var countdown = 0

    private var backgroundColor: Color {
        themeManager.isDarkMode
            ? AppTheme.Colors.DarkMode.background
            : AppTheme.Colors.LightMode.background
    }

    private var textPrimary: Color {
        themeManager.isDarkMode
            ? AppTheme.Colors.DarkMode.textPrimary
            : AppTheme.Colors.LightMode.textPrimary
    }

    private var textSecondary: Color {
        themeManager.isDarkMode
            ? AppTheme.Colors.DarkMode.textSecondary
            : AppTheme.Colors.LightMode.textSecondary
    }

    private var cardBackground: Color {
        themeManager.isDarkMode
            ? AppTheme.Colors.DarkMode.cardBackground
            : AppTheme.Colors.LightMode.cardBackground
    }

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            VStack(spacing: AppTheme.Spacing.xl) {
                Spacer()

                // Email icon
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.accent.opacity(0.15))
                        .frame(width: 120, height: 120)

                    Image(systemName: "envelope.badge")
                        .font(.system(size: 50))
                        .foregroundColor(AppTheme.Colors.accent)
                }

                // Title and message
                VStack(spacing: AppTheme.Spacing.md) {
                    Text("Check Your Email")
                        .font(AppTheme.Typography.title)
                        .foregroundColor(textPrimary)
                        .multilineTextAlignment(.center)

                    Text("We sent a verification link to")
                        .font(AppTheme.Typography.body)
                        .foregroundColor(textSecondary)
                        .multilineTextAlignment(.center)

                    Text(email)
                        .font(AppTheme.Typography.body.weight(.semibold))
                        .foregroundColor(textPrimary)
                        .multilineTextAlignment(.center)
                }

                // Instructions
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    InstructionRow(number: 1, text: "Open your email app")
                    InstructionRow(number: 2, text: "Find the email from Runaway")
                    InstructionRow(number: 3, text: "Tap the verification link")
                }
                .padding(AppTheme.Spacing.lg)
                .background(cardBackground)
                .cornerRadius(AppTheme.CornerRadius.medium)
                .padding(.horizontal, AppTheme.Spacing.lg)

                Spacer()

                // Actions
                VStack(spacing: AppTheme.Spacing.md) {
                    // Open Mail button
                    Button(action: openMailApp) {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Image(systemName: "envelope.open")
                                .font(.title3)
                            Text("Open Mail App")
                                .font(AppTheme.Typography.body.weight(.semibold))
                        }
                        .foregroundColor(AppTheme.Colors.pine)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.md)
                        .background(AppTheme.Colors.strideLime)
                        .cornerRadius(AppTheme.CornerRadius.medium)
                    }

                    // Resend email button
                    Button(action: resendEmail) {
                        Group {
                            if isResending {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.Colors.accent))
                            } else if countdown > 0 {
                                Text("Resend email in \(countdown)s")
                                    .foregroundColor(textSecondary)
                            } else {
                                Text("Didn't receive it? Resend email")
                                    .foregroundColor(AppTheme.Colors.accent)
                            }
                        }
                        .font(AppTheme.Typography.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.sm)
                    }
                    .disabled(isResending || countdown > 0)

                    // Back to sign in
                    Button(action: onBackToSignIn) {
                        Text("Back to Sign In")
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(textSecondary)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.bottom, AppTheme.Spacing.xl)
            }
        }
        .navigationBarBackButtonHidden(true)
        .alert("Email Sent", isPresented: $showResendSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A new verification email has been sent to \(email)")
        }
        .alert("Verification Failed", isPresented: $showVerificationError) {
            Button("Resend Email") {
                resendEmail()
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(verificationErrorMessage.isEmpty
                 ? "The verification link has expired or is invalid. Please request a new one."
                 : verificationErrorMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("EmailVerificationFailed"))) { notification in
            if let errorMessage = notification.userInfo?["error"] as? String {
                verificationErrorMessage = errorMessage
            }
            showVerificationError = true
        }
        .onChange(of: userSession.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                // User verified their email - dismiss to let ContentView handle navigation
                #if DEBUG
                print("✅ EmailVerificationPendingView: User authenticated via state change, dismissing")
                #endif
                dismiss()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("EmailVerificationCompleted"))) { _ in
            // Email verification completed via deep link - dismiss to let ContentView handle navigation
            #if DEBUG
            print("✅ EmailVerificationPendingView: Email verification completed notification received, dismissing")
            #endif
            dismiss()
        }
        .onAppear {
            // Check if user is already authenticated (e.g., app was relaunched after verification)
            if userSession.isAuthenticated {
                #if DEBUG
                print("✅ EmailVerificationPendingView: User already authenticated on appear, dismissing")
                #endif
                dismiss()
            }
        }
        .task {
            // Continuously check auth state in case it changes while view is visible
            for await _ in supabase.auth.authStateChanges.map({ $0.0 }) {
                if userSession.isAuthenticated {
                    #if DEBUG
                    print("✅ EmailVerificationPendingView: Auth state changed, dismissing")
                    #endif
                    await MainActor.run {
                        dismiss()
                    }
                    break
                }
            }
        }
    }

    private func openMailApp() {
        if let mailURL = URL(string: "message://") {
            UIApplication.shared.open(mailURL)
        }
    }

    private func resendEmail() {
        isResending = true

        Task {
            await onResendEmail()

            await MainActor.run {
                isResending = false
                showResendSuccess = true
                startCountdown()
            }
        }
    }

    private func startCountdown() {
        countdown = 60

        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if countdown > 0 {
                countdown -= 1
            } else {
                timer.invalidate()
            }
        }
    }
}

// MARK: - Instruction Row

private struct InstructionRow: View {
    @ObservedObject private var themeManager = ThemeManager.shared

    let number: Int
    let text: String

    private var textPrimary: Color {
        themeManager.isDarkMode
            ? AppTheme.Colors.DarkMode.textPrimary
            : AppTheme.Colors.LightMode.textPrimary
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Text("\(number)")
                .font(AppTheme.Typography.caption.weight(.bold))
                .foregroundColor(AppTheme.Colors.pine)
                .frame(width: 24, height: 24)
                .background(AppTheme.Colors.strideLime)
                .clipShape(Circle())

            Text(text)
                .font(AppTheme.Typography.body)
                .foregroundColor(textPrimary)

            Spacer()
        }
    }
}

#Preview {
    EmailVerificationPendingView(
        email: "test@example.com",
        onResendEmail: {},
        onBackToSignIn: {}
    )
    .environmentObject(ThemeManager.shared)
}
