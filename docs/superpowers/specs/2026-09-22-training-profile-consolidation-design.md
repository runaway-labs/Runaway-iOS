# Training Profile Consolidation Design

**Date:** 2026-09-22

## Purpose

Replace Runaway's two competing goal/profile destinations with one Training Profile that captures what the athlete wants to become. The recommendation engine retains precise benchmarks and constraints, but the primary interface no longer presents individual lifts or raw database metrics as the athlete's top-level goals.

## Product model

Runaway distinguishes three layers:

1. **Outcome goals** describe the athlete's durable intent.
2. **Training strategy** translates each outcome into weekly programming responsibilities.
3. **Benchmarks and evidence** give the engine measurable starting points and progress signals.

The athlete edits outcomes and preferences. Runaway derives strategy. Benchmarks are optional, editable supporting evidence rather than required goals.

## Initial outcome goals

### Marathon Ready

An ongoing goal with no required race date. Runaway develops aerobic capacity, weekly running durability, long-run tolerance, and speed while maintaining readiness to enter a race-specific block later. A future marathon race can add a dated specialization and taper without replacing this outcome.

### Lean + Strong

Develop and maintain an athletic, muscular, reasonably lean physique while preserving running performance and recovery. Programming emphasizes balanced full-body strength with additional chest, shoulders, arms, and forearms according to the athlete's saved preferences.

### Strong, Durable Core

Build trunk strength, stability, and fatigue resistance that support running, lifting, posture, and injury resilience. Core work is embedded in weekly prescriptions and progresses through volume, exercise difficulty, range, and control.

## Supporting benchmarks

The existing evidence remains available to the engine:

- Bench press baseline: 225 pounds for 4 repetitions.
- Strict pull-up baseline: 5 repetitions.
- Height, weight, equipment, availability, and saved limitations.
- Running history, weekly volume, long-run history, pace, heart rate, training load, and recovery trends.

Bench and pull-up values are not mandatory goals. They appear under an optional Benchmarks section and may be updated or removed without disabling Lean + Strong. The previously inferred targets of 225 pounds for 8 repetitions and 10 pull-ups must not be treated as user-confirmed targets.

## Single destination

The You screen exposes one row named **Training Profile**. It replaces both the legacy Training Preferences destination and the advanced Goals & Current Ability destination.

Training Profile contains:

- **Your outcomes:** selectable outcome cards with a short explanation and active state.
- **Weekly rhythm:** available days, available minutes, preferred activity mix, and whether two-a-day sessions are allowed.
- **Body and equipment:** optional height, weight, and available equipment.
- **Benchmarks:** optional running, lifting, and bodyweight evidence.
- **Considerations:** injuries, limitations, and training constraints.

There is no second goal editor elsewhere in Settings or You.

## Goal input experience

The default interface uses human-readable cards rather than metric enums or database-shaped forms. Each active outcome offers only choices that materially change programming:

- Marathon Ready: current running consistency, preferred weekly running frequency, and optional future race connection.
- Lean + Strong: preferred strength frequency and physique emphasis.
- Strong, Durable Core: desired core frequency, defaulting to inclusion within strength sessions.

Raw metric names, internal priority enum values, and unit storage formats are never shown. Advanced benchmark entry is optional and visually subordinate.

## Persistence and reconciliation

`athlete_training_profile_snapshots` in Supabase is the authoritative cross-device profile. The protected local profile is an encrypted offline cache.

On load:

1. Render the protected local cache immediately when available.
2. Fetch the authenticated athlete's remote snapshot.
3. Replace local state only when the remote revision is newer or local data is absent.
4. Preserve unsynced local edits and show a clear retry state instead of reporting success.

On save:

1. Validate that at least one outcome is active and that required values are sensible.
2. Write the protected local cache.
3. Sync the same profile through the authenticated Edge Function.
4. Mark the view saved only after remote acknowledgement.
5. Enqueue athlete-state recomputation when the profile fingerprint changes.

The legacy training-preferences store may remain as a compatibility reader during migration, but it must no longer be an independent writer of goals. Existing scheduling values migrate into the unified profile once and then use the unified save path.

## Engine projection

Outcome goals project into engine responsibilities rather than one-off targets:

- Marathon Ready gives running an equal primary role and supplies minimum weekly run frequency, progressive volume, long-run exposure, and intensity distribution.
- Lean + Strong gives strength an equal primary role and supplies minimum weekly strength frequency plus progressive overload.
- Strong, Durable Core requires core exercise coverage in the strength prescription and tracks its own completion/progression evidence.

Bench, pull-up, and future benchmarks seed safe prescriptions but never create a required top-level goal. Missing benchmarks lower specificity; they do not block recommendation generation.

## Seeded profile migration

The production profile will be converted from three metric-shaped goals to the three approved outcomes. Existing numerical evidence is retained as benchmarks. The ongoing Marathon Ready goal retains the current 20-mile weekly distance as a present training reference, not a permanent finish line.

No race date or marathon finish-time target is invented.

## Error handling

- A profile with no active outcomes cannot be saved and receives a clear inline explanation.
- Remote sync failure leaves local edits marked as unsynced and offers retry.
- Stale writes are reconciled by revision; they never silently overwrite a newer remote profile.
- Invalid benchmark data is isolated to the benchmark field and does not discard valid outcomes or scheduling preferences.
- If remote fetch fails, the protected local cache remains usable and visibly identified as pending synchronization.

## Testing and acceptance

- Exactly one Training Profile entry is visible across You and Settings.
- Saving outcomes, schedule, body/equipment, benchmarks, and considerations produces one protected profile and one matching remote snapshot.
- A fresh install or second device loads the remote profile.
- Existing legacy preferences migrate without creating duplicate goals.
- Marathon Ready works without a race date.
- Bench and pull-up evidence influences strength doses without appearing as mandatory goals.
- Lean + Strong remains functional without any lift benchmark.
- Strong, Durable Core produces measurable core work in complete strength prescriptions.
- Save failures remain visible and never display a false success state.
- Profile changes enqueue and produce a valid shadow prescription.

## Out of scope

- Body-fat estimation from height and weight.
- Calorie or nutrition prescriptions.
- A social goal-sharing system.
- Race-time prediction guarantees.
- Publishing the shadow prescription into Today or Plan as part of this change.
