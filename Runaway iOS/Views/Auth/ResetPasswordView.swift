import SwiftUI
import Supabase

enum PasswordRecoveryLink {
    static func shouldPresentReset(for url: URL, hasPendingRequest: Bool) -> Bool {
        isRecoveryCallback(url) || hasPendingRequest
    }

    static func isRecoveryCallback(_ url: URL) -> Bool {
        callbackType(in: url) == "recovery"
    }

    private static func callbackType(in url: URL) -> String? {
        let queryType = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "type" })?
            .value

        if let queryType {
            return queryType
        }

        guard let fragment = url.fragment,
              let fragmentComponents = URLComponents(string: "https://callback.invalid/?\(fragment)") else {
            return nil
        }

        return fragmentComponents.queryItems?
            .first(where: { $0.name == "type" })?
            .value
    }
}

enum PasswordRecoveryRequest {
    private static let requestedAtKey = "passwordRecoveryRequestedAt"
    private static let validityDuration: TimeInterval = 60 * 60

    static func markRequested(
        at date: Date = Date(),
        defaults: UserDefaults = .standard
    ) {
        defaults.set(date.timeIntervalSince1970, forKey: requestedAtKey)
    }

    static func hasRecentRequest(
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> Bool {
        let timestamp = defaults.double(forKey: requestedAtKey)
        guard timestamp > 0 else { return false }
        return isRecent(requestedAt: Date(timeIntervalSince1970: timestamp), now: now)
    }

    static func isRecent(requestedAt: Date?, now: Date = Date()) -> Bool {
        guard let requestedAt else { return false }
        let age = now.timeIntervalSince(requestedAt)
        return age >= 0 && age <= validityDuration
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: requestedAtKey)
    }
}

struct ResetPasswordView: View {
    let onComplete: () -> Void

    @State private var password = ""
    @State private var confirmation = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didUpdatePassword = false

    private var validationMessage: String? {
        if password.count < 8 {
            return "Use at least 8 characters."
        }
        if password != confirmation {
            return "Passwords do not match."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.DarkMode.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppTheme.Spacing.xl) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.primary)
                            .frame(width: 72, height: 72)
                            .background(AppTheme.Colors.primary.opacity(0.16))
                            .clipShape(Circle())

                        VStack(spacing: AppTheme.Spacing.sm) {
                            Text("Choose a new password")
                                .font(.title2.bold())
                                .foregroundStyle(AppTheme.Colors.DarkMode.textPrimary)

                            Text("Your recovery link was verified. Set a new password to secure your account.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Colors.DarkMode.textSecondary)
                                .multilineTextAlignment(.center)
                        }

                        VStack(spacing: AppTheme.Spacing.md) {
                            SecureField("New password", text: $password)
                                .textContentType(.newPassword)
                                .padding()
                                .background(AppTheme.Colors.DarkMode.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))

                            SecureField("Confirm new password", text: $confirmation)
                                .textContentType(.newPassword)
                                .submitLabel(.done)
                                .onSubmit(updatePassword)
                                .padding()
                                .background(AppTheme.Colors.DarkMode.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
                        }
                        .foregroundStyle(AppTheme.Colors.DarkMode.textPrimary)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }

                        Button(action: updatePassword) {
                            Group {
                                if isLoading {
                                    ProgressView()
                                        .tint(AppTheme.Colors.pine)
                                } else {
                                    Text("Update Password")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.Colors.pine)
                        .background(AppTheme.Colors.strideLime)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
                        .disabled(isLoading || validationMessage != nil)
                        .opacity(validationMessage == nil ? 1 : 0.55)
                    }
                    .padding(AppTheme.Spacing.xl)
                }
            }
            .interactiveDismissDisabled()
            .alert("Password updated", isPresented: $didUpdatePassword) {
                Button("Continue", action: onComplete)
            } message: {
                Text("Your new password is ready to use.")
            }
        }
    }

    private func updatePassword() {
        guard !isLoading else { return }
        guard validationMessage == nil else {
            errorMessage = validationMessage
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                _ = try await supabase.auth.update(user: UserAttributes(password: password))
                password = ""
                confirmation = ""
                isLoading = false
                didUpdatePassword = true
            } catch {
                isLoading = false
                errorMessage = "This recovery link is invalid or expired. Request a new link and try again."
            }
        }
    }
}

#Preview {
    ResetPasswordView(onComplete: {})
}
