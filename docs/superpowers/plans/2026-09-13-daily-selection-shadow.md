# Daily selection shadow comparison

**Goal:** Compare an explainable goal-based daily selection with existing Next Up without changing the live plan.

**Scope:** Executes the shadow-selection portion of task 6 in the cohesive training-system plan. No progression, notifications, cloud writes, or activation switch is introduced.

## Policy

- Consume existing validated session previews, never generate new exercise loads or running intensities here.
- Consider primary goals before supporting goals. An unavailable primary prescription is not silently replaced by a supporting goal.
- Preserve explicit user choices. Missing, out-of-range, or below-70 readiness blocks this experimental selector, following the existing app's proceed threshold rather than claiming clinical validation.
- Any recorded training today blocks an additional shadow selection pending double-session support.
- Compare distinct completed training days in the previous seven local calendar days. Multiple strength sets on one day count once; planned workouts never enter this history.
- Among equal-priority disciplines, use equal target shares. Share deficit is `1 / disciplineCount - completedDisciplineDays / totalDisciplineDays`; with no history, observed share is zero.
- Among eligible previews, select the largest share deficit, then the oldest most recent training day. Exact ties require athlete choice, including multiple goals within the same discipline.
- These are exposure/fairness heuristics, not comparisons of physiological workload, progression, or proof of safety. Current previews retain their own limitations.

## Implementation

1. Add regression tests to the existing recommendation test file for fairness, duplicate observations, priority, exact ties, missing readiness, explicit choices, and date boundaries.
2. Add `Models/GoalDailyShadowPolicy.swift` for pure selection and projection from validated snapshots.
3. Add `Components/GoalDailyShadowComparison.swift` for a read-only comparison sheet showing current Next Up, the shadow result, ranking inputs, exclusions, and limitations.
4. Add a comparison entry below the existing session-preview sheet in `Views/AthleteTrainingProfileView.swift`.
5. Run focused tests, then the full unit suite. UI smoke testing and live activation remain separate checkpoints.

## Release boundary

The comparison cannot write to TrainingPlanService, DataManager, widgets, or notifications. It cannot mark any session complete. No external model or service is called by this feature. The profile snapshot and current Next Up inputs may have different capture times, which the UI must disclose.
