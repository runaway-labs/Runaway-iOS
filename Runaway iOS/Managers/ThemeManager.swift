//
//  ThemeManager.swift
//  Runaway iOS
//
//  Manages app-wide theme (dark/light mode) with persistence
//

import SwiftUI

// MARK: - Theme Mode Enum
enum ThemeMode: String, CaseIterable {
    case dark = "dark"
    case light = "light"

    var displayName: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }

    var iconName: String {
        switch self {
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        }
    }
}

// MARK: - Theme Manager
@MainActor
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    private let themeKey = "app_theme_mode"

    @Published var currentTheme: ThemeMode {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: themeKey)
        }
    }

    private init() {
        // Default to dark mode
        if let savedTheme = UserDefaults.standard.string(forKey: themeKey),
           let theme = ThemeMode(rawValue: savedTheme) {
            self.currentTheme = theme
        } else {
            self.currentTheme = .dark // Default to dark
        }
    }

    var isDarkMode: Bool {
        currentTheme == .dark
    }

    func toggle() {
        currentTheme = isDarkMode ? .light : .dark
    }
}

// MARK: - Dynamic Theme Colors
/// Colors that automatically switch based on current theme
struct DynamicColors {
    @ObservedObject private var themeManager = ThemeManager.shared

    // MARK: - Backgrounds
    var background: Color {
        themeManager.isDarkMode ? AppTheme.Colors.DarkMode.background : AppTheme.Colors.LightMode.background
    }

    var backgroundElevated: Color {
        themeManager.isDarkMode ? AppTheme.Colors.DarkMode.backgroundElevated : AppTheme.Colors.LightMode.backgroundElevated
    }

    // MARK: - Cards
    var cardBackground: Color {
        themeManager.isDarkMode ? AppTheme.Colors.DarkMode.cardBackground : AppTheme.Colors.LightMode.cardBackground
    }

    var cardBackgroundElevated: Color {
        themeManager.isDarkMode ? AppTheme.Colors.DarkMode.cardBackgroundElevated : AppTheme.Colors.LightMode.cardBackgroundElevated
    }

    // MARK: - Surfaces
    var surfaceBackground: Color {
        themeManager.isDarkMode ? AppTheme.Colors.DarkMode.surfaceBackground : AppTheme.Colors.LightMode.surfaceBackground
    }

    // MARK: - Text
    var textPrimary: Color {
        themeManager.isDarkMode ? AppTheme.Colors.DarkMode.textPrimary : AppTheme.Colors.LightMode.textPrimary
    }

    var textSecondary: Color {
        themeManager.isDarkMode ? AppTheme.Colors.DarkMode.textSecondary : AppTheme.Colors.LightMode.textSecondary
    }

    var textTertiary: Color {
        themeManager.isDarkMode ? AppTheme.Colors.DarkMode.textTertiary : AppTheme.Colors.LightMode.textTertiary
    }

    // MARK: - Accent
    // Lime in dark mode. Moss in light mode, where lime text on chalk fails contrast.
    var accent: Color {
        themeManager.isDarkMode ? AppTheme.Colors.DarkMode.accent : AppTheme.Colors.LightMode.accent
    }

    // MARK: - Dividers & Borders
    var divider: Color {
        themeManager.isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    var border: Color {
        themeManager.isDarkMode ? Color.white.opacity(0.18) : Color.black.opacity(0.12)
    }
}
