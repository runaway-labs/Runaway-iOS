# Performance Coach Daily Decision Design

**Date:** 2026-09-21  
**Status:** Awaiting written-spec approval

## Purpose

Runaway currently asks the athlete to make today's training decision through three competing experiences: the Performance Coach recommendation, `Adjust today`, and `Set today's commitment` in Activities. This design consolidates them into one daily decision flow owned by Performance Coach.

The result should make one question unmistakable: **What am I doing today?** Runaway recommends an exact answer, the athlete can choose another complete prescription, and an explicit commitment updates the rest of the product.

## Product principles

1. **One authority:** Today's planned workout is the source of truth for recommendations, commitments, widgets, notifications, and completion matching.
2. **Recommendation is not commitment:** Runaway can recommend without claiming the athlete has agreed. Commitment remains an explicit action.
3. **Agency with consequences:** The athlete can choose any enabled activity, recovery, rest, or a custom workout. Runaway previews the effect on the remaining week before saving.
4. **Never hide constraints:** Unsupported or unsafe-in-context options remain visible and explain why they cannot currently be committed.
5. **History records work:** Activities contains completed and imported evidence, not future intentions.
6. **Protect evidence:** Completed workouts and accepted results are never rewritten by rebalancing.

## Information architecture

### Today

The existing Next Up card becomes the single Performance Coach decision surface. It has four states:

| State | Meaning | Primary action | Secondary action |
|---|---|---|---|
| Recommended | Runaway has generated today's prescription | Commit to this workout | Choose something else |
| Reviewing | The athlete is comparing or editing a prescription | Review week impact | Back to recommendation |
| Committed | The athlete explicitly accepted an exact prescription | View committed workout | Change |
| Completed | Evidence satisfies the committed prescription | Review result | View week |

The card displays:

- Workout name and modality.
- Exact dose: duration, distance, pace only for running, and sets/reps/load for strength.
- The deterministic reason it was selected.
- Readiness or recovery constraint when one affected the decision.
- Commitment status.
- One visually dominant action at a time.

`Adjust today` is removed as a separate row. Its adaptive behavior moves behind `Choose something else` and `Change` inside the Performance Coach card.

### Workout chooser

The chooser is a native sheet using the existing Runaway surface, typography, spacing, and semantic colors. It contains:

1. **Runaway's recommendation** at the top, including its exact prescription and reason.
2. **Your activities**, sourced from enabled Training Profile activities and grouped by modality.
3. **Recovery and rest**, always visible.
4. **Build my own**, for an exact custom prescription.
5. **Unavailable choices**, visible but disabled with a specific reason and a route to the relevant setting when appropriate.

The chooser must not use the old four-case `CommitmentActivityType` as its catalog. It uses `WorkoutType` and Training Profile preferences so running, walking, strength, cycling, swimming, yoga, cross-training, recovery, and rest remain available when configured.

### Prescription editor

Selecting a choice creates an editable draft, never an immediate plan mutation.

- Running: duration and/or distance, plus an optional calibrated pace target.
- Walking, cycling, swimming, yoga, cross-training: duration and optional distance where meaningful.
- Strength: focus, duration, exercises, sets, reps, and load.
- Rest and recovery: intent and optional recovery guidance; no fabricated pace or distance.
- Custom: modality first, then the fields valid for that modality.

The draft is validated before Runaway offers commitment. Required prescription fields come from existing complete-prescription policies where available.

### Week-impact preview

Before commitment, the sheet shows a compact before/after preview:

- Today: current workout → proposed workout.
- Sessions moved later in the week.
- Sessions reduced or removed.
- Goal-critical and completed sessions protected.
- Weekly running volume and training-day changes.
- A plain-language reason for each meaningful change.

The final action reads `Commit to [workout name]`. Nothing is persisted before this action.

### Activities

`CompactCommitmentCard` is removed from Activities. Activities remains a record of completed/imported work with filtering, totals, and activity details.

Commitment completion may be represented on the matching activity detail or Today completion state, but no future-action control appears in Activities.

## Data model

### Authoritative commitment

Add optional commitment metadata to `DailyWorkout`:

```swift
struct WorkoutCommitment: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case recommendation
        case alternative
        case custom
    }

    let committedAt: Date
    let source: Source
    let prescriptionFingerprint: String
    let originalWorkoutID: String?
}
```

`DailyWorkout.commitment` is the authoritative statement of intent. The fingerprint covers all prescription-defining fields so a later edit cannot incorrectly appear to retain the original commitment.

If a committed workout changes, the app creates a new commitment timestamp and fingerprint after the athlete approves the updated week impact.

Completion remains derived from accepted completion data and imported activity evidence. It is not manually stored inside commitment metadata.

### Legacy `daily_commitments`

New Performance Coach actions stop writing standalone `daily_commitments` records. Existing records remain readable during transition but do not override a committed `DailyWorkout`.

Compatibility behavior:

1. A current-plan workout with commitment metadata always wins.
2. If no plan commitment exists, an unfulfilled legacy commitment may be displayed only as a migration prompt inside Performance Coach.
3. Accepting the migration maps the legacy activity to a complete workout draft and requires confirmation.
4. Historical legacy rows are not deleted automatically.
5. The Activities commitment card and old creation/edit sheets become unreachable before their implementation is removed in a later cleanup.

No destructive database migration is required for the first release.

## Decision and rebalancing architecture

Introduce one orchestration boundary, `TodayWorkoutDecisionService`, responsible for:

1. Building the complete set of candidate choices from Training Profile.
2. Creating a fully specified draft for the selected modality.
3. Asking the existing adaptive policy for a candidate rebalanced week.
4. Producing a deterministic `TodayWorkoutDecisionPreview` containing before/after changes and blockers.
5. Validating that the active plan revision still matches the preview.
6. Applying the rebalanced plan with commitment metadata in one plan update.
7. Requesting workout-prompt and widget synchronization after success.

The service does not own UI and does not generate prescriptions through an LLM. Existing deterministic policies produce the workout and plan changes; on-device intelligence may explain those facts without altering quantities.

### Atomicity and stale data

The plan revision captured when previewing is checked again when committing.

- If unchanged, apply the previewed plan.
- If changed, do not partially save. Rebuild the preview and tell the athlete what changed.
- If plan persistence fails, retain the draft in memory and offer retry.
- Widget and notification publication happen only after the plan update succeeds.
- A downstream sync failure does not roll back the plan; it shows a retryable sync status and requests synchronization when the app next becomes active.

## Completion matching

Imported activity evidence is matched against the committed workout using existing semantic activity categories and completion policies.

- Correct modality and sufficient evidence: completed.
- Partial prescribed work: partial completion where supported.
- Different activity: recorded in Activities but does not silently satisfy the commitment.
- Manually accepted completion: uses the existing accepted-completion path.

Existing celebrations remain, but they trigger from the transition of the committed workout to completed rather than from a separate `daily_commitments` row.

## Notifications and widgets

Both surfaces read the same committed workout used by Today.

### Notifications

- Before commitment: recommend today's current prescription.
- After commitment: reinforce the committed workout and exact dose.
- After completion: suppress redundant workout reminders.
- After a committed-workout change: publish the new prescription revision.

### Widget

- Recommended state: `UP NEXT` with the recommended workout.
- Committed state: `COMMITTED` with the exact workout and dose.
- Completed state: accomplishment-focused completion treatment.
- No running pace for non-running modalities.

The existing shared widget snapshot remains the transport; commitment metadata changes its presentation and AppIntent actions.

## App Intents

Widget and notification intents should route into the same decision flow:

- `CommitWorkoutIntent`: commits only the currently published recommendation revision.
- `ReviewWorkoutOptionsIntent`: opens the chooser without changing the plan.
- `ViewCommittedWorkoutIntent`: opens the committed workout detail.

An intent with a stale plan revision opens Runaway for review rather than applying an outdated prescription.

## Visual system

**Human:** an athlete checking the app shortly before deciding how to train.  
**Task:** understand one exact recommendation, choose deliberately, and commit.  
**Feel:** decisive and energizing, like a coach handing over today's card, without pressure or clutter.

- **Hierarchy:** workout prescription is the focal point; commitment is the only dominant action.
- **Palette:** existing graphite/night surfaces; amber for decisions; blue for information and navigation; green for recovery/completion status.
- **Depth:** existing low-contrast borders and surface shifts; no new shadow language.
- **Typography:** existing rounded Runaway hierarchy; exact quantities use tabular numerals.
- **Spacing:** existing 4-point-derived theme scale; tightly group prescription facts and separate decision controls with larger section spacing.
- **Motion:** short state transition after commitment and existing celebration behavior after completion; respect reduced motion.

## Accessibility

- Every action has at least a 44-point hit area.
- VoiceOver reads modality, workout, exact dose, reason, status, and action in that order.
- Disabled choices expose their blocker and are not communicated by color alone.
- Dynamic Type may wrap prescription details without clipping the primary action.
- Commitment and completion states use text and symbols in addition to color.

## Analytics

Track the decision funnel without recording sensitive prescription text:

- Recommendation viewed.
- Chooser opened.
- Alternative selected by modality and source.
- Custom draft created.
- Preview blocked and blocker category.
- Recommendation committed.
- Alternative committed.
- Commitment changed.
- Commitment completed or partially completed.
- Plan/widget/notification synchronization failure.

Existing commitment analytics may be retained as aliases during transition, then renamed after dashboards are updated.

## Testing

### Policy and model tests

- Fingerprint changes when any prescription-defining field changes.
- Every enabled Training Profile activity produces visible candidates.
- Rest and recovery remain visible.
- Unsupported candidates expose deterministic blockers.
- Completed sessions survive rebalancing unchanged.
- Goal-critical sessions move or produce an explicit blocker rather than disappearing silently.
- Stale plan revisions cannot commit.
- Running pace never appears for non-running workouts.

### Integration tests

- Commit the original recommendation.
- Select and commit each supported modality.
- Build and commit custom running and strength prescriptions.
- Change an existing commitment and rebalance again.
- Match full, partial, mismatched, and duplicate imported activity evidence.
- Verify notification and widget snapshots use the committed revision.
- Verify a sync failure leaves the committed plan intact and retryable.
- Verify legacy commitment migration does not overwrite a plan commitment.

### UI tests

- Activities has no commitment card.
- Today exposes one decision surface and no separate `Adjust today` row.
- The chooser displays all profile-enabled activities and explained disabled choices.
- The week-impact preview is reachable before commitment.
- Recommended, committed, and completed states have correct primary actions.
- Dynamic Type and VoiceOver preserve the decision hierarchy.

## Rollout sequence

1. Add commitment metadata, fingerprinting, and decision-preview models.
2. Add the orchestration service around existing deterministic policies.
3. Build the unified chooser, prescription editor, and impact preview.
4. Replace `Adjust today` with integrated Performance Coach actions.
5. Remove the Activities commitment entry point.
6. Switch widgets, notifications, completion matching, and celebrations to plan commitment metadata.
7. Add legacy commitment migration behavior.
8. Run focused policy/integration tests, full build, simulator flow, and physical-device notification/widget checks.

## Out of scope

- Rebuilding Training Profile.
- Introducing external LLM APIs.
- Deleting historical `daily_commitments` rows.
- Replacing the full weekly-plan algorithm.
- Redesigning Activities beyond removing future-action UI.
- Starting or recording a live workout from Runaway.
