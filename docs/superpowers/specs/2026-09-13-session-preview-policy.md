# Goal session preview policy v1

Status: non-live executable preview. Not connected to Next Up, weekly scheduling,
widgets, notifications, or an LLM. No claim of medical clearance or improved outcomes.

## Purpose and boundaries

Offer goal-specific, typed running and strength options with explicit missing-data
reasons. Preserve equal-primary goals. Ordering is stable, not a recommendation that
one discipline outranks the other. No weekly anti-starvation guarantee is claimed.

Inputs are an account-owned profile and COMPLETE observation history. Reject mixed
accounts, invalid records, orphaned/branched/cyclic corrections. Future observations
are excluded. Planned workouts have no input parameter and cannot count as completed
work. Body measurements are not activity. A recorded set is not a completed session.

Fingerprints include canonical goals, observations, local day/time zone, constraints,
and engine version, excluding labels, presentation units, and save-only revisions.
These fingerprints are local cache identities, not anonymized data for transmission.

## Explicit product heuristics, not validated physiological rules

- Use a 28-calendar-day evidence window. This is a preview recency policy, not a
  scientifically established detraining cutoff.
- Running: reserve five minutes each for warm-up/cooldown. Work is the minimum of
  latest recorded elapsed duration, 20 minutes, and the remaining time budget.
  Require at least five minutes of work. No numeric pace, distance progression,
  race forecast, readiness inference, or missed-session catch-up.
- Elapsed duration can include stopped time. It is context, NOT proof of continuous
  running capacity. The preview explicitly asks the athlete to confirm comfort.
- Strength: one supported goal exercise, two sets of six to eight repetitions,
  90 seconds between sets, and 2-3 reps in reserve. Reserve five minutes warm-up,
  two minutes setup, one minute per set, and three minutes cooldown (13.5 minutes
  total; UI minimum rounds up to 14 whole available minutes).
- Reuse a load only from the latest exact-variant/convention observation with at
  least eight repetitions and explicit RIR >=2. Never derive load from a goal,
  assume missing effort, increase load, or transfer a machine setting.
- Unknown external load yields a load-selection calibration block; unknown
  bodyweight capacity asks for an easier supported variant/measurement instead.
- Any training recorded today blocks another automatic preview until full-session
  completion and remaining-time accounting exist, even when doubles are enabled.
- Nonempty limitations block previews. Free text is not interpreted as clearance.
- Readiness is not wired into this slice. It is neither set to zero nor treated as
  permission for hard training. This is not an adaptive daily recommendation yet.

## Evidence context

ACSM's 2026 overview supports progressive resistance training in healthy adults and
reports benefits of multiple sets, with prescriptions varying by outcome. It does
NOT validate this app's 6-8 rep calibration block, timing allowances, 28-day cutoff,
or load-reuse policy. Those are explicit product heuristics requiring coach review.
https://pubmed.ncbi.nlm.nih.gov/41843416/

Buist et al.'s novice-runner trial found no injury reduction for its tested graded
10%-rule program versus the comparator. Do not present a universal percentage
increase as an injury-prevention guarantee. This preview adds no progression rule.
https://pubmed.ncbi.nlm.nih.gov/17940147/

## Remaining release gates

Connect real session results and subjective recovery; evaluate equipment identity,
partial completion, progression, calendar/deadline feasibility and weekly fairness.
Review representative prescriptions with qualified training professionals. Add a
user-facing preview and explicit activation/rollback before replacing live Next Up.
