# Result-driven training reviews implementation plan

> Use superpowers:executing-plans. Continue inline under the approved progression and remaining-week integration work.

**Goal:** Make saved actual session results affect engine inputs, progression review and remaining-week conflict review.

**Architecture:** Validate owner-scoped session results beside observations, include eligible results in the decision fingerprint, and retain them in the preview snapshot. Pure review policies consume actual results; the existing comparison sheet presents their conclusions. No live plan rewrite or inferred workload is introduced.

**Tech stack:** Swift, SwiftUI, existing protected local repository, Swift Testing.

**Spec:** Approved completion-to-progression design in this conversation and `2026-09-12-cohesive-training-system.md`.

## Execution

- [ ] Add focused regressions before implementation: owner/as-of filtering, fingerprint changes, training-today protection, partial-result handling, distinct-day repeat evidence, and preservation of explicit rest/workout choices.
- [ ] Add `sessionResults` to `TrainingDecisionInputs` and its fingerprint payload. Validate complete histories before filtering future timestamps; reject duplicate result IDs and duplicate reference keys.
- [ ] Load results when generating a preview, not through an independent cache. Include availability and results in the immutable snapshot. Bump the engine version.
- [ ] Treat any confirmed work today as a reason to review additional-session planning. Add only actual running/strength entries to exposure-day history; existing day-set deduplication prevents records and observations from inflating day counts.
- [ ] Implement `TrainingProgressionService.assess`: use the latest relevant result; never bypass a partial, difficult or uncomfortable recent session in favor of an older favorable result. Two matching, comfortable full sessions on distinct local days permit review of an increase, not an automatic numerical increase.
- [ ] Implement `RemainingWeekTrainingPolicy.review`: inspect tomorrow through Saturday using calendar arithmetic. Preserve recorded days, explicit choices and rest. Flag missing/insufficient availability and adjacent demanding work. Missed past plans never enter the recovery evidence channel.
- [ ] Present both reviews in the existing daily comparison, with snapshot timing and explicit non-activation language.
- [ ] Compile and run the focused recommendation-policy suite; report results without claiming live adaptation or UI testing.

## Numerical boundaries and sources

The 28-day review window, whole-session effort thresholds (4 for comfortable
running; 6 for strength), two distinct matching days, and recovery-review flags
are conservative product heuristics, not validated injury-risk calculations.
Every performed strength set must report at least two reps in reserve to qualify.
Changes in dose, partial work or insufficient evidence prevent automatic
qualification. Machine/bodyweight assistance and load conventions remain distinct.

- [ACSM 2026 resistance guidance](https://acsm.org/resistance-training-guidelines-update-2026/): individualization and consistency, not a mandate for a fixed load jump.
- [BJSM running cohort](https://bjsm.bmj.com/content/59/17/1203): session-distance spikes warrant attention; a blanket 10% increase is not a guarantee of safety. We do not transfer distance-risk findings into an invented duration formula.

## Explicit remaining work

Numerical progression needs a defined available equipment increment and a
reviewed running progression policy. Applying a changed week still needs a
shared decision revision, import reconciliation, visible change receipt and
concurrency-safe undo. This task creates connected reviews, not those write paths.
