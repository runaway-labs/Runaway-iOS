# Strength Zone Workout Builder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace movement-by-movement custom strength setup with an accessible multi-select zone builder that recommends focus areas and generates complete, equipment-aware prescriptions.

**Architecture:** Add a stable six-zone domain model and profile preferences, derive trustworthy zone exposure only from attributable exercise records, rank eligible zones with a deterministic policy, and generate workouts from a typed exercise catalog. Keep policy and generation outside SwiftUI; the existing Performance Coach flow consumes snapshots and passes the generated `DailyWorkout` through the current week-impact and commitment services.

**Tech Stack:** Swift 6, SwiftUI, Observation/Combine, Swift Testing, Codable protected profile persistence, Supabase profile JSON sync, Xcode asset catalogs.

**Spec:** `docs/superpowers/specs/2026-09-25-strength-zone-workout-builder-design.md`

## Global Constraints

- Athlete-facing zones are exactly Chest, Back, Shoulders, Arms, Legs, and Core.
- Suggestions are deterministic and template-driven; no generative model selects zones or exercises.
- Excluded zones are never recommended, scored, selected, or added as supporting work.
- Unknown external strength sessions contribute generic workload only and never infer zone exposure.
- Existing profiles migrate with suggestions enabled and every zone available.
- Missing strength benchmarks fall back to RIR/RPE guidance and do not block strength selection.
- Settings live under the main Settings hierarchy and are not linked from the decision sheet.
- The six anatomical icons are original vector assets and remain identifiable without color.
- No backend insight, widget, or notification behavior consumes zone data in this release.

## Review Focus

- A schema-v2 profile with no strength settings decodes and migrates to all zones enabled without data loss; pinned in Task 1 migration tests.
- An athlete who excludes every zone sees a humane empty state and no generator bypass; pinned in Tasks 1, 5, and 7.
- A duration-only Garmin or HealthKit strength activity cannot fabricate zone history; pinned in Task 3 data-integrity tests.
- Selecting many zones in a short duration returns a clear duration/volume tradeoff rather than a token ineffective workout; pinned in Task 5 generator tests.
- Legs may be deprioritized near protected run work but remains selectable when available; pinned in Task 4 recommendation tests and Task 7 UI tests.

---

### Task 1: Strength Zones, Preferences, and Profile Migration

**Files:**
- Create: `Runaway iOS/Models/StrengthZone.swift`
- Modify: `Runaway iOS/Models/AthleteTrainingProfile.swift`
- Modify: `Runaway iOS/Runaway iOSTests/AthleteOutcomeTests.swift`
- Modify: `Runaway iOS/Runaway iOSTests/AthleteTrainingProfileRemoteServiceTests.swift`

**Interfaces:**
- Produces: `StrengthZone`, `StrengthMovementPattern`, `StrengthRecommendationPreferences.default`, and `AthleteTrainingProfile.resolvedStrengthRecommendations`.
- Produces: `AthleteTrainingProfile.migrateStrengthRecommendations()` for explicit schema-v2 migration.
- Consumes: existing `AthleteTrainingProfile` Codable and remote profile round-trip.

- [ ] **Step 1: Write failing model and migration tests**

Add Swift Testing cases that assert all six stable raw values, default availability, exclusion behavior, schema-v2 JSON decoding without the new key, explicit migration to schema version 3, and remote round-trip preservation:

```swift
@Test func legacyProfileMigratesToSafeStrengthDefaults() throws {
    let legacy = """{"schemaVersion":2,"athleteID":94451852,"goals":[],"availability":[],"equipment":[],"reportedLimitations":""}"""
    var profile = try JSONDecoder().decode(AthleteTrainingProfile.self, from: Data(legacy.utf8))
    profile.migrateStrengthRecommendations()
    #expect(profile.schemaVersion == 3)
    #expect(profile.resolvedStrengthRecommendations.suggestionsEnabled)
    #expect(profile.resolvedStrengthRecommendations.availableZones == Set(StrengthZone.allCases))
}

@Test func allZonesMayBeExcludedWithoutInventingAReason() {
    let preferences = StrengthRecommendationPreferences(suggestionsEnabled: true, availableZones: [])
    #expect(preferences.availableZones.isEmpty)
}
```

- [ ] **Step 2: Run the focused tests and confirm failure**

Run:

```bash
xcodebuild test -project "Runaway iOS.xcodeproj" -scheme "Runaway iOS" -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -parallel-testing-enabled NO -only-testing:'Runaway iOSTests/AthleteOutcomeTests' -only-testing:'Runaway iOSTests/AthleteTrainingProfileRemoteServiceTests'
```

Expected: FAIL because the zone and preference types do not exist.

- [ ] **Step 3: Add the domain model and migration**

Create:

```swift
enum StrengthZone: String, Codable, CaseIterable, Identifiable, Sendable {
    case chest, back, shoulders, arms, legs, core
    var id: String { rawValue }
}

enum StrengthMovementPattern: String, Codable, CaseIterable, Sendable {
    case squat, hinge, horizontalPush, verticalPush, horizontalPull, verticalPull
    case loadedCarry, trunkFlexion, trunkExtension, antiExtension, antiRotation
    case lateralStability, isolation
}

struct StrengthRecommendationPreferences: Codable, Equatable, Sendable {
    var suggestionsEnabled: Bool
    var availableZones: Set<StrengthZone>
    static let `default` = Self(suggestionsEnabled: true, availableZones: Set(StrengthZone.allCases))
}
```

Update `AthleteTrainingProfile.currentSchemaVersion` to `3`, add optional persisted `strengthRecommendations`, expose a resolved nonoptional accessor, and migrate only when the field is absent. Keep the stored field optional so synthesized decoding accepts schema-v2 payloads.

- [ ] **Step 4: Validate profile ownership and round-trip behavior**

Extend `validationIssues()` to reject unknown schema versions but allow zero available zones. Update profile load paths to call both `migrateLegacyGoalsToOutcomes()` and `migrateStrengthRecommendations()` before presenting or saving.

- [ ] **Step 5: Run focused tests**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 6: Commit the domain slice**

```bash
git add 'Runaway iOS/Models/StrengthZone.swift' 'Runaway iOS/Models/AthleteTrainingProfile.swift' 'Runaway iOS/Runaway iOSTests/AthleteOutcomeTests.swift' 'Runaway iOS/Runaway iOSTests/AthleteTrainingProfileRemoteServiceTests.swift'
git commit -m 'feat: add strength zone preferences'
```

### Task 2: Typed Strength Exercise Catalog

**Files:**
- Create: `Runaway iOS/Models/StrengthExerciseDefinition.swift`
- Create: `Runaway iOS/Services/StrengthExerciseCatalog.swift`
- Create: `Runaway iOS/Runaway iOSTests/StrengthExerciseCatalogTests.swift`

**Interfaces:**
- Consumes: `StrengthZone`, `StrengthMovementPattern`, and existing `StrengthEquipment`.
- Produces: `StrengthExerciseDefinition` and `StrengthExerciseCatalog.exercises(equipment:availableZones:)`.
- Produces stable exercise IDs used by generation, accepted prescriptions, observations, and exposure history.

- [ ] **Step 1: Write failing catalog tests**

Cover unique IDs, nonempty names, valid primary zones, secondary-zone subset enforcement, equipment filtering, exclusion filtering, and minimum catalog coverage for every zone/equipment combination:

```swift
@Test func excludedZoneCannotLeakThroughSecondaryExposure() {
    let values = StrengthExerciseCatalog.exercises(
        equipment: .fullGym,
        availableZones: [.chest, .arms]
    )
    #expect(values.allSatisfy { [.chest, .arms].contains($0.primaryZone) })
    #expect(values.allSatisfy { $0.secondaryZones.isSubset(of: [.chest, .arms]) })
}
```

- [ ] **Step 2: Run and confirm failure**

```bash
xcodebuild test -project "Runaway iOS.xcodeproj" -scheme "Runaway iOS" -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -parallel-testing-enabled NO -only-testing:'Runaway iOSTests/StrengthExerciseCatalogTests'
```

Expected: FAIL because the catalog does not exist.

- [ ] **Step 3: Implement the definition and catalog API**

```swift
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

enum StrengthExerciseCatalog {
    static let all: [StrengthExerciseDefinition]
    static func definition(id: String) -> StrengthExerciseDefinition?
    static func exercises(equipment: StrengthEquipment, availableZones: Set<StrengthZone>) -> [StrengthExerciseDefinition]
}
```

Populate stable entries for bodyweight, dumbbells, and full-gym variants. Required progression families include push-up/bench press, row, pull-up/pulldown, overhead press, lateral raise, squat, split squat, hinge/RDL, calf raise, curl, triceps extension, hanging knee raise, dead bug, plank, Pallof press, back extension, and loaded carry.

- [ ] **Step 4: Enforce catalog invariants in one initializer check**

Add an internal validator used by tests to ensure IDs and progression family IDs are nonempty, primary zones are never duplicated in secondary zones, and `.unspecified` equipment resolves to bodyweight-safe entries rather than returning an empty catalog.

- [ ] **Step 5: Run the catalog tests**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 6: Commit the catalog slice**

```bash
git add 'Runaway iOS/Models/StrengthExerciseDefinition.swift' 'Runaway iOS/Services/StrengthExerciseCatalog.swift' 'Runaway iOS/Runaway iOSTests/StrengthExerciseCatalogTests.swift'
git commit -m 'feat: add typed strength exercise catalog'
```

### Task 3: Trustworthy Zone Exposure History

**Files:**
- Create: `Runaway iOS/Models/StrengthZoneExposure.swift`
- Create: `Runaway iOS/Services/StrengthZoneHistoryService.swift`
- Create: `Runaway iOS/Runaway iOSTests/StrengthZoneHistoryServiceTests.swift`

**Interfaces:**
- Consumes: catalog IDs from Task 2, `[TrainingObservation]`, `[TrainingSessionResult]`, and `[DailyWorkout]`.
- Produces: `StrengthZoneHistoryService.snapshot(...) -> StrengthZoneHistorySnapshot`.
- Produces: per-zone attributable sets, last-trained date, confidence, and source result IDs.

- [ ] **Step 1: Write failing attribution tests**

Add cases for exact accepted/completed prescriptions, skipped result entries, partial completion, primary set credit, `0.5` secondary credit, duplicate result IDs, and generic external activities. Pin the critical integrity rule:

```swift
@Test func durationOnlyExternalStrengthDoesNotCreateZoneExposure() {
    let snapshot = StrengthZoneHistoryService.snapshot(
        workouts: [], observations: [], sessionResults: [],
        unattributedStrengthDates: [Date(timeIntervalSince1970: 1_800_000_000)]
    )
    #expect(snapshot.exposures.isEmpty)
    #expect(snapshot.hasUnattributedStrengthWork)
}
```

- [ ] **Step 2: Run and confirm failure**

```bash
xcodebuild test -project "Runaway iOS.xcodeproj" -scheme "Runaway iOS" -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -parallel-testing-enabled NO -only-testing:'Runaway iOSTests/StrengthZoneHistoryServiceTests'
```

Expected: FAIL because history types do not exist.

- [ ] **Step 3: Implement exposure values and snapshot**

```swift
struct StrengthZoneExposure: Equatable, Sendable {
    let zone: StrengthZone
    let effectiveWorkingSets: Double
    let lastTrainedAt: Date
    let sourceResultIDs: Set<UUID>
}

struct StrengthZoneHistorySnapshot: Equatable, Sendable {
    let generatedAt: Date
    let exposures: [StrengthZone: StrengthZoneExposure]
    let hasUnattributedStrengthWork: Bool
}
```

The service must deduplicate by result ID and accepted prescription ID before aggregation. Only stable catalog IDs may produce zone exposure. A skipped entry contributes zero. Completed repetitions below half the prescribed lower bound contribute zero; other partial entries scale set credit by completion fraction capped at `1.0`.

- [ ] **Step 4: Add controlled context labels**

Implement `StrengthZoneHistoryPresentation.context(for:now:calendar:)` returning `.trainedYesterday`, `.daysAgo(Int)`, `.lowVolume`, `.recovered`, or `.noRecentData`. Clamp elapsed history beyond 42 days to `.noRecentData`.

- [ ] **Step 5: Run history tests**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 6: Commit the history slice**

```bash
git add 'Runaway iOS/Models/StrengthZoneExposure.swift' 'Runaway iOS/Services/StrengthZoneHistoryService.swift' 'Runaway iOS/Runaway iOSTests/StrengthZoneHistoryServiceTests.swift'
git commit -m 'feat: derive attributable strength zone history'
```

### Task 4: Deterministic Zone Recommendation Policy

**Files:**
- Create: `Runaway iOS/Models/StrengthZoneRecommendation.swift`
- Create: `Runaway iOS/Services/StrengthZoneRecommendationPolicy.swift`
- Create: `Runaway iOS/Runaway iOSTests/StrengthZoneRecommendationPolicyTests.swift`

**Interfaces:**
- Consumes: `AthleteTrainingProfile`, `TrainingProfile`, `WeeklyTrainingPlan`, `StrengthZoneHistorySnapshot`, and a date.
- Produces: `[StrengthZoneRecommendation]` sorted by descending score then stable zone order.
- Produces controlled `StrengthZoneRecommendationReason` values and a combined explanation.

- [ ] **Step 1: Write failing recommendation tests**

Cover exclusions, suggestions disabled, insufficient history, active `.durableCore` and `.leanStrong` outcomes, recent work penalty, current-week volume, and run adjacency. Pin athlete agency:

```swift
@Test func upcomingLongRunDeprioritizesButDoesNotDisableLegs() {
    let recommendations = StrengthZoneRecommendationPolicy.recommendations(for: contextWithTomorrowLongRun)
    let legs = recommendations.first { $0.zone == .legs }
    #expect(legs != nil)
    #expect(legs?.reasons.contains(.protectUpcomingRun) == true)
    #expect(legs?.isSelectable == true)
}
```

- [ ] **Step 2: Run and confirm failure**

```bash
xcodebuild test -project "Runaway iOS.xcodeproj" -scheme "Runaway iOS" -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -parallel-testing-enabled NO -only-testing:'Runaway iOSTests/StrengthZoneRecommendationPolicyTests'
```

Expected: FAIL because recommendation types do not exist.

- [ ] **Step 3: Implement explicit recommendation inputs and outputs**

```swift
enum StrengthZoneRecommendationReason: String, Codable, Sendable {
    case goalSupport, weeklyVolumeGap, wellRecovered, protectUpcomingRun
    case recentlyTrained, insufficientHistory
}

struct StrengthZoneRecommendation: Identifiable, Equatable, Sendable {
    let zone: StrengthZone
    let score: Double
    let reasons: [StrengthZoneRecommendationReason]
    let context: StrengthZoneHistoryContext
    let isSelectable: Bool
    var id: StrengthZone { zone }
}
```

Use one versioned score table in `StrengthZoneRecommendationPolicy.version`. Hard eligibility checks run before scoring. Keep score values internal and show only reason templates in UI.

- [ ] **Step 4: Implement ranking and explanation rules**

Return no recommendations when `suggestionsEnabled` is false. Otherwise select at most two `Coach pick` recommendations, favoring goal support and attributable weekly volume gaps. Penalize recent same-zone work. Apply a Legs penalty near a hard or long run, never an exclusion. Treat missing history as low confidence rather than extreme need.

- [ ] **Step 5: Run recommendation tests**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 6: Commit the recommendation slice**

```bash
git add 'Runaway iOS/Models/StrengthZoneRecommendation.swift' 'Runaway iOS/Services/StrengthZoneRecommendationPolicy.swift' 'Runaway iOS/Runaway iOSTests/StrengthZoneRecommendationPolicyTests.swift'
git commit -m 'feat: recommend strength focus zones'
```

### Task 5: Deterministic Workout Generator and Persisted Metadata

**Files:**
- Create: `Runaway iOS/Models/GeneratedStrengthWorkout.swift`
- Create: `Runaway iOS/Services/StrengthWorkoutGenerator.swift`
- Modify: `Runaway iOS/Models/WeeklyTrainingPlan.swift`
- Modify: `Runaway iOS/Models/AcceptedTrainingPrescription.swift`
- Create: `Runaway iOS/Runaway iOSTests/StrengthWorkoutGeneratorTests.swift`
- Modify: `Runaway iOS/Runaway iOSTests/TodayWorkoutDecisionServiceTests.swift`

**Interfaces:**
- Consumes: selected `Set<StrengthZone>`, duration, catalog, equipment, experience, goals, available zones, history, and upcoming plan.
- Produces: `StrengthWorkoutGenerator.generate(_:) throws -> GeneratedStrengthWorkout`.
- Produces: `StrengthPrescriptionMetadata` persisted on `DailyWorkout` and copied through decision/commitment transforms.

- [ ] **Step 1: Write failing generator tests**

Cover one-zone, multi-zone, all-zone, bodyweight, dumbbell, full-gym, unspecified equipment, missing benchmarks, excluded secondary zones, compound-before-accessory ordering, goal-aware Core volume, supporting-work explanation, and inadequate duration:

```swift
@Test func shortDurationWithSixZonesReturnsTradeoff() {
    #expect(throws: StrengthWorkoutGenerationError.insufficientDuration(
        minimumMinutes: 45,
        requestedMinutes: 20
    )) {
        try StrengthWorkoutGenerator.generate(sixZoneTwentyMinuteRequest)
    }
}
```

- [ ] **Step 2: Run and confirm failure**

```bash
xcodebuild test -project "Runaway iOS.xcodeproj" -scheme "Runaway iOS" -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -parallel-testing-enabled NO -only-testing:'Runaway iOSTests/StrengthWorkoutGeneratorTests' -only-testing:'Runaway iOSTests/TodayWorkoutDecisionServiceTests'
```

Expected: FAIL because generation and metadata do not exist.

- [ ] **Step 3: Implement request, result, and metadata types**

```swift
struct StrengthWorkoutGenerationRequest: Sendable {
    let selectedZones: Set<StrengthZone>
    let availableZones: Set<StrengthZone>
    let durationMinutes: Int
    let equipment: StrengthEquipment
    let experience: TrainingExperience
    let outcomes: [AthleteOutcome]
    let history: StrengthZoneHistorySnapshot
    let upcomingWorkouts: [DailyWorkout]
}

struct StrengthPrescriptionMetadata: Codable, Equatable, Sendable {
    let policyVersion: String
    let focusZones: Set<StrengthZone>
    let supportingZones: Set<StrengthZone>
    let exerciseIDs: [String]
}
```

Add optional `strengthPrescription` to `DailyWorkout` so old cached plans decode safely. Ensure every constructor that transforms or copies a `DailyWorkout` preserves it. Extend accepted prescription storage with optional strength metadata rather than changing existing required fields.

- [ ] **Step 4: Implement deterministic generation**

Allocate at least 70% of effective working sets to selected zones. Choose distinct movement patterns before adding isolation. Add at most one supporting movement unless the duration is 60 minutes or more. Use 2 RIR when no trustworthy load benchmark exists. Compute rest and estimated duration from working sets instead of hardcoding `45`.

- [ ] **Step 5: Preserve metadata through preview and commit**

Update `TodayWorkoutDecisionService`, `WorkoutCommitment`, `RemainingWeekTrainingPolicy`, and any compiler-identified `DailyWorkout` copy sites so strength metadata survives week impact preview, commitment, plan regeneration protection, and Codable round-trip.

- [ ] **Step 6: Run generator and decision tests**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 7: Commit the generator slice**

```bash
git add 'Runaway iOS/Models/GeneratedStrengthWorkout.swift' 'Runaway iOS/Services/StrengthWorkoutGenerator.swift' 'Runaway iOS/Models/WeeklyTrainingPlan.swift' 'Runaway iOS/Models/AcceptedTrainingPrescription.swift' 'Runaway iOS/Services/TodayWorkoutDecisionService.swift' 'Runaway iOS/Models/WorkoutCommitment.swift' 'Runaway iOS/Services/RemainingWeekTrainingPolicy.swift' 'Runaway iOS/Runaway iOSTests/StrengthWorkoutGeneratorTests.swift' 'Runaway iOS/Runaway iOSTests/TodayWorkoutDecisionServiceTests.swift'
git commit -m 'feat: generate zone-based strength workouts'
```

### Task 6: Main Settings Integration

**Files:**
- Create: `Runaway iOS/Views/StrengthRecommendationSettingsView.swift`
- Modify: `Runaway iOS/Views/SettingsView.swift`
- Modify: `Runaway iOS/ViewModels/AthleteTrainingProfileEditorModel.swift`
- Create: `Runaway iOS/Runaway iOSTests/StrengthRecommendationSettingsTests.swift`

**Interfaces:**
- Consumes: profile migration and persistence from Task 1.
- Produces: one main Settings route and bindings for global suggestions plus six availability switches.
- Does not expose a Settings link from any Performance Coach view.

- [ ] **Step 1: Write failing settings-state tests**

Test that toggling suggestions does not alter available zones, excluding a zone does not require a reason, all zones may be excluded, cancellation does not save, save updates revision/time, and round-trip persistence keeps exclusions.

- [ ] **Step 2: Run and confirm failure**

```bash
xcodebuild test -project "Runaway iOS.xcodeproj" -scheme "Runaway iOS" -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -parallel-testing-enabled NO -only-testing:'Runaway iOSTests/StrengthRecommendationSettingsTests'
```

Expected: FAIL because the settings model/view does not exist.

- [ ] **Step 3: Add editor-model mutations**

```swift
func setStrengthSuggestionsEnabled(_ enabled: Bool)
func setStrengthZone(_ zone: StrengthZone, available: Bool)
```

Both mutate `draft.strengthRecommendations`, preserving unrelated profile fields. Saving continues through `AthleteTrainingProfileStore.saveAndSync` and its existing ownership/revision checks.

- [ ] **Step 4: Build the Settings screen**

Create a form titled `Strength recommendations` with a `Strength focus suggestions` switch and an `Available training zones` section. Use human-centered footer copy: `Turn off any zone Runaway should not suggest or include. You never need to provide a reason.` Include a clear all-zones-excluded explanation without blocking Save.

- [ ] **Step 5: Add the main Settings route**

Add `Strength recommendations` under `Your training` in `SettingsView`, below `Training profile`. Subtitle: `Choose focus suggestions and available zones`. Do not add a gear, shortcut, or navigation affordance to `TodayWorkoutDecisionSheet`.

- [ ] **Step 6: Run settings tests**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 7: Commit the settings slice**

```bash
git add 'Runaway iOS/Views/StrengthRecommendationSettingsView.swift' 'Runaway iOS/Views/SettingsView.swift' 'Runaway iOS/ViewModels/AthleteTrainingProfileEditorModel.swift' 'Runaway iOS/Runaway iOSTests/StrengthRecommendationSettingsTests.swift'
git commit -m 'feat: add strength recommendation settings'
```

### Task 7: Zone Selection and Generated Prescription UI

**Files:**
- Create: `Runaway iOS/Views/Coach/StrengthZoneSelectionView.swift`
- Create: `Runaway iOS/Components/StrengthZoneIcon.swift`
- Create: `Runaway iOS/Assets.xcassets/StrengthZones/Chest.imageset/Contents.json`
- Create: `Runaway iOS/Assets.xcassets/StrengthZones/Chest.imageset/strength-zone-chest.svg`
- Create: `Runaway iOS/Assets.xcassets/StrengthZones/Back.imageset/Contents.json`
- Create: `Runaway iOS/Assets.xcassets/StrengthZones/Back.imageset/strength-zone-back.svg`
- Create: matching Shoulder, Arms, Legs, and Core image sets and SVGs
- Modify: `Runaway iOS/Models/TodayWorkoutChoice.swift`
- Modify: `Runaway iOS/Models/TodayWorkoutChoicePolicy.swift`
- Modify: `Runaway iOS/ViewModels/TodayWorkoutDecisionViewModel.swift`
- Modify: `Runaway iOS/Views/Coach/TodayWorkoutDecisionSheet.swift`
- Modify: `Runaway iOS/Runaway iOSTests/TodayWorkoutChoicePolicyTests.swift`
- Modify: `Runaway iOS/Runaway iOSTests/TodayWorkoutDecisionViewModelTests.swift`

**Interfaces:**
- Consumes: profile settings, recommendation output, history snapshot, and generator from Tasks 1–5.
- Produces: `TodayWorkoutDecisionViewModel.strengthSelection`, `strengthRecommendations`, and `generateStrengthDraft(duration:)`.
- Produces: an accessible reusable `StrengthZoneIcon(zone:selected:)`.

- [ ] **Step 1: Write failing decision-state tests**

Pin the flow: selecting Strength enters `.choosingStrengthZones`; selecting multiple zones preserves order-independent state; coach picks preselect only when the athlete explicitly taps them; unavailable zones never appear; Legs remains selectable when merely deprioritized; generation errors preserve selection; and successful generation enters `.editing` with exact exercises.

- [ ] **Step 2: Run and confirm failure**

```bash
xcodebuild test -project "Runaway iOS.xcodeproj" -scheme "Runaway iOS" -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -parallel-testing-enabled NO -only-testing:'Runaway iOSTests/TodayWorkoutChoicePolicyTests' -only-testing:'Runaway iOSTests/TodayWorkoutDecisionViewModelTests'
```

Expected: FAIL because the zone-selection phase does not exist.

- [ ] **Step 3: Extend decision state without duplicating strength paths**

Add `.choosingStrengthZones` to `Phase`. Route both ordinary Strength and `Custom strength` into the same selection state. Remove the hardcoded Squat/Push/Hinge/Pull custom draft. Replace the broad missing-benchmarks blocker with generator fallback guidance.

- [ ] **Step 4: Add original anatomical vector assets**

Create six monochrome template-rendered SVG assets based on the approved anatomical direction. Use a consistent body silhouette, front-facing Chest/Shoulders/Arms/Legs/Core, rear-facing Back, and distinct filled muscle geometry. Verify each at 32 and 44 points before use. Do not ship the raster concept sheet.

- [ ] **Step 5: Build the zone-selection screen**

Use a two-column adaptive grid that becomes one column at accessibility Dynamic Type sizes. Each tile shows icon, visible name, selected checkmark, optional `Coach pick`, and one neutral context label. The primary action reads `Build my workout · N zones` and is disabled at zero selections with the visible message `Choose at least one focus zone.`

- [ ] **Step 6: Update generated prescription presentation**

Show primary/supporting labels, set and rep dose, RIR/load guidance, and rest beneath each generated exercise. Explain a supporting movement in one compact note. Keep the existing `Use this workout` and conditional week-impact flow unchanged.

- [ ] **Step 7: Add accessibility behavior**

Give each tile a combined label/value/hint, expose selected state through `.accessibilityAddTraits(.isSelected)`, retain visible names, meet 44-point targets, and avoid reading `Coach pick` as part of the zone name.

- [ ] **Step 8: Run decision tests**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 9: Commit the UI slice**

```bash
git add 'Runaway iOS/Views/Coach/StrengthZoneSelectionView.swift' 'Runaway iOS/Components/StrengthZoneIcon.swift' 'Runaway iOS/Assets.xcassets/StrengthZones' 'Runaway iOS/Models/TodayWorkoutChoice.swift' 'Runaway iOS/Models/TodayWorkoutChoicePolicy.swift' 'Runaway iOS/ViewModels/TodayWorkoutDecisionViewModel.swift' 'Runaway iOS/Views/Coach/TodayWorkoutDecisionSheet.swift' 'Runaway iOS/Runaway iOSTests/TodayWorkoutChoicePolicyTests.swift' 'Runaway iOS/Runaway iOSTests/TodayWorkoutDecisionViewModelTests.swift'
git commit -m 'feat: add strength zone selection flow'
```

### Task 8: End-to-End Integration and Release Gate

**Files:**
- Modify: `Runaway iOS/Runaway iOSTests/CommitmentIntegrationTests.swift`
- Modify: `Runaway iOS/Runaway iOSTests/TrainingProfileIntegrationTests.swift`
- Modify: `Runaway iOS/Runaway iOSTests/Task7ReliabilityFollowupTests.swift`
- Modify: `Runaway iOS/Runaway iOSUITests/Runaway_iOSUITests.swift`

**Interfaces:**
- Consumes: all earlier tasks.
- Produces: release-level evidence that settings, generation, week recalibration, commitment, completion metadata, and relaunch persistence form one coherent flow.

- [ ] **Step 1: Add end-to-end behavioral tests**

Cover these journeys:

```swift
@Test func selectedZonesGenerateCommitAndSurvivePlanReload() throws
@Test func excludedZoneCannotReturnThroughSupportingWork() throws
@Test func completedGeneratedWorkoutFeedsAttributableZoneHistory() throws
@Test func genericImportedStrengthRemainsUnattributed() throws
@Test func profileMigrationPreservesGoalsAvailabilityEquipmentAndLimitations() throws
```

- [ ] **Step 2: Add UI smoke coverage**

Launch with deterministic fixtures, enter Performance Coach, choose Strength, multi-select Back and Core, generate the prescription, verify exercise rows, commit it, and confirm the Plan screen displays the committed strength workout. Separately navigate through main Settings and verify suggestion and zone switches persist after closing and reopening the screen.

- [ ] **Step 3: Run the focused feature suite**

```bash
xcodebuild test -project "Runaway iOS.xcodeproj" -scheme "Runaway iOS" -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -parallel-testing-enabled NO \
  -only-testing:'Runaway iOSTests/StrengthExerciseCatalogTests' \
  -only-testing:'Runaway iOSTests/StrengthZoneHistoryServiceTests' \
  -only-testing:'Runaway iOSTests/StrengthZoneRecommendationPolicyTests' \
  -only-testing:'Runaway iOSTests/StrengthWorkoutGeneratorTests' \
  -only-testing:'Runaway iOSTests/StrengthRecommendationSettingsTests' \
  -only-testing:'Runaway iOSTests/TodayWorkoutChoicePolicyTests' \
  -only-testing:'Runaway iOSTests/TodayWorkoutDecisionViewModelTests' \
  -only-testing:'Runaway iOSTests/TodayWorkoutDecisionServiceTests' \
  -only-testing:'Runaway iOSTests/CommitmentIntegrationTests' \
  -only-testing:'Runaway iOSTests/TrainingProfileIntegrationTests'
```

Expected: PASS.

- [ ] **Step 4: Run the full unit suite**

```bash
xcodebuild test -project "Runaway iOS.xcodeproj" -scheme "Runaway iOS" -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -parallel-testing-enabled NO -only-testing:'Runaway iOSTests'
```

Expected: PASS with no regressions in plan generation, accepted prescriptions, coach decisions, profile sync, widgets, or notifications.

- [ ] **Step 5: Perform the approved visual and accessibility review**

Build on an iPhone 17 Pro simulator and inspect zone selection, generated prescription, and main Settings in light/dark appearance, default/AX5 Dynamic Type, Reduce Motion, and VoiceOver. Confirm the vector regions remain recognizable at tile size, no white-on-light regressions return, and no Settings affordance appears inside the workout flow.

- [ ] **Step 6: Commit the integration gate**

```bash
git add 'Runaway iOS/Runaway iOSTests/CommitmentIntegrationTests.swift' 'Runaway iOS/Runaway iOSTests/TrainingProfileIntegrationTests.swift' 'Runaway iOS/Runaway iOSTests/Task7ReliabilityFollowupTests.swift' 'Runaway iOS/Runaway iOSUITests/Runaway_iOSUITests.swift'
git commit -m 'test: verify strength zone workout flow'
```

