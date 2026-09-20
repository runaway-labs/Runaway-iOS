# Complete running prescription preview

## Scope

Extend the existing easy-running preview with typed, ordered warm-up, running,
optional recovery, and cooldown blocks. Keep the active plan, shadow selector,
widgets and notifications unchanged. A walk-break toggle is explicitly local to
this preview; reopening resets it. No new external model or server dependency.

## Evidence and numerical limits

The input builder and goal engine retain responsibility for account ownership,
corrected observations, the 28-day evidence window, today's availability,
reported limitations, and evidence of already-completed training today.

The extracted RunningPrescriptionPolicy preserves the existing product limits:
five-minute warm-up and cooldown; main block capped at the smallest of the latest
recorded elapsed duration (rounded down to seconds), 20 minutes, and remaining
available time. At least five main-block minutes and 15 total minutes are needed.
Invalid or missing elapsed duration produces a blocker. Clamp finite doubles
before integer conversion and reject inadequate budgets before subtraction.

Elapsed time is not continuous-running evidence, pace calibration, or clearance
to train. No race target, goal baseline, or historical average speed is converted
into prescribed pace or distance. This pass intentionally uses duration targets.

The optional one-minute walking break replaces 60 seconds of main-block running.
The remainder is split around it; an odd second goes to the second running block.
Warm-up, cooldown and total time remain unchanged. This is an explicit product
option, not a researched optimum or a mandatory run/walk ratio. More walking or
ending early remains allowed; there is no instruction to catch up afterward.

## Presentation

Use the existing blue running accent and native toggle. Ordered steps are a
workout sequence, not separate cards. Text scales and time labels can stack.
Show the actual evidence date, elapsed minutes, and distance in the goal's saved
unit, defaulting to miles only when the goal is absent. Do not use global unit
settings to relabel a saved kilometer goal. Goal-specific explanations distinguish
race preparation, weekly distance and weekly time without claiming progress.

## Sources and boundaries

- [CDC: measuring physical activity intensity](https://www.cdc.gov/physical-activity-basics/measuring/index.html)
  supports using conversation as an intensity cue. It does not validate our
  duration cap or establish this athlete's training zones.
- [NHS: Couch to 5K running plan](https://www.nhs.uk/better-health/get-active/get-running-with-couch-to-5k/couch-to-5k-running-plan/)
  provides examples of warm-up/cooldown walks and mixed running/walking sessions.
  We are not implementing that nine-week program or claiming its outcomes.

Readiness-aware progression, race-specific sessions, physiological load,
remaining-week recovery and live engine activation remain separate work.

## Focused acceptance

Test budget preservation; observed-duration and preview caps; missing, nonfinite,
and too-short evidence; tiny/negative budgets; minimum sessions; exact recovery
arithmetic including odd durations; and saved-unit conversion. Compile the new
SwiftUI route with the focused existing recommendation-policy suite. This does
not replace a simulator interaction test or an athlete-specific training review.
