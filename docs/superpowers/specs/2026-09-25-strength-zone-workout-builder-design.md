# Strength Zone Workout Builder Design

**Date:** September 25, 2026  
**Status:** Proposed for implementation  
**Product:** Runaway iOS

## Purpose

Replace movement-by-movement custom strength setup with a zone-first experience. The athlete selects the areas they want to emphasize, and Runaway generates a complete, explainable strength prescription that respects goals, recent training, recovery, running workload, available equipment, and physical limitations.

The feature must make strength planning easier without pretending that incomplete activity data is precise. It must also avoid language or scoring that frames a disability, limitation, or intentionally excluded body area as neglect or failure.

## Success Criteria

- An athlete can select one or more strength zones without choosing individual exercises.
- Runaway recommends appropriate zones based on attributable training history and current context.
- A recommendation explains itself with concise, neutral language.
- Excluded zones are never recommended, scored as overdue, or silently added to a workout.
- The generated workout contains specific exercises, sequence, sets, repetitions, intensity guidance, and rest.
- Generated exercises match the athlete's equipment and structured zone availability.
- Selected zones remain the workout's primary focus; any supporting work is limited and explained.
- The resulting workout continues through the existing week-impact and commitment flow.
- Settings are managed from the main Settings experience, not from the workout-selection sheet.
- Existing users migrate safely without inferred exclusions.

## Evidence Basis

The model follows current resistance-training guidance that prioritizes consistent coverage of major muscle groups, gradual progression, and goal-specific weekly volume. Runaway uses six athlete-facing zones: Chest, Back, Shoulders, Arms, Legs, and Core. Internally, exercises retain movement-pattern metadata so zone selection does not produce an unbalanced list of isolation exercises.

The six zones intentionally combine hips with Legs and abdomen/trunk with Core. This keeps the selection model understandable while preserving more precise exercise metadata underneath.

## Experience Architecture

### Entry

The existing Performance Coach activity catalog continues to offer Strength. Selecting Strength opens the zone-selection stage instead of immediately displaying a generic full-body prescription.

An existing recommended strength workout may preselect the zones represented by that recommendation. Choosing custom strength also enters the same zone-selection stage, ensuring there is only one strength-building model.

### Zone Selection

The screen presents six multi-select tiles:

- Chest
- Back
- Shoulders
- Arms
- Legs
- Core

Each tile contains an original anatomical vector icon. The icons share one simplified, gender-neutral body silhouette and highlight the relevant anatomical region in Runaway amber. Back uses a rear-facing silhouette; the remaining zones use the clearest front or partial-body view. Icons must remain distinguishable at 32 points and must not rely on color alone: silhouette shape and highlighted-region geometry must also differ.

The athlete may select any number of available zones. The interface recommends one to three focus zones for a typical 30-to-60-minute session but does not impose an arbitrary maximum. If the selection cannot receive useful volume within the chosen duration, the generated preview explains the tradeoff and offers either a longer duration or fewer focus zones.

### Recommendation Presentation

When strength focus suggestions are enabled, Runaway may mark one or more tiles with `Coach pick`. A tile can show one short context label:

- `Trained yesterday`
- `3d ago`
- `Low volume`
- `Recovered`
- `No recent data`

Runaway never shows punitive elapsed-time language such as `50 weeks overdue`. History beyond a useful confidence window becomes `No recent data`.

A compact coach note explains the combined recommendation in plain language. Example: `Back + Core fit today best. They support your lean-strength and durable-core goals without adding heavy leg stress before your next run.`

When suggestions are disabled, the same selectable zones remain visible without coach badges, recency labels, or recommendation copy.

### Generated Workout

After zone selection, Runaway creates a concrete prescription containing:

- Workout title and estimated duration
- Selected primary zones
- Ordered exercises
- Primary and supporting zone labels
- Sets and repetition ranges
- Load guidance using known performance evidence, percentage guidance, or RIR/RPE
- Rest intervals
- A concise explanation for any balance movement outside the selected zones

The athlete reviews the prescription before using it. Existing commitment behavior remains intact: a choice that does not alter future work commits directly; a choice that rebalances future sessions shows the existing week-impact review before confirmation.

Exercise swapping is outside the first implementation unless a generated exercise is unavailable because of equipment or a configured limitation. The architecture must permit substitutions later without changing the persisted workout model.

## Settings

The controls live under:

`Settings → Coaching & Personalization → Strength Recommendations`

They are not linked from the strength-selection workflow.

### Strength Focus Suggestions

A global switch controls coach picks, recommendation ordering, contextual recency labels, and recommendation explanations. Turning it off does not disable zone selection or workout generation.

### Available Training Zones

Each zone has an independent inclusion switch. An excluded zone:

- Is not offered as a selectable focus
- Is never recommended
- Receives no deficit or overdue score
- Is never added as supporting work
- Does not reduce a coverage or completeness score
- Can be restored at any time

The settings page explains that exclusions can reflect disability, injury, medical guidance, preference, or any other reason. Runaway does not require the athlete to disclose a reason.

The existing free-text limitations field remains useful for nuance but is not parsed as a safety mechanism. Structured exclusions are the authoritative control for zone availability.

## Domain Model

### StrengthZone

Add a stable Codable enum:

```swift
enum StrengthZone: String, Codable, CaseIterable, Sendable {
    case chest
    case back
    case shoulders
    case arms
    case legs
    case core
}
```

### Strength Recommendation Preferences

Add a versioned value to the athlete training profile:

```swift
struct StrengthRecommendationPreferences: Codable, Equatable, Sendable {
    var suggestionsEnabled: Bool
    var availableZones: Set<StrengthZone>
}
```

Migration defaults:

- `suggestionsEnabled = true`
- `availableZones = Set(StrengthZone.allCases)`

No migration infers an exclusion from missing history, free text, activity frequency, HealthKit data, or an absent benchmark.

### Exercise Definition

Introduce a typed exercise catalog entry separate from the accepted workout's display `Exercise` value:

```swift
struct StrengthExerciseDefinition: Identifiable, Sendable {
    let id: String
    let displayName: String
    let primaryZone: StrengthZone
    let secondaryZones: Set<StrengthZone>
    let movementPattern: StrengthMovementPattern
    let supportedEquipment: Set<StrengthEquipment>
    let unilateral: Bool
    let progressionFamilyID: String
}
```

`StrengthMovementPattern` includes squat, hinge, horizontalPush, verticalPush, horizontalPull, verticalPull, loadedCarry, trunkFlexion, trunkExtension, antiExtension, antiRotation, lateralStability, and isolation.

The catalog uses stable identifiers so performance history survives display-name changes and exercise substitutions.

### Zone Exposure

A completed exercise contributes:

- Full working-set credit to its primary zone
- Partial credit to declared secondary zones
- No credit for warm-up sets
- Reduced or no credit when completion data says the exercise was skipped or substantially incomplete

The exact secondary multiplier is policy-versioned. The initial value is 0.5 and must be covered by tests rather than scattered through UI code.

## Source-of-Truth and Data Integrity

Zone history is derived only when the completed record identifies exercises with stable catalog IDs or can be matched deterministically to an accepted Runaway prescription.

External strength activities that contain only a title and duration are recorded as strength workload but do not credit individual zones. A generic `Strength`, `Weight Training`, or `Full Body` activity cannot be used to infer Chest, Back, Shoulders, Arms, Legs, or Core exposure.

Duplicate-source reconciliation occurs before zone exposure is calculated. Garmin, HealthKit, and app records representing the same workout must not multiply zone volume.

The generated and accepted prescription stores the policy version, selected focus zones, supporting zones, exercise catalog IDs, and intended dose. Completion stores attributable exercise outcomes when available. This creates evidence for future set-volume and dose-response insights without changing the current UI.

## Recommendation Policy

The first version is deterministic and explainable. It does not use a generative model to select zones.

### Eligibility

A zone is eligible only when:

- It is included in `availableZones`.
- Current plan constraints do not prohibit it.
- The generator can produce at least one suitable exercise using available equipment.

### Scoring Inputs

For each eligible zone, compute a policy-versioned score from:

- Attributable working-set volume in the current and prior weeks
- Time since the last attributable meaningful dose
- Active outcomes and strength goals
- Recent same-zone and adjacent-zone workload
- Current recovery/readiness constraints
- Running-plan adjacency, especially hard running and long-run proximity for Legs
- The current week's already planned strength coverage
- Exercise availability for the athlete's equipment

Unknown history lowers confidence; it does not create an extreme recency score.

### Selection and Explanation

The policy returns ranked zone recommendations with reason codes and confidence. UI copy is rendered from controlled templates, not free-form model output. Example reason codes include:

- `goal_support`
- `weekly_volume_gap`
- `well_recovered`
- `protect_upcoming_run`
- `recently_trained`
- `insufficient_history`

Recommendations are advisory. Athlete selection always wins unless a zone has been explicitly excluded.

## Workout Generation Policy

The generator is deterministic and split into independently testable stages:

1. Resolve eligible exercises from equipment and zone availability.
2. Allocate working-set volume across selected focus zones.
3. Choose movement patterns that avoid unnecessary duplication.
4. Add the minimum supporting work required for balance.
5. Order high-skill compound movements before accessory and core work unless the training goal requires another order.
6. Assign sets, repetitions, intensity, and rest from goals, experience, benchmarks, and recent performance.
7. Fit the prescription to the selected duration.
8. Return explanation codes for recommendations and supporting exercises.

For the athlete's current `Lean + Strong` and `Strong, Durable Core` outcomes, the initial policy favors sustainable hypertrophy and strength volume while preserving running quality. It avoids heavy lower-body prescriptions immediately before protected hard or long running sessions.

If benchmarks are missing, the generator can still prescribe an exercise using RIR/RPE guidance. Missing strength benchmarks should no longer block all strength selection; they only prevent precise starting-load prescriptions.

## Error and Empty States

- No zones selected: disable workout generation and explain `Choose at least one focus zone.`
- All zones excluded: explain that no strength zones are currently available and direct the athlete to the main Settings path.
- No compatible exercise for a selected zone: preserve the selection, explain the equipment conflict, and offer compatible equipment or another zone.
- Insufficient history: show `No recent data`; never fabricate recency.
- Generation failure: preserve zone selection and duration so retrying does not discard work.
- Persistence failure: retain the generated draft and show the existing non-destructive commit error state.

## Accessibility

- Every icon has a visible zone name and a VoiceOver label; icons are never the sole identifier.
- Selected state uses checkmarks and accessibility state in addition to amber styling.
- `Coach pick` is exposed as supplementary context, not as part of the zone name.
- Tiles and switches meet a minimum 44-by-44-point target.
- Dynamic Type can reflow the zone grid to one column.
- Reduced Motion removes nonessential selection transitions.
- Color contrast is validated in both light and dark appearance.
- Settings language never assumes why a zone is excluded.

## Visual Design

The zone screen uses Runaway's existing dark performance-coach hierarchy, amber commitment accent, blue secondary actions, rounded surfaces, and compact coaching language. It does not introduce a separate design system.

The anatomical icon family is original vector artwork. It uses a consistent gender-neutral silhouette and highlighted muscle geometry based on the approved visual direction. Raster concept art is not shipped. Each icon is reviewed at native tile size, in selected and unselected states, and in both app appearances.

## Components and Boundaries

- `StrengthZone`: stable athlete-facing taxonomy.
- `StrengthExerciseCatalog`: exercise metadata and equipment eligibility.
- `StrengthZoneHistoryService`: converts attributable completed exercise work into zone exposure.
- `StrengthZoneRecommendationPolicy`: ranks eligible zones and emits reason codes.
- `StrengthWorkoutGenerator`: builds a concrete prescription from selected zones and context.
- `StrengthZoneSelectionView`: selection-only UI with recommendation context.
- `StrengthRecommendationSettingsView`: main Settings controls.
- Existing `TodayWorkoutDecisionService`: previews week impact and commits the generated draft.

The views do not calculate recommendations or choose exercises. Policies do not read SwiftUI or persistence directly. Services receive explicit snapshots so they remain deterministic and testable.

## Testing Strategy

### Model and Migration Tests

- Existing profiles migrate with suggestions on and all zones available.
- Decoding remains compatible with older profile payloads.
- Exclusions round-trip through local and Supabase persistence.

### Recommendation Tests

- Excluded zones never appear or receive scores.
- Unknown history produces `insufficient_history`, not exaggerated recency.
- Recent attributable work lowers repeat priority.
- Goal-aligned zones receive appropriate support.
- Hard or long upcoming runs reduce heavy Legs priority without permanently excluding Legs.
- Suggestions-off mode returns no UI recommendations while preserving generation capability.

### Generator Tests

- Every generated exercise supports the athlete's equipment.
- Selected zones receive the majority of working-set credit.
- Supporting exercises remain limited and carry explanations.
- Excluded zones receive neither primary nor secondary exposure.
- Prescriptions fit duration budgets or return an explicit tradeoff.
- Missing benchmarks produce RIR/RPE guidance rather than a blocked workout.
- Exercise IDs, sets, reps, and intensity survive preview and commitment.

### Data Integrity Tests

- Generic external strength activities do not infer zone exposure.
- Duplicate activity sources do not duplicate zone volume.
- Exact accepted prescriptions can attribute completed exercise work.
- Partial completion reduces exposure appropriately.

### UI and Accessibility Tests

- Multi-selection, deselection, and selected-state announcements work.
- Dynamic Type reflows without clipping.
- VoiceOver identifies zone, state, recommendation, and recency context.
- Light and dark appearances preserve contrast.
- Settings are reachable from the main Settings hierarchy and absent from the decision-sheet toolbar.

## Rollout

The feature ships behind a local capability flag until profile migration, deterministic generation, and commitment persistence pass. No server-generated recommendation or notification depends on the new zone data during the first release. Existing full-body planned workouts continue to render normally. The new builder applies when the athlete actively chooses or changes to Strength.

After sufficient attributable completions exist, zone exposure may feed the backend insight pipeline. That later integration requires its own validation and does not block this feature.

## Out of Scope

- Free-form AI workout generation
- Automatic medical interpretation of limitations
- Exercise video or coaching media
- Manual exercise-by-exercise workout construction
- Social comparison or normative body-part scoring
- Automatic zone exclusion based on disability inference
- Immediate UI presentation of machine-learning insights

