# Unified Athlete State Engine

Date: 2026-09-22
Status: Approved design

## Purpose

Runaway will turn imported Garmin and Apple Health evidence into a versioned, explainable athlete state and use that state to produce goal-specific daily prescriptions and adaptive weekly plans. The engine is deterministic. Apple Foundation Models may explain a decision conversationally, but cannot create, replace, or intensify a prescription.

This replaces the current fragmented path in which readiness is calculated primarily from HealthKit, training load is approximated from duration and running pace, goal previews do not drive the active scheduler, and scheduled notifications can only reuse a previously published recommendation.

## Product outcomes

- Prescribe a complete session with time, distance or sets, intensity, recovery, and a reason tied to current evidence.
- Keep recommendations current when the iPhone app has not been opened.
- Adapt the rest of the week after a completed, missed, shortened, extended, or substituted session.
- Treat running and strength as equal first-class goals while supporting cycling, swimming, walking, mobility, and recovery work.
- Explain which measurements affected a decision, which were missing, and how confident the engine is.
- Preserve the exact source evidence used for every calculation and make decisions reproducible by policy version and input fingerprint.

## Non-goals

- Diagnose illness, overtraining, injury, or medical conditions.
- Predict injury from an acute-to-chronic workload ratio.
- Use VO2 max as a direct substitute for demonstrated running performance.
- Let a language model invent training mathematics or override safety constraints.
- Redesign the current interface during the data and shadow-evaluation stages.

## Core principles

1. Missing data lowers confidence; it never lowers readiness by itself.
2. Recovery evidence may maintain or reduce planned intensity, but may not promote an unplanned hard session.
3. A goal supplies direction. Demonstrated capacity supplies the starting point.
4. Fitness, fatigue, recovery, and goal progression remain separate signals rather than being hidden inside one unexplained score.
5. Every fallback is identified as a fallback and carries lower confidence.
6. Exact provider values remain immutable in raw evidence. Normalized values are derived, versioned, and replaceable.

## Source precedence and deduplication

Garmin is authoritative for data produced by the connected Fenix device. Apple Health fills gaps after duplicate detection.

Deduplication order:

1. Match an existing provider and external activity identifier.
2. Match a previously recorded cross-provider identity when available.
3. Otherwise compare athlete, modality, start time, elapsed duration, and distance using conservative tolerances.
4. If a probable duplicate cannot be resolved safely, retain both records but exclude the lower-confidence record from training mathematics and flag it for reconciliation.

The engine must never sum both a Garmin activity and its Apple Health mirror. Source provenance, raw provider identifier, exclusion reason, and deduplication confidence remain queryable.

For same-day recovery measurements, Garmin wins when it contains the Fenix-derived measurement. Apple Health may fill a metric that Garmin did not supply; it must not overwrite a present Garmin metric merely because it arrived later.

## Data flow

1. Garmin webhook and backfill deliveries store raw provider evidence idempotently.
2. Apple Health sync stores normalized evidence with source identifiers.
3. Evidence normalization assigns local calendar day, modality, provenance, and deduplication state.
4. A training-load calculation is produced for every eligible completed activity.
5. A daily athlete-state calculation updates fitness, fatigue, recovery signals, confidence, and current performance evidence.
6. The planner evaluates goals, availability, current phase, recent completion, and athlete state.
7. A versioned daily prescription and remaining-week proposal are published atomically.
8. Notification, app, widget, and App Intent consumers read the same published prescription.
9. Apple Foundation Models may turn the structured reasons into natural language on device. Structured values and decisions remain unchanged.

Recalculation is triggered after Garmin ingestion, Apple Health sync, profile or goal edits, workout completion reconciliation, and before scheduled recommendation notifications. A scheduled repair job recomputes stale or interrupted states.

## Activity training load

Every eligible session produces:

- `load_value`
- `load_method`
- `load_confidence`
- `policy_version`
- `input_fingerprint`
- modality-specific progression evidence
- structured limitations and fallback reasons

### Method precedence

1. User-recorded session RPE: `duration_minutes * RPE`, using a 1-10 scale.
2. Heart-rate-zone load when valid zone durations and personal heart-rate bounds exist.
3. Heart-rate-reserve estimate when average heart rate, resting heart rate, and credible maximum heart rate exist.
4. Modality-specific conservative duration estimate.

An inferred heart-rate effort is not labeled as user RPE. Each method is calibrated onto a session-load scale but retains its method so unlike evidence is not presented as equally precise.

### Modality rules

- Running and cycling retain duration, distance, elevation, pace or speed, heart rate, and workout structure.
- Strength retains exercise, sets, repetitions, external load, load convention, and RIR or RPE. Hard sets and exercise-specific volume drive strength progression; cardiovascular load alone cannot represent a strength session.
- Swimming uses duration, distance, stroke evidence, and heart rate when available.
- Walking and mobility contribute low training load and active-recovery evidence. They do not satisfy a run or strength prescription unless the plan explicitly prescribed that modality.
- Unsupported or ambiguous activities may count toward total activity time but do not satisfy a goal-specific prescription automatically.

Load values are rounded only for presentation where appropriate. Calculations retain full floating-point precision, and exact Garmin values remain in raw evidence.

## Fitness and fatigue

Daily eligible session load is accumulated without using an acute-to-chronic ratio as a causal injury predictor.

Two exponentially weighted histories are maintained:

- Fitness: 42-day half-life.
- Fatigue: 7-day half-life.

For a daily load `x` and half-life `h`:

`alpha = 1 - exp(-ln(2) / h)`

`state_today = alpha * x + (1 - alpha) * state_yesterday`

Training balance is the difference between fitness and fatigue. Recent ramp is shown as a descriptive change against the athlete's own established history. These values guide plan spacing and tapering; they must not be described as injury probabilities or medical risk scores.

When fewer than 28 days of load history exist, the engine reports a provisional state with reduced confidence. It must not manufacture a mature chronic baseline from defaults.

## Recovery state

Recovery evaluates available same-day and rolling evidence:

- Natural-log HRV trend against the athlete's baseline.
- Resting-heart-rate deviation.
- Sleep duration, sleep score, and sleep continuity.
- Garmin stress.
- Body Battery and overnight change when available.
- Garmin recovery time.
- Recent hard-session exposure and current fatigue state.
- Optional athlete-reported soreness, stress, illness, and motivation in a later phase.

Baselines use robust rolling statistics over up to 28 valid days and require at least 14 valid observations before being considered established. Outliers do not silently redefine the baseline. Baselines are metric- and source-specific.

Recovery produces:

- Direction: supportive, neutral, caution, or protective.
- Maximum allowed intensity adjustment: maintain, reduce one level, reduce two levels, or rest/recovery only.
- Confidence: low, medium, or high.
- Structured contributing and missing signals.

A single abnormal wearable reading creates at most caution unless an explicit safety rule applies. Multiple aligned negative signals may reduce training. Missing measurements reduce confidence and appear in the explanation, but contribute no negative points.

The existing 0-100 readiness value may remain as a display summary during migration, but prescription logic consumes the structured recovery direction, cap, and confidence rather than relying on score bands alone.

## Performance and goals

### Running

- Establish current ability from recent races, time trials, or qualifying completed efforts.
- Prefer comparable, recent performances and retain recency and measurement confidence.
- Build pace or effort bands from demonstrated capacity, not desired race pace or VO2 max alone.
- Use VO2 max as a longitudinal supporting signal and anomaly check.
- Progress weekly volume and key-session difficulty independently.
- Keep most work easy, protect spacing between hard sessions, and taper relative to the goal date.
- If no valid performance baseline exists, prescribe by duration and conversational effort until sufficient evidence exists.

### Strength

- Evaluate progress by exercise identity and load convention.
- Use completed sets, repetitions, load, and RIR/RPE to select the next dose.
- Use double progression: earn repetitions within the target range before increasing load.
- Respect equipment, movement-pattern balance, session duration, and interference with key endurance sessions.
- Never infer a safe external load from body weight, VO2 max, or heart-rate response.

### Multiple goals

Equal-priority goals share weekly capacity explicitly. The planner protects the minimum effective dose for each active primary goal, then assigns remaining capacity according to goal timeline, current phase, availability, recovery cap, and recent adherence. It must explain any goal tradeoff.

## Weekly planning and adaptation

The weekly planner owns the active schedule. Goal preview policies become inputs to this planner rather than a disconnected alternative.

Planning order:

1. Reserve non-negotiable availability and explicit rest constraints.
2. Place key goal sessions with required recovery spacing.
3. Place complementary strength, aerobic, and mobility work.
4. Apply current recovery intensity cap.
5. Fit complete prescriptions into available time.
6. Validate volume progression, movement balance, and consecutive hard days.
7. Publish the plan and structured reasons.

After completion reconciliation, the planner compares prescribed and completed dose. It then updates the remaining week rather than merely marking a card complete. Substitutions can satisfy compatible intent, but an unrelated activity cannot silently satisfy a key session.

Completed sessions are immutable evidence. Future sessions may change; past prescriptions and decision receipts remain available in the coach decision trail.

## Canonical execution and clients

The canonical deterministic engine runs in Supabase Edge Functions because Garmin delivery and scheduled notifications must remain current while the app is closed. It uses no external LLM API.

The iOS app:

- Fetches the latest versioned athlete state and prescription.
- Caches a last-known-good snapshot for offline screens, widgets, and App Intents.
- Clearly shows staleness and confidence.
- Can request recalculation after local Apple Health sync or user edits.
- Uses Apple Foundation Models only for conversational explanation over approved structured data.

Notifications, widgets, Today, Plan, and Coach Activity must resolve the same prescription identifier and status. No client creates an independent competing recommendation.

## Persistence and reproducibility

Add versioned records for:

- Per-activity calculated training load.
- Daily athlete state.
- Published prescription and remaining-week revision.
- Calculation input fingerprint and policy version.
- Source coverage and confidence.
- Structured reason codes.

Reprocessing the same evidence under the same policy version must produce the same result. A policy upgrade creates a new calculation revision rather than rewriting historical decision evidence.

All timestamps remain absolute instants. Daily aggregation uses the athlete's saved time zone and stores the derived local date explicitly. Daylight-saving transitions and travel require dedicated tests.

## Failure behavior

- Incomplete ingestion leaves the prior published prescription active and marks it stale; it does not publish a partial replacement.
- Missing baseline data produces conservative prescriptions and low confidence, not fabricated normal values.
- Duplicate or ambiguous activities are excluded from load until resolved.
- A failed recalculation is retried idempotently and recorded with a bounded diagnostic payload.
- Notification delivery never claims a new recommendation unless the referenced prescription was published successfully.
- The app remains usable from the last-known-good state and shows when fresh evidence is pending.

## Safety constraints

- Reported pain, injury, illness, or explicit medical restriction blocks automatic intensification.
- Recovery evidence cannot increase planned intensity above the goal plan.
- Load trends are not described as injury predictions.
- No pace, weight, or duration target is generated without qualifying evidence and an identified fallback policy.
- Hard running sessions and demanding lower-body strength sessions receive configurable separation.
- Maximum week-over-week progression is discipline-specific, conservative, versioned, and bypassed only through an explicit user-reviewed decision.
- The engine explains limitations and recommends professional guidance when the request exceeds fitness planning.

## Rollout

### Stage 1: Evidence and shadow state

- Complete Garmin-to-iOS biometric decoding.
- Add deduplicated activity-load records.
- Calculate fitness, fatigue, recovery, and confidence without changing recommendations.
- Compare results against current prescriptions and completed behavior.

### Stage 2: Shadow prescriptions

- Generate complete goal-specific daily and weekly proposals without publishing them to users.
- Record differences, blockers, fallback usage, and safety-rule activations.
- Tune only through versioned policy changes and regression fixtures.

### Stage 3: Reviewed activation

- Present the new prescription and explanation in an internal review surface.
- Activate it for Today and Plan after representative cases pass.
- Keep an immediate rollback to the last stable policy version.

### Stage 4: Unified delivery

- Drive notifications, widgets, App Intents, Coach Activity, and weekly adaptation from the same published prescription.
- Add on-device conversational explanation after deterministic parity is established.

## Testing and acceptance criteria

### Unit tests

- Garmin-first source precedence and cross-provider deduplication.
- Session-load methods and confidence fallbacks.
- Strength load independent of cardiovascular response.
- EWMA behavior, empty days, sparse history, and policy-version reproducibility.
- Recovery baselines, missing data, outliers, and aligned negative signals.
- Running and strength progression constraints.
- Multiple equal-priority goals and limited availability.
- Completion, partial completion, substitution, missed session, and remaining-week recalculation.

### Integration tests

- Garmin delivery through normalized evidence, athlete state, plan, notification, and widget snapshot.
- Apple Health mirror does not double count a Garmin session.
- App-closed Garmin activity changes the next scheduled notification.
- Failed ingestion or calculation retains the prior last-known-good prescription.
- Time-zone and daylight-saving boundaries preserve the intended training day.

### Golden scenarios

Maintain anonymized deterministic fixtures covering at minimum:

- Established runner with good recovery.
- Runner with aligned poor sleep, depressed HRV, and elevated resting heart rate.
- Sparse wearable data.
- Strength-focused athlete with RIR history.
- Equal running and strength goals.
- Unplanned long run replacing strength day.
- Garmin workout mirrored into Apple Health.
- Several app-closed days followed by Garmin webhook updates.

### Activation gates

- No duplicate session load in representative production history.
- Every prescription identifies its evidence, policy version, confidence, and fallback reasons.
- No missing metric reduces recovery by itself.
- Current and historical prescriptions remain reproducible from stored inputs.
- Notification, app, widget, and Coach Activity agree on prescription identity and status.
- Shadow results are reviewed before they can change production plans.

## Success measurement

- Percentage of prescriptions generated without low-confidence fallback.
- Percentage of completed sessions reconciled to the intended prescription.
- Rate of manual session replacement after recommendation.
- Plan adherence by goal and modality, without penalizing approved substitutions.
- Frequency and reason for recovery-driven reductions.
- Stale-prescription notification prevention.
- User-reported usefulness and perceived explanation quality.

Success is not a higher readiness score or more workouts. Success is a safer, more specific, explainable prescription that responds correctly to what the athlete actually did.
