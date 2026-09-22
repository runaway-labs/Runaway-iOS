# Performance Coach Daily Decision Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Performance Coach, `Adjust today`, and the Activities commitment card with one exact, explicit, adaptive daily workout decision flow.

**Architecture:** `DailyWorkout` becomes the authoritative commitment record through immutable commitment metadata and a prescription fingerprint. A deterministic decision service builds candidates, complete drafts, and revision-bound week previews before applying a committed plan; Today, notifications, widgets, completion matching, and celebrations consume that same plan state. Legacy `daily_commitments` remains readable for migration but receives no new writes from the unified flow.

**Tech Stack:** Swift 6, SwiftUI, Observation, Swift Testing/XCTest, Supabase Swift, WidgetKit, AppIntents, UserNotifications, iOS 27.

**Spec:** `docs/superpowers/specs/2026-09-21-performance-coach-daily-decision-design.md`

## Global Constraints

- iOS 27 and compatible Apple Intelligence hardware only.
- No external LLM APIs; deterministic policy owns every quantity and plan mutation.
- On-device intelligence may explain supplied facts but cannot alter a prescription.
- Completed workouts and accepted results must never be rewritten.
- The athlete explicitly commits; choosing or previewing never persists a plan.
- Every Training Profile activity with a positive weekly frequency must remain visible.
- Disabled choices explain their blocker instead of disappearing.
- Running pace must never appear for a non-running modality.
- Activities is completed/imported history only.
- Existing `daily_commitments` rows are not destructively deleted.
- Use existing Runaway theme tokens, controls, typography, and spacing.

## Review Focus

- A plan changes between preview and commitment: reject the stale preview without partially writing the plan or commitment.
- A profile enables a modality that lacks a complete generated prescription: show it with an actionable blocker rather than hiding or inventing a dose.
- An imported activity has the right modality but insufficient dose: preserve it in Activities and report partial/not-complete accurately.
- Widget or notification publication fails after plan persistence: keep the commitment, expose retryable sync state, and republish on activation.
- A legacy commitment exists on the same day as committed plan metadata: the committed plan wins and legacy data cannot overwrite it.

---

### Task 1: Authoritative Workout Commitment Metadata

**Files:**
- Modify: `Runaway iOS/Models/WeeklyTrainingPlan.swift`
- Create: `Runaway iOS/Models/WorkoutCommitment.swift`
- Test: `Runaway iOS/Runaway iOSTests/WorkoutCommitmentTests.swift`

**Interfaces:**
- Consumes: `DailyWorkout`, `AcceptedTrainingPrescription`, `AcceptedWorkoutCompletion`.
- Produces: `WorkoutCommitment`, `WorkoutCommitment.Source`, `WorkoutPrescriptionFingerprint.make(_:)`, `DailyWorkout.commitment`.

- [ ] **Step 1: Write failing fingerprint and Codable tests**

```swift
import Testing
@testable import Runaway_iOS

@Suite("Workout commitment")
struct WorkoutCommitmentTests {
    @Test func fingerprintChangesForDoseButNotCompletionState() throws {
        let original = workout(duration: 40, distance: 4)
        let changedDose = workout(duration: 45, distance: 4)
        let completed = workout(duration: 40, distance: 4, completed: true)

        #expect(try WorkoutPrescriptionFingerprint.make(original) != WorkoutPrescriptionFingerprint.make(changedDose))
        #expect(try WorkoutPrescriptionFingerprint.make(original) == WorkoutPrescriptionFingerprint.make(completed))
    }

    @Test func commitmentRoundTripsInsideWorkout() throws {
        let base = workout(duration: 45, distance: nil)
        let commitment = WorkoutCommitment(
            committedAt: Date(timeIntervalSince1970: 1_800_000_000),
            source: .alternative,
            prescriptionFingerprint: try WorkoutPrescriptionFingerprint.make(base),
            originalWorkoutID: "original"
        )
        let committed = workout(duration: 45, distance: nil, commitment: commitment)
        let decoded = try JSONDecoder().decode(DailyWorkout.self, from: JSONEncoder().encode(committed))
        #expect(decoded.commitment == commitment)
    }

    private func workout(
        duration: Int,
        distance: Double?,
        completed: Bool = false,
        commitment: WorkoutCommitment? = nil
    ) -> DailyWorkout {
        DailyWorkout(
            id: "today", date: Date(timeIntervalSince1970: 1_800_000_000),
            dayOfWeek: .monday, workoutType: distance == nil ? .strengthTraining : .easyRun,
            title: distance == nil ? "Strength" : "Easy run", description: "Test prescription",
            duration: duration, distance: distance, targetPace: distance == nil ? nil : "10:00 /mi",
            exercises: nil, isCompleted: completed, completedActivityId: nil,
            commitment: commitment
        )
    }
}
```

- [ ] **Step 2: Run the focused tests and confirm missing types fail**

Run:

```bash
xcodebuild -project 'Runaway iOS.xcodeproj' -scheme 'Runaway iOS' \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
  -only-testing:'Runaway iOSTests/WorkoutCommitmentTests' test
```

Expected: compilation fails because `WorkoutCommitment` and `WorkoutPrescriptionFingerprint` do not exist.

- [ ] **Step 3: Add commitment metadata and stable prescription fingerprinting**

```swift
struct WorkoutCommitment: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case recommendation, alternative, custom
    }
    let committedAt: Date
    let source: Source
    let prescriptionFingerprint: String
    let originalWorkoutID: String?
}

enum WorkoutPrescriptionFingerprint {
    static func make(_ workout: DailyWorkout) throws -> String
}
```

Fingerprint a private sorted-key payload containing workout type, title, description, duration, distance, semantic target pace, exercises, and accepted prescription. Exclude completion and commitment metadata. Add `var commitment: WorkoutCommitment? = nil` to `DailyWorkout` and its coding keys.

- [ ] **Step 4: Run the focused tests**

Expected: all `WorkoutCommitmentTests` pass.

- [ ] **Step 5: Commit this independently reviewable model change**

```bash
git add 'Runaway iOS/Models/WeeklyTrainingPlan.swift' \
  'Runaway iOS/Models/WorkoutCommitment.swift' \
  'Runaway iOS/Runaway iOSTests/WorkoutCommitmentTests.swift'
git commit -m 'feat: make workout commitment part of the plan'
```

### Task 2: Complete Choice Catalog and Draft Prescription Policy

**Files:**
- Create: `Runaway iOS/Models/TodayWorkoutChoice.swift`
- Create: `Runaway iOS/Models/TodayWorkoutChoicePolicy.swift`
- Modify: `Runaway iOS/Models/CompleteStrengthSessionPolicy.swift`
- Modify: `Runaway iOS/Models/TodayRecommendationDetailPolicy.swift`
- Test: `Runaway iOS/Runaway iOSTests/TodayWorkoutChoicePolicyTests.swift`

**Interfaces:**
- Consumes: `TrainingProfile`, `WorkoutType`, `DailyWorkout`, readiness score, current recommendation, complete strength prescription policy.
- Produces: `TodayWorkoutChoice`, `TodayWorkoutChoice.Availability`, `TodayWorkoutDraft`, `TodayWorkoutChoicePolicy.choices(context:)`, `TodayWorkoutChoicePolicy.draft(for:context:)`.

- [ ] **Step 1: Write failing visibility and prescription tests**

```swift
@Test func everyEnabledProfileActivityIsVisibleAlongsideRecoveryAndRest() throws {
    let context = ChoiceTestContext.profile(running: 3, strength: 2, cycling: 1, swimming: 1)
    let choices = TodayWorkoutChoicePolicy.choices(context: context)
    #expect(Set(choices.map(\.activity)).isSuperset(of: [.running, .strength, .cycling, .swimming]))
    #expect(choices.contains { $0.workoutType == .rest })
}

@Test func unsupportedDoseIsVisibleWithSpecificBlocker() throws {
    let choices = TodayWorkoutChoicePolicy.choices(context: .profileWithoutStrengthBenchmarks)
    let strength = try #require(choices.first { $0.activity == .strength })
    #expect(strength.availability == .blocked(.missingStrengthBenchmarks))
}

@Test func nonRunningDraftNeverCarriesPace() throws {
    let draft = try #require(TodayWorkoutChoicePolicy.draft(for: .walking, context: .ready))
    #expect(draft.workout.displayTargetPace == nil)
}
```

- [ ] **Step 2: Run the focused tests and confirm the policy is missing**

Expected: compilation fails for the new choice types.

- [ ] **Step 3: Implement choice, blocker, and draft types**

```swift
struct TodayWorkoutChoice: Identifiable, Equatable, Sendable {
    enum Availability: Equatable, Sendable {
        case available
        case blocked(TodayWorkoutChoiceBlocker)
    }
    let id: String
    let activity: TrainingActivity?
    let workoutType: WorkoutType
    let title: String
    let reason: String
    let availability: Availability
    let isRecommended: Bool
}

struct TodayWorkoutDraft: Equatable, Sendable {
    var workout: DailyWorkout
    let source: WorkoutCommitment.Source
    let reason: String
}
```

Candidate generation must enumerate Training Profile activities before filtering for safety. Map all supported `WorkoutType` variants for each enabled modality, append recovery/rest, and expose blocker text for unavailable options. Generate complete default doses through existing deterministic policies.

- [ ] **Step 4: Add custom draft validation tests and implementation**

```swift
@Test func customStrengthRequiresExercisesSetsAndReps() {
    let invalid = TodayWorkoutDraft.customStrength(exercises: [])
    #expect(invalid.validationIssues == [.missingExercises])
}

@Test func customRunAcceptsTimeOrDistanceButRejectsNeither() {
    #expect(TodayWorkoutDraft.customRun(minutes: 30, miles: nil).validationIssues.isEmpty)
    #expect(TodayWorkoutDraft.customRun(minutes: nil, miles: nil).validationIssues == [.missingRunningDose])
}
```

Add modality-aware validation that never accepts pace as the only running dose and requires sets/reps for every strength exercise.

- [ ] **Step 5: Run all choice-policy tests**

Expected: all tests pass, including profile modalities, blockers, and custom validation.

- [ ] **Step 6: Commit the choice policy**

```bash
git add 'Runaway iOS/Models/TodayWorkoutChoice.swift' \
  'Runaway iOS/Models/TodayWorkoutChoicePolicy.swift' \
  'Runaway iOS/Models/CompleteStrengthSessionPolicy.swift' \
  'Runaway iOS/Models/TodayRecommendationDetailPolicy.swift' \
  'Runaway iOS/Runaway iOSTests/TodayWorkoutChoicePolicyTests.swift'
git commit -m 'feat: offer complete daily workout choices'
```

### Task 3: Revision-Bound Week Preview and Atomic Commitment

**Files:**
- Create: `Runaway iOS/Models/TodayWorkoutDecisionPreview.swift`
- Create: `Runaway iOS/Services/TodayWorkoutDecisionService.swift`
- Modify: `Runaway iOS/Services/RemainingWeekTrainingPolicy.swift`
- Modify: `Runaway iOS/Managers/DataManager.swift`
- Test: `Runaway iOS/Runaway iOSTests/TodayWorkoutDecisionServiceTests.swift`

**Interfaces:**
- Consumes: `TodayWorkoutDraft`, current `WeeklyTrainingPlan`, `TrainingProfile`, existing plan fingerprint, existing remaining-week policy.
- Produces: `TodayWorkoutDecisionPreview`, `TodayWorkoutDecisionService.preview(draft:context:)`, `TodayWorkoutDecisionService.commit(preview:currentPlan:)`.

- [ ] **Step 1: Write failing preview invariants**

```swift
@Test func previewProtectsCompletedAndGoalCriticalWork() throws {
    let preview = try service.preview(draft: .walking, context: .weekWithCompletedRunAndKeyLongRun)
    #expect(preview.proposedPlan.completedWorkoutIDs == preview.originalPlan.completedWorkoutIDs)
    #expect(preview.proposedPlan.containsGoalCriticalLongRun)
}

@Test func previewDoesNotPersist() throws {
    _ = try service.preview(draft: .walking, context: context)
    #expect(repository.savedPlans.isEmpty)
}

@Test func stalePreviewCannotCommit() throws {
    let preview = try service.preview(draft: .walking, context: context)
    #expect(throws: TodayWorkoutDecisionError.stalePlan) {
        try service.commit(preview: preview, currentPlan: context.changedPlan)
    }
    #expect(repository.savedPlans.isEmpty)
}
```

- [ ] **Step 2: Run tests and confirm the decision service is absent**

Expected: compilation fails for `TodayWorkoutDecisionService`.

- [ ] **Step 3: Implement immutable preview output**

```swift
struct TodayWorkoutDecisionPreview: Identifiable, Sendable {
    let id: UUID
    let originalPlanRevision: String
    let originalPlan: WeeklyTrainingPlan
    let proposedPlan: WeeklyTrainingPlan
    let committedWorkoutID: String
    let changes: [CoachChange]
    let warnings: [TodayWorkoutDecisionWarning]
    let createdAt: Date
}
```

Build the proposed week by replacing today with the draft, rebalancing only future incomplete sessions, and deriving human-readable changes. Add commitment metadata only to the proposed workout. Do not mutate `DataManager` during preview.

- [ ] **Step 4: Implement revision-checked commit**

```swift
@MainActor
protocol TodayWorkoutPlanPersisting {
    func activePlan() -> WeeklyTrainingPlan?
    func save(_ plan: WeeklyTrainingPlan, expectedRevision: String) throws
}

func commit(
    preview: TodayWorkoutDecisionPreview,
    currentPlan: WeeklyTrainingPlan
) throws -> WeeklyTrainingPlan
```

Recompute the current fingerprint, reject mismatch, validate ownership and commitment fingerprint, then call one existing plan update. On success post one named notification/request-sync event consumed by widgets and workout prompts.

- [ ] **Step 5: Add failure-boundary tests**

```swift
@Test func persistenceFailureLeavesOriginalActiveAndDraftRetryable() throws {
    repository.saveError = TestError.offline
    let preview = try service.preview(draft: .walking, context: context)
    #expect(throws: TestError.offline) { try service.commit(preview: preview, currentPlan: context.plan) }
    #expect(repository.active == context.plan)
    #expect(preview.proposedPlan.workout(for: .monday)?.commitment != nil)
}
```

- [ ] **Step 6: Run decision-service and existing rebalancing tests**

Expected: new tests pass and existing `TodayRecommendationPolicyTests` and remaining-week tests remain green.

- [ ] **Step 7: Commit the atomic decision service**

```bash
git add 'Runaway iOS/Models/TodayWorkoutDecisionPreview.swift' \
  'Runaway iOS/Services/TodayWorkoutDecisionService.swift' \
  'Runaway iOS/Services/RemainingWeekTrainingPolicy.swift' \
  'Runaway iOS/Managers/DataManager.swift' \
  'Runaway iOS/Runaway iOSTests/TodayWorkoutDecisionServiceTests.swift'
git commit -m 'feat: preview and commit adaptive daily plans'
```

### Task 4: Unified Performance Coach Decision Experience

**Files:**
- Create: `Runaway iOS/Views/Coach/TodayWorkoutDecisionSheet.swift`
- Create: `Runaway iOS/Views/Coach/TodayWorkoutPrescriptionEditor.swift`
- Create: `Runaway iOS/Views/Coach/WeekImpactPreview.swift`
- Create: `Runaway iOS/ViewModels/TodayWorkoutDecisionViewModel.swift`
- Modify: `Runaway iOS/Components/WorkoutComponents.swift`
- Modify: `Runaway iOS/Views/TrainingView.swift`
- Modify: `Runaway iOS/Views/WeeklyTrainingPlanView.swift`
- Test: `Runaway iOS/Runaway iOSTests/TodayWorkoutDecisionViewModelTests.swift`
- Test: `Runaway iOS/Runaway iOSUITests/PerformanceCoachDecisionUITests.swift`

**Interfaces:**
- Consumes: Task 2 choices/drafts and Task 3 preview/commit service.
- Produces: one stateful Performance Coach card and `TodayWorkoutDecisionSheet`.

- [ ] **Step 1: Write view-model state-transition tests**

```swift
@Test func recommendationRequiresExplicitCommit() async throws {
    let model = TodayWorkoutDecisionViewModel.stub()
    await model.load()
    #expect(model.phase == .recommended)
    await model.select(model.recommendedChoiceID)
    #expect(model.phase == .editing)
    #expect(model.persistedPlan.commitment == nil)
    await model.buildPreview()
    #expect(model.phase == .previewing)
    #expect(model.persistedPlan.commitment == nil)
    try await model.commit()
    #expect(model.phase == .committed)
}

@Test func blockedChoiceExplainsWhyAndCannotPreview() async {
    let model = TodayWorkoutDecisionViewModel.stub(blocked: .missingStrengthBenchmarks)
    await model.select("strength")
    #expect(model.blockerMessage == "Add current strength benchmarks to build a complete strength prescription.")
    #expect(model.canPreview == false)
}
```

- [ ] **Step 2: Run tests and confirm the view model is absent**

Expected: compilation fails for `TodayWorkoutDecisionViewModel`.

- [ ] **Step 3: Implement the observable view model**

```swift
@MainActor @Observable
final class TodayWorkoutDecisionViewModel {
    enum Phase: Equatable { case loading, recommended, choosing, editing, previewing, committing, committed, failed }
    private(set) var phase: Phase
    private(set) var choices: [TodayWorkoutChoice]
    var draft: TodayWorkoutDraft?
    private(set) var preview: TodayWorkoutDecisionPreview?
    private(set) var errorMessage: String?
}
```

Keep all mutations behind `select`, `updateDraft`, `buildPreview`, and `commit`. A failed save returns to preview with the draft intact.

- [ ] **Step 4: Replace the detached Today adjustment row**

Modify the Next Up/Performance Coach component so it owns:

```swift
PerformanceCoachActionState(
    status: workout.commitment == nil ? .recommended : .committed,
    primaryTitle: workout.commitment == nil ? "Commit to this workout" : "View committed workout",
    secondaryTitle: workout.commitment == nil ? "Choose something else" : "Change"
)
```

Remove the standalone `Adjust today` row and route both secondary actions to `TodayWorkoutDecisionSheet`.

- [ ] **Step 5: Build the chooser and prescription editor**

Use native `Button`, `NavigationStack`, `sheet`, `Form`/Runaway card primitives, `DatePicker` only where date is relevant, and existing theme tokens. Show every choice; blocked rows remain non-committing buttons with their explanation visible. Use modality-specific editor sections and a single dominant amber continuation action.

- [ ] **Step 6: Build the week-impact preview**

Render `preview.changes` as concise before/after rows, followed by protected-session and weekly-volume summaries. The only persistence action is:

```swift
Button("Commit to \(draft.workout.title)") {
    Task { try await model.commit() }
}
```

- [ ] **Step 7: Add UI assertions for hierarchy and options**

```swift
func testTodayHasOneDecisionSurfaceAndAllProfileActivities() throws {
    app.launchArguments += ["-uiFixture", "multi-activity-profile"]
    app.launch()
    XCTAssertEqual(app.buttons["Adjust today"].count, 0)
    app.buttons["Choose something else"].tap()
    XCTAssertTrue(app.buttons["Running"].exists)
    XCTAssertTrue(app.buttons["Strength"].exists)
    XCTAssertTrue(app.buttons["Cycling"].exists)
    XCTAssertTrue(app.buttons["Swimming"].exists)
    XCTAssertTrue(app.buttons["Rest"].exists)
    XCTAssertTrue(app.buttons["Build my own"].exists)
}
```

- [ ] **Step 8: Run view-model tests, UI tests, and an iOS 27 build**

Expected: transitions pass, chooser exposes all fixture activities, and the app builds.

- [ ] **Step 9: Commit the unified Today experience**

```bash
git add 'Runaway iOS/Views/Coach' 'Runaway iOS/ViewModels/TodayWorkoutDecisionViewModel.swift' \
  'Runaway iOS/Components/WorkoutComponents.swift' 'Runaway iOS/Views/TrainingView.swift' \
  'Runaway iOS/Views/WeeklyTrainingPlanView.swift' \
  'Runaway iOS/Runaway iOSTests/TodayWorkoutDecisionViewModelTests.swift' \
  'Runaway iOS/Runaway iOSUITests/PerformanceCoachDecisionUITests.swift'
git commit -m 'feat: unify todays performance coach decision'
```

### Task 5: Retire Activities Commitment UI and Migrate Legacy Intent

**Files:**
- Modify: `Runaway iOS/Views/ActivitiesView.swift`
- Delete: `Runaway iOS/Components/CompactCommitmentCard.swift`
- Create: `Runaway iOS/Services/LegacyCommitmentMigrationService.swift`
- Modify: `Runaway iOS/Services/CommitmentService.swift`
- Modify: `Runaway iOS/Managers/DataManager.swift`
- Test: `Runaway iOS/Runaway iOSTests/LegacyCommitmentMigrationTests.swift`
- Test: `Runaway iOS/Runaway iOSUITests/ActivitiesHistoryUITests.swift`

**Interfaces:**
- Consumes: legacy `DailyCommitment`, current committed plan workout, Task 2 draft policy.
- Produces: `LegacyCommitmentMigrationService.proposal(legacy:plan:profile:)`; no new commitment writes from current UI.

- [ ] **Step 1: Write precedence and migration tests**

```swift
@Test func committedPlanAlwaysWinsOverLegacyRow() throws {
    let result = service.proposal(legacy: .run, plan: .withCommittedStrength, profile: .mixed)
    #expect(result == nil)
}

@Test func legacyRowCreatesAReviewableDraftWithoutPersisting() throws {
    let result = try #require(service.proposal(legacy: .walk, plan: .uncommitted, profile: .mixed))
    #expect(result.draft.workout.workoutType == .walking)
    #expect(result.requiresConfirmation)
    #expect(repository.savedPlans.isEmpty)
}
```

- [ ] **Step 2: Run tests and confirm migration service is absent**

Expected: compilation fails for the migration service.

- [ ] **Step 3: Implement read-only legacy migration proposals**

Map the four legacy activity types to Task 2 choices. Never mutate the plan from a legacy row. Surface the proposal inside Performance Coach once per day with `Review old commitment`; confirmation proceeds through the normal preview flow.

- [ ] **Step 4: Remove future-action UI from Activities**

Delete `CompactCommitmentCard()` from `ActivitiesView`, remove the component file from the target, and leave activity summary, filters, sync, empty state, and activity rows unchanged.

- [ ] **Step 5: Disable current-product writes through `CommitmentService`**

Move `createCommitment` and `updateCommitment` behind a clearly named legacy-only interface used by migration/widget cleanup code. Remove all current UI callers. Keep decoding and historical fetch behavior.

- [ ] **Step 6: Add and run Activities UI assertion**

```swift
func testActivitiesContainsOnlyRecordedWork() {
    app.launch()
    app.tabBars.buttons["Activities"].tap()
    XCTAssertFalse(app.staticTexts["Set today's commitment"].exists)
    XCTAssertTrue(app.staticTexts["YOUR WORK, RECORDED"].exists)
}
```

Expected: migration tests and Activities UI test pass.

- [ ] **Step 7: Commit legacy retirement**

```bash
git add -A 'Runaway iOS/Views/ActivitiesView.swift' \
  'Runaway iOS/Components/CompactCommitmentCard.swift' \
  'Runaway iOS/Services/LegacyCommitmentMigrationService.swift' \
  'Runaway iOS/Services/CommitmentService.swift' 'Runaway iOS/Managers/DataManager.swift' \
  'Runaway iOS/Runaway iOSTests/LegacyCommitmentMigrationTests.swift' \
  'Runaway iOS/Runaway iOSUITests/ActivitiesHistoryUITests.swift'
git commit -m 'refactor: retire the separate commitment experience'
```

### Task 6: Commitment Completion and Celebration

**Files:**
- Create: `Runaway iOS/Models/CommittedWorkoutCompletionPolicy.swift`
- Modify: `Runaway iOS/Services/TrainingEvidenceImportService.swift`
- Modify: `Runaway iOS/Services/CelebrationService.swift`
- Modify: `Runaway iOS/Models/AcceptedPrescriptionCompletionPolicy.swift`
- Test: `Runaway iOS/Runaway iOSTests/CommittedWorkoutCompletionPolicyTests.swift`

**Interfaces:**
- Consumes: committed `DailyWorkout`, imported `Activity`, accepted completion/result.
- Produces: `CommittedWorkoutCompletionPolicy.status(workout:evidence:) -> WorkoutCompletionStatus` and one completion-transition event.

- [ ] **Step 1: Write full, partial, mismatch, and duplicate evidence tests**

```swift
@Test(arguments: [
    CompletionCase.run(fullMiles: 4, actualMiles: 4, expected: .complete),
    CompletionCase.run(fullMiles: 4, actualMiles: 2, expected: .partial),
    CompletionCase.modalityMismatch(expected: .notCompleted),
    CompletionCase.duplicateImport(expected: .complete)
])
func completionStatus(testCase: CompletionCase) throws {
    #expect(CommittedWorkoutCompletionPolicy.status(
        workout: testCase.workout,
        evidence: testCase.evidence
    ) == testCase.expected)
}
```

- [ ] **Step 2: Run tests and confirm the policy is absent**

Expected: compilation fails for `CommittedWorkoutCompletionPolicy`.

- [ ] **Step 3: Implement semantic matching**

Reuse existing activity-category mappings and accepted-prescription completion thresholds. Require matching modality; compare time/distance for endurance and accepted blocks for strength. Deduplicate by existing imported source record IDs.

- [ ] **Step 4: Trigger celebration only on a status transition**

Emit one event when a committed workout moves from not-completed/partial to complete. Route that event to existing celebration intensity using the committed prescription's significance; never celebrate repeated sync of the same activity.

- [ ] **Step 5: Run completion, evidence-import, and duplicate-activity tests**

Expected: all pass with one celebration for one completion transition.

- [ ] **Step 6: Commit completion integration**

```bash
git add 'Runaway iOS/Models/CommittedWorkoutCompletionPolicy.swift' \
  'Runaway iOS/Services/TrainingEvidenceImportService.swift' \
  'Runaway iOS/Services/CelebrationService.swift' \
  'Runaway iOS/Models/AcceptedPrescriptionCompletionPolicy.swift' \
  'Runaway iOS/Runaway iOSTests/CommittedWorkoutCompletionPolicyTests.swift'
git commit -m 'feat: complete committed workouts from real evidence'
```

### Task 7: Notifications, Widget, and App Intents Use the Commitment

**Files:**
- Modify: `Runaway iOS/Models/WorkoutPrompt.swift`
- Modify: `Runaway iOS/Services/WorkoutPromptService.swift`
- Modify: `Runaway iOS/Services/PushNotificationService.swift`
- Modify: `Runaway iOS/Services/WidgetSyncService.swift`
- Modify: `RunawayWidget/RunawayWidget.swift`
- Create: `RunawayWidget/PerformanceCoachIntents.swift`
- Modify: `Runaway iOS/Views/MainView.swift`
- Test: `Runaway iOS/Runaway iOSTests/CommittedWorkoutDeliveryTests.swift`
- Test: `Runaway iOS/Runaway iOSTests/WidgetCommitmentTests.swift`

**Interfaces:**
- Consumes: committed current-plan workout and prescription fingerprint.
- Produces: committed prompt publication, widget commitment state, `CommitWorkoutIntent`, `ReviewWorkoutOptionsIntent`, `ViewCommittedWorkoutIntent`.

- [ ] **Step 1: Write delivery precedence and suppression tests**

```swift
@Test func committedWorkoutOverridesUncommittedRecommendation() throws {
    let publication = WorkoutPromptPublication.make(context: .committedStrengthOverRecommendedWalk)
    #expect(publication.today?.workout.workoutType.isStrength == true)
    #expect(publication.today?.state == .committed)
}

@Test func completedCommitmentSuppressesReminder() throws {
    let publication = WorkoutPromptPublication.make(context: .completedCommittedRun)
    #expect(publication.today == nil)
}
```

- [ ] **Step 2: Write widget state and stale-intent tests**

```swift
@Test func widgetUsesCommittedLabelAndExactDose() {
    let snapshot = WidgetTrainingSnapshot.make(context: .committedStrength)
    #expect(snapshot.nextUpStatus == .committed)
    #expect(snapshot.nextUpDose == "45 min · 5 exercises")
    #expect(snapshot.nextUpPace == nil)
}

@Test func staleIntentRequiresAppReviewInsteadOfCommitting() async throws {
    let result = try await CommitWorkoutIntent(revision: "old").perform(using: .newRevision)
    #expect(result.opensReview)
    #expect(result.didMutatePlan == false)
}
```

- [ ] **Step 3: Run tests and confirm missing delivery state fails**

Expected: compilation fails for committed publication/widget states and intents.

- [ ] **Step 4: Publish committed workout state**

Extend prompt content and widget snapshot with `recommended`, `committed`, and `completed` state plus the prescription fingerprint. Prefer committed current-plan content, preserve semantic pace filtering, and suppress post-completion reminders.

- [ ] **Step 5: Add revision-safe App Intents**

`CommitWorkoutIntent` may commit only the exact currently published recommendation revision through `TodayWorkoutDecisionService`. A mismatch returns an app-opening result targeted at review. The review and view intents route through existing app routing to the unified sheet/detail.

- [ ] **Step 6: Make synchronization failure retryable**

After a successful plan commit, request widget reload and workout-prompt publication. Preserve plan state if either fails, set a sync-status message, and retry through the existing foreground `requestSync` path.

- [ ] **Step 7: Run delivery, widget, intent, and notification tests**

Expected: committed content wins, completion suppresses reminders, stale intents do not mutate, and non-running pace remains absent.

- [ ] **Step 8: Commit cross-surface propagation**

```bash
git add 'Runaway iOS/Models/WorkoutPrompt.swift' 'Runaway iOS/Services/WorkoutPromptService.swift' \
  'Runaway iOS/Services/PushNotificationService.swift' 'Runaway iOS/Services/WidgetSyncService.swift' \
  'RunawayWidget/RunawayWidget.swift' 'RunawayWidget/PerformanceCoachIntents.swift' \
  'Runaway iOS/Views/MainView.swift' \
  'Runaway iOS/Runaway iOSTests/CommittedWorkoutDeliveryTests.swift' \
  'Runaway iOS/Runaway iOSTests/WidgetCommitmentTests.swift'
git commit -m 'feat: carry workout commitments across ios surfaces'
```

### Task 8: Full Regression, Accessibility, and Physical-Device Handoff

**Files:**
- Modify only files implicated by failing verification; do not add scope.
- Update: `docs/superpowers/specs/2026-09-21-performance-coach-daily-decision-design.md` only if implementation intentionally differs from the approved contract.

**Interfaces:**
- Consumes: completed Tasks 1-7.
- Produces: verified release candidate and a concise physical-device checklist.

- [ ] **Step 1: Run focused model and integration suites**

```bash
xcodebuild -project 'Runaway iOS.xcodeproj' -scheme 'Runaway iOS' \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
  -only-testing:'Runaway iOSTests/WorkoutCommitmentTests' \
  -only-testing:'Runaway iOSTests/TodayWorkoutChoicePolicyTests' \
  -only-testing:'Runaway iOSTests/TodayWorkoutDecisionServiceTests' \
  -only-testing:'Runaway iOSTests/TodayWorkoutDecisionViewModelTests' \
  -only-testing:'Runaway iOSTests/LegacyCommitmentMigrationTests' \
  -only-testing:'Runaway iOSTests/CommittedWorkoutCompletionPolicyTests' \
  -only-testing:'Runaway iOSTests/CommittedWorkoutDeliveryTests' \
  -only-testing:'Runaway iOSTests/WidgetCommitmentTests' test
```

Expected: zero failing tests. If the simulator runner fails before bootstrap, preserve the xcresult evidence and use an already-booted simulator before classifying it as infrastructure.

- [ ] **Step 2: Run the full app and widget build**

```bash
xcodebuild -project 'Runaway iOS.xcodeproj' -scheme 'Runaway iOS' \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
  build CODE_SIGNING_ALLOWED=NO
```

Expected: `BUILD SUCCEEDED` with no new warnings in changed files.

- [ ] **Step 3: Run UI tests for Today and Activities**

```bash
xcodebuild -project 'Runaway iOS.xcodeproj' -scheme 'Runaway iOS' \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
  -only-testing:'Runaway iOSUITests/PerformanceCoachDecisionUITests' \
  -only-testing:'Runaway iOSUITests/ActivitiesHistoryUITests' test
```

Expected: one daily decision surface, all fixture modalities visible, explicit commitment required, and no Activities commitment card.

- [ ] **Step 4: Perform simulator accessibility and visual checks**

Check default and accessibility Dynamic Type for recommended, chooser, editor, impact, committed, error, and completed states. With VoiceOver, confirm the card reads workout, dose, reason, status, then actions. Confirm 44-point hit targets, no clipped actions, semantic status text, and reduced-motion behavior.

- [ ] **Step 5: Perform physical-device notification and widget checks**

On a production-capable device:

1. Commit the recommendation and confirm Today changes to `Committed`.
2. Confirm the widget changes to `COMMITTED` with the same dose.
3. Schedule a workout notification and confirm it names the committed workout.
4. Change to a different modality and confirm week preview, widget, and later notification update.
5. Import a matching activity and confirm completion plus one celebration.
6. Confirm no reminder is delivered after completion.

- [ ] **Step 6: Review the final diff against the approved specification**

Confirm every spec section has an implementation or explicit out-of-scope disposition. Confirm no current UI writes standalone commitments and no raw internal reason codes appear in user-facing copy.

- [ ] **Step 7: Commit only verification-driven corrections**

```bash
git add -A
git commit -m 'fix: complete performance coach verification'
```

Skip this commit when verification required no corrections.
