# Runaway Coach Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Runaway-owned activity recording with a proactive, deterministic training agent that observes imported evidence, safely adapts plans, requests approval for material changes, and explains decisions on-device.

**Architecture:** The iPhone owns health evidence, training mathematics, decision classification, authoritative plan mutations, audit history, and Apple Foundation Models narration. Supabase provides authenticated storage, scheduling, APNs delivery, and opaque wake-up coordination only; it never calculates or generates training prescriptions.

**Tech Stack:** Swift 6.4, SwiftUI, Swift Testing/XCTest, HealthKit, Foundation Models, UserNotifications, App Intents, WidgetKit, Supabase Swift, Supabase Postgres/RLS, Deno Edge Functions, APNs.

**Spec:** `docs/superpowers/specs/2026-09-20-runaway-coach-agent-design.md`

## Global Constraints

- Deployment remains iOS 27 on Apple Intelligence-capable hardware.
- No external LLM endpoint, key, client, or fallback is permitted.
- Apple Foundation Models may narrate structured decisions but may not calculate or persist prescriptions.
- Raw HealthKit measurements remain on-device.
- Supabase stores only synchronization, delivery, approval, and non-sensitive decision metadata.
- Runaway must not start GPS, HealthKit workout sessions, or recording-specific Live Activities.
- Imported Apple Health, Apple Watch, and Garmin activities remain authoritative evidence sources.
- Safe changes are visible, logged, reversible, and may never increase weekly load.
- Material changes remain proposals until explicit athlete approval.
- Every mutation verifies athlete ownership and expected plan revision.

## Review Focus

- Duplicate HealthKit, Garmin, and APNs events must produce one decision and one notification; Tasks 2 and 5 pin idempotency.
- A delayed background event must never overwrite a newer user choice or plan revision; Tasks 4 and 5 pin stale-revision behavior.
- Missing readiness, weather, or local-model availability must lower confidence or use deterministic copy without blocking the workout; Tasks 3 and 7 pin degraded operation.
- Removing recording must not remove imported history, manual completion, reconciliation, or Apple Watch workout handoff; Task 1 pins retained behavior.
- Logout or athlete switching must prevent one athlete's pending events, decisions, or notifications from appearing for another; Tasks 4 and 6 pin ownership isolation.

---

### Task 1: Retire Runaway Activity Recording

**Files:**
- Create: `scripts/verify-no-activity-recorder.sh`
- Delete: `Runaway iOS/Views/RunRecordingView.swift`
- Delete: `Runaway iOS/Services/RunRecorder.swift`
- Delete: `Runaway iOS/Services/HealthKit/HealthKitWorkoutService.swift`
- Delete: `RunawayWidget/RunawayWidgetLiveActivity.swift`
- Modify: `Runaway iOS/Views/MainView.swift`
- Modify: `RunawayWidget/RunawayWidgetBundle.swift`
- Modify: `Runaway iOS/Info.plist`
- Modify: `RunawayWidget/Info.plist`
- Test: `Runaway iOS/Runaway iOSTests/ActivityRecordingRetirementTests.swift`

**Interfaces:**
- Consumes: Existing imported `Activity`, `TrainingObservation`, `TrainingSessionResult`, and Apple Watch handoff flows.
- Produces: An import-only app with no recorder symbols, recording UI, workout-session creation, or recording Live Activity.

- [ ] **Step 1: Add a failing source-boundary test**

Create `scripts/verify-no-activity-recorder.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
forbidden='RunRecordingView|RunRecorder|HealthKitWorkoutService|StartRunFAB|RunawayWidgetLiveActivity|startWorkout\('
if rg -n "$forbidden" 'Runaway iOS' RunawayWidget Shared; then
  echo "Runaway-owned activity recording is still present" >&2
  exit 1
fi
```

Add `ActivityRecordingRetirementTests` that verifies `AppRouter.deepLinkRoute` still resolves imported activity details and `TrainingSessionReferenceBuilder` still creates completion references from imported evidence.

- [ ] **Step 2: Run the boundary test and verify it fails**

Run: `bash scripts/verify-no-activity-recorder.sh`

Expected: FAIL with references in `MainView.swift`, recorder services, and the widget Live Activity.

- [ ] **Step 3: Remove recorder entry points and implementation**

Delete `showingRunRecording`, the Today overlay, its full-screen cover, and `StartRunFAB` from `MainView`. Delete the four recorder-only files and remove `RunawayWidgetLiveActivity()` from `RunawayWidgetBundle`.

Remove `NSSupportsLiveActivities` and recorder-only location background modes when they are not used by another declared feature. Keep HealthKit read authorization, activity history, reconciliation, manual completion, and imported activity routes unchanged.

- [ ] **Step 4: Prove the recorder is gone and retained flows compile**

Run: `bash scripts/verify-no-activity-recorder.sh`

Expected: PASS with no output.

Run: `xcodebuild test -project 'Runaway iOS.xcodeproj' -scheme 'Runaway iOS' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:'Runaway iOSTests/ActivityRecordingRetirementTests'`

Expected: PASS.

- [ ] **Step 5: Commit the recorder retirement**

```bash
git add -A -- 'Runaway iOS/Views/MainView.swift' 'Runaway iOS/Views/RunRecordingView.swift' 'Runaway iOS/Services/RunRecorder.swift' 'Runaway iOS/Services/HealthKit/HealthKitWorkoutService.swift' 'RunawayWidget/RunawayWidgetLiveActivity.swift' 'RunawayWidget/RunawayWidgetBundle.swift' 'Runaway iOS/Info.plist' 'RunawayWidget/Info.plist' 'Runaway iOS/Runaway iOSTests/ActivityRecordingRetirementTests.swift' scripts/verify-no-activity-recorder.sh
git commit -m "refactor: retire in-app activity recording"
```

### Task 2: Define Coach Events and Decisions

**Files:**
- Create: `Runaway iOS/Models/CoachEvent.swift`
- Create: `Runaway iOS/Models/CoachDecision.swift`
- Test: `Runaway iOS/Runaway iOSTests/CoachDomainTests.swift`

**Interfaces:**
- Consumes: Athlete IDs, workout/result identifiers, opaque plan revisions, and normalized event payload values.
- Produces: `CoachEvent`, `CoachChange`, `CoachProposal`, `CoachDecision`, `CoachDecisionClassification`, and `CoachDecisionState`.

- [ ] **Step 1: Write failing domain validation tests**

Cover stable identity, finite dates, positive athlete ownership, deduplication keys, Codable round trips, state transitions, and rejection of empty proposals.

```swift
@Test func duplicateSourceEventsHaveTheSameIdentity() throws {
    let first = CoachEvent(athleteID: 42, kind: .workoutImported,
        source: .healthKit, occurredAt: instant, receivedAt: instant,
        sourceRecordID: "health-123", payload: .workoutImported(activityID: 99))
    let retry = CoachEvent(athleteID: 42, kind: .workoutImported,
        source: .healthKit, occurredAt: instant, receivedAt: instant.addingTimeInterval(5),
        sourceRecordID: "health-123", payload: .workoutImported(activityID: 99))
    #expect(first.deduplicationKey == retry.deduplicationKey)
}
```

- [ ] **Step 2: Run domain tests and verify they fail**

Run: `xcodebuild test -project 'Runaway iOS.xcodeproj' -scheme 'Runaway iOS' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:'Runaway iOSTests/CoachDomainTests'`

Expected: FAIL because coach domain types do not exist.

- [ ] **Step 3: Implement immutable domain types**

```swift
struct CoachEvent: Codable, Equatable, Identifiable, Sendable {
    enum Source: String, Codable, Sendable { case app, healthKit, garmin, weather, schedule, athlete, notification }
    enum Kind: String, Codable, Sendable { case appForegrounded, scheduledCheckIn, workoutImported, sessionResultChanged, sessionElapsed, readinessChanged, weatherChanged, availabilityChanged, profileChanged, reevaluationRequested, proposalResponded }
    let id: UUID
    let athleteID: Int
    let kind: Kind
    let source: Source
    let occurredAt: Date
    let receivedAt: Date
    let sourceRecordID: String
    let payload: Payload
    var deduplicationKey: String { "\(athleteID):\(source.rawValue):\(sourceRecordID)" }
    var isValid: Bool { athleteID > 0 && !sourceRecordID.isEmpty && occurredAt.timeIntervalSince1970.isFinite && receivedAt >= occurredAt }
}
```

`CoachDecision` stores event IDs, before/after revision strings, structured reason codes, changes, confidence, missing-data flags, policy version, lifecycle state, timestamps, and reversible prior plan data. Generated prose is excluded from authoritative evidence.

- [ ] **Step 4: Run domain tests**

Run the Task 2 test command.

Expected: PASS.

- [ ] **Step 5: Commit coach domain types**

```bash
git add 'Runaway iOS/Models/CoachEvent.swift' 'Runaway iOS/Models/CoachDecision.swift' 'Runaway iOS/Runaway iOSTests/CoachDomainTests.swift'
git commit -m "feat: add coach event and decision domain"
```

### Task 3: Add Deterministic Adjustment Classification

**Files:**
- Create: `Runaway iOS/Services/CoachAdjustmentPolicy.swift`
- Test: `Runaway iOS/Runaway iOSTests/CoachAdjustmentPolicyTests.swift`

**Interfaces:**
- Consumes: `CoachProposal`, `WeeklyTrainingPlan`, availability, safety flags, and expected revision.
- Produces: `CoachAdjustmentPolicy.classify(_:) -> CoachDecisionClassification` plus machine-readable reasons.

- [ ] **Step 1: Write the failing classification matrix**

```swift
#expect(policy.classify(reducedEasyDuration) == .automatic)
#expect(policy.classify(movedRecoveryWithinWindow) == .automatic)
#expect(policy.classify(increasedWeeklyLoad) == .approvalRequired)
#expect(policy.classify(replacedKeyWorkout) == .approvalRequired)
#expect(policy.classify(consecutiveHighIntensity) == .blocked)
#expect(policy.classify(painOverride) == .blocked)
#expect(policy.classify(staleRevision) == .blocked)
```

Add missing-weather and missing-readiness cases. They lower confidence without fabricating evidence or blocking an otherwise valid unchanged workout.

- [ ] **Step 2: Run classification tests and verify they fail**

Run: `xcodebuild test -project 'Runaway iOS.xcodeproj' -scheme 'Runaway iOS' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:'Runaway iOSTests/CoachAdjustmentPolicyTests'`

Expected: FAIL.

- [ ] **Step 3: Implement a pure value-type policy**

```swift
enum CoachAdjustmentPolicy {
    static let version = "coach-adjustment-v1"

    static func classify(_ proposal: CoachProposal) -> CoachDecisionClassification {
        if proposal.isStale || proposal.safetyFlags.contains(.pain) || proposal.createsUnsafeIntensitySpacing { return .blocked }
        if proposal.weeklyLoadDelta > 0 || proposal.replacesKeyWorkout || proposal.cascadingChangeCount > 1 { return .approvalRequired }
        return .automatic
    }
}
```

Automatic changes must preserve completed sessions, explicit choices, availability, and key-session spacing and may not increase weekly load.

- [ ] **Step 4: Run classification tests**

Run the Task 3 test command.

Expected: PASS.

- [ ] **Step 5: Commit adjustment classification**

```bash
git add 'Runaway iOS/Services/CoachAdjustmentPolicy.swift' 'Runaway iOS/Runaway iOSTests/CoachAdjustmentPolicyTests.swift'
git commit -m "feat: classify safe coach adaptations"
```

### Task 4: Persist the Coach Ledger and Revision-Safe Undo

**Files:**
- Modify: `Runaway iOS/Services/ProtectedTrainingRepository.swift`
- Create: `Runaway iOS/Services/CoachDecisionLedger.swift`
- Test: `Runaway iOS/Runaway iOSTests/CoachDecisionLedgerTests.swift`

**Interfaces:**
- Consumes: Valid events and decisions for the active athlete.
- Produces: `appendEvent`, `pendingEvents`, `markProcessed`, `appendDecision`, `decisions`, `replaceDecision(expected:)`, and `undo(decisionID:currentPlan:)`.

- [ ] **Step 1: Write failing ledger tests**

Cover idempotent event retries, conflicting duplicates, ownership isolation, append-only history, compare-and-swap transitions, stale Undo, and athlete switching.

```swift
let saved = try ledger.append(event)
#expect(try ledger.append(event) == saved)
#expect(throws: ProtectedTrainingRepository.RepositoryError.ownershipMismatch) {
    try foreignLedger.append(event)
}
```

- [ ] **Step 2: Run ledger tests and verify they fail**

Run: `xcodebuild test -project 'Runaway iOS.xcodeproj' -scheme 'Runaway iOS' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:'Runaway iOSTests/CoachDecisionLedgerTests'`

Expected: FAIL.

- [ ] **Step 3: Add protected event and decision storage**

Store one atomic JSON envelope per event under `coach-events/` and one per decision under `coach-decisions/`. Reuse complete file protection, sorted-key encoding, and active-athlete ownership checks.

Use compare-and-swap transitions:

```swift
func replaceDecision(_ updated: CoachDecision, expected original: CoachDecision, athleteID: Int) throws -> CoachDecision
```

Undo verifies the active plan fingerprint equals the applied fingerprint before restoring the encoded prior `WeeklyTrainingPlan`. Undo appends a reversal decision instead of rewriting history.

- [ ] **Step 4: Run ledger tests**

Run the Task 4 test command.

Expected: PASS.

- [ ] **Step 5: Commit the protected ledger**

```bash
git add 'Runaway iOS/Services/ProtectedTrainingRepository.swift' 'Runaway iOS/Services/CoachDecisionLedger.swift' 'Runaway iOS/Runaway iOSTests/CoachDecisionLedgerTests.swift'
git commit -m "feat: persist auditable coach decisions"
```

### Task 5: Build Plan Comparison, Coordination, and Event Catch-Up

**Files:**
- Create: `Runaway iOS/Services/CoachPlanComparator.swift`
- Create: `Runaway iOS/Services/CoachCoordinator.swift`
- Create: `Runaway iOS/Services/CoachEventService.swift`
- Modify: `Runaway iOS/Services/TrainingDecisionInputBuilder.swift`
- Modify: `Runaway iOS/Services/RemainingWeekTrainingPolicy.swift`
- Modify: `Runaway iOS/Services/TrainingEvidenceImportService.swift`
- Modify: `Runaway iOS/Managers/DataManager.swift`
- Modify: `Runaway iOS/AppDelegate.swift`
- Test: `Runaway iOS/Runaway iOSTests/CoachCoordinatorTests.swift`
- Test: `Runaway iOS/Runaway iOSTests/CoachEventServiceTests.swift`

**Interfaces:**
- Consumes: Events, profile/history/results, active plan, readiness/weather/availability, and `GoalDrivenTrainingEngine` outputs.
- Produces: `CoachCoordinator.process(_:context:) async throws -> CoachProcessingResult` and `CoachEventService.processPending(athleteID:)`.

- [ ] **Step 1: Write failing orchestration scenarios**

Pin no-op decisions, missed sessions, unexpected workouts, partial completion, recovery degradation, weather reduction, automatic application, approval persistence without activation, blocked proposals, duplicate events, chronological catch-up, athlete switching, and stale revisions.

```swift
let result = try await coordinator.process(importedStrengthEvent, context: context)
#expect(result.decision.classification == .automatic)
#expect(result.decision.state == .applied)
#expect(result.activePlan.workout(for: tomorrow)?.workoutType != .lowerBody)
```

- [ ] **Step 2: Run coordinator tests and verify they fail**

Run: `xcodebuild test -project 'Runaway iOS.xcodeproj' -scheme 'Runaway iOS' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:'Runaway iOSTests/CoachCoordinatorTests' -only-testing:'Runaway iOSTests/CoachEventServiceTests'`

Expected: FAIL.

- [ ] **Step 3: Implement comparison and coordination**

`CoachPlanComparator` converts before/after plans into typed `CoachChange` values. The coordinator performs one guarded transaction:

```swift
func process(_ event: CoachEvent, context: CoachContext) async throws -> CoachProcessingResult {
    let stored = try ledger.append(event)
    if let existing = try ledger.decision(forEvent: stored.id) { return .existing(existing) }
    let proposal = try proposalBuilder.propose(event: stored, context: context)
    let classification = CoachAdjustmentPolicy.classify(proposal)
    return try ledger.commit(proposal, classification: classification, expectedRevision: context.planRevision)
}
```

A no-op marks the event processed without creating an intrusive notification. Existing deterministic policies remain the only plan-generation authority.

- [ ] **Step 4: Connect event ingestion**

`AppDelegate` recognizes `sync_type == "coach_event"`, persists the opaque event before returning background fetch completion, and processes only after authenticated ownership exists. `TrainingEvidenceImportService` emits a stable event after evidence is committed. `DataManager` processes pending events after a complete refresh.

- [ ] **Step 5: Run orchestration and existing engine tests**

Run the Task 5 command, then:

`xcodebuild test -project 'Runaway iOS.xcodeproj' -scheme 'Runaway iOS' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:'Runaway iOSTests/TodayRecommendationPolicyTests' -only-testing:'Runaway iOSTests/GoalDrivenTrainingEngineTests'`

Expected: PASS.

- [ ] **Step 6: Commit coordination and catch-up**

```bash
git add 'Runaway iOS/Services/CoachPlanComparator.swift' 'Runaway iOS/Services/CoachCoordinator.swift' 'Runaway iOS/Services/CoachEventService.swift' 'Runaway iOS/Services/TrainingDecisionInputBuilder.swift' 'Runaway iOS/Services/RemainingWeekTrainingPolicy.swift' 'Runaway iOS/Services/TrainingEvidenceImportService.swift' 'Runaway iOS/Managers/DataManager.swift' 'Runaway iOS/AppDelegate.swift' 'Runaway iOS/Runaway iOSTests/CoachCoordinatorTests.swift' 'Runaway iOS/Runaway iOSTests/CoachEventServiceTests.swift'
git commit -m "feat: coordinate proactive plan adaptations"
```

### Task 6: Add Coach Activity, Approval, Undo, and Notifications

**Files:**
- Create: `Runaway iOS/ViewModels/CoachActivityViewModel.swift`
- Create: `Runaway iOS/Views/Coach/CoachActivityView.swift`
- Create: `Runaway iOS/Views/Coach/CoachDecisionDetailView.swift`
- Create: `Runaway iOS/Components/CoachChangeBanner.swift`
- Modify: `Runaway iOS/Navigation/Router.swift`
- Modify: `Runaway iOS/Views/MainView.swift`
- Modify: `Runaway iOS/Views/PlanView.swift`
- Modify: `Runaway iOS/Views/SettingsView.swift`
- Modify: `Runaway iOS/Services/PushNotificationService.swift`
- Modify: `Runaway iOS/AppDelegate.swift`
- Test: `Runaway iOS/Runaway iOSTests/CoachActivityViewModelTests.swift`
- Test: `Runaway iOS/Runaway iOSTests/CoachNotificationTests.swift`

**Interfaces:**
- Consumes: Athlete-scoped ledger decisions, coordinator approval/undo methods, opaque notification identifiers, and expected revision.
- Produces: Coach history, decision details, proposal review, approval, rejection, Undo, and authenticated notification routes.

- [ ] **Step 1: Write failing UX state and notification tests**

Test grouping, pending-first ordering, foreign-athlete filtering, stale approval messaging, Undo success, malformed UUIDs, duplicate notification actions, and notification arrival before login.

```swift
await model.load(athleteID: 42)
#expect(model.sections.flatMap(\.decisions).allSatisfy { $0.athleteID == 42 })
#expect(model.pending.first?.availableActions == [.accept, .keepOriginal])
```

- [ ] **Step 2: Run UX tests and verify they fail**

Run: `xcodebuild test -project 'Runaway iOS.xcodeproj' -scheme 'Runaway iOS' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:'Runaway iOSTests/CoachActivityViewModelTests' -only-testing:'Runaway iOSTests/CoachNotificationTests'`

Expected: FAIL.

- [ ] **Step 3: Implement the trust-centered interface**

Add `.coachActivity` and `.coachDecision(UUID)` routes. `CoachChangeBanner` appears only for a recent applied change or pending proposal. Decision detail renders change, reason, evidence, goal effect, confidence/missing data, before/after, then actions. Pending proposals never replace the active Plan workout until accepted.

Add `Coach activity` to Settings.

- [ ] **Step 4: Register and route notification actions**

Register `RUNAWAY_COACH_AUTOMATIC` with Review and Undo and `RUNAWAY_COACH_APPROVAL` with Review, Accept, and Keep Original. Actions enqueue authenticated coordinator commands; they never mutate the plan directly inside `AppDelegate`.

Payloads contain only opaque decision/revision identifiers and action categories.

- [ ] **Step 5: Run UX tests and build**

Run the Task 6 test command.

Run: `xcodebuild build -project 'Runaway iOS.xcodeproj' -scheme 'Runaway iOS' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

Expected: PASS and BUILD SUCCEEDED.

- [ ] **Step 6: Commit UX and notifications**

```bash
git add 'Runaway iOS/ViewModels/CoachActivityViewModel.swift' 'Runaway iOS/Views/Coach' 'Runaway iOS/Components/CoachChangeBanner.swift' 'Runaway iOS/Navigation/Router.swift' 'Runaway iOS/Views/MainView.swift' 'Runaway iOS/Views/PlanView.swift' 'Runaway iOS/Views/SettingsView.swift' 'Runaway iOS/Services/PushNotificationService.swift' 'Runaway iOS/AppDelegate.swift' 'Runaway iOS/Runaway iOSTests/CoachActivityViewModelTests.swift' 'Runaway iOS/Runaway iOSTests/CoachNotificationTests.swift'
git commit -m "feat: add transparent coach decision experience"
```

### Task 7: Add Local Narration, Widgets, and App Intents

**Files:**
- Create: `Runaway iOS/Services/CoachNarrator.swift`
- Modify: `Runaway iOS/Services/FoundationModels/FoundationModelsService.swift`
- Modify: `Runaway iOS/Views/Coach/CoachDecisionDetailView.swift`
- Modify: `Runaway iOS/Services/WidgetSyncService.swift`
- Modify: `Shared/TrainingProgressSnapshot.swift`
- Modify: `RunawayWidget/RunawayWidget.swift`
- Modify: `RunawayWidget/BecomingWidgetIntent.swift`
- Modify: `Runaway iOS/AppIntents/RunawayIntents.swift`
- Test: `Runaway iOS/Runaway iOSTests/CoachNarratorTests.swift`
- Test: `Runaway iOS/Runaway iOSTests/CoachWidgetSnapshotTests.swift`

**Interfaces:**
- Consumes: A minimized `CoachDecisionNarrationInput` and the latest accepted decision.
- Produces: Local or deterministic `CoachNarration`, `CoachWidgetSnapshot`, Review/Undo intents, and a grounded daily brief.

- [ ] **Step 1: Write failing narrator and snapshot tests**

Test unavailable model, thrown generation, unsupported claims, changed numerical values, applied versus pending widget state, stale snapshots, completed prescriptions, and no cross-athlete cache reuse.

```swift
let narration = await narrator.explain(input, generator: FailingGenerator())
#expect(narration.provenance == .deterministic)
#expect(narration.summary.contains(input.primaryChange.displayValue))
#expect(pendingSnapshot.activeWorkoutID == originalWorkout.id)
```

- [ ] **Step 2: Run tests and verify they fail**

Run: `xcodebuild test -project 'Runaway iOS.xcodeproj' -scheme 'Runaway iOS' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:'Runaway iOSTests/CoachNarratorTests' -only-testing:'Runaway iOSTests/CoachWidgetSnapshotTests'`

Expected: FAIL.

- [ ] **Step 3: Implement bounded local narration**

```swift
protocol CoachTextGenerating {
    func generate(prompt: String, systemPrompt: String, maxTokens: Int) async throws -> String
}

func explain(_ input: CoachDecisionNarrationInput) async -> CoachNarration {
    guard model.isAvailable else { return templates.render(input) }
    do { return try validator.accept(model.generate(input), for: input) }
    catch { return templates.render(input) }
}
```

Generated output must preserve supplied quantities and reason codes or be discarded. No remote fallback is permitted.

- [ ] **Step 4: Extend shared snapshots and intents**

Persist decision ID, state, headline, short reason, updated time, and Undo availability only. Pending proposals may show `Review change` but continue displaying the original active workout. Widget choices create reevaluation events instead of directly mutating plan cache state.

- [ ] **Step 5: Run tests and build the widget**

Run the Task 7 tests plus `-only-testing:'Runaway iOSTests/FoundationModelsIdentityTests'`.

Run: `xcodebuild build -project 'Runaway iOS.xcodeproj' -scheme 'RunawayWidgetExtension' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

Expected: PASS and BUILD SUCCEEDED.

- [ ] **Step 6: Commit system experiences**

```bash
git add 'Runaway iOS/Services/CoachNarrator.swift' 'Runaway iOS/Services/FoundationModels/FoundationModelsService.swift' 'Runaway iOS/Views/Coach/CoachDecisionDetailView.swift' 'Runaway iOS/Services/WidgetSyncService.swift' 'Shared/TrainingProgressSnapshot.swift' 'RunawayWidget/RunawayWidget.swift' 'RunawayWidget/BecomingWidgetIntent.swift' 'Runaway iOS/AppIntents/RunawayIntents.swift' 'Runaway iOS/Runaway iOSTests/CoachNarratorTests.swift' 'Runaway iOS/Runaway iOSTests/CoachWidgetSnapshotTests.swift'
git commit -m "feat: explain coach decisions across system experiences"
```

### Task 8: Add Deterministic Edge Coordination

**Repository:** `/Users/jack.rudelic/projects/labs/runaway/runaway-edge`

**Files:**
- Create: `supabase/migrations/20260920_coach_delivery.sql`
- Create: `supabase/functions/send-coach-events/policy.ts`
- Create: `supabase/functions/send-coach-events/policy.test.ts`
- Create: `supabase/functions/send-coach-events/index.ts`
- Modify: `supabase/functions/_shared/apns.ts`
- Modify: `supabase/functions/send-workout-prompts/index.ts`
- Test: `supabase/functions/send-coach-events/policy.test.ts`

**Interfaces:**
- Consumes: Athlete-owned device registration, schedules, opaque decision metadata, delivery acknowledgement, and server-known elapsed-session events.
- Produces: RLS-protected schedules/deliveries, claimed APNs work, silent wake payloads, visible approval notifications, and receipts.

- [ ] **Step 1: Write failing pure policy tests**

Test due-time calculation across time zones and DST, slot uniqueness, retries, expiration, opaque payload construction, and absence of health detail.

```typescript
Deno.test("coach wake payload contains no health detail", () => {
  const payload = buildCoachWakePayload(sampleDelivery)
  assertEquals(payload.aps["content-available"], 1)
  assertEquals(Object.keys(payload).sort(), ["aps", "coach_event_id", "sync_type"])
})
```

- [ ] **Step 2: Run Edge policy tests and verify they fail**

From `runaway-edge`, run: `deno test supabase/functions/send-coach-events/policy.test.ts`

Expected: FAIL because the policy module does not exist.

- [ ] **Step 3: Add RLS-protected coordination storage**

Create `coach_event_schedules`, `coach_event_deliveries`, and `coach_delivery_receipts`. Athletes manage only their own schedules and receipts. Only `service_role` claims or changes delivery state. Uniqueness on `(athlete_id, device_id, event_key)` enforces idempotency.

The claim function uses `FOR UPDATE SKIP LOCKED`, bounded attempts, expiration, and retry timestamps. Payload rows contain opaque IDs and action category only.

- [ ] **Step 4: Implement and test APNs delivery**

Reuse `_shared/apns.ts`. `send-coach-events` requires the internal job secret, claims due rows, sends either a silent `coach_event` wake or visible decision notification, and records APNs status without logging tokens or content.

Run: `deno test supabase/functions/send-coach-events/policy.test.ts supabase/functions/send-workout-prompts/policy.test.ts supabase/functions/_shared/internal-handlers.test.ts`

Expected: PASS.

- [ ] **Step 5: Prevent duplicate legacy prompts**

Change `send-workout-prompts` to skip athletes whose coach capability is enabled. Preserve legacy delivery for older clients. Add a test proving the same athlete and slot cannot receive both a workout prompt and coach event.

- [ ] **Step 6: Commit Edge coordination**

```bash
git add supabase/migrations/20260920_coach_delivery.sql supabase/functions/send-coach-events supabase/functions/_shared/apns.ts supabase/functions/send-workout-prompts/index.ts
git commit -m "feat: coordinate proactive coach delivery"
```

### Task 9: Full Regression, Device Verification, and Rollout

**Files:**
- Modify: `docs/superpowers/plans/2026-09-20-runaway-coach-agent.md` only to check completed boxes during execution.
- Test: Entire iOS and Edge suites.

**Interfaces:**
- Consumes: Completed Tasks 1-8.
- Produces: A verified release candidate, deployed deterministic Edge coordination, and physical-device evidence.

- [x] **Step 1: Run the complete iOS suite serially**

Run: `xcodebuild test -project 'Runaway iOS.xcodeproj' -scheme 'Runaway iOS' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -resultBundlePath /tmp/RunawayCoachAgent.xcresult`

Expected: 0 failures; the existing device-only test may remain skipped with its explicit reason.

- [x] **Step 2: Run architectural boundary checks**

Run: `bash scripts/verify-no-activity-recorder.sh`

Run: `rg -n 'OpenAI|Anthropic|Gemini|chat/completions|responses/v1|api\.openai|api\.anthropic' 'Runaway iOS' RunawayWidget Shared`

Expected: No production external-LLM client or endpoint. Test fixtures and documentation matches are reviewed rather than ignored.

- [x] **Step 3: Run Edge tests**

From `runaway-edge`, run: `deno test supabase/functions/send-coach-events/policy.test.ts supabase/functions/send-workout-prompts/policy.test.ts supabase/functions/_shared/internal-handlers.test.ts`

Expected: PASS.

- [ ] **Step 4: Perform simulator visual verification**

Verify Today without the recorder FAB, automatic adaptation banner, pending proposal without active-plan replacement, Coach activity history, decision detail, Undo, Plan consistency, and widget snapshots.

- [x] **Step 5: Deploy migration and Edge Function**

Apply `20260920_coach_delivery.sql`, deploy `send-coach-events` with JWT verification disabled only for its internal-secret-protected endpoint, and confirm the internal job secret exists. Do not enable production scheduling until device registration publishes coach capability.

- [ ] **Step 6: Perform physical-device verification**

Verify HealthKit and Garmin imports, delayed catch-up, one automatic adaptation with Undo, one approval-required proposal, notification actions, local narration and deterministic fallback, App Intent routing, widget refresh, and Apple Watch workout handoff.

- [ ] **Step 7: Enable production delivery and monitor one cycle**

Confirm one claimed row reaches `sent`, the device acknowledges it, and a duplicate delivery does not create a second decision. Keep legacy workout prompts enabled only for clients without coach capability.

- [x] **Step 8: Commit verification evidence separately**

In `Runaway iOS`:

```bash
git add docs/superpowers/plans/2026-09-20-runaway-coach-agent.md
git commit -m "docs: record Runaway Coach verification"
```

Push each repository's reviewed commits to its own `main` only after its complete suite passes.
