import Foundation

enum StrengthZone: String, Codable, CaseIterable, Identifiable, Sendable {
    case chest
    case back
    case shoulders
    case arms
    case legs
    case core

    var id: String { rawValue }
}

enum StrengthMovementPattern: String, Codable, CaseIterable, Sendable {
    case squat
    case hinge
    case horizontalPush
    case verticalPush
    case horizontalPull
    case verticalPull
    case loadedCarry
    case trunkFlexion
    case trunkExtension
    case antiExtension
    case antiRotation
    case lateralStability
    case isolation
}

struct StrengthRecommendationPreferences: Codable, Equatable, Sendable {
    var suggestionsEnabled: Bool
    var availableZones: Set<StrengthZone>

    static let `default` = StrengthRecommendationPreferences(
        suggestionsEnabled: true,
        availableZones: Set(StrengthZone.allCases)
    )
}
