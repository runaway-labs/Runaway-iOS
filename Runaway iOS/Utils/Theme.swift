import SwiftUI

// MARK: - App Theme
// Night pine canvas with stride lime actions. Amber is identity only.
// Tight card borders, aggressive type hierarchy. UI fonts stay as they are.

struct AppTheme {

    // MARK: - Colors
    struct Colors {

        // MARK: - Brand Accent
        // Amber is identity only: the brand mark, run activity color, and the user's own map track.
        static let warmAmber    = RunawayPalette.amber // #F59E0B
        static let amberLight   = Color(red: 0.984, green: 0.749, blue: 0.298) // #FBBF4C
        static let amberDark    = Color(red: 0.780, green: 0.475, blue: 0.012) // #C77903

        // Stride lime is the only action fill. Text and icons on that fill use pine.
        static let strideLime        = RunawayPalette.strideLime // #D6F35A
        static let strideLimePressed = RunawayPalette.strideLimePressed // #C8E94A
        static let pine              = RunawayPalette.pine // #202E28
        static let moss              = RunawayPalette.moss // #496550

        // Informational blue. Not the lime "stride" and not an action fill.
        static let infoBlue      = RunawayPalette.infoBlue // #3894FA
        static let infoBlueLight = RunawayPalette.infoBlueLight // #66B8FF
        static let recoveryMint  = Color(red: 0.180, green: 0.760, blue: 0.650) // #2EC2A6

        // Secondary palette
        static let deepPurple      = Color(red: 0.416, green: 0.106, blue: 0.604) // #6A1B9A
        static let deepPurpleLight = Color(red: 0.55, green: 0.25, blue: 0.72)
        static let deepPurpleDark  = Color(red: 0.30, green: 0.05, blue: 0.45)
        static let forestGreen     = Color(red: 0.180, green: 0.490, blue: 0.196) // #2E7D32
        static let forestGreenLight = Color(red: 0.30, green: 0.62, blue: 0.32)
        static let forestGreenDark  = Color(red: 0.12, green: 0.38, blue: 0.14)
        static let teal      = Color(red: 0.0, green: 0.475, blue: 0.420)
        static let tealLight = Color(red: 0.15, green: 0.60, blue: 0.55)
        static let tealDark  = Color(red: 0.0, green: 0.35, blue: 0.30)
        static let swimBlue  = Color(red: 0.251, green: 0.651, blue: 0.902) // #40A6E6

        // MARK: - Accent
        // Text and icon accent. Lime on a dark canvas, moss on a light one.
        // Lime text on chalk is about 1.2:1, so fills use strideLime instead.
        // Moss is in use while Design confirms the light accent.
        private static var isDarkModeFromDefaults: Bool {
            UserDefaults.standard.string(forKey: "app_theme_mode") != "light"
        }
        static var accent: Color {
            Color(UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(DarkMode.accent)
                    : UIColor(LightMode.accent)
            })
        }
        static var accentLight: Color { strideLimePressed }
        static let accentDark = strideLimePressed

        // Primary text
        static let primary      = Color.white
        static let primaryLight = Color(red: 0.95, green: 0.95, blue: 0.97)
        static let primaryDark  = Color(red: 0.88, green: 0.88, blue: 0.92)
        static let purple = deepPurple
        static let purpleLight = deepPurpleLight
        static let purpleDark = deepPurpleDark

        // MARK: - Global dark backgrounds (shared between modes when forced dark)
        static let background           = RunawayPalette.nightPine // #0C1210
        static let backgroundElevated   = RunawayPalette.backgroundElevated // #101815
        static let cardBackground       = RunawayPalette.cardBackground // #131B18
        static let cardBackgroundElevated = RunawayPalette.cardBackgroundElevated // #1A2420
        static let surfaceBackground    = RunawayPalette.surfaceBackground // #223029
        static let surfaceElevated      = RunawayPalette.surfaceElevated // #283931

        // Text (dark bg). Tertiary is about 4.1:1 on surfaceElevated, so keep it off that surface.
        // textQuaternary is for disabled or decorative marks only.
        static let textPrimary    = RunawayPalette.textPrimary // #F3F5EF
        static let textSecondary  = RunawayPalette.textSecondary // #9AA59E
        static let textTertiary   = RunawayPalette.textTertiary // #8E9992
        static let textQuaternary = Color(red: 0.267, green: 0.286, blue: 0.318) // #444951
        static let textOnLight    = Color(red: 0.08, green: 0.08, blue: 0.10)
        static let textSecondaryOnLight = Color(red: 0.35, green: 0.35, blue: 0.42)

        // MARK: - Status
        static let success           = forestGreenLight
        static let successBackground = forestGreen.opacity(0.20)
        // Warning text and icons. #E2B714 in dark, #7A620A in light (5.87:1 on white).
        // Fills and marks on an always-dark surface use DarkMode.warning, which stays #E2B714.
        static var warning: Color {
            Color(UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(DarkMode.warning)
                    : UIColor(LightMode.warning)
            })
        }
        static var warningBackground: Color { warning.opacity(0.15) }
        static let error             = Color(red: 1.0, green: 0.38, blue: 0.38)
        static let errorBackground   = Color(red: 1.0, green: 0.38, blue: 0.38).opacity(0.15)
        static let info              = infoBlueLight
        static let infoBackground    = infoBlue.opacity(0.14)

        // MARK: - Icon colors
        static let iconPrimary  = Color.white
        static let iconSecondary = Color(red: 0.60, green: 0.63, blue: 0.68)
        static var iconAccent: Color { accent }
        static let iconSuccess  = forestGreenLight
        static var iconWarning: Color { warning }
        static let iconError    = error
        static let iconMuted    = Color(red: 0.44, green: 0.47, blue: 0.51)

        // MARK: - Gradients
        static let accentGradient = LinearGradient(
            colors: [strideLime, strideLimePressed],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let purpleBlueGradient = LinearGradient(
            colors: [deepPurple, warmAmber],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let tealGreenGradient = LinearGradient(
            colors: [teal, forestGreen],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let primaryGradient = LinearGradient(
            colors: [cardBackground, background],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let successGradient = LinearGradient(
            colors: [forestGreenLight, forestGreen],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let warningGradient = LinearGradient(
            colors: [DarkMode.warning, DarkMode.warning.opacity(0.75)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let errorGradient = LinearGradient(
            colors: [error, error.opacity(0.85)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let backgroundGradient = LinearGradient(
            colors: [backgroundElevated, background],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )

        // MARK: - Activity type colors
        static func activityColor(for type: String) -> Color {
            switch type.lowercased() {
            case "run", "trail run", "trailrun", "virtual run", "virtualrun": return warmAmber
            case "walk", "hike": return forestGreenLight
            case "weight training", "weighttraining", "workout": return deepPurpleLight
            case "bike", "ride", "cycling": return tealLight
            case "swim", "swimming": return swimBlue
            case "yoga": return deepPurpleLight
            default: return amberLight
            }
        }

        // MARK: - Semantic
        struct Semantic {
            static let link = infoBlueLight
            static let linkVisited = infoBlue
            static let interactive = strideLime
            static let interactiveHover = strideLimePressed
            static let interactivePressed = strideLimePressed
            static let progressTrack = Color.white.opacity(0.10)
            static let progressFill = strideLime
            static let divider = Color.white.opacity(0.07)
            static let border = Color.white.opacity(0.08)
            static let borderFocused = strideLime
            static let overlayLight = Color.white.opacity(0.05)
            static let overlayMedium = Color.white.opacity(0.10)
            static let overlayDark = Color.black.opacity(0.55)
        }

        // MARK: - Light Mode
        struct LightMode {
            static let background         = Color(red: 0.95, green: 0.95, blue: 0.96)
            static let backgroundElevated = Color(red: 0.97, green: 0.97, blue: 0.98)
            static let cardBackground     = Color.white
            static let cardBackgroundElevated = Color(red: 0.99, green: 0.99, blue: 1.0)
            static let surfaceBackground  = Color(red: 0.94, green: 0.94, blue: 0.95)
            static let surfaceElevated    = Color(red: 0.92, green: 0.92, blue: 0.93)
            static let textPrimary        = Color(red: 0.08, green: 0.08, blue: 0.10)
            static let textSecondary      = Color(red: 0.32, green: 0.32, blue: 0.38)
            static let textTertiary       = Color(red: 0.48, green: 0.48, blue: 0.54)
            static let textQuaternary     = Color(red: 0.62, green: 0.62, blue: 0.68)
            // Accent text and tint. Lime is a fill only in light mode.
            static let accent             = moss
            static let accentBright       = pine
            // Warning text and icons on light surfaces. Design confirmed #7A620A.
            static let warning            = RunawayPalette.warningOnLight
        }

        // MARK: - Dark Mode (night pine + stride lime)
        struct DarkMode {
            static let background         = RunawayPalette.nightPine // #0C1210
            static let backgroundElevated = RunawayPalette.backgroundElevated // #101815
            static let cardBackground     = RunawayPalette.cardBackground // #131B18
            static let cardBackgroundElevated = RunawayPalette.cardBackgroundElevated // #1A2420
            static let surfaceBackground  = RunawayPalette.surfaceBackground // #223029
            static let surfaceElevated    = RunawayPalette.surfaceElevated // #283931

            // Text. Tertiary is about 4.1:1 on surfaceElevated, so keep it off that surface.
            // textQuaternary is for disabled or decorative marks only.
            static let textPrimary    = RunawayPalette.textPrimary // #F3F5EF
            static let textSecondary  = RunawayPalette.textSecondary // #9AA59E
            static let textTertiary   = RunawayPalette.textTertiary // #8E9992
            static let textQuaternary = Color(red: 0.267, green: 0.286, blue: 0.318) // #444951

            // Accent. Use this on surfaces that stay dark in both appearance modes.
            static let accent      = strideLime
            static let accentBright = strideLimePressed
            // Warning text, icons, and indicators on always-dark surfaces.
            static let warning     = RunawayPalette.warning

            // Tab bar matches backgroundElevated.
            static let tabBarBackground = backgroundElevated
        }
    }

    // MARK: - Typography
    struct Typography {
        static let display   = Font.system(size: 40, weight: .bold,     design: .rounded)
        static let largeTitle = Font.system(size: 32, weight: .bold,    design: .rounded)
        static let title     = Font.system(size: 24, weight: .semibold, design: .rounded)
        static let title2    = Font.system(size: 20, weight: .semibold, design: .rounded)
        static let title3    = Font.system(size: 17, weight: .semibold, design: .rounded)
        static let headline  = Font.system(size: 18, weight: .semibold, design: .rounded)
        static let body      = Font.system(size: 16, weight: .regular,  design: .rounded)
        static let bodyBold  = Font.system(size: 16, weight: .semibold, design: .rounded)
        static let bodyMedium = Font.system(size: 16, weight: .medium,  design: .rounded)
        static let callout   = Font.system(size: 15, weight: .regular,  design: .rounded)
        static let calloutBold = Font.system(size: 15, weight: .semibold, design: .rounded)
        static let subheadline = Font.system(size: 14, weight: .regular, design: .rounded)
        static let subheadlineBold = Font.system(size: 14, weight: .semibold, design: .rounded)
        static let footnote  = Font.system(size: 13, weight: .regular,  design: .rounded)
        static let footnoteBold = Font.system(size: 13, weight: .semibold, design: .rounded)
        static let caption   = Font.system(size: 12, weight: .medium,   design: .rounded)
        static let caption2  = Font.system(size: 11, weight: .regular,  design: .rounded)
        static let numberLarge  = Font.system(size: 40, weight: .bold,  design: .rounded)
        static let numberMedium = Font.system(size: 28, weight: .bold,  design: .rounded)
        static let numberSmall  = Font.system(size: 20, weight: .bold,  design: .rounded)
        static let heroExtraLarge = Font.system(size: 80, weight: .bold, design: .rounded)
        static let heroLarge      = Font.system(size: 64, weight: .bold, design: .rounded)
        static let heroMedium     = Font.system(size: 56, weight: .bold, design: .rounded)
        static func allCapsHeader(size: CGFloat = 17, weight: Font.Weight = .semibold, tracking: CGFloat = 2.0) -> Font {
            Font.system(size: size, weight: weight, design: .rounded)
        }
        static let easyRunHeader  = Font.system(size: 17, weight: .light, design: .rounded)
        static let tempoRunHeader = Font.system(size: 17, weight: .bold,  design: .rounded)
        static let speedWorkHeader = Font.system(size: 17, weight: .heavy, design: .rounded)
    }

    // MARK: - Spacing
    struct Spacing {
        static let xxs: CGFloat = 2
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 12
        static let lg:  CGFloat = 16
        static let xl:  CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        static let huge: CGFloat = 40
        static let massive: CGFloat = 48
        // Design-system aliases (match CSS --sp-* tokens)
        static let xl2: CGFloat = 24
        static let xl3: CGFloat = 32
        static let xl4: CGFloat = 40
        static let xl5: CGFloat = 48
    }

    // MARK: - Corner Radius
    struct CornerRadius {
        static let tiny:       CGFloat = 4
        static let small:      CGFloat = 8
        static let medium:     CGFloat = 12
        static let large:      CGFloat = 16
        static let extraLarge: CGFloat = 20
        static let huge:       CGFloat = 24
        static let massive:    CGFloat = 32
        static let pill:       CGFloat = 999
    }

    // MARK: - Shadows (subtle on near-black — Copilot style)
    struct Shadows {
        static let veryLight:  (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) = (.black.opacity(0.20), 2,  0, 1)
        static let light:      (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) = (.black.opacity(0.28), 4,  0, 2)
        static let medium:     (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) = (.black.opacity(0.35), 8,  0, 4)
        static let heavy:      (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) = (.black.opacity(0.45), 12, 0, 6)
        static let extraHeavy: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) = (.black.opacity(0.55), 16, 0, 8)
        // Amber glows for Runaway brand moments
        static let accentGlow:  (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) = (Colors.warmAmber.opacity(0.30), 12, 0, 4)
        static let orangeGlow:  (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) = (Colors.warmAmber.opacity(0.30), 12, 0, 4)
        static let purpleGlow:  (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) = (Colors.deepPurple.opacity(0.30), 12, 0, 4)
        static let tealGlow:    (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) = (Colors.teal.opacity(0.30), 12, 0, 4)
        static let greenGlow:   (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) = (Colors.forestGreen.opacity(0.30), 12, 0, 4)
    }

    // MARK: - Opacity
    struct Opacity {
        static let transparent: Double = 0.0
        static let veryLight:   Double = 0.05
        static let light:       Double = 0.10
        static let medium:      Double = 0.15
        static let mediumPlus:  Double = 0.20
        static let strong:      Double = 0.30
        static let veryStrong:  Double = 0.50
        static let heavy:       Double = 0.70
        static let veryHeavy:   Double = 0.85
        static let opaque:      Double = 1.0
    }

    // MARK: - Border Width
    struct BorderWidth {
        static let thin:       CGFloat = 0.5
        static let regular:    CGFloat = 1.0
        static let medium:     CGFloat = 1.5
        static let thick:      CGFloat = 2.0
        static let extraThick: CGFloat = 3.0
    }

    // MARK: - Layout
    struct Layout {
        static let fabSize:                 CGFloat = 56
        static let fabOffset:               CGFloat = 20
        static let mapPreviewHeight:        CGFloat = 200
        static let mapSnapshotHeight:       CGFloat = 250
        static let metricCardMinHeight:     CGFloat = 100
        static let cardImageHeight:         CGFloat = 180
        static let progressRingSize:        CGFloat = 180
        static let progressRingLineWidth:   CGFloat = 20
        static let listItemMinHeight:       CGFloat = 60
        static let compactListItemHeight:   CGFloat = 44
        static let iconSmall:               CGFloat = 16
        static let iconMedium:              CGFloat = 24
        static let iconLarge:               CGFloat = 32
        static let iconExtraLarge:          CGFloat = 48
        static let pillHeight:              CGFloat = 32
        static let badgeSize:               CGFloat = 20
        static let touchTargetMinimum:      CGFloat = 44
        static let touchTargetPreferred:    CGFloat = 48
        static let touchTargetMotionMinimum:   CGFloat = 60
        static let touchTargetMotionPreferred: CGFloat = 80
    }
}

// MARK: - View Extensions
extension View {
    /// Lime accent for canvases and bars that are always night pine.
    func darkSurfaceTint() -> some View {
        tint(AppTheme.Colors.DarkMode.accent)
    }

    /// Moss in Light, lime in Dark. Use on light or adaptive content and on system alerts.
    func adaptiveSurfaceTint() -> some View {
        tint(AppTheme.Colors.accent)
    }

    /// Standard dark card — barely raised from background, thin border (Copilot style)
    func primaryCard() -> some View {
        self
            .padding(AppTheme.Spacing.lg)
            .background(AppTheme.Colors.DarkMode.cardBackground)
            .cornerRadius(AppTheme.CornerRadius.large)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
    }

    /// Elevated card — one step up from primary card
    func elevatedCard() -> some View {
        self
            .padding(AppTheme.Spacing.lg)
            .background(AppTheme.Colors.DarkMode.cardBackgroundElevated)
            .cornerRadius(AppTheme.CornerRadius.large)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            )
    }

    /// Action card. Lime fill with pine text and icons. No amber glow.
    func accentCard() -> some View {
        self
            .padding(AppTheme.Spacing.lg)
            .foregroundColor(AppTheme.Colors.pine)
            .background(AppTheme.Colors.strideLime)
            .cornerRadius(AppTheme.CornerRadius.large)
    }

    /// Surface card — theme-aware, for nested content
    func surfaceCard() -> some View {
        modifier(SurfaceCardModifier())
    }

    /// Orange / amber variant (alias)
    func orangeCard() -> some View { accentCard() }

    /// Teal card
    func tealCard() -> some View {
        self
            .padding(AppTheme.Spacing.lg)
            .background(AppTheme.Colors.teal)
            .cornerRadius(AppTheme.CornerRadius.large)
            .shadow(color: AppTheme.Colors.teal.opacity(0.30), radius: 10, x: 0, y: 4)
    }

    /// Purple card
    func purpleCard() -> some View {
        self
            .padding(AppTheme.Spacing.lg)
            .background(AppTheme.Colors.deepPurple)
            .cornerRadius(AppTheme.CornerRadius.large)
            .shadow(color: AppTheme.Colors.deepPurple.opacity(0.30), radius: 10, x: 0, y: 4)
    }

    /// Green card
    func greenCard() -> some View {
        self
            .padding(AppTheme.Spacing.lg)
            .background(AppTheme.Colors.forestGreen)
            .cornerRadius(AppTheme.CornerRadius.large)
            .shadow(color: AppTheme.Colors.forestGreen.opacity(0.30), radius: 10, x: 0, y: 4)
    }

    /// Glass card
    func glassCard() -> some View {
        self
            .padding(AppTheme.Spacing.lg)
            .background(.ultraThinMaterial)
            .background(Color.black.opacity(0.3))
            .cornerRadius(AppTheme.CornerRadius.large)
    }

    /// Glass card with a lime edge for calls to action.
    func glassCardAccent() -> some View {
        self
            .padding(AppTheme.Spacing.lg)
            .background(.ultraThinMaterial)
            .background(AppTheme.Colors.strideLime.opacity(0.12))
            .cornerRadius(AppTheme.CornerRadius.large)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                    .stroke(AppTheme.Colors.strideLime.opacity(0.25), lineWidth: 1)
            )
    }

    func frostedGlass() -> some View {
        self.background(.regularMaterial).cornerRadius(AppTheme.CornerRadius.large)
    }

    func glassCardLight() -> some View {
        self
            .padding(AppTheme.Spacing.lg)
            .background(.ultraThinMaterial)
            .background(Color.white.opacity(0.7))
            .cornerRadius(AppTheme.CornerRadius.large)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    // MARK: - Buttons
    func primaryButton() -> some View {
        self
            .font(AppTheme.Typography.bodyBold)
            .foregroundColor(AppTheme.Colors.pine)
            .padding(.horizontal, AppTheme.Spacing.xl)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(AppTheme.Colors.strideLime)
            .cornerRadius(AppTheme.CornerRadius.large)
    }

    func secondaryButton() -> some View {
        self
            .font(AppTheme.Typography.bodyBold)
            .foregroundColor(Color.white)
            .padding(.horizontal, AppTheme.Spacing.xl)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(AppTheme.Colors.DarkMode.cardBackground)
            .cornerRadius(AppTheme.CornerRadius.large)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    func tertiaryButton() -> some View {
        self
            .font(AppTheme.Typography.bodyBold)
            .foregroundColor(AppTheme.Colors.accent)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.sm)
    }

    func destructiveButton() -> some View {
        self
            .font(AppTheme.Typography.bodyBold)
            .foregroundColor(.white)
            .padding(.horizontal, AppTheme.Spacing.xl)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(AppTheme.Colors.error)
            .cornerRadius(AppTheme.CornerRadius.large)
    }

    // MARK: - Shadow
    func themeShadow(_ level: ShadowLevel = .medium) -> some View {
        let s: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat)
        switch level {
        case .veryLight:  s = AppTheme.Shadows.veryLight
        case .light:      s = AppTheme.Shadows.light
        case .medium:     s = AppTheme.Shadows.medium
        case .heavy:      s = AppTheme.Shadows.heavy
        case .extraHeavy: s = AppTheme.Shadows.extraHeavy
        case .accentGlow: s = AppTheme.Shadows.accentGlow
        case .orangeGlow: s = AppTheme.Shadows.orangeGlow
        case .purpleGlow: s = AppTheme.Shadows.purpleGlow
        case .tealGlow:   s = AppTheme.Shadows.tealGlow
        case .greenGlow:  s = AppTheme.Shadows.greenGlow
        }
        return self.shadow(color: s.color, radius: s.radius, x: s.x, y: s.y)
    }
}

// MARK: - Surface Card Modifier
struct SurfaceCardModifier: ViewModifier {
    @ObservedObject private var themeManager = ThemeManager.shared
    func body(content: Content) -> some View {
        content
            .padding(AppTheme.Spacing.md)
            .background(themeManager.isDarkMode
                ? AppTheme.Colors.DarkMode.cardBackground
                : AppTheme.Colors.LightMode.cardBackground)
            .cornerRadius(AppTheme.CornerRadius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                    .stroke(Color.white.opacity(themeManager.isDarkMode ? 0.07 : 0.0), lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(themeManager.isDarkMode ? 0.35 : 0.08),
                radius: themeManager.isDarkMode ? 8 : 4,
                x: 0,
                y: themeManager.isDarkMode ? 4 : 2
            )
    }
}

// MARK: - Shadow Level
enum ShadowLevel {
    case veryLight, light, medium, heavy, extraHeavy
    case accentGlow, orangeGlow, purpleGlow, tealGlow, greenGlow
}

// MARK: - Adaptive Color Helpers
// Theme-aware colors that resolve via UIKit trait collections —
// no ThemeManager dependency required at the call site.
extension AppTheme.Colors {
    static var adaptiveBackground: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(AppTheme.Colors.DarkMode.background)
                : UIColor(AppTheme.Colors.LightMode.background)
        })
    }

    static var adaptiveCardBackground: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(AppTheme.Colors.DarkMode.cardBackground)
                : UIColor(AppTheme.Colors.LightMode.cardBackground)
        })
    }

    static var adaptiveSurfaceBackground: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(AppTheme.Colors.DarkMode.surfaceBackground)
                : UIColor(AppTheme.Colors.LightMode.surfaceBackground)
        })
    }

    static var adaptiveTextPrimary: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(AppTheme.Colors.DarkMode.textPrimary)
                : UIColor(AppTheme.Colors.LightMode.textPrimary)
        })
    }

    static var adaptiveTextSecondary: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(AppTheme.Colors.DarkMode.textSecondary)
                : UIColor(AppTheme.Colors.LightMode.textSecondary)
        })
    }

    static var adaptiveTextTertiary: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(AppTheme.Colors.DarkMode.textTertiary)
                : UIColor(AppTheme.Colors.LightMode.textTertiary)
        })
    }

}

// MARK: - SF Symbols Icons
struct AppIcons {
    static let home         = "house.fill"
    static let activities   = "figure.run"
    static let insights     = "chart.line.uptrend.xyaxis"
    static let leaderboard  = "person.3.fill"
    static let profile      = "person.crop.circle.fill"
    static let eco          = "leaf.fill"
    static let consumption  = "bolt.fill"
    static let carbon       = "cloud.fill"
    static let charity      = "heart.fill"
    static let distance     = "road.lanes"
    static let pace         = "speedometer"
    static let time         = "stopwatch.fill"
    static let consistency  = "calendar.badge.clock"
    static let improving    = "arrow.up.circle.fill"
    static let stable       = "minus.circle.fill"
    static let declining    = "arrow.down.circle.fill"
    static let trophy       = "trophy.fill"
    static let medal        = "medal.fill"
    static let refresh      = "arrow.clockwise"
    static let settings     = "gearshape.fill"
    static let signOut      = "rectangle.portrait.and.arrow.right"
    static let analyze      = "brain.head.profile"
    static let analysis     = "chart.bar.doc.horizontal.fill"
    static let add          = "plus.circle.fill"
    static let edit         = "pencil.circle.fill"
    static let delete       = "trash.fill"
    static let share        = "square.and.arrow.up"
    static let back         = "chevron.left"
    static let forward      = "chevron.right"
    static let up           = "chevron.up"
    static let down         = "chevron.down"
    static let close        = "xmark"
    static let checkmark    = "checkmark.circle.fill"
    static let warning      = "exclamationmark.triangle.fill"
    static let error        = "xmark.circle.fill"
    static let info         = "info.circle.fill"
}
