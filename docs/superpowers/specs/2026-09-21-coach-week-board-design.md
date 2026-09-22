# Coach Week Board Design

**Date:** 2026-09-21  
**Status:** Awaiting written-spec approval

## Purpose

Replace the Plan tab's duplicated Today card and passive weekly timeline with one cohesive Coach Week Board. The board explains how the current week fits together, makes progress and adaptation legible, and routes today's decision back through the unified Performance Coach.

## Product boundary

Each primary tab owns one question:

- **Today:** What should I do now?
- **Plan:** How does this week fit together?
- **Activities:** What work did I actually complete?
- **You:** What inputs and preferences shape the plan?

The Plan tab may explain and navigate every day, but it must not create a second workout-decision system. Only today's row exposes commitment actions, and those actions use `TodayWorkoutDecisionSheet`.

## Consistency review

### Today

Today already owns the authoritative Performance Coach decision surface. Its exact prescription, commitment status, weather context, readiness, and completion behavior remain unchanged. The Week Board must use the same workout titles, dose formatting, commitment metadata, and completion rules.

### Plan

The existing `TodayWorkoutCard` followed by `TrainingWeekTimeline` repeats today while under-explaining the rest of the week. Status language is incomplete, future sessions lack prescription context, and commitment is not visible. These two surfaces will be replaced by one board.

The existing plan-regeneration control remains secondary. It must not visually compete with today's Coach decision or imply that an athlete must regenerate the full week to change today's workout.

### Activities

Activities correctly owns completed and imported evidence. No planning or commitment control will be added there. Week Board completion states link to existing workout/activity details rather than duplicating the activity log.

### You

You remains the source for Training Profile, goals, units, body measurements, notification schedules, and settings. A missing profile input may be explained by the board, but editing it routes to the existing setting rather than embedding profile controls in Plan.

### Coach activity and details

Coach Activity remains the audit trail for recommendations and meaningful changes. The Week Board may label an adapted workout, but detailed reasons live in the existing Coach decision detail. Workout detail sheets remain the destination for prescription and completed-result detail.

## Information architecture

Within the existing Plan tab order:

1. Upcoming race context.
2. Training-plan heading and recent Coach-change banner.
3. Existing compact plan header and baseline context.
4. **Coach Week Board.**
5. Adaptive insights and training principles.

`TodayWorkoutCard` and `TrainingWeekTimeline` are removed from this composition. `WeeklyTrainingPlanView` is not introduced as another route or duplicate surface.

## Coach Week Board

### Header

The board header contains:

- `THIS WEEK` eyebrow and localized week range.
- Completion summary, such as `2 of 5 sessions complete`.
- Planned training time for non-rest workouts.
- A concise weekly focus derived from the existing plan focus or workout mix; no generated claim is invented.

### Seven-day rail

All plan workouts appear in chronological order along one subtle vertical rail. Each row contains:

- Localized weekday and date.
- Modality symbol.
- Workout title.
- Exact relevant dose.
- One canonical status label.
- Optional adaptation note when supported by a recent Coach decision.
- A disclosure indicator only when tapping can reveal meaningful detail.

The rail visually connects the week without turning every day into an isolated card. Today receives the strongest surface shift and spacing; other rows remain quieter.

### Canonical statuses

- **Recommended:** today's uncommitted prescription.
- **Committed:** today's prescription has valid commitment metadata.
- **Completed:** accepted or imported evidence fully satisfies the workout.
- **Partial:** recorded evidence does not satisfy the full prescription.
- **Upcoming:** future prescribed work.
- **Rest:** intentional recovery day.
- **Missed:** a past non-rest workout has no matching evidence.

Status is always communicated by text and symbol, never color alone.

### Dose formatting

- Running: duration, distance, then target pace when available.
- Walking, cycling, and swimming: duration and distance when available; never inherit running pace.
- Strength: duration plus exercise count, with sets/reps/load in detail.
- Mobility, yoga, and cross-training: duration.
- Rest: recovery intent, with no fabricated dose.

All distance formatting uses `UnitPreferences`, while a race-specific unit remains race-owned.

## Interaction model

### Today

- Recommended: primary action `Commit`; secondary action `Change`.
- Committed: primary action `View workout`; secondary action `Change`.
- Completed or partial: primary action `Review result`.
- Rest: `Review recovery day`, with `Change` available through Performance Coach.

Commit and Change present the existing `TodayWorkoutDecisionSheet`. The board does not mutate a plan directly.

### Past days

Completed and partial rows open recorded workout/result detail. Missed rows open planned workout detail with a factual missed-state explanation. They do not offer retroactive commitment.

### Future days

Future rows open prescription detail. Editing future sessions is out of scope for this pass; week changes continue to come from deterministic Coach rebalancing so completed and goal-critical work remains protected.

### Coach adaptations

When a recent `CoachDecision` maps to a workout, the row displays a restrained `Rebalanced` note. Selecting it opens the existing Coach decision detail. If a reliable workout mapping is unavailable, no adaptation badge is shown.

## Visual system

**Human:** an athlete scanning the week before or after training.  
**Task:** understand progress, today's decision, and what comes next in seconds.  
**Feel:** a purposeful training board, earned and athletic rather than administrative.

- **Hierarchy:** today is the focal row through surface, weight, and space rather than a second oversized card.
- **Palette:** graphite foundation; amber for today's decision; blue for upcoming information; mint for earned completion; muted neutral for rest and missed states.
- **Depth:** retain Runaway's low-contrast borders and tonal surface shifts; no new shadow language.
- **Typography:** rounded Runaway hierarchy, tabular numbers for dates and doses, tracked eyebrow labels.
- **Spacing:** existing four-point token scale; compact day rows with stronger separation around today.
- **Motion:** short symbol/status replacement when the plan changes; no continuous animation. Respect Reduce Motion.

## Data and architecture

Create a presentation layer derived from existing data rather than another stored model:

- `CoachWeekBoardPresentation` derives header metrics, day status, dose, tint, and actions from `WeeklyTrainingPlan`, activities, and commitment/completion metadata.
- `CoachWeekBoard` renders the presentation and emits typed user actions.
- `PlanView` owns sheet presentation and routes actions to existing workout detail, result detail, Coach detail, or `TodayWorkoutDecisionSheet`.

No Supabase schema, Edge Function, notification, widget, or recommendation-engine change is required.

## Error and empty states

- Existing loading and no-plan states remain.
- A malformed workout still appears with modality and title; unavailable dose fields are omitted rather than fabricated.
- If the current plan changes while a sheet is open, the existing revision check prevents stale commitment.
- A workout with conflicting completion signals favors accepted completion, then matched activity evidence, then stored `isCompleted`.

## Accessibility

- Each row has a minimum 44-point target.
- VoiceOver order: date, status, modality, workout, exact dose, action.
- Dynamic Type may wrap the title and dose without clipping status.
- The rail is decorative and hidden from accessibility.
- Color is never the sole status indicator.

## Scope

### Included

- Replace Plan's duplicate today/timeline surfaces with Coach Week Board.
- Shared status and dose presentation consistent with Today, widgets, and notifications.
- Today commitment actions routed through Performance Coach.
- Existing workout, result, and Coach-detail destinations.

### Not included

- Editing arbitrary future days.
- New plan-generation algorithms.
- New backend persistence.
- Activities or You redesigns.
- Unifying every legacy workout-detail implementation in this pass.
- Adding another weekly-plan route.

## Acceptance criteria

- The Plan tab shows every day once and today is not duplicated.
- Today clearly displays Recommended, Committed, Partial, or Completed state.
- Every non-rest workout displays a modality-appropriate exact dose without non-running pace.
- Commit and Change use the existing Performance Coach decision flow.
- Completed and partial rows reach result/detail content.
- Activities remains history-only and You remains profile/settings-only.
- The board updates when the authoritative weekly plan changes.
- VoiceOver and Dynamic Type preserve the weekly hierarchy.

