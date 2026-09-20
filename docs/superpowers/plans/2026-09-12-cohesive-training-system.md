# Cohesive Training System Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task in the current conversation. Do not create separate tasks, worktrees or commits without user authorization. Each milestone is a reviewable deliverable; later milestones are not permission for a single large rewrite.

**Goal:** Turn equally prioritized running and strength goals into specific, explainable prescriptions shared by the app, widgets and scheduled notifications.

**Architecture:** Introduce account-owned, versioned goal and baseline data, then a deterministic prescription and decision layer. Keep the existing engine behind an adapter during migration. Apple on-device models interpret bounded adjustments and explain validated decisions; they do not own training calculations.

**Tech Stack:** Swift, SwiftUI, existing local persistence, Foundation Models, App Intents, WidgetKit, ActivityKit, Supabase Postgres and Edge Functions.

**Spec:** `docs/superpowers/specs/2026-09-12-cohesive-training-system-design.md`

## Global constraints

- Running and strength are equal priorities for this athlete.
- All generative inference remains on-device using Apple models.
- No external LLM providers or Private Cloud Compute.
- Preserve existing race dates and user-entered units; use canonical units for calculations.
- Default presentation stays miles unless the user chooses otherwise.
- Doubles require opt-in.
- Optional height and weight retain units, source and measurement dates.
- Missing readiness is unknown, not zero or 100.
- Preserve completed history and explicit edits.
- Never label APNs acceptance as confirmed on-screen delivery.
- Keep existing tabs and the accomplishment-focused widget identity.
- No production migration, test notification or TestFlight upload without explicit authorization for that action.
- Before each coding task, read only its required files once and make one planned edit pass. Do not rerun inspection merely to verify edits.
- Run the acceptance tests below when testing is authorized. Stop for approval if a newly introduced bug requires another correction pass.

## Delivery boundaries

Milestone 1 is an independently usable goal/profile editor and decision diagnostics.
Milestone 2 is a tested running-and-strength prescription engine. Milestone 3 is
results-driven adaptation. Milestone 4 unifies app surfaces. Milestone 5 upgrades
notification content and Apple integrations. Do not mark the product complete at
the end of the profile milestone.

## Milestone 1: Measurable, account-owned profile

### Task 1: Typed goal portfolio and performance evidence

Create `Runaway iOS/Models/AthleteTrainingProfile.swift` and
`Runaway iOS/Runaway iOSTests/AthleteTrainingProfileTests.swift`.
Update `Runaway iOS.xcodeproj/project.pbxproj` so the test file is excluded from
the app target and included in the test target, following existing exceptions.

Use a new aggregate rather than prematurely widening the legacy `primary` enum:

```swift
enum TrainingDiscipline: String, Codable { case running, strength }
enum GoalPriority: String, Codable { case equalPrimary, supporting }
enum LoadConvention: String, Codable { case total, perHand, machine, bodyweight }

struct GoalMeasurement: Codable, Equatable {
    var distanceMeters: Double?
    var durationSeconds: Double?
    var loadKilograms: Double?
    var repetitions: Int?
    var exerciseID: String?
    var loadConvention: LoadConvention?
}

struct AthleteTrainingGoal: Codable, Equatable, Identifiable {
    var id: UUID
    var discipline: TrainingDiscipline
    var priority: GoalPriority
    var baseline: GoalMeasurement?
    var baselineMeasuredAt: Date?
    var target: GoalMeasurement
    var deadlineLocalDate: String?
    var sourceRaceID: Int?
    var enteredDistanceUnit: String?
    var enteredLoadUnit: String?
    var isActive: Bool
}
```

The aggregate contains `schemaVersion`, `athleteID`, `revision`, `goals`, the
existing activity preferences, per-weekday available minutes, doubles consent,
equipment and optional dated body measurements. Use stable IDs for exercise
variants, not labels that change with localization. Add a typed metric category
to distinguish event performance from weekly process targets before persistence.

- [ ] Write decoding, equal-priority round-trip and invalid-measurement tests.
- [ ] Reject nonfinite/nonpositive target values, missing exercise identity for a
  strength target, inconsistent load conventions and invalid local-date strings.
- [ ] Keep unknown baselines optional. Never populate an unobserved load or pace.
- [ ] Validate with explicit field errors; do not silently demote a goal.

Required examples:

```swift
XCTAssertEqual(decoded.goals.filter { $0.priority == .equalPrimary }.count, 2)
XCTAssertNil(unmeasuredGoal.baseline)
XCTAssertEqual(decoded.goals.first?.deadlineLocalDate, "2026-11-01")
XCTAssertEqual(decoded.goals.first?.enteredDistanceUnit, "km")
```

### Task 2: Account-scoped storage and non-destructive migration

Create `Runaway iOS/Services/AthleteTrainingProfileStore.swift` and
`Runaway iOS/Runaway iOSTests/AthleteTrainingProfileStoreTests.swift`.
Integrate through `Runaway iOS/Models/UserSession.swift` and
`Runaway iOS/Managers/DataManager.swift` after reading their account lifecycle.
Use `Runaway iOS/Services/TrainingProfileStore.swift` only as a legacy input.

Interface:

```swift
@MainActor
protocol AthleteTrainingProfilePersisting {
    func load(athleteID: Int) throws -> AthleteTrainingProfile?
    func save(_ profile: AthleteTrainingProfile, athleteID: Int) throws
    func clearSession()
}
```

- [ ] Persist an encoded envelope under `athleteTrainingProfile.v2.<athleteID>`;
  verify envelope ownership before returning it. Publish only after encoding succeeds.
- [ ] Keep legacy bytes intact. Unowned legacy preferences require confirmation
  for the current account; do not silently attribute them to the next signed-in user.
- [ ] Import races through stable source IDs, preserving original dates/units.
  Reimport updates linked fields without duplicating goals or overriding priority.
- [ ] Account changes cancel pending loads and clear the in-memory aggregate and
  decision cache. A late response cannot publish into another account.
- [ ] A corrupt record produces recoverable setup/error state without overwriting
  its bytes with defaults. Failure to save retains the previous profile.
- [ ] Prove user A cannot see user B's goals and a second migration creates no duplicates.

New profile editing initially uses explicit local persistence. Do not imply
cross-device sync until a separate owner-RLS migration and conflict-handling
adapter are approved and tested. Expose that persistence status honestly.

### Task 3: Profile editing in existing navigation

Create `Runaway iOS/Views/AthleteTrainingProfileView.swift`,
`Runaway iOS/Components/TrainingGoalEditor.swift` and
`Runaway iOS/Components/PerformanceBaselineEditor.swift`.
Modify `Runaway iOS/Views/SettingsView.swift` to open the new profile route.
Retain existing `TrainingProfileView.swift` / `TrainingProfileComponents.swift`
as the legacy activity-mix editor until the new engine is connected.

- [ ] Sections: Goals, Current ability, Weekly availability, Equipment, Optional
  measurements. Show a summary and completion state for each section.
- [ ] Seed running and strength as equally prioritized only after the athlete
  confirms that choice; preserve other users' preferences.
- [ ] Make target and observed performance separate fields. Never require a
  maximal lifting test to finish setup.
- [ ] Date editors persist date-only values. Unit changes convert values;
  presentation never silently relabels miles as kilometers or pounds as kilograms.
- [ ] Save validates all sections, preserves drafts on error and shows a visible
  completion receipt. Cancel makes no persisted changes.
- [ ] Share the same editor components with onboarding after locating its actual
  route; no new tab and no duplicate profile representation.

Acceptance: create one race target and one strength target, restart the app,
reopen both, edit one, cancel another edit, and switch accounts without leakage.

### Task 4: Explain the current decision before replacing it

Create `Runaway iOS/Models/TrainingDecisionTrace.swift` and
`Runaway iOS/Services/TrainingDecisionTraceStore.swift`.
Instrument `Runaway iOS/Models/TodayRecommendationPolicy.swift` and
`Runaway iOS/Models/ComplementarySchedulingPolicy.swift` without changing ranking.
Expose diagnostics through the existing recommendation details in
`Runaway iOS/Components/ReadinessComponents.swift`.

- [ ] Record source timestamps, readiness value and missingness, selected goals,
  planned versus completed activity, candidate scores, exclusion reasons and
  selected branch. Do not log raw health data remotely.
- [ ] Store a bounded, account-owned trace locally; expose a readable explanation.
- [ ] Show whether a decision is current, cached, unavailable or awaiting profile data.
- [ ] Reproduce the Walking case from captured inputs. If the original inputs
  were not retained, state that and reproduce the problematic branch with fixtures.

Milestone 1 exit: the athlete can save precise equal-priority targets and inspect
why the existing engine made a choice. This milestone does not yet claim improved
prescriptions or cloud profile synchronization.

## Milestone 2: Precise prescriptions and a shared decision

### Task 5: Validated training inputs and prescription types

Create `Models/TrainingDecision.swift`, `Models/WorkoutPrescription.swift` and
`Services/TrainingDecisionInputBuilder.swift` inside `Runaway iOS/`.
Create matching tests under `Runaway iOS/Runaway iOSTests/`.

```swift
struct RunningBlock: Codable, Equatable {
    var repetitions: Int
    var durationSeconds: Int?
    var distanceMeters: Double?
    var recoverySeconds: Int?
    var targetPaceSecondsPerKilometer: Double?
    var effortInstruction: String
}

struct StrengthPrescription: Codable, Equatable {
    var exerciseID: String
    var sets: Int
    var repetitionsLower: Int
    var repetitionsUpper: Int
    var restSeconds: Int
    var loadKilograms: Double?
    var loadConvention: LoadConvention
    var effortInstruction: String
}
```

- [ ] Require positive durations/distances, valid repetition bounds and known load
  conventions. Use effort-only prescriptions when load evidence is absent.
- [ ] Assemble completed workload from actual completions. Yesterday's uncompleted
  plan can be a missed session, never evidence of completed physical load.
- [ ] Keep readiness freshness/confidence and unavailable values distinct.
- [ ] Fingerprint goals, observations, availability, completed activity and engine
  version deterministically. Exclude display-only formatting from the fingerprint.

### Task 6: Candidate selection and progression

Create `Services/GoalDrivenTrainingEngine.swift`,
`Services/RunningPrescriptionPolicy.swift`,
`Services/StrengthPrescriptionPolicy.swift` and tests for each.
Adapt `Services/TrainingPlanService.swift` and `Models/WeeklyTrainingPlan.swift`
without deleting the legacy path before equivalence/migration tests pass.

- [ ] Review training evidence for progression and load-management rules before
  implementing numerical coefficients. Record sources and assumptions alongside
  the policy; a target pace alone cannot establish current training zones.
- [ ] Filter safety, availability and equipment conflicts before scoring.
- [ ] Score equal-priority disciplines using normalized goal fit and unmet planned
  frequency. Do not compare mileage directly to lifting tonnage.
- [ ] Return a typed prescription, supporting goal IDs and reason codes. Unknown
  inputs return calibrated effort guidance or a specific question, not invented numbers.
- [ ] Detect infeasible goals/capacity and ask the athlete to choose a tradeoff;
  do not reduce strength first or stack missed hard sessions as catch-up debt.
- [ ] Gate activation behind an account-specific engine version with a reversible
  switch. Compare shadow decisions before changing the visible plan.

Required regression fixtures: equal priorities with limited days; two idle days;
low confidence versus genuinely low readiness; planned versus completed long run;
unknown lifting baseline; available dumbbells versus full gym; and explicit rest.

## Milestone 3: Results drive adaptation

### Task 7: Completion, progress and remaining-week changes

Create `Models/TrainingSessionResult.swift` and
`Services/TrainingProgressionService.swift`. Integrate existing
`Components/WorkoutComponents.swift`, `Managers/DataManager.swift` and
`ViewModels/WorkoutReflectionViewModel.swift` after focused reads.

- [ ] Log actual sets, repetitions, load convention and effort separately from
  prescriptions. Runs retain actual distance, duration and structured completion.
- [ ] Match imported and manually logged sessions without double-counting.
- [ ] Update discipline-specific progress from valid observations, not a generic
  completion percentage that implies achieved performance.
- [ ] Recalculate remaining work after completion or adjustment, preserving completed
  history and explicit choices. Show an itemized change receipt and undo.
- [ ] Test partial completion, exercise substitution, failed save, concurrent activity
  import and undo after a later session. Reject undo that would overwrite newer facts.

## Milestone 4: One experience across surfaces

### Task 8: Shared decision store and presentation

Create `Services/TrainingDecisionStore.swift` and
`Components/TrainingPrescriptionCard.swift`. Integrate
`Views/MainView.swift`, `Views/WeeklyTrainingPlanView.swift`,
`Components/ReadinessComponents.swift`, `Components/WorkoutComponents.swift`,
`Services/WidgetSyncService.swift` and `Models/WorkoutPrompt.swift`.
Adapt `RunawayWidget/ProgressWidgetSnapshot.swift` and
`RunawayWidget/AccomplishmentWidgetView.swift` while preserving their identity.

- [ ] Store one decision revision per session and account. All readers use that
  revision rather than recomputing a competing recommendation.
- [ ] Today: precise session, two equal-status goal lanes, why today, Start and Adjust.
- [ ] Plan: running/strength relationship, completed work and visible future changes.
- [ ] Widget: accomplishment first, useful next action second; never replace it with
  a generic recommendation-only card.
- [ ] Use native materials on controls, legible workout content, limited purposeful
  color and completion motion. Test large text, increased contrast and Reduce Motion.
- [ ] Test app/widget/notification agreement after goal edits, completion, account
  changes and cache expiration. Old links resolve to current context with disclosure.

## Milestone 5: Intelligence, notifications and iOS 27

### Task 9: Bounded on-device interpretation and explanations

Adapt `Services/FoundationModels/FoundationModelsService.swift` and create
`Services/TrainingAdjustmentInterpreter.swift` plus
`Services/TrainingExplanationGenerator.swift`.

- [ ] Use installed-SDK-supported structured generation for time/equipment requests.
  Return proposed constraints; preview meaningful changes before applying them.
- [ ] Bind model context to the decision revision. Discard responses generated for
  an obsolete profile/session or a different signed-in athlete.
- [ ] Validate every numeric claim against typed prescriptions. Fall back to
  deterministic explanations on unavailability, timeout or validation failure.
- [ ] Evaluate requests such as "30 minutes, dumbbells only", incompatible equipment,
  unsupported requests and attempts to bypass training constraints.
- [ ] Use iOS 27 Dynamic Profiles and Evaluations only after SDK capability checks;
  do not switch to cloud providers if local generation is unavailable.

### Task 10: Notification lifecycle and useful system actions

Adapt `Models/WorkoutPrompt.swift`, `Services/WorkoutPromptService.swift`,
`Services/PushNotificationService.swift` and `Views/WorkoutPromptSettingsView.swift`.
Backend scope: `../runaway-edge/supabase/functions/send-workout-prompts/index.ts`,
`policy.ts`, their tests and a CLI-generated migration for delivery reason fields.
Widget scope: `RunawayWidget/AppIntent.swift` and
`RunawayWidget/RunawayWidgetLiveActivity.swift`.

- [ ] Define pre-session, unfinished-session and reflection messages using the
  shared decision/result. Multiple times are distinct check-ins, not duplicate titles.
- [ ] Preserve private Lock Screen text by default, per-time dedupe, bounded retry
  and expiration. Skip or refresh stale and completed recommendations appropriately.
- [ ] Record queued, skipped with reason, APNs accepted and opened separately.
  Do not claim the backend can confirm a banner was displayed.
- [ ] Recheck current revision before sending and on opening. Scheduled delivery
  cannot guarantee that the on-device model runs at that exact moment.
- [ ] Add session-bound Start/Resume and supported adjustment intents. Use a Live
  Activity for an active session/rest timer, never a permanent day-long advert.
- [ ] Evaluate iOS 27 entity schemas, View Annotations and App Intents Testing
  against actual SDK availability and privacy requirements.
- [ ] Rehearse database changes with rollback, test ownership/RLS and invalid payloads,
  and perform authorized real-device background and locked-screen delivery checks.

## Validation and release checkpoints

Tests belong in both Xcode membership exception lists. Use the existing unit-test
target; do not accidentally compile XCTest files into the app again.

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project 'Runaway iOS.xcodeproj' -scheme 'Runaway iOS' \
  -destination 'platform=iOS Simulator,id=3C30155F-C99D-4446-AFD0-C6C73F762AE5' \
  '-only-testing:Runaway iOSTests' test
```

For each milestone, run focused tests first, then the full unit suite when authorized.
Record actual results, not assumptions. UI acceptance additionally covers all Save,
Cancel, Start, Adjust and notification routes; permissions and unsupported-device
states remain visible. Do not infer training quality from compilation alone.

Release only after representative prescriptions have been reviewed, engine rollback
is available, migrations preserve existing data, and the user authorizes archive
and upload. Keep profile, engine and notification rollout states separately visible.
