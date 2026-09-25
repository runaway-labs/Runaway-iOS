import Foundation

struct StrengthExerciseDefinition: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let primaryZone: StrengthZone
    let secondaryZones: Set<StrengthZone>
    let movementPattern: StrengthMovementPattern
    let supportedEquipment: Set<StrengthEquipment>
    let unilateral: Bool
    let progressionFamilyID: String
}
