import Foundation
import Testing
@testable import Runaway_iOS

@MainActor
struct StrengthRecommendationSettingsTests {
    @Test func suggestionsTogglePreservesAvailableZones() {
        let model = AthleteTrainingProfileEditorModel(athleteID: 42)
        let zones = model.draft.resolvedStrengthRecommendations.availableZones

        model.setStrengthSuggestionsEnabled(false)

        #expect(model.draft.resolvedStrengthRecommendations.suggestionsEnabled == false)
        #expect(model.draft.resolvedStrengthRecommendations.availableZones == zones)
    }

    @Test func zonesCanBeExcludedWithoutAReason() {
        let model = AthleteTrainingProfileEditorModel(athleteID: 42)

        model.setStrengthZone(.legs, available: false)

        #expect(!model.draft.resolvedStrengthRecommendations.availableZones.contains(.legs))
        #expect(model.draft.reportedLimitations.isEmpty)
    }

    @Test func everyZoneMayBeExcluded() {
        let model = AthleteTrainingProfileEditorModel(athleteID: 42)

        for zone in StrengthZone.allCases {
            model.setStrengthZone(zone, available: false)
        }

        #expect(model.draft.resolvedStrengthRecommendations.availableZones.isEmpty)
        #expect(model.draft.resolvedStrengthRecommendations.suggestionsEnabled)
    }

    @Test func preferenceRoundTripPreservesExclusions() throws {
        let model = AthleteTrainingProfileEditorModel(athleteID: 42)
        model.setStrengthSuggestionsEnabled(false)
        model.setStrengthZone(.legs, available: false)
        model.setStrengthZone(.shoulders, available: false)

        let data = try JSONEncoder().encode(model.draft)
        let restored = try JSONDecoder().decode(AthleteTrainingProfile.self, from: data)

        #expect(restored.resolvedStrengthRecommendations == model.draft.resolvedStrengthRecommendations)
    }

    @Test func editingDoesNotPretendToSaveOrChangeOwnershipMetadata() {
        let model = AthleteTrainingProfileEditorModel(athleteID: 42)
        let revision = model.draft.revision
        let updatedAt = model.draft.updatedAt

        model.setStrengthZone(.arms, available: false)

        #expect(model.draft.revision == revision)
        #expect(model.draft.updatedAt == updatedAt)
        #expect(model.receipt == nil)
    }
}
