# Coach Week Board Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Plan tab's duplicate Today card and passive weekly timeline with one authoritative, accessible Coach Week Board.

**Architecture:** A pure `CoachWeekBoardPresentation` derives canonical status, dose, summary, and available actions from the accepted weekly plan and recorded evidence. A focused SwiftUI `CoachWeekBoard` renders that presentation and emits typed actions; `PlanView` owns navigation and sends today's commitment actions into the existing `TodayWorkoutDecisionSheet`.

**Tech Stack:** Swift 6, SwiftUI, Observation, Swift Testing, iOS 27.

**Spec:** `docs/superpowers/specs/2026-09-21-coach-week-board-design.md`

## Global Constraints

- Today owns the workout decision; Plan only explains and navigates the week.
- Activities remains completed/imported history only.
- You remains profile, goals, units, notifications, and settings.
- Use the authoritative `WeeklyTrainingPlan`; do not add persistence or another plan state.
- Commit and Change must use `TodayWorkoutDecisionSheet` and its revision check.
- Running pace must never appear for non-running modalities.
- Distance presentation must honor `UnitPreferences`.
- Completed work and accepted results must never be mutated by presentation code.
- Use existing Runaway graphite, amber, blue, and mint semantic tokens.
- Keep minimum hit targets at 44 points and expose status in text and symbols.
- Do not add an external model, backend endpoint, Edge Function, or database migration.
- Do not run git commands unless the user explicitly requests them.

## Review Focus

- A committed workout whose prescription fingerprint no longer matches must not display as Committed.
- A non-running workout carrying stale `targetPace` data must never display pace.
- A past rest day must remain Rest rather than Missed.
- Partial accepted completion must outrank stored `isCompleted` and display Partial.
- A plan with missing duration, distance, or exercises must omit unknown dose fields without fabricating text or crashing.

---

### Task 1: Deterministic Week Presentation

**Files:**
- Create: `Runaway iOS/Models/CoachWeekBoardPresentation.swift`
- Create: `Runaway iOS/Runaway iOSTests/CoachWeekBoardPresentationTests.swift`
- Modify: `Runaway iOS.xcodeproj/project.pbxproj` only if synchronized-group test membership requires an exception entry.

**Interfaces:**
- Consumes: `WeeklyTrainingPlan`, `[Activity]`, `CoachDecision?`, `WorkoutPrescriptionFingerprint.make(_:)`, `UnitFormatter`, `Calendar`.
- Produces: `CoachWeekBoardPresentation.make(plan:activities:recentDecision:calendar:distanceFormatter:)`, `CoachWeekBoardPresentation.Day`, `CoachWeekBoardPresentation.Status`, and `CoachWeekBoardPresentation.Action`.

- [ ] **Step 1: Write failing presentation tests**

Add a Swift Testing suite covering canonical state precedence, modality-safe dose formatting, summary math, and malformed prescriptions:

```swift
import Testing
import Foundation
@testable import Runaway_iOS

@Suite("Coach week board presentation")
struct CoachWeekBoardPresentationTests {
    @Test func todayUsesRecommendationThenValidCommitment() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let recommended = fixtureWorkout(id: "today", date: now, type: .easyRun, duration: 40, distance: 4)
        let recommendation = CoachWeekBoardPresentation.make(
            plan: fixturePlan(workouts: [recommended]), activities: [], recentDecision: nil,
            now: now, calendar: utcCalendar, distanceFormatter: { "\($0) distance" }
        )
        #expect(recommendation.days[0].status == .recommended)
        #expect(recommendation.days[0].actions == [.commit, .change])

        var committed = recommended
        committed.commitment = WorkoutCommitment(
            committedAt: now, source: .recommendation,
            prescriptionFingerprint: try WorkoutPrescriptionFingerprint.make(recommended),
            originalWorkoutID: recommended.id
        )
        let commitment = CoachWeekBoardPresentation.make(
            plan: fixturePlan(workouts: [committed]), activities: [], recentDecision: nil,
            now: now, calendar: utcCalendar, distanceFormatter: { "\($0) distance" }
        )
        #expect(commitment.days[0].status == .committed)
        #expect(commitment.days[0].actions == [.viewWorkout, .change])

        committed.commitment = WorkoutCommitment(
            committedAt: now, source: .recommendation,
            prescriptionFingerprint: "stale-fingerprint",
            originalWorkoutID: committed.id
        )
        let stale = CoachWeekBoardPresentation.make(
            plan: fixturePlan(workouts: [committed]), activities: [], recentDecision: nil,
            now: now, calendar: utcCalendar, distanceFormatter: { "\($0) distance" }
        )
        #expect(stale.days[0].status == .recommended)
        #expect(stale.days[0].actions == [.commit, .change])
    }

    @Test func partialOutranksStoredCompletion() {
        let workout = fixtureWorkout(type: .strengthTraining, duration: 45, completed: true,
            acceptedCompletion: AcceptedWorkoutCompletion(
                resultID: UUID(), completedAt: Date(timeIntervalSince1970: 1_790_000_000),
                elapsedSeconds: 1_200, isPartial: true
            ))
        let day = presentation(for: workout).days[0]
        #expect(day.status == .partial)
        #expect(day.actions == [.reviewResult])
    }

    @Test func stalePaceNeverAppearsOutsideRunning() {
        let walk = fixtureWorkout(type: .walking, duration: 30, distance: 2, targetPace: "9:22 /mi")
        let day = presentation(for: walk).days[0]
        #expect(!day.dose.contains("9:22"))
    }

    @Test func pastRestIsRestAndMissingDoseIsSafe() {
        let rest = fixtureWorkout(type: .rest, duration: nil)
        let day = presentation(for: rest, now: rest.date.addingTimeInterval(86_400)).days[0]
        #expect(day.status == .rest)
        #expect(day.dose == "Recovery is part of the plan")
    }

    @Test func headerCountsOnlyTrainingSessionsAndMinutes() {
        let plan = fixturePlan(workouts: [
            fixtureWorkout(id: "run", type: .easyRun, duration: 40),
            fixtureWorkout(id: "lift", type: .strengthTraining, duration: 45),
            fixtureWorkout(id: "rest", type: .rest, duration: nil)
        ])
        let board = CoachWeekBoardPresentation.make(
            plan: plan, activities: [], recentDecision: nil,
            now: plan.workouts[0].date, calendar: utcCalendar,
            distanceFormatter: { "\($0) distance" }
        )
        #expect(board.plannedSessionCount == 2)
        #expect(board.plannedMinutes == 85)
    }
}
```

The fixture helpers must construct stable dates in a UTC calendar and valid `DailyWorkout`/`WeeklyTrainingPlan` values using the current model initializers. `fixtureWorkout` accepts `completed` and `acceptedCompletion`, constructs the workout once, then assigns optional accepted metadata in the same pattern as `AcceptedWorkoutCompletionProjection`.

- [ ] **Step 2: Run the focused suite and confirm it fails**

Run only after the user authorizes validation:

```bash
xcodebuild -project 'Runaway iOS.xcodeproj' -scheme 'Runaway iOS' \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
  -only-testing:'Runaway iOSTests/CoachWeekBoardPresentationTests' test
```

Expected: compilation fails because `CoachWeekBoardPresentation` does not exist.

- [ ] **Step 3: Implement the pure presentation model**

Create these public-in-module shapes:

```swift
import Foundation

struct CoachWeekBoardPresentation: Equatable {
    enum Status: String, Equatable {
        case recommended, committed, completed, partial, upcoming, rest, missed
    }

    enum Action: Equatable {
        case commit, change, viewWorkout, reviewResult
    }

    struct Day: Identifiable, Equatable {
        let id: String
        let workoutID: String
        let date: Date
        let weekday: String
        let dayNumber: String
        let title: String
        let modality: WorkoutType
        let dose: String
        let status: Status
        let actions: [Action]
        let adaptationDecisionID: UUID?
        let isToday: Bool
    }

    let weekRange: String
    let completedSessionCount: Int
    let plannedSessionCount: Int
    let plannedMinutes: Int
    let weeklyFocus: String
    let days: [Day]
}
```

Implement `make` with this status precedence:

```swift
private static func status(
    for workout: DailyWorkout,
    activities: [Activity],
    now: Date,
    calendar: Calendar
) -> Status {
    if workout.acceptedCompletion?.isPartial == true { return .partial }
    if workout.commitment != nil {
        switch CommittedWorkoutCompletionPolicy.status(for: workout, activities: activities) {
        case .complete: return .completed
        case .partial: return .partial
        case .notCompleted: break
        }
    }
    if workout.acceptedCompletion != nil || workout.isCompleted { return .completed }
    if workout.workoutType == .rest { return .rest }
    if calendar.isDate(workout.date, inSameDayAs: now) {
        guard let commitment = workout.commitment,
              (try? WorkoutPrescriptionFingerprint.make(workout)) == commitment.prescriptionFingerprint else {
            return .recommended
        }
        return .committed
    }
    return workout.date < calendar.startOfDay(for: now) ? .missed : .upcoming
}
```

Implement action mapping exactly:

```swift
private static func actions(for status: Status, isToday: Bool) -> [Action] {
    switch status {
    case .recommended where isToday: [.commit, .change]
    case .committed where isToday: [.viewWorkout, .change]
    case .completed, .partial: [.reviewResult]
    case .rest where isToday: [.viewWorkout, .change]
    default: [.viewWorkout]
    }
}
```

Build dose pieces by modality. Append `displayTargetPace` only when `workout.workoutType.isRunning`. Omit missing values. Return `Recovery is part of the plan` for rest and `Prescription details unavailable` only when a non-rest workout has no duration, distance, exercises, or valid running pace.

Derive `weeklyFocus` deterministically from non-rest modality counts, for example `2 runs · 2 strength sessions`; never invoke a model or invent a training claim.

- [ ] **Step 4: Run the focused suite and confirm it passes**

Run only after the user authorizes validation. Expected: all presentation tests pass.

---

### Task 2: Crafted Coach Week Board Component

**Files:**
- Create: `Runaway iOS/Components/Progress/CoachWeekBoard.swift`
- Modify: `Runaway iOS.xcodeproj/project.pbxproj` only if synchronized group membership requires it.

**Interfaces:**
- Consumes: `CoachWeekBoardPresentation`, `AppTheme`, `TrainingProgressStyle`.
- Produces: `CoachWeekBoard.init(presentation:onAction:)` and `CoachWeekBoard.UserAction`.

- [ ] **Step 1: Define the typed UI action boundary**

```swift
struct CoachWeekBoard: View {
    enum UserAction {
        case commit(String)
        case change(String)
        case viewWorkout(String)
        case reviewResult(String)
        case reviewCoachDecision(UUID)
    }

    let presentation: CoachWeekBoardPresentation
    let onAction: (UserAction) -> Void
}
```

Workout IDs, rather than copied workout values, force `PlanView` to resolve the latest authoritative plan before routing.

- [ ] **Step 2: Build the header and connected rail**

Use existing tokens and this hierarchy:

```swift
VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
    header
    VStack(spacing: 0) {
        ForEach(Array(presentation.days.enumerated()), id: \.element.id) { index, day in
            dayRow(day, isLast: index == presentation.days.count - 1)
        }
    }
}
.padding(AppTheme.Spacing.lg)
.background(TrainingProgressStyle.surface, in: RoundedRectangle(cornerRadius: 22))
.overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.08), lineWidth: 1))
```

Render the rail as a decorative two-point vertical line behind 32-point status nodes. Use:

- Amber node and `surfaceBackground` shift for today.
- Mint check for completed.
- Half-filled circle and orange text for partial.
- Blue node for upcoming.
- Muted moon for rest.
- Muted dashed-circle treatment for missed.

Do not create seven separate card containers. Today wins through a quiet surface shift, stronger title weight, and 4 points of additional vertical space.

- [ ] **Step 3: Add canonical row content and actions**

Each row reads in this order:

```text
MON 21    COMMITTED
Easy Run
40 min · 4.0 mi · 10:15 /mi
[View workout] [Change]
```

Use `Button` for every action, minimum height 44. The first action uses amber only for today's Commit; Change and detail actions use blue text. Completed rows use mint status but no mint-filled button.

If `adaptationDecisionID` exists, show a compact `arrow.triangle.branch` + `Rebalanced` button below the dose and emit `.reviewCoachDecision(id)`.

- [ ] **Step 4: Add accessibility and reduced-motion behavior**

Combine each row's passive content for VoiceOver with an accessibility label ordered as date, status, modality, title, and dose. Keep action buttons separate. Mark the rail hidden from accessibility. Apply symbol replacement only:

```swift
.contentTransition(.symbolEffect(.replace))
.animation(.easeOut(duration: 0.18), value: day.status)
```

Wrap movement effects in `@Environment(\.accessibilityReduceMotion)` and omit animation when enabled.

- [ ] **Step 5: Add preview fixtures for all states**

The file's `#Preview` must show seven days containing recommended, committed, completed, partial, upcoming, rest, and missed states at a large Dynamic Type size. This is a development preview, not a parallel production model.

---

### Task 3: Plan Tab Integration and Routing

**Files:**
- Modify: `Runaway iOS/Views/PlanView.swift`
- Delete after integration: `Runaway iOS/Components/Progress/TrainingWeekTimeline.swift`

**Interfaces:**
- Consumes: `CoachWeekBoardPresentation.make`, `CoachWeekBoard.UserAction`, `TodayWorkoutDecisionSheet`, `PlanWorkoutDetailSheet`, `AppRouter.Route.coachDecision`.
- Produces: one Plan-tab weekly surface with no duplicate Today card.

- [ ] **Step 1: Add authoritative action state to `PlanView`**

Add:

```swift
@EnvironmentObject private var trainingProfileStore: TrainingProfileStore
@State private var decisionWorkout: DailyWorkout?
@State private var decisionStartsWithChoices = false
```

Add a sheet that resolves the current plan and uses the existing decision flow:

```swift
.sheet(item: $decisionWorkout) { workout in
    if let plan = dataManager.currentWeeklyPlan {
        TodayWorkoutDecisionSheet(
            plan: plan,
            profile: trainingProfileStore.profile,
            recommendedWorkout: workout,
            startChoosing: decisionStartsWithChoices
        )
    }
}
```

- [ ] **Step 2: Replace duplicate weekly surfaces**

Remove the `TodayWorkoutCard` block and `TrainingWeekTimeline` call. Insert one board:

```swift
CoachWeekBoard(
    presentation: CoachWeekBoardPresentation.make(
        plan: plan,
        activities: dataManager.activities,
        recentDecision: coachDecision,
        distanceFormatter: {
            UnitFormatter.formatDistance($0, unit: unitPreferences.distanceUnit, decimals: 1)
        }
    ),
    onAction: handleWeekBoardAction
)
```

Adapt the formatter's input conversion to the actual `DailyWorkout.distance` storage unit once, inside the presentation builder, so every caller uses the same contract.

- [ ] **Step 3: Resolve every action against the latest plan**

Implement:

```swift
private func handleWeekBoardAction(_ action: CoachWeekBoard.UserAction) {
    func workout(_ id: String) -> DailyWorkout? {
        dataManager.currentWeeklyPlan?.workouts.first { $0.id == id }
    }

    switch action {
    case .commit(let id):
        decisionStartsWithChoices = false
        decisionWorkout = workout(id)
    case .change(let id):
        decisionStartsWithChoices = true
        decisionWorkout = workout(id)
    case .viewWorkout(let id), .reviewResult(let id):
        showingWorkoutDetail = workout(id)
    case .reviewCoachDecision(let id):
        router.navigate(to: .coachDecision(id))
    }
}
```

If a workout disappeared because the plan changed, perform no stale navigation; the board will refresh from `dataManager.currentWeeklyPlan`.

- [ ] **Step 4: Remove obsolete local Plan components**

Delete the unused `TodayWorkoutCard` declaration from `PlanView.swift`. Delete `TrainingWeekTimeline.swift` after confirming no remaining references. Keep `WeeklyTrainingPlanView` untouched because removing that legacy file is outside this feature's scope.

- [ ] **Step 5: Verify cross-screen functional boundaries**

Run only after the user authorizes validation:

```bash
rg -n "TodayWorkoutCard|TrainingWeekTimeline|CompactCommitmentCard" 'Runaway iOS' -g '*.swift'
```

Expected:

- No `TodayWorkoutCard` or `TrainingWeekTimeline` production references.
- No `CompactCommitmentCard` reference from `ActivitiesView`.
- Today and Plan both invoke `TodayWorkoutDecisionSheet` for commitment changes.

Then build the signed simulator app:

```bash
xcodebuild -project 'Runaway iOS.xcodeproj' -scheme 'Runaway iOS' \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' build
```

Expected: `BUILD SUCCEEDED`.

---

### Task 4: Visual and Physical-Device Acceptance

**Files:**
- Modify only files from Tasks 1-3 if the checks reveal defects.

**Interfaces:**
- Consumes: completed Coach Week Board implementation.
- Produces: accepted Plan-tab experience across content states and device sizes.

- [ ] **Step 1: Inspect the authenticated Plan tab in the simulator**

Confirm:

- Race context, plan header, Week Board, insights, and principles form a clear descending hierarchy.
- Today appears exactly once.
- Seven day rows fit without horizontal clipping.
- The rail remains continuous through wrapped titles.
- Amber is concentrated on today's decision rather than every heading.

- [ ] **Step 2: Inspect accessibility states**

Check default, Accessibility XL, and Reduce Motion. Confirm every action has a 44-point target and status remains understandable without color.

- [ ] **Step 3: Exercise functional routes on a physical device**

Confirm:

- Recommended `Commit` opens the current prescription and commits successfully.
- `Change` opens all profile-enabled alternatives and previews week impact.
- Committed `View workout` opens the committed dose.
- Completed and partial rows open result/detail content.
- Rebalanced opens the matching Coach decision.
- Widget and notification still reflect the same committed workout after a Plan-tab change.

- [ ] **Step 4: Run focused and full regression validation**

Run only after the user authorizes validation:

```bash
xcodebuild -project 'Runaway iOS.xcodeproj' -scheme 'Runaway iOS' \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
  -only-testing:'Runaway iOSTests/CoachWeekBoardPresentationTests' \
  -only-testing:'Runaway iOSTests/TodayWorkoutDecisionServiceTests' \
  -only-testing:'Runaway iOSTests/TodayWorkoutDecisionViewModelTests' test
```

Expected: all selected tests pass. Do not archive, upload, commit, or push until the user explicitly requests those operations.
