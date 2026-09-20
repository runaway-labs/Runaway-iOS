# Runaway: goal-driven running and strength

Status: proposed design for approval; no production behavior changed.

## Product contract

Running and strength are equal priorities for this athlete. Neither is silently
demoted to supporting work. Equal priority means equal consideration of progress
and constraints, not equal mileage, minutes, or an automatic 50/50 session split.

Every recommendation must answer: what exactly, which goal, why today, what data
supports the decision, and what changes in the remaining week?

All generative inference remains on-device using Apple models. No external LLM
providers or Private Cloud Compute. Supabase remains responsible for account
storage and notification delivery, not cloud workout generation.

## Confirmed current limitations

- TrainingProfile.validated enforces exactly one primary activity and reduces
  supporting sessions before primary sessions when capacity is exceeded.
- TrainingProfile stores activity frequencies, equipment category and experience,
  but not measurable strength targets, performance baselines or per-day minutes.
- GoalManager selects one running goal, preferring the largest target among
  upcoming races within 90 days. Explicit athlete priority needs to replace that
  inference for the new goal portfolio.
- TodayRecommendationPolicy's selection interface has no direct goal inputs.
  Goals may influence an upstream plan, but the daily selector cannot directly
  compare candidate sessions against running and strength targets.
- Readiness below 50 selects recovery; 50 through 69 reduces intensity. These
  branches do not receive confidence, measurement age or readiness components.
- The context builder can fall back to yesterday's planned workout when there is
  no recorded completion. Planned demand is not evidence of completed load.
- TrainingPlanService.personalizePlanLocally asks the model for a two-to-three
  sentence note about a fixed schedule; it does not create the prescription.
- Notification publication stores daily recommendations for delivery later.
  Multiple notification times do not themselves cause fresh on-device inference.

These explain structural weaknesses, not the proven cause of the athlete's
specific Walking recommendation. Preserve/replay its actual decision inputs
before claiming that incident resolved.

## Chosen architecture

Prefer an incremental replacement over a full rewrite or a prompt-only upgrade.
Keep existing app routes and completed history while introducing versioned types
and adapters. A prompt-only change cannot repair missing goals or scheduling rules;
a rewrite risks losing established race, widget and activity behavior.

### 1. Athlete training profile and goal portfolio

- Multiple active goals: race performance, running consistency/volume, specific
  strength performance, and supporting activities. Distinguish outcome targets
  from weekly process targets; do not compare incompatible target values.
- Every goal has an ID, discipline, measurement definition, baseline and date,
  target, deadline if applicable, explicit priority and lifecycle state.
- Running performance pairs distance with elapsed time and records terrain and
  observation date. A desired race pace is not evidence of current training pace.
- Strength baselines include exercise/variant, equipment, load convention,
  repetitions, sets and reported effort. Distinguish total load, per-hand load,
  machine-specific load and bodyweight work.
- Availability includes per-day minutes, preferred sessions, permitted doubles,
  equipment and reported limitations. Doubles require opt-in.
- Optional height and weight retain units, source and measurement dates. They
  are not readiness proxies or prerequisites for receiving a workout.
- Preserve existing race dates and user-entered units; use canonical units for
  calculations. Default presentation stays miles unless the user chooses otherwise.
- Missing baselines yield a clearly labelled calibration session or effort-based
  prescription, not invented pace or weight and not an automatic walking fallback.

### 2. Deterministic prescription engine

Separate input assembly, candidate construction, constraint filtering, ranking,
prescription and explanation. Use typed values, not free-form model text, for
durations, distance, load, sets, reps, rest and interval structure.

Maintain separate running and strength progress measures. Do not equate running
mileage with lifted tonnage or average them into a misleading fitness score.

Proposed selection objective, after hard constraints:

`score = runningGoalFit + strengthGoalFit + preferenceFit - fatigueConflict - timeMismatch - repetitionPenalty`

Goal-fit terms are normalized within their own discipline and equally weighted
for this profile. The score is a transparent ranking heuristic, not a validated
physiological prediction. Exact coefficients and progression rules must be
reviewed against appropriate training evidence and evaluated before release.

Actual completed activity determines historical load; planned future sessions
determine scheduling conflicts. Missing readiness is unknown, not zero or 100.
Use readiness freshness, confidence and reported condition rather than a single
opaque cutoff. Safety constraints remain ahead of target chasing.

Running prescriptions contain warm-up, work/recovery blocks and cool-down with
time/distance and supported pace or effort targets. Strength prescriptions contain
exercise selection, sets, reps, rest, known load or effort target, substitutions
and explicit progression conditions based on logged results.

Impossible targets or incompatible availability produce an explanation and a
choice, not silently reduced strength training or fabricated precision.

### 3. One recommendation record

Create a versioned TrainingDecision containing athlete ID, local day/time zone,
session ID, goal IDs, prescription, input fingerprint, engine version, timestamp,
validity, confidence, reason codes and rejected-candidate reasons.

Today, Plan, workout detail, widgets and notifications consume that record rather
than independently selecting workouts. Account changes clear cached decisions.
Goal edits, completed sessions, time-budget changes and meaningful new recovery
data invalidate affected decisions. Preserve completed history and explicit edits;
recalculate remaining sessions and show the change receipt with undo.

### 4. On-device Apple Intelligence

Use structured generation to interpret bounded requests such as "30 minutes,
dumbbells only" into proposed constraint changes. Preview meaningful changes
before committing. Tools expose only the validated training context.

Generate concise explanations from the decision record. Validate all numeric
claims against the prescription. The model must not independently change loads,
pace, completion status or goals. Deterministic explanations remain available
when the model is unavailable, slow or fails validation.

### 5. Notifications that represent useful moments

Keep the multi-time schedule. Distinguish pre-session recommendation, unfinished
session reminder and post-session reflection rather than repeating the same title.
Suppress obsolete and already-completed recommendations using fresh synced data.
Respect Lock Screen privacy; specific workout detail is opt-in.

A schedule is not permission to guarantee background model execution. Prepare
decisions while the app can run; stale data gets an honest refresh check-in.
Delivery status distinguishes queued, skipped with reason, accepted by APNs and
opened. Never label APNs acceptance as confirmed on-screen delivery. Bound retries
and expiration and preserve per-time deduplication.

### 6. UX and iOS 27 opportunities

Keep existing tabs and the accomplishment-focused widget identity. Today shows
one hero prescription, two equal-status goal progress lanes, a short "why today"
and visible Start / Adjust actions. Plan shows the relationship between sessions
and both goals. Profile uses progressive sections with completion summaries, not
one intimidating questionnaire.

Use restrained native materials for navigation, clear opaque workout content,
strong numeric hierarchy, accessible contrast and purposeful completion motion.
Avoid the black-and-amber-only look, excessive glass and competing cards. Respect
Dynamic Type, Reduce Motion and increased contrast; color is not the only cue.

Apple's iOS 27 documentation identifies these opportunities:

- Foundation Models Dynamic Profiles for bounded interpretation/explanation modes.
- Evaluations framework for measuring explanation fidelity and request handling.
- App Intents entity/intent schemas and View Annotations for actions on the
  current session, plus App Intents Testing for system-path integration checks.
- Updated native materials, typography and widget customization.

Validate each API against the installed SDK and supported hardware before adoption.
Interactive widgets and workout Live Activities remain useful existing platform
capabilities, not inventions of iOS 27. Use them for Start/Resume, rest countdowns
and explicit completion, not a permanent daily notification banner.

## Delivery sequence and acceptance gates

1. Evidence and profile foundation: capture decision traces; migrate goals and
   profile without changing history; represent equal priorities and missing data.
2. Engine vertical slice: produce a justified run or strength prescription from
   both goals; changing time/equipment adapts the prescription deterministically.
3. Results and weekly adaptation: log actual sets/load/effort and run completion;
   rebalance remaining work without rewriting completed sessions.
4. Unified surfaces: wire Today, Plan, details and existing widgets to the same
   revision, with accomplishment-focused presentation and clear adjustment routes.
5. Notification lifecycle and Apple integrations: validated messages/actions,
   observability, system integration tests and real-device delivery checks.

Regression scenarios include two days without training; missing/stale readiness;
long run completed versus merely planned; limited equipment; competing deadlines;
unknown lifting loads; one discipline starved by limited availability; a shortened
session; manual changes; activity arriving after a notification was prepared;
goal-unit/date preservation; account switching; DST; and model unavailability.

Do not deploy the new engine broadly until these scenarios pass and representative
sessions have been reviewed for training quality. Roll out through a reversible
engine-version switch. No automatic production migration or TestFlight upload is
part of this design-only pass.

## Sources

- Apple iOS 27 overview: https://developer.apple.com/ios/whats-new/
- Foundation Models updates: https://developer.apple.com/documentation/updates/foundationmodels
- Widget and Live Activity interactions: https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities

Primary code references: Models/TrainingProfile.swift,
Models/TodayRecommendationPolicy.swift, Managers/GoalManager.swift,
Services/TrainingPlanService.swift, and the existing workout prompt pipeline.
