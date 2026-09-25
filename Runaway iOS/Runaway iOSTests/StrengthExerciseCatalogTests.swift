import Testing
@testable import Runaway_iOS

@Suite("Strength exercise catalog")
struct StrengthExerciseCatalogTests {
    @Test("Catalog identifiers and definitions are stable and valid")
    func catalogInvariants() {
        let values = StrengthExerciseCatalog.all

        #expect(!values.isEmpty)
        #expect(Set(values.map(\.id)).count == values.count)
        #expect(values.allSatisfy { !$0.id.isEmpty && !$0.displayName.isEmpty })
        #expect(values.allSatisfy { !$0.progressionFamilyID.isEmpty })
        #expect(values.allSatisfy { !$0.secondaryZones.contains($0.primaryZone) })
        #expect(StrengthExerciseCatalog.validationIssues().isEmpty)
    }

    @Test("Every supported setup covers every strength zone")
    func everyEquipmentSetupCoversEveryZone() {
        for equipment in [StrengthEquipment.bodyweight, .dumbbells, .fullGym] {
            let values = StrengthExerciseCatalog.exercises(
                equipment: equipment,
                availableZones: Set(StrengthZone.allCases)
            )

            for zone in StrengthZone.allCases {
                #expect(values.contains { $0.primaryZone == zone })
            }
            #expect(values.allSatisfy { $0.supportedEquipment.contains(equipment) })
        }
    }

    @Test("Excluded zones never leak through secondary exposure")
    func excludedZoneCannotLeakThroughSecondaryExposure() {
        let allowed: Set<StrengthZone> = [.chest, .arms]
        let values = StrengthExerciseCatalog.exercises(
            equipment: .fullGym,
            availableZones: allowed
        )

        #expect(values.allSatisfy { allowed.contains($0.primaryZone) })
        #expect(values.allSatisfy { $0.secondaryZones.isSubset(of: allowed) })
    }

    @Test("Unspecified equipment resolves to bodyweight-safe exercises")
    func unspecifiedEquipmentIsBodyweightSafe() {
        let zones = Set(StrengthZone.allCases)
        let unspecified = StrengthExerciseCatalog.exercises(
            equipment: .unspecified,
            availableZones: zones
        )

        #expect(!unspecified.isEmpty)
        #expect(unspecified.allSatisfy { $0.supportedEquipment.contains(.bodyweight) })
    }

    @Test("Definitions can be resolved by their stable identifier")
    func definitionLookup() throws {
        let first = try #require(StrengthExerciseCatalog.all.first)
        #expect(StrengthExerciseCatalog.definition(id: first.id) == first)
        #expect(StrengthExerciseCatalog.definition(id: "not-a-real-exercise") == nil)
    }
}
