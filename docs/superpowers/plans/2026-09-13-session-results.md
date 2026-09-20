# Completed Session Results Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Record confirmed actual work against a complete prescription before building progression and remaining-week adaptation.

**Architecture:** A Codable prescription reference and actual entries share stable item identifiers. Store the entire session atomically in the existing account-owned protected repository. The preview can open an explicit completion form; saving does not modify the live plan or duplicate imported activity observations.

**Tech Stack:** Swift, SwiftUI, Foundation, existing protected JSON repository, Swift Testing.

**Spec:** Approved conversation design: quick confirmation with editable differences, explicit effort/discomfort, and no inferred completion from a planned workout.

## Constraints

- Local-only; no external model, backend, deployment, or git operation.
- Reference and actual values remain separate. Unknown loads and actual repetitions require entry.
- A skipped item has no performed values. Unilateral sets have distinct left/right items.
- Save requires explicit confirmation; Cancel writes nothing.
- Atomic whole-session writes, owner checks, idempotent retries and duplicate-reference rejection.
- These records do not yet drive progression, live planning, widgets or notifications.

## Task 1: Result contract and persistence

Files: create `Runaway iOS/Models/TrainingSessionResult.swift`; modify
`Runaway iOS/Services/ProtectedTrainingRepository.swift`; add tests to the existing
`TodayRecommendationPolicyTests.swift` test-target member.

- [ ] Write tests before production implementation, then run the focused suite.
- [ ] Define `TrainingSessionResult.isValid`: finite dates and elapsed time, positive owner,
  unique matching reference/actual item IDs, required effort and body response, valid
  typed values, no invented data for skipped items, and elapsed time covering timed parts.
- [ ] Implement `sessionResults(athleteID:)` and `appendSessionResult(_:athleteID:)`.
  Reject changed retries and duplicate reference keys rather than overwrite history.
- [ ] Exercise missing calibration load, partial completion, ownership and retry behavior.

```swift
let saved = try repository.appendSessionResult(result, athleteID: result.reference.athleteID)
#expect(saved == result)
#expect(try repository.sessionResults(athleteID: result.reference.athleteID).count == 1)
```

## Task 2: Explicit completion form

Create `Runaway iOS/Views/TrainingSessionResultView.swift` and
`Runaway iOS/Models/TrainingSessionReferenceBuilder.swift`.
Modify `GoalSessionPreview.swift`, `AthleteTrainingProfileEditorModel.swift`,
`CompleteGoalSessionPreviewView.swift`, and `RunningPrescriptionPreview.swift`.

- [ ] Include the authenticated profile owner in the preview snapshot.
- [ ] Capture typed running blocks, including the chosen walk break, or the complete
  strength prescription, including distinct unilateral sets and load conventions.
- [ ] Show editable known values; require actual reps, unknown weights, set effort,
  whole-session effort, discomfort response and actual elapsed time.
- [ ] Provide an explicit copy-to-matching-sets action, never silently copy effort.
- [ ] Permit skipped items and save a derived partial-completion status.
- [ ] Show a local-save receipt; close on account invalidation. Explain that live
  plan changes and progression are not activated by this save.
- [ ] Compile and run the focused suite. Report actual results; do not claim UI
  interaction testing or full progression integration from unit tests alone.

## Follow-on dependency

Progression must consume these verified results, reconcile linked imports, and
separate partial completion from complete qualifying sessions. Remaining-week
adaptation must preserve completed history and explicit choices, with a change
receipt and concurrency-safe undo. Neither is implicitly activated by this task.
