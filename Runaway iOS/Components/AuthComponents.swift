//
//  AuthComponents.swift
//  Runaway iOS
//
//  Reusable authentication UI components
//

import SwiftUI

// MARK: - Auth TextField

/// A customizable text field for authentication forms
struct AuthTextField: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var text: String
    let placeholder: String
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .never
    var textContentType: UITextContentType?

    private var backgroundColor: Color {
        colorScheme == .dark
            ? AppTheme.Colors.DarkMode.cardBackground
            : AppTheme.Colors.LightMode.cardBackground
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.15)
            : Color.black.opacity(0.1)
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textInputAutocapitalization(autocapitalization)
            .keyboardType(keyboardType)
            .autocorrectionDisabled()
            .textContentType(textContentType)
            .padding(AppTheme.Spacing.md)
            .background(backgroundColor)
            .foregroundColor(colorScheme == .dark ? .white : .primary)
            .cornerRadius(AppTheme.CornerRadius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                    .stroke(borderColor, lineWidth: 1)
            )
    }
}

// MARK: - Auth Secure Field

/// A secure text field with show/hide password toggle
struct AuthSecureField: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var text: String
    let placeholder: String
    var textContentType: UITextContentType? = .password
    var onEditingChanged: ((Bool) -> Void)?

    @State private var isSecure: Bool = true

    private var backgroundColor: Color {
        colorScheme == .dark
            ? AppTheme.Colors.DarkMode.cardBackground
            : AppTheme.Colors.LightMode.cardBackground
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.15)
            : Color.black.opacity(0.1)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .textContentType(textContentType)
                        .onSubmit { onEditingChanged?(false) }
                } else {
                    TextField(placeholder, text: $text)
                        .textContentType(textContentType)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .padding(AppTheme.Spacing.md)
            .padding(.trailing, 44) // Space for toggle button
            .background(backgroundColor)
            .foregroundColor(colorScheme == .dark ? .white : .primary)
            .cornerRadius(AppTheme.CornerRadius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                    .stroke(borderColor, lineWidth: 1)
            )

            Button(action: { isSecure.toggle() }) {
                Image(systemName: isSecure ? "eye.slash.fill" : "eye.fill")
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
            }
            .padding(.trailing, 4)
        }
    }
}

// MARK: - Auth Button

/// A customizable button for authentication forms
struct AuthButton: View {
    let title: String
    let action: () -> Void
    var style: ButtonStyle = .primary
    var isEnabled: Bool = true
    var isLoading: Bool = false
    var systemImage: String? = nil

    enum ButtonStyle {
        case primary
        case secondary
        case social
        case text
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:
            return isEnabled ? AppTheme.Colors.strideLime : Color.gray.opacity(0.3)
        case .secondary:
            return Color.clear
        case .social:
            return Color.white
        case .text:
            return Color.clear
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:
            return AppTheme.Colors.pine
        case .secondary:
            return AppTheme.Colors.accent
        case .social:
            return .black
        case .text:
            return AppTheme.Colors.accent
        }
    }

    private var borderColor: Color {
        switch style {
        case .secondary:
            return AppTheme.Colors.accent
        case .social:
            return Color.gray.opacity(0.3)
        default:
            return Color.clear
        }
    }

    var body: some View {
        Button(action: {
            if isEnabled && !isLoading {
                action()
            }
        }) {
            HStack(spacing: AppTheme.Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: foregroundColor))
                        .scaleEffect(0.8)
                } else {
                    if let systemImage = systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 18, weight: .medium))
                    }
                    Text(title)
                        .font(AppTheme.Typography.body.weight(.semibold))
                }
            }
            .foregroundColor(isEnabled ? foregroundColor : .gray)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(backgroundColor)
            .cornerRadius(AppTheme.CornerRadius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                    .stroke(borderColor, lineWidth: style == .secondary || style == .social ? 1.5 : 0)
            )
        }
        .disabled(!isEnabled || isLoading)
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}

// MARK: - Auth Divider

/// A divider with text in the middle (e.g., "or")
struct AuthDivider: View {
    let text: String

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)

            Text(text)
                .font(AppTheme.Typography.caption)
                .foregroundColor(.secondary)

            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
        }
    }
}

// MARK: - Auth Header

/// A header component with logo and title
struct AuthHeader: View {
    let title: String
    let subtitle: String?

    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Logo
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.accent.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "figure.run")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(AppTheme.Colors.accent)
            }

            // Title
            Text(title)
                .font(AppTheme.Typography.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            // Subtitle
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(AppTheme.Typography.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Auth Link Button

/// A text button for navigation (e.g., "Don't have an account? Sign up")
struct AuthLinkButton: View {
    let text: String
    let actionText: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(AppTheme.Typography.body)
                .foregroundColor(.secondary)

            Button(action: action) {
                Text(actionText)
                    .font(AppTheme.Typography.body.weight(.semibold))
                    .foregroundColor(AppTheme.Colors.accent)
            }
        }
    }
}

// MARK: - Validation Message

/// An inline validation message
struct ValidationMessage: View {
    let message: String
    let type: MessageType

    enum MessageType {
        case error
        case success
        case info
    }

    private var color: Color {
        switch type {
        case .error: return .red
        case .success: return .green
        case .info: return .secondary
        }
    }

    private var icon: String {
        switch type {
        case .error: return "exclamationmark.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 14))
            Text(message)
                .font(AppTheme.Typography.caption)
        }
        .foregroundColor(color)
    }
}

// MARK: - Previews

#Preview("Auth Components") {
    VStack(spacing: 20) {
        AuthHeader(title: "Welcome Back", subtitle: "Sign in to continue")

        AuthTextField(text: .constant(""), placeholder: "Email")

        AuthSecureField(text: .constant(""), placeholder: "Password")

        AuthButton(title: "Sign In", action: {}, style: .primary)

        AuthButton(title: "Sign In with Apple", action: {}, style: .social, systemImage: "apple.logo")

        AuthDivider(text: "or")

        AuthButton(title: "Create Account", action: {}, style: .secondary)

        AuthLinkButton(text: "Don't have an account?", actionText: "Sign up", action: {})

        ValidationMessage(message: "Password must be at least 8 characters", type: .error)
    }
    .padding()
}
