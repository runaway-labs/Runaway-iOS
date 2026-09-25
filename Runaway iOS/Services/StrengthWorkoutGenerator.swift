import Foundation

enum StrengthWorkoutGenerator {
    static let version = "strength-workout-generator-v1"

    static func generate(
        _ request: StrengthWorkoutGenerationRequest
    ) throws -> GeneratedStrengthWorkout {
        guard !request.selectedZones.isEmpty else {
            throw StrengthWorkoutGenerationError.noFocusZones
        }

        if let unavailable = ordered(request.selectedZones).first(where: { !request.availableZones.contains($0) }) {
            throw StrengthWorkoutGenerationError.unavailableZone(unavailable)
        }

        let minimumMinutes = max(20, request.selectedZones.count * 7 + 3)
        guard request.durationMinutes >= minimumMinutes else {
            throw StrengthWorkoutGenerationError.insufficientDuration(
                minimumMinutes: minimumMinutes,
                requestedMinutes: request.durationMinutes
            )
        }

        let catalog = StrengthExerciseCatalog.exercises(
            equipment: request.equipment,
            availableZones: request.availableZones
        )
        for zone in ordered(request.selectedZones) where !catalog.contains(where: { $0.primaryZone == zone }) {
            throw StrengthWorkoutGenerationError.noCompatibleExercise(zone)
        }

        let desiredExerciseCount = min(
            request.durationMinutes >= 60 ? 7 : request.durationMinutes >= 45 ? 5 : 3,
            catalog.count
        )
        var chosen: [StrengthExerciseDefinition] = []
        var usedPatterns = Set<StrengthMovementPattern>()
        var usedFamilies = Set<String>()

        let focusZoneOrder = ordered(request.selectedZones).sorted { lhs, rhs in
            let lhsCompound = catalog.contains { $0.primaryZone == lhs && $0.movementPattern != .isolation }
            let rhsCompound = catalog.contains { $0.primaryZone == rhs && $0.movementPattern != .isolation }
            if lhsCompound != rhsCompound { return lhsCompound }
            return zoneIndex(lhs) < zoneIndex(rhs)
        }

        for zone in focusZoneOrder {
            let candidates = catalog.filter { $0.primaryZone == zone }
            guard let exercise = bestCandidate(
                from: candidates,
                usedPatterns: usedPatterns,
                usedFamilies: usedFamilies
            ) else { continue }
            chosen.append(exercise)
            usedPatterns.insert(exercise.movementPattern)
            usedFamilies.insert(exercise.progressionFamilyID)
        }

        let additionalFocus = catalog.filter {
            request.selectedZones.contains($0.primaryZone) && !chosen.contains($0)
        }
        for candidate in sortedCandidates(additionalFocus, usedPatterns: usedPatterns, usedFamilies: usedFamilies) {
            guard chosen.count < desiredExerciseCount else { break }
            chosen.append(candidate)
            usedPatterns.insert(candidate.movementPattern)
            usedFamilies.insert(candidate.progressionFamilyID)
        }

        var supportingIDs = Set<String>()
        if request.durationMinutes >= 60, chosen.count < desiredExerciseCount {
            let supporting = catalog.filter {
                !request.selectedZones.contains($0.primaryZone) && !chosen.contains($0)
            }
            if let candidate = sortedCandidates(
                supporting,
                usedPatterns: usedPatterns,
                usedFamilies: usedFamilies
            ).first {
                chosen.append(candidate)
                supportingIDs.insert(candidate.id)
            }
        }

        chosen.sort { lhs, rhs in
            let lhsIsolation = lhs.movementPattern == .isolation
            let rhsIsolation = rhs.movementPattern == .isolation
            if lhsIsolation != rhsIsolation { return !lhsIsolation }
            return catalogIndex(lhs.id) < catalogIndex(rhs.id)
        }

        let defaultSets: Int
        switch request.experience {
        case .beginner: defaultSets = 2
        case .intermediate: defaultSets = 3
        case .advanced: defaultSets = 4
        }

        let durableCore = request.outcomes.contains(.durableCore)
        var grantedCoreBonus = false
        let generated = chosen.map { definition -> GeneratedStrengthExercise in
            let supporting = supportingIDs.contains(definition.id)
            var sets = supporting ? 2 : defaultSets
            if durableCore, definition.primaryZone == .core, !supporting, !grantedCoreBonus {
                sets += 1
                grantedCoreBonus = true
            }
            return GeneratedStrengthExercise(
                id: definition.id,
                name: definition.displayName,
                primaryZone: definition.primaryZone,
                secondaryZones: definition.secondaryZones,
                sets: sets,
                repetitions: repetitions(for: definition.movementPattern),
                loadGuidance: loadGuidance(for: request.equipment),
                targetRIR: 2,
                restSeconds: restSeconds(for: definition.movementPattern),
                isSupporting: supporting
            )
        }

        let supportingZones = Set(generated.filter(\.isSupporting).map(\.primaryZone))
        let metadata = StrengthPrescriptionMetadata(
            policyVersion: version,
            focusZones: request.selectedZones,
            supportingZones: supportingZones,
            exerciseIDs: generated.map(\.id)
        )
        let estimatedSeconds = 6 * 60 + generated.reduce(0) {
            $0 + $1.sets * (45 + $1.restSeconds)
        }
        let estimate = Int(ceil(Double(estimatedSeconds) / 60.0))
        let explanation = supportingZones.isEmpty
            ? "Built around your selected focus zones with distinct movement patterns first."
            : "Built around your selected focus zones, with one supporting movement for a balanced session."

        return GeneratedStrengthWorkout(
            exercises: generated,
            estimatedDurationMinutes: estimate,
            metadata: metadata,
            explanation: explanation
        )
    }

    private static func bestCandidate(
        from candidates: [StrengthExerciseDefinition],
        usedPatterns: Set<StrengthMovementPattern>,
        usedFamilies: Set<String>
    ) -> StrengthExerciseDefinition? {
        sortedCandidates(candidates, usedPatterns: usedPatterns, usedFamilies: usedFamilies).first
    }

    private static func sortedCandidates(
        _ candidates: [StrengthExerciseDefinition],
        usedPatterns: Set<StrengthMovementPattern>,
        usedFamilies: Set<String>
    ) -> [StrengthExerciseDefinition] {
        candidates.sorted { lhs, rhs in
            let lhsRank = candidateRank(lhs, usedPatterns: usedPatterns, usedFamilies: usedFamilies)
            let rhsRank = candidateRank(rhs, usedPatterns: usedPatterns, usedFamilies: usedFamilies)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return catalogIndex(lhs.id) < catalogIndex(rhs.id)
        }
    }

    private static func candidateRank(
        _ value: StrengthExerciseDefinition,
        usedPatterns: Set<StrengthMovementPattern>,
        usedFamilies: Set<String>
    ) -> Int {
        var rank = value.movementPattern == .isolation ? 20 : 0
        if usedPatterns.contains(value.movementPattern) { rank += 5 }
        if usedFamilies.contains(value.progressionFamilyID) { rank += 10 }
        return rank
    }

    private static func ordered(_ zones: Set<StrengthZone>) -> [StrengthZone] {
        StrengthZone.allCases.filter(zones.contains)
    }

    private static func zoneIndex(_ zone: StrengthZone) -> Int {
        StrengthZone.allCases.firstIndex(of: zone) ?? 0
    }

    private static func catalogIndex(_ id: String) -> Int {
        StrengthExerciseCatalog.all.firstIndex { $0.id == id } ?? .max
    }

    private static func repetitions(for pattern: StrengthMovementPattern) -> String {
        switch pattern {
        case .antiExtension, .antiRotation, .lateralStability:
            return "30-45 sec"
        case .loadedCarry:
            return "30-40 m/side"
        case .isolation, .trunkFlexion, .trunkExtension:
            return "10-15"
        default:
            return "6-10"
        }
    }

    private static func restSeconds(for pattern: StrengthMovementPattern) -> Int {
        pattern == .isolation ? 60 : 90
    }

    private static func loadGuidance(for equipment: StrengthEquipment) -> String {
        switch equipment {
        case .bodyweight, .unspecified:
            return "Bodyweight or a variation that leaves 2 RIR"
        case .dumbbells:
            return "Choose dumbbells that leave 2 RIR"
        case .fullGym:
            return "Choose a controlled load that leaves 2 RIR"
        }
    }
}
