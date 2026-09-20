# Runaway Coach Agent Design

**Date:** 2026-09-20  
**Status:** Approved design, awaiting implementation planning

## Purpose

Runaway will become a persistent, proactive training coach rather than an activity recorder. It will observe structured evidence from Apple Health, Apple Watch, Garmin, weather, the athlete's goals, and explicit user input; determine whether the current prescription still fits; safely adapt the plan; and explain every decision.

The product promise is:

> Runaway notices what changed, makes the safest useful adjustment, and shows the athlete exactly why.

Runaway will not record workouts, GPS routes, or live HealthKit workout sessions. External fitness systems remain the evidence sources. Runaway owns prescription, reconciliation, adaptation, explanation, and accountability.

## Product Principles

1. Training mathematics are deterministic, versioned, and testable.
2. Apple Foundation Models may explain decisions but may not create authoritative prescriptions or mutate training state.
3. Safe, bounded adaptations may apply automatically and must remain visible and reversible.
4. Material changes require athlete approval before becoming active.
5. Every decision records its evidence, confidence, effect, and prior state.
6. Raw HealthKit data remains on the device.
7. Supabase coordinates delivery and synchronization; it does not act as the coach.
8. Delayed background execution must degrade gracefully and reconcile on the next available execution opportunity.

## Scope

### Included

- Retirement of Runaway-owned activity recording
- Event-driven coach coordination
- Deterministic plan reevaluation
- Automatic safe adaptations
- Approval-required plan proposals
- Decision history, explanations, and Undo
- HealthKit, Garmin, weather, schedule, profile, and foreground triggers
- Actionable notifications
- On-device conversational explanations
- Widget and App Intent integration
- Deterministic Edge Function scheduling, wake-up, and delivery receipts

### Excluded

- Cloud-hosted or external LLM calls
- Continuous unrestricted background execution
- Medical diagnosis or treatment
- Autonomous changes to goals or race dates
- Automatic increases in weekly training load
- In-app GPS, route, or live workout recording
- A general-purpose chatbot

## Activity Recorder Retirement

Runaway will remove:

- All `Start Activity` entry points
- In-app GPS and workout recording UI
- Run recorder controls and recording state
- HealthKit workout-session creation
- Recording-specific Live Activities
- Recorder-specific notification and deep-link routes
- Recorder-only services once no remaining dependency requires them

Runaway will retain:

- HealthKit and Garmin authorization and imports
- Activity history and activity details
- Imported workout reconciliation
- Duplicate activity protection
- Automatic prescription completion
- Manual completion, partial completion, correction, and unlinking
- Prescription viewing
- Sending structured workouts to Apple Watch where supported

Primary prescription actions will be `View workout`, `Send to Watch`, `Mark complete`, and `Change today`. No Runaway surface will imply that Runaway itself records a workout.

Existing historical activities remain intact. Removing the recorder must not delete or reinterpret prior activity records.

## Architecture

### CoachEvent

`CoachEvent` is a normalized, immutable observation that may justify reevaluation. Each event contains:

- Stable event identifier
- Athlete identifier
- Event type
- Source
- Occurrence time
- Receipt time
- Related workout or decision identifier when applicable
- Source revision or deduplication key
- Minimal structured payload

Initial event types include:

- App foregrounded
- Scheduled check-in reached
- HealthKit workout imported or changed
- Garmin workout imported or changed
- Prescription completed, partially completed, skipped, or corrected
- Planned session elapsed without matching evidence
- Readiness evidence materially changed
- Weather materially changed near a planned outdoor session
- Athlete availability changed
- Goal or profile changed
- Athlete manually requested reevaluation
- Coach proposal accepted, rejected, or undone

### CoachCoordinator

`CoachCoordinator` owns event ingestion and orchestration. It:

1. Validates event ownership and structure.
2. Deduplicates already processed events.
3. Loads the latest protected training snapshot.
4. Rejects stale processing attempts.
5. Determines whether reevaluation is necessary.
6. Builds fresh deterministic training inputs.
7. Requests a proposed plan revision from the existing training policies.
8. Passes changes through `CoachAdjustmentPolicy`.
9. Persists the decision before publishing UI or notification updates.
10. Synchronizes Today, Plan, widgets, App Intents, and notifications to the same revision.

The coordinator contains orchestration, not training formulas.

### Deterministic Training Engine

The existing goal-driven engine, progression service, prescription policies, completion evidence, and remaining-week policy remain the mathematical authority.

The engine receives a structured snapshot and returns a structured proposal containing:

- Previous prescription
- Proposed prescription
- Evidence used
- Expected goal effect
- Numerical deltas
- Safety flags
- Missing-data flags
- Policy version

No generated text is accepted as an engine input.

### CoachAdjustmentPolicy

`CoachAdjustmentPolicy` classifies each proposal as:

- `automatic`
- `approvalRequired`
- `blocked`

The policy returns machine-readable reasons and must be deterministic.

### CoachDecisionLedger

The ledger is the authoritative audit history. Each record contains:

- Decision identifier and athlete ownership
- Triggering event identifiers
- Previous and proposed plan revisions
- Evidence summary
- Structured reason codes
- Confidence and missing-data indicators
- Classification
- Current lifecycle state
- Athlete response
- Applied time
- Reversal data
- Notification delivery state
- Engine and policy versions

Lifecycle states include `proposed`, `applied`, `rejected`, `superseded`, `undone`, and `blocked`.

Undo creates a new ledger entry that restores the prior valid revision. History is append-only; records are not silently rewritten.

### CoachNarrator

`CoachNarrator` uses Apple Foundation Models to convert an already completed structured decision into concise natural language.

It may:

- Explain why a workout was selected
- Summarize what changed
- Answer questions about known structured evidence
- Produce short and detailed explanation variants

It may not:

- Change numerical dosage
- Add unsupported evidence
- Modify goals or schedules
- Persist generated claims as authoritative state
- Call a remote model

A deterministic template renderer is always available. If the local model is unavailable, unsupported, times out, or produces invalid output, the template explanation is displayed.

### CoachNotificationRouter

The router converts ledger state into actionable notification categories. Supported actions include:

- Review workout
- Accept changes
- Keep original
- Move later
- Undo

Notification payloads carry opaque decision and revision identifiers. Sensitive health measurements and detailed reasons are loaded after authenticated app launch rather than embedded in push payloads.

## Autonomy Rules

### Automatic Changes

Runaway may automatically:

- Move an easy or recovery session within a nearby safe scheduling window
- Reduce duration, distance, sets, or intensity when recovery evidence deteriorates
- Preserve a missed session's intended stimulus in a safer form
- Adjust pace or effort guidance for a material weather change
- Rebalance running and strength after an unexpected imported workout
- Substitute an equivalent strength movement for available equipment
- Restore a previously reduced session when new evidence supports restoration

Automatic changes must:

- Stay within explicit deterministic bounds
- Never increase total weekly load
- Preserve key-session spacing and recovery constraints
- Create a ledger record
- Notify the athlete
- Include a reason and confidence state
- Offer Undo

### Approval-Required Changes

Runaway requires approval before:

- Replacing or removing a key workout
- Increasing total weekly load
- Moving a key workout outside its safe scheduling window
- Changing a goal, target date, or training phase
- Applying multiple cascading changes across the week
- Resuming intensity after pain, illness, or an extended gap
- Choosing between materially different goal priorities

Until approval, the currently active plan remains authoritative.

### Blocked Changes

Runaway must block a proposal that would:

- Create an unsafe workload spike to compensate for missed training
- Produce unsupported consecutive high-intensity sessions
- Increase load based only on generated language or motivation
- Override pain, illness, or recovery safety signals
- Violate athlete ownership or plan-revision constraints
- Use stale evidence to overwrite a newer plan

## Event and Decision Flow

1. An event is observed locally or delivered as a wake-up signal.
2. The coordinator validates and deduplicates it.
3. A fresh protected training snapshot is loaded.
4. Deterministic policies compare the active plan with current evidence.
5. No meaningful delta produces a logged no-op and no intrusive notification.
6. A meaningful proposal is classified by adjustment policy.
7. An automatic proposal is atomically persisted and applied.
8. An approval-required proposal is persisted without replacing the active plan.
9. A blocked proposal records its safety reason without modifying the plan.
10. The narrator creates an optional local explanation.
11. The notification router publishes the appropriate action.
12. Today, Plan, widgets, and App Intents refresh from the same accepted revision.

## User Experience

### Today

Today presents the active prescription and, when relevant, a concise `Coach changed your plan` treatment. The treatment states what changed and why without displacing the workout itself.

### Plan

Plan shows accepted adaptations inline and clearly distinguishes pending proposals from active schedule changes.

### Coach Decision Detail

The decision detail contains:

- What changed
- Why it changed
- Evidence used
- Effect on the goal
- Confidence and missing information
- Previous plan
- Current plan or proposal
- Approval, rejection, or Undo controls

### Coach Activity

A new Coach activity history provides a human-readable audit trail of observations, decisions, approvals, reversals, blocked changes, and notification delivery. It is not presented as a developer log.

### Conversational Questions

Supported questions are grounded in structured state, including:

- Why this workout today?
- What changed after my last workout?
- What happens if I skip this?
- Can I lift instead?
- How does this advance my goal?
- What information is missing?

The app provides deterministic responses when Apple Foundation Models are unavailable.

## Background Execution and Backend Coordination

iOS background execution is opportunistic. Runaway will not claim continuous execution.

Supabase Edge Functions may:

- Maintain notification schedules
- Send silent wake-up signals
- Deliver visible notifications
- Track delivery acknowledgements
- Synchronize structured plan and decision revisions
- Detect server-known elapsed schedules

Supabase Edge Functions may not:

- Call an external LLM
- Calculate readiness or workout dosage
- Invent or modify prescriptions
- Receive unnecessary raw HealthKit measurements

If iOS delays processing:

- The event remains pending.
- Visible notifications avoid claiming that an unapplied adaptation occurred.
- The next permitted background execution or foreground launch processes pending events chronologically.
- Revision checks prevent delayed work from overwriting newer athlete actions.

## Privacy and Security

- Raw HealthKit measurements remain on-device.
- The backend stores only state required for synchronization and delivery.
- Notification payloads exclude sensitive health data.
- Every mutation verifies athlete ownership.
- Plan updates use revision-based conflict protection.
- Apple Foundation Models receive minimized structured summaries.
- No external LLM endpoint, key, client, or fallback is permitted.
- Approval-required changes cannot be activated by notification delivery alone.
- Decision and action history is visible to the athlete.

Backend-safe fields include plan revision, decision identifier, schedule, delivery status, approval state, and non-sensitive action category.

## Error Handling

- Duplicate events return the existing processing result.
- Invalid or foreign-owned events are rejected and logged securely.
- Stale proposals become `superseded` and cannot apply.
- Partial persistence failures publish no UI or notification state until the authoritative write succeeds.
- Narration failures use deterministic copy.
- Notification failures remain visible in delivery state and retry according to bounded policy.
- Missing weather or readiness data lowers confidence rather than fabricating values.
- Import delays are reconciled when evidence arrives, without duplicating completion.

## Rollout Sequence

1. Remove activity recording and preserve import-only evidence flows.
2. Add event, decision, classification, and ledger models.
3. Add coordinator orchestration around existing training policies.
4. Add automatic safe adaptations and Undo.
5. Add approval-required proposals and notification actions.
6. Add HealthKit, Garmin, weather, schedule, and foreground triggers.
7. Add local conversational narration and deterministic fallback.
8. Add Coach decision detail and activity history.
9. Extend widgets and App Intents with accepted decision state.
10. Add deterministic Edge Function wake-up coordination and delivery receipts.

## Testing Strategy

Unit and integration coverage must include:

- Event validation and deduplication
- Athlete ownership enforcement
- Automatic, approval-required, and blocked classification
- Revision conflict and stale-proposal handling
- Atomic application and Undo restoration
- Missed-workout adaptation
- Unexpected-workout adaptation
- Partial completion adaptation
- Recovery and weather-driven reduction
- Key-session spacing preservation
- Notification action routing
- Delayed background catch-up
- Narration failure fallback
- HealthKit and Garmin reconciliation
- Consistency across Today, Plan, widgets, and notifications
- Absence of external LLM network paths
- Absence of activity-recording routes and HealthKit workout creation

Physical-device verification must cover HealthKit background delivery, Garmin synchronization, silent and visible push behavior, notification actions, Apple Foundation Models availability states, App Intent routing, widget refresh, and Apple Watch workout handoff where supported.

## Acceptance Criteria

The feature is complete when:

1. No Runaway UI can start or record an activity.
2. Existing activity history and imported completion continue to work.
3. Meaningful evidence changes produce one deduplicated coach decision.
4. Safe changes apply automatically with explanation and Undo.
5. Material changes remain pending until explicit approval.
6. Blocked changes cannot mutate the active plan.
7. Every change is attributable to structured evidence and versioned policy.
8. Today, Plan, widgets, App Intents, and notifications agree on the active revision.
9. Delayed execution catches up without stale overwrites or duplicate adaptations.
10. The app remains useful when local generative narration is unavailable.
11. No external LLM receives athlete data or generates training state.
12. Backend coordination remains deterministic and contains no coaching logic.

