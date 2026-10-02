//
//  SignUpView.swift
//  Runaway iOS
//
//  Sign up view with password confirmation and validation
//

import SwiftUI
import Combine

struct SignUpView: View {
    @Environment(UserSession.self) var userSession
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel = SignUpViewModel()

    @State private var showError = false
    @State private var showEmailVerification = false

    private var backgroundColor: Color {
        themeManager.isDarkMode
            ? AppTheme.Colors.DarkMode.background
            : AppTheme.Colors.LightMode.background
    }

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            // Dismiss keyboard on tap
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }

            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.lg) {
                    Spacer()
                        .frame(height: AppTheme.Spacing.xl)

                    // Header
                    AuthHeader(
                        title: "Create Account",
                        subtitle: "Start your running journey today"
                    )

                    Spacer()
                        .frame(height: AppTheme.Spacing.md)

                    // Form fields
                    VStack(spacing: AppTheme.Spacing.md) {
                        // Email field
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            Text("Email")
                                .font(AppTheme.Typography.caption)
                                .foregroundColor(.secondary)

                            AuthTextField(
                                text: $viewModel.email,
                                placeholder: "Enter your email",
                                keyboardType: .emailAddress,
                                textContentType: .emailAddress
                            )
                            .onChange(of: viewModel.email) { _, _ in
                                viewModel.validateEmail()
                            }

                            if let error = viewModel.emailError {
                                ValidationMessage(message: error, type: .error)
                            }
                        }

                        // Password field
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            Text("Password")
                                .font(AppTheme.Typography.caption)
                                .foregroundColor(.secondary)

                            AuthSecureField(
                                text: $viewModel.password,
                                placeholder: "Create a password",
                                textContentType: .newPassword
                            )
                            .onChange(of: viewModel.password) { _, _ in
                                viewModel.validatePassword()
                                viewModel.validatePasswordMatch()
                            }

                            // Password strength indicator
                            if !viewModel.password.isEmpty {
                                PasswordStrengthView(password: viewModel.password)
                            }

                            if let error = viewModel.passwordError {
                                ValidationMessage(message: error, type: .error)
                            }
                        }

                        // Confirm password field
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            Text("Confirm Password")
                                .font(AppTheme.Typography.caption)
                                .foregroundColor(.secondary)

                            AuthSecureField(
                                text: $viewModel.confirmPassword,
                                placeholder: "Confirm your password",
                                textContentType: .newPassword
                            )
                            .onChange(of: viewModel.confirmPassword) { _, _ in
                                viewModel.validatePasswordMatch()
                            }

                            if let error = viewModel.confirmPasswordError {
                                ValidationMessage(message: error, type: .error)
                            } else if viewModel.passwordsMatch && !viewModel.confirmPassword.isEmpty {
                                ValidationMessage(message: "Passwords match", type: .success)
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.lg)

                    // Terms agreement. The checkbox and the legal links are separate
                    // accessibility elements so VoiceOver can activate each link on its own.
                    SignUpTermsAgreement(isAgreed: $viewModel.agreedToTerms)
                        .padding(.horizontal, AppTheme.Spacing.lg)

                    // Sign up button
                    AuthButton(
                        title: "Create Account",
                        action: { signUp() },
                        style: .primary,
                        isEnabled: viewModel.isFormValid,
                        isLoading: viewModel.isLoading
                    )
                    .padding(.horizontal, AppTheme.Spacing.lg)

                    Spacer()

                    // Sign in link
                    AuthLinkButton(
                        text: "Already have an account?",
                        actionText: "Sign in",
                        action: { dismiss() }
                    )
                    .padding(.bottom, AppTheme.Spacing.xl)
                }
                    .frame(minHeight: max(0, geometry.size.height - 150))
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                }
            }
        }
        .alert("Sign Up Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred")
        }
        .navigationDestination(isPresented: $showEmailVerification) {
            EmailVerificationPendingView(
                email: viewModel.email,
                onResendEmail: {
                    try? await userSession.resendVerificationEmail(email: viewModel.email)
                },
                onBackToSignIn: {
                    // Pop back to root
                    showEmailVerification = false
                    dismiss()
                }
            )
            .environment(userSession)
            .environmentObject(themeManager)
        }
    }

    private func signUp() {
        Task {
            do {
                try await viewModel.signUp(userSession: userSession)
                showEmailVerification = true
            } catch {
                showError = true
            }
        }
    }
}

// MARK: - Terms agreement

/// Checkbox plus Terms of Service and Privacy Policy links.
/// The links match the destinations in Settings.
private struct SignUpTermsAgreement: View {
    @Binding var isAgreed: Bool

    private static let termsOfServiceURL = URL(string: "https://runawayendurance.com/terms")!
    private static let privacyPolicyURL = URL(string: "https://runawayendurance.com/privacy")!

    private let glyphSize: CGFloat = 20
    private let hitSize: CGFloat = 44

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            checkbox

            legalCopy
                .padding(.top, (hitSize - glyphSize) / 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var checkbox: some View {
        Button(action: { isAgreed.toggle() }) {
            Image(systemName: isAgreed ? "checkmark.square.fill" : "square")
                .font(.system(size: glyphSize))
                .foregroundColor(isAgreed ? AppTheme.Colors.accent : .secondary)
                .frame(width: hitSize, height: hitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("I agree to the Terms of Service and Privacy Policy")
        .accessibilityValue(isAgreed ? "Checked" : "Unchecked")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isAgreed ? .isSelected : [])
    }

    private var legalCopy: some View {
        FlowLayout(spacing: AppTheme.Spacing.xs) {
            Text("I agree to the")
                .font(AppTheme.Typography.caption)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            legalLink("Terms of Service", url: Self.termsOfServiceURL)

            Text("and")
                .font(AppTheme.Typography.caption)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            legalLink("Privacy Policy", url: Self.privacyPolicyURL)
        }
        .accessibilityElement(children: .contain)
    }

    private func legalLink(_ title: String, url: URL) -> some View {
        Link(destination: url) {
            Text(title)
                .font(AppTheme.Typography.caption)
                .underline()
                .foregroundColor(AppTheme.Colors.accent)
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isLink)
    }
}

// MARK: - Password Strength View

struct PasswordStrengthView: View {
    let password: String

    private var strength: Int {
        ValidationUtils.passwordStrength(password)
    }

    private var strengthColor: Color {
        switch strength {
        case 0: return .red
        case 1: return .orange
        case 2: return .yellow
        case 3: return .green
        case 4: return .green
        default: return .gray
        }
    }

    private var strengthText: String {
        ValidationUtils.passwordStrengthDescription(password)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Strength bars
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index < strength ? strengthColor : Color.gray.opacity(0.3))
                        .frame(height: 4)
                }
            }

            // Strength text
            Text(strengthText)
                .font(.system(size: 11))
                .foregroundColor(strengthColor)
        }
    }
}

// MARK: - Sign Up View Model

@MainActor
class SignUpViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var agreedToTerms = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var emailError: String?
    @Published var passwordError: String?
    @Published var confirmPasswordError: String?

    var passwordsMatch: Bool {
        ValidationUtils.passwordsMatch(password, confirmPassword)
    }

    var isFormValid: Bool {
        ValidationUtils.isValidEmail(email) &&
        ValidationUtils.isValidPassword(password) &&
        passwordsMatch &&
        agreedToTerms
    }

    func validateEmail() {
        if email.isEmpty {
            emailError = nil
        } else {
            emailError = ValidationUtils.emailValidationMessage(email)
        }
    }

    func validatePassword() {
        if password.isEmpty {
            passwordError = nil
        } else {
            passwordError = ValidationUtils.passwordValidationMessage(password)
        }
    }

    func validatePasswordMatch() {
        confirmPasswordError = ValidationUtils.passwordMatchMessage(password, confirmPassword)
    }

    func signUp(userSession: UserSession) async throws {
        // Validate form
        validateEmail()
        validatePassword()
        validatePasswordMatch()

        guard isFormValid else {
            throw AuthError(type: .invalidForm)
        }

        isLoading = true
        errorMessage = nil

        do {
            try await userSession.signUp(email: email.trimmed, password: password)
        } catch {
            let authError = AuthError.from(error)
            errorMessage = authError.localizedDescription
            isLoading = false
            throw authError
        }

        isLoading = false
    }
}

#Preview {
    NavigationStack {
        SignUpView()
            .environment(UserSession.shared)
            .environmentObject(ThemeManager.shared)
    }
}
