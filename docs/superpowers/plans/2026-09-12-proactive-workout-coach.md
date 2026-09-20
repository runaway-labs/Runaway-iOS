# Proactive workout recommendations: comparison and implementation plan

Status: code-grounded comparison and proposed implementation. No new scheduling feature is deployed by this document. Apple model output quality has not yet been benchmarked on a physical device.

## Product requirement

Runaway proactively recommends the right full workout or run for the day at the athlete's chosen time, based on goals, completed training, available equipment, time, and current self-reported constraints. Opening the notification leads to that recommendation in Next Up, not an activity-synced message or a separate chatbot.

This is a workout planning and execution feature, not motivational copy or a repeating generic reminder. A justified recovery day is a valid recommendation. Changing or completing today's workout updates the remaining week without rewriting completed sessions.

Proposed initial delivery preference: 7 a.m. America/Chicago, drawn from the user's existing coaching conversation. Make time and time zone editable. Require explicit feature opt-in; an existing system notification permission is not consent to all coaching reminders. No automatic noon check-in. Optional follow-up is tied to a time the athlete chooses for that workout.

## Reference comparison

Count full sessions once; substitutions and set-by-set replies are modifications to a session, not new workouts. These are behavioral references, not instructions to reproduce every historical coaching suggestion.

| Reference conversation | What the experience provides | Runaway gap / benchmark |
| --- | --- | --- |
| Bench Workout Plan (August 27) | Prior-performance context, equipment substitutions, progression during the session | Exercise-level performance history and substitutions based on available equipment |
| Bench Workout Plan (September 3) | Changed working loads and a session shortened around work | Time budget, completed-set tracking, and preservation of completed work when shortening |
| Home Core Workout Plan | Equipment-specific core session, technique feedback, no unnecessary finisher | Real equipment inventory, stable exercise IDs, instructional cues and stopping rules |
| Home Core Workout Plan (following-day recommendation) | Running considered alongside strength and prior core fatigue | Recent muscle-group loading and actual recovery feedback, not only a global readiness score |
| Knee Soreness Workout Plan | Upper-body choice, modified exercises, adaptation to reported fatigue | Structured body-area restrictions and conservative constraints; no diagnosis or automatic clearance to run |
| Treadmill Run Walk Plan | Warm-up, timed work/recovery blocks, cooldown, effort target | Structured run steps and internally consistent duration totals |
| Running With Sore Knees | Conservative, conditional recommendation instead of a generic hard run | Do not interpret absent symptom information as recovery; check-in or conservative fallback where appropriate |
| Physique Training Plan | Strength development and running treated as meaningful concurrent goals | General strength/physique goals alongside running goals, without conflating them |
| Question response | Proactive morning plan and request for a training commitment | Timed delivery, actionable destination, opt-in commitment reminder |

The existing conversations contain historical facts and preferences, not necessarily today's state. Present imported goals/equipment for confirmation before using them in production recommendations. Do not automatically treat old soreness as current or a past best set as a required working weight.

## What the current code supports

- TrainingProfile stores activity preferences, weekly frequency, unavailable days, broad strength-equipment categories and experience.
- DailyWorkout and Exercise can represent basic exercises, sets, free-text reps and weight.
- TodayRecommendationPolicy supports choosing a workout and adapting the rest of the week.
- TrainingPlanService.personalizePlanLocally generates a coaching note for an already chosen schedule; this does not generate complete personalized prescriptions.
- A profile-based strength fallback currently contains a placeholder exercise. That is not acceptable for the proposed ready-to-start workout experience.
- FoundationModelsService creates a new LanguageModelSession for each call. Its maxTokens argument is not passed into generation, and one generation failure disables subsequent attempts until availability is rechecked.
- Production APNs delivery has been confirmed on the user's phone after correcting the bundle identifier. The existing activity notification path is event-driven, not a daily recommendation scheduler. Its single athlete token also needs replacement for reliable multi-device use.

## Recommended architecture

Use Runaway's deterministic planning rules plus Apple on-device generation. Do not add external LLM API calls or make a consumer ChatGPT task responsible for production scheduling.

The planning rules select session purpose and enforce equipment, time, progression and recovery constraints. The Apple model can propose a structured prescription and explain it using a small, relevant context packet. Validate generated exercises and loads against the catalogue and constraints. Guided generation ensures output shape, not workout correctness. Fall back to complete rule-based sessions if the model is unavailable or invalid.

The server handles scheduling and notification dispatch using a validated recommendation snapshot and synced state. It does not run the Apple model. Recompute on device when the app is active and after relevant training/profile changes; refresh supported background work opportunistically. Do not depend on a silent push starting model generation at a precise time.

## Implementation sequence

### 1. Reference scenarios and complete workout prescriptions

Touch existing Models/TrainingProfile.swift, Models/WeeklyTrainingPlan.swift and Services/TrainingPlanService.swift. Add focused workout-prescription and training-context types rather than growing the service further.

- Represent distinct running, strength-performance and physique objectives, including priority and optional date. Preserve existing running-goal behavior.
- Add home/gym equipment inventory with available loads and selectable substitutions; keep schema migrations compatible with old profiles.
- Represent strength exercises with stable IDs, warm-up versus working sets, unit-tagged loads, rep ranges, rest, effort targets, substitutions and instructional cues.
- Represent running warm-up, work/recovery repeats, cooldown, duration/distance and effort targets. Keep all calculations in typed units.
- Store actual sets/reps/loads and reported effort separately from planned values, with source and timestamps. Aggregate activity mileage alone cannot support strength progression.
- Produce complete, executable deterministic sessions before enabling generated variations. Remove placeholder prescriptions from this flow.
- Build fixtures from the reference scenarios; exclude private identifiers and raw conversation exports from committed test artifacts.

### 2. Contextual selection and Apple generation pilot

Extend TodayRecommendationPolicy and integrate a dedicated prescription generator with FoundationModelsService.

- Use recent completed activity, exercise history, current goals, current restrictions, equipment, session duration and upcoming important runs.
- Treat missing readiness as unknown; never silently equate missing information with full readiness. Do not let one readiness number override explicit restrictions or completed work.
- Include reasons and source timestamps with the chosen session. Rules must explain the decision even without the model.
- Fix output-length enforcement and recoverable error handling in the model service. Serialize or isolate generation requests and bound context.
- Generate and validate structured prescriptions. Never let model prose directly mutate the plan.
- On completion, shortened sessions, substitutions or new restrictions, update future recommendations while preserving the activity/set ledger and explicit user choices.
- Run the same scenarios on a compatible physical iPhone repeatedly. Compare rule-only and Apple-assisted output with the references; do not claim ChatGPT-equivalent quality from mocked tests.

### 3. Timed recommendation delivery -- required first-release feature

Add coaching notification preferences and recommendation persistence, plus a scheduled internal Edge Function in runaway-edge. Extend PushNotificationService and the existing settings/onboarding surfaces.

- Store opt-in, local notification time, IANA time zone, selected days and optional commitment-reminder preference. Handle daylight saving, changed schedules and an explicit travel/time-zone policy.
- Persist a recommendation ID, athlete ID, local training date, revision, source-data revision, generated time, expiry, rationale codes and complete workout. Keep unnecessary health details out of push payloads.
- Reuse the existing authenticated app/backend boundary and internal-job secret policy. Keep per-user ownership checks/RLS and do not expose tokens to other athletes.
- Replace single-token storage with per-installation registration, APNs environment, invalid-token cleanup and sign-out detachment. Preserve older installations during rollout without duplicate legacy/new sends.
- Check current preferences, source revision, completion, expiry and restrictions immediately before dispatch. Only call a workout ready when a valid full prescription exists.
- If context is stale, unsynced or incomplete, send an honest check-in prompt such as "Check in to choose today's session"; do not pretend the phone generated a fresh workout while asleep.
- Claim scheduled sends atomically and key them by athlete/local date/message kind. Bound retries and use expiration/collapse identifiers; do not promise exactly-once delivery across ambiguous APNs failures.
- Suppress commitment reminders once the session is completed. Apply changes to queued reminders; previously delivered notification text cannot always be recalled.
- APNs acceptance is not proof of display; Focus, permissions, connectivity and OS delivery behavior remain relevant. Delivery timing is a target, not a guarantee.

### 4. Existing-screen experience

Extend MainView, Navigation/Router.swift and the existing Next Up/workout detail components. No new chatbot tab.

- Daily notification opens a recommendation route keyed by ID/date/revision, distinct from activity_id.
- Next Up and notification detail use the same current recommendation. An older notification opens the current version with a clear change explanation; a prior day's link does not masquerade as today's workout.
- Present workout title, expected time, full steps and a short "Why today" explanation.
- Actions: Start, Choose a time, Change workout, and Update how I feel. Ask about current constraints only when needed.
- Choosing a time offers one optional reminder at that time. Do not enable unsolicited repeat nudges.
- During strength sessions, record results and allow equipment substitutions or shortening without erasing completed sets. Protect saved progress across app restarts.
- When already completed, show completion/progress instead of inviting a duplicate session. Update widgets from the same recommendation and completion state.
- Show disabled notification permission and offer a Settings link without implying that device registration alone proves delivery is working.

## Acceptance tests and rollout gates

1. Every reference scenario produces a complete workout or a justified recovery/check-in result; no placeholder exercises.
2. Equipment availability, time limits, unit conversion, rest totals and completed-work preservation are enforced independently of model output.
3. Prior strength results influence a progression decision; absent data does not produce fabricated personal records or working weights.
4. A hard recent run does not automatically imply another run or a hard leg session. Goal balance and reported constraints affect the choice.
5. On-device trials assess specificity, usefulness, variety, factual grounding and latency. Record actual results, failures and fallback frequency; the present code review is not that trial.
6. Daily notifications respect opt-in, chosen time zone, daylight-saving transitions and changed settings. No noon reminder without explicit opt-in.
7. Notification and Next Up refer to the same recommendation version, including after a workout change, completion, sign-out or cold launch.
8. Stale snapshots never claim fresh personalization; missing model access leaves a complete rule-based workout or honest check-in.
9. Duplicate scheduler runs, invalid device tokens, ambiguous send failures and multiple devices do not create uncontrolled reminder loops.
10. Test on the user's physical iPhone with a near-future chosen delivery time: app open, backgrounded and not running. Confirm actual receipt and destination, not only HTTP 200.

Roll out behind an opt-in feature flag. Finish the workout-quality pilot before enabling daily recommendations broadly, but include timed notifications in the first end-to-end pilot rather than deferring them as optional polish.

## Documentation references

- Apple Foundation Models guided generation and tools: https://developer.apple.com/videos/play/wwdc2025/301/
- Apple background execution strategies: https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app
- ChatGPT scheduled task capabilities and limitations: https://help.openai.com/en/articles/10291617-tasks-in-chatgpt
