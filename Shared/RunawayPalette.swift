import SwiftUI

/// Shared Runaway color tokens from runaway-trails `design/tokens.json` v0.2.
/// This file lives in the Shared group, which belongs to both the app and the widget extension.
enum RunawayPalette {
    /// sRGB channel. Pass the 0–255 component so the hex conversion stays exact.
    private static func channel(_ value: Double) -> Double { value / 255.0 }

    // Dark ramp
    static let nightPine = Color(red: channel(12), green: channel(18), blue: channel(16)) // #0C1210
    static let backgroundElevated = Color(red: channel(16), green: channel(24), blue: channel(21)) // #101815
    static let cardBackground = Color(red: channel(19), green: channel(27), blue: channel(24)) // #131B18
    static let cardBackgroundElevated = Color(red: channel(26), green: channel(36), blue: channel(32)) // #1A2420
    static let surfaceBackground = Color(red: channel(34), green: channel(48), blue: channel(41)) // #223029
    static let surfaceElevated = Color(red: channel(40), green: channel(57), blue: channel(49)) // #283931

    // Text on dark
    static let textPrimary = Color(red: channel(243), green: channel(245), blue: channel(239)) // #F3F5EF
    static let textSecondary = Color(red: channel(154), green: channel(165), blue: channel(158)) // #9AA59E
    static let textTertiary = Color(red: channel(142), green: channel(153), blue: channel(146)) // #8E9992

    // Action
    static let strideLime = Color(red: channel(214), green: channel(243), blue: channel(90)) // #D6F35A
    static let strideLimePressed = Color(red: channel(200), green: channel(233), blue: channel(74)) // #C8E94A
    static let pine = Color(red: channel(32), green: channel(46), blue: channel(40)) // #202E28
    static let moss = Color(red: channel(73), green: channel(101), blue: channel(80)) // #496550

    // Identity
    static let amber = Color(red: channel(245), green: channel(158), blue: channel(11)) // #F59E0B

    // Severity. Not amber, and not a weather color.
    // #E2B714 is the dark-surface warning. Light-mode text and icons use warningOnLight.
    static let warning = Color(red: channel(226), green: channel(183), blue: channel(20)) // #E2B714
    static let warningOnLight = Color(red: channel(122), green: channel(98), blue: channel(10)) // #7A620A

    // Informational blue. Named so it is not confused with stride lime.
    static let infoBlue = Color(red: channel(56), green: channel(148), blue: channel(250)) // #3894FA
    static let infoBlueLight = Color(red: channel(102), green: channel(184), blue: channel(255)) // #66B8FF
}
