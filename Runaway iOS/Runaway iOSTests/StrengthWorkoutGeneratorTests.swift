import Foundation
import Testing
@testable import Runaway_iOS

struct StrengthWorkoutGeneratorTests {
    @Test func oneZoneWorkoutKeepsFocusAndPersistsMetadata() throws {
        let workout = try StrengthWorkoutGenerator.generate(request(zones: [.core], duration: 30))

        #expect(workout.exercises.allSatisfy { $0.primaryZone == .core })
        #expect(workout.metadata.focusZones == [.core])
        #expect(workout.metadata.exerciseIDs == workout.exercises.map(\.id))
        #expect(workout.exercises.allSatisfy { $0.targetRIR == 2 })
    }

    @Test func multiZoneWorkoutAllocatesAtLeastSeventyPercentToFocus() throws {
        let workout = try StrengthWorkoutGenerator.generate(
            request(zones: [.chest, .back, .core], duration: 60, equipment: .fullGym)
        )
        let focusSets = workout.exercises
            .filter { workout.metadata.focusZones.contains($0.primaryZone) }
            .reduce(0) { $0 + $1.sets }
        let allSets = workout.exercises.reduce(0) { $0 + $1.sets }

        #expect(Double(focusSets) / Double(allSets) >= 0.7)
        #expect(Set(workout.exercises.map(\.primaryZone)).isSuperset(of: [.chest, .back, .core]))
    }

    @Test(arguments: [StrengthEquipment.bodyweight, .dumbbells, .fullGym, .unspecified])
    func generatedExercisesRespectEquipment(_ equipment: StrengthEquipment) throws {
        let workout = try StrengthWorkoutGenerator.generate(
            request(zones: [.legs, .core], duration: 45, equipment: equipment)
        )
        let resolved = equipment == .unspecified ? StrengthEquipment.bodyweight : equipment

        #expect(workout.exercises.allSatisfy {
            StrengthExerciseCatalog.definition(id: $0.id)?.supportedEquipment.contains(resolved) == true
        })
    }

    @Test func disabledSecondaryZonesAreNeverIntroduced() throws {
        let workout = try StrengthWorkoutGenerator.generate(
            request(zones: [.back], available: [.back, .core], duration: 30, equipment: .fullGym)
        )

        #expect(workout.exercises.allSatisfy { exercise in
            guard let definition = StrengthExerciseCatalog.definition(id: exercise.id) else { return false }
            return definition.secondaryZones.isSubset(of: [.back, .core])
        })
    }

    @Test func compoundPatternsComeBeforeIsolation() throws {
        let workout = try StrengthWorkoutGenerator.generate(
            request(zones: [.shoulders, .arms], duration: 45, equipment: .fullGym)
        )
        let patterns = workout.exercises.compactMap {
            StrengthExerciseCatalog.definition(id: $0.id)?.movementPattern
        }
        let firstIsolation = patterns.firstIndex(of: .isolation)
        let lastCompound = patterns.lastIndex { $0 != .isolation }

        if let firstIsolation, let lastCompound {
            #expect(lastCompound < firstIsolation)
        }
    }

    @Test func durableCoreGoalAddsCoreVolume() throws {
        let baseline = try StrengthWorkoutGenerator.generate(
            request(zones: [.chest, .core], duration: 45, equipment: .fullGym, outcomes: [.leanStrong])
        )
        let durable = try StrengthWorkoutGenerator.generate(
            request(zones: [.chest, .core], duration: 45, equipment: .fullGym, outcomes: [.durableCore])
        )

        #expect(sets(for: .core, in: durable) > sets(for: .core, in: baseline))
    }

    @Test func supportingMovementIsExplained() throws {
        let workout = try StrengthWorkoutGenerator.generate(
            request(zones: [.chest], available: [.chest, .arms, .core], duration: 60, equipment: .fullGym)
        )

        #expect(workout.metadata.supportingZones.count <= 1)
        if !workout.metadata.supportingZones.isEmpty {
            #expect(workout.explanation.localizedCaseInsensitiveContains("support"))
        }
    }

    @Test func shortDurationWithSixZonesReturnsTradeoff() {
        #expect(throws: StrengthWorkoutGenerationError.insufficientDuration(
            minimumMinutes: 45,
            requestedMinutes: 20
        )) {
            try StrengthWorkoutGenerator.generate(
                request(zones: Set(StrengthZone.allCases), duration: 20, equipment: .fullGym)
            )
        }
    }

    private func request(
        zones: Set<StrengthZone>,
        available: Set<StrengthZone> = Set(StrengthZone.allCases),
        duration: Int,
        equipment: StrengthEquipment = .bodyweight,
        outcomes: [AthleteOutcome] = AthleteOutcome.defaults
    ) -> StrengthWorkoutGenerationRequest {
        StrengthWorkoutGenerationRequest(
            selectedZones: zones,
            availableZones: available,
            durationMinutes: duration,
            equipment: equipment,
            experience: .intermediate,
            outcomes: outcomes,
            history: StrengthZoneHistorySnapshot(
                generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                exposures: [:],
                hasUnattributedStrengthWork: false
            ),
            upcomingWorkouts: []
        )
    }

    private func sets(for zone: StrengthZone, in workout: GeneratedStrengthWorkout) -> Int {
        workout.exercises.filter { $0.primaryZone == zone }.reduce(0) { $0 + $1.sets }
    }
}
