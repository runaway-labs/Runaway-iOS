# Unified Athlete State Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Garmin-first, deterministic athlete-state engine that calculates trustworthy training load, fitness, fatigue, recovery, and complete goal-specific prescriptions while keeping every Runaway surface synchronized.

**Architecture:** Supabase stores immutable provider evidence, versioned per-activity loads, daily athlete states, calculation jobs, and prescription revisions. Edge Functions perform canonical deterministic calculations so Garmin updates and scheduled notifications work while the app is closed; iOS consumes and caches the same versioned result, while Apple Foundation Models may explain but never alter it.

**Tech Stack:** PostgreSQL/Supabase RLS and cron, Supabase Edge Functions with Deno/TypeScript, Swift 6/SwiftUI, WidgetKit, App Intents, Apple Foundation Models, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-22-unified-athlete-state-engine.md`

## Global Constraints

- Garmin is authoritative for connected-Fenix evidence; Apple Health fills only missing, deduplicated evidence.
- No external LLM API may participate in calculation, prescription, or explanation.
- Missing measurements lower confidence and never lower recovery by themselves.
- Recovery may maintain or reduce planned intensity; it may not create an unplanned hard session.
- Exact provider values remain in raw evidence; calculations retain full precision and round only at presentation boundaries.
- Training-load trends must not be labeled as injury probabilities or medical diagnoses.
- Every derived record carries `policy_version`, `input_fingerprint`, confidence, provenance, and structured reasons.
- Notification, Today, Plan, widget, App Intent, and Coach Activity must reference the same published prescription identity.
- Stage 1 and Stage 2 run in shadow mode and cannot alter production recommendations.

## Review Focus

- A Garmin workout mirrored into Apple Health must create one eligible load record, with Garmin retained as authoritative.
- A day with missing HRV or sleep must retain neutral recovery contribution and lower confidence rather than reducing readiness.
- A strength session with low average heart rate must retain meaningful strength progression and session load.
- A Garmin event received while the app is closed must update shadow state and, after activation, the scheduled prescription.
- Time-zone travel and daylight-saving transitions must preserve the athlete's intended local training day.

## Delivery Gates

- **Gate A after Task 5:** Schema, deduplication, load, recovery, fitness/fatigue, and automatic Garmin-triggered shadow calculations are deployed and observable. No user-facing recommendation changes.
- **Gate B after Task 7:** Complete shadow prescriptions pass golden scenarios and production comparison. No publishing until explicitly activated.
- **Gate C after Task 9:** All app surfaces use one published prescription; legacy independent calculations can be retired separately.

---

### Task 1: Versioned Athlete-State Persistence and Security

**Files:**
- Create: `../runaway-edge/supabase/migrations/20260922220000_add_athlete_state_engine.sql`
- Create: `../runaway-edge/supabase/tests/athlete_state_engine.sql`

**Interfaces:**
- Consumes: Existing `public.athletes`, `public.activities`, authenticated athlete ownership through `athletes.auth_user_id`.
- Produces: `activity_training_loads`, `athlete_daily_states`, `athlete_state_jobs`, `athlete_training_profile_snapshots`, and `training_prescription_revisions` with owner-scoped RLS; also replaces the broad authenticated read policy on `weekly_training_plans`.

- [ ] **Step 1: Write the failing SQL contract test**

Create `athlete_state_engine.sql` with assertions that all five tables exist, duplicate fingerprints are rejected, owners can read their rows, unrelated authenticated users cannot read them, and anonymous users receive zero rows. Assert that `weekly_training_plans` is also owner-readable only. Include the critical uniqueness checks:

```sql
insert into public.activity_training_loads
  (athlete_id, activity_id, policy_version, input_fingerprint, load_value, load_method, confidence)
values
  (:athlete_id, :activity_id, 'load-v1', 'same-input', 120.5, 'session_rpe', 'high');

-- The same activity/policy/input must fail with unique_violation.
insert into public.activity_training_loads
  (athlete_id, activity_id, policy_version, input_fingerprint, load_value, load_method, confidence)
values
  (:athlete_id, :activity_id, 'load-v1', 'same-input', 120.5, 'session_rpe', 'high');
```

- [ ] **Step 2: Run the database test to verify it fails**

Run from `runaway-edge`:

```bash
npx --yes supabase@latest db test supabase/tests/athlete_state_engine.sql
```

Expected: FAIL because the athlete-state tables do not exist.

- [ ] **Step 3: Add the schema, constraints, indexes, and RLS**

Create the migration with these stable shapes:

```sql
create table public.activity_training_loads (
  id uuid primary key default gen_random_uuid(),
  athlete_id bigint not null references public.athletes(id) on delete cascade,
  activity_id bigint not null references public.activities(id) on delete cascade,
  policy_version text not null,
  input_fingerprint text not null,
  load_value double precision not null check (load_value >= 0),
  load_method text not null check (load_method in
    ('session_rpe','heart_rate_zones','heart_rate_reserve','modality_duration','excluded')),
  confidence text not null check (confidence in ('low','medium','high')),
  details jsonb not null default '{}'::jsonb,
  excluded_reason text,
  calculated_at timestamptz not null default now(),
  unique (activity_id, policy_version, input_fingerprint)
);

create table public.athlete_daily_states (
  id uuid primary key default gen_random_uuid(),
  athlete_id bigint not null references public.athletes(id) on delete cascade,
  state_date date not null,
  policy_version text not null,
  input_fingerprint text not null,
  fitness_load double precision not null,
  fatigue_load double precision not null,
  training_balance double precision not null,
  recovery_direction text not null check (recovery_direction in
    ('supportive','neutral','caution','protective')),
  intensity_cap text not null check (intensity_cap in
    ('maintain','reduce_one','reduce_two','recovery_only')),
  confidence text not null check (confidence in ('low','medium','high')),
  reasons jsonb not null,
  source_coverage jsonb not null,
  calculated_at timestamptz not null default now(),
  unique (athlete_id, state_date, policy_version, input_fingerprint)
);

create table public.athlete_state_jobs (
  athlete_id bigint primary key references public.athletes(id) on delete cascade,
  reason text not null,
  status text not null default 'pending' check (status in ('pending','processing','failed')),
  attempt_count integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  last_error text,
  updated_at timestamptz not null default now()
);

create table public.athlete_training_profile_snapshots (
  athlete_id bigint primary key references public.athletes(id) on delete cascade,
  revision uuid not null,
  schema_version integer not null check (schema_version > 0),
  input_fingerprint text not null,
  profile jsonb not null,
  updated_at timestamptz not null,
  received_at timestamptz not null default now()
);

create table public.training_prescription_revisions (
  id uuid primary key default gen_random_uuid(),
  athlete_id bigint not null references public.athletes(id) on delete cascade,
  prescription_date date not null,
  policy_version text not null,
  input_fingerprint text not null,
  status text not null check (status in ('shadow','published','superseded')),
  prescription jsonb not null,
  remaining_week jsonb not null,
  reasons jsonb not null,
  confidence text not null check (confidence in ('low','medium','high')),
  calculated_at timestamptz not null default now(),
  unique (athlete_id, prescription_date, policy_version, input_fingerprint)
);

create unique index one_published_prescription_per_day
on public.training_prescription_revisions (athlete_id, prescription_date)
where status = 'published';
```

Enable RLS on all five tables. Add authenticated `select` policies using an `exists` subquery against `athletes.id` and `athletes.auth_user_id = auth.uid()`. Do not create client insert/update/delete policies; profile writes go through the validated Edge Function in Task 7. Add indexes for `(athlete_id, calculated_at desc)`, job due time, and prescription date/status.

Drop `"Authenticated read access"` from `weekly_training_plans` and replace it with an owner-only policy using the same `athletes.auth_user_id = auth.uid()` ownership check. The SQL test must prove one authenticated athlete cannot read another athlete's weekly plan.

- [ ] **Step 4: Run SQL tests and schema lint**

```bash
npx --yes supabase@latest db test supabase/tests/athlete_state_engine.sql
npx --yes supabase@latest db lint --level warning
```

Expected: PASS; no new security or structural warnings.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260922220000_add_athlete_state_engine.sql supabase/tests/athlete_state_engine.sql
git commit -m "feat: add versioned athlete state storage"
```

---

### Task 2: Garmin-First Evidence Deduplication

**Files:**
- Create: `../runaway-edge/supabase/functions/_shared/training-evidence.ts`
- Create: `../runaway-edge/supabase/functions/_shared/training-evidence.test.ts`
- Modify: `../runaway-edge/supabase/functions/_shared/garmin-ingest.ts`
- Modify: `Runaway iOS/Runaway iOS/Services/TrainingEvidenceImportService.swift`
- Test: `Runaway iOS/Runaway iOS/Runaway iOSTests/ActivityObservationGeneratorTests.swift`

**Interfaces:**
- Consumes: Normalized `activities` rows and raw provider identifiers.
- Produces: `resolveEvidence(candidates: ActivityEvidence[]): EvidenceResolution[]` and idempotent `enqueueAthleteState(athleteID, reason)` calls after evidence changes.

- [ ] **Step 1: Write failing Deno deduplication tests**

Cover exact provider IDs, mirrored Garmin/Apple activities within tolerance, same-day distinct workouts, ambiguous candidates, and DST-local-day independence:

```ts
Deno.test('keeps Garmin and excludes its Apple Health mirror', () => {
  const result = resolveEvidence([
    evidence({ source: 'garmin', externalID: 'g-1', start: '2026-09-22T13:00:00Z', duration: 3600, distance: 10000 }),
    evidence({ source: 'apple_health', externalID: 'hk-9', start: '2026-09-22T13:00:45Z', duration: 3592, distance: 10030 }),
  ])
  assertEquals(result.filter(x => x.eligible).map(x => x.source), ['garmin'])
  assertEquals(result.find(x => x.source === 'apple_health')?.reason, 'probable_garmin_mirror')
})

Deno.test('does not merge two real workouts close together', () => {
  const result = resolveEvidence([
    evidence({ source: 'garmin', start: '2026-09-22T13:00:00Z', duration: 1800, distance: 5000 }),
    evidence({ source: 'apple_health', start: '2026-09-22T14:00:00Z', duration: 1800, distance: 5000 }),
  ])
  assertEquals(result.filter(x => x.eligible).length, 2)
})
```

- [ ] **Step 2: Run the focused tests and verify failure**

```bash
npx --yes deno@2.5.2 test supabase/functions/_shared/training-evidence.test.ts
```

Expected: FAIL because `resolveEvidence` does not exist.

- [ ] **Step 3: Implement conservative deterministic matching**

Define the public boundary:

```ts
export type EvidenceSource = 'garmin' | 'apple_health' | 'manual' | 'strava'

export interface ActivityEvidence {
  activityID: number
  athleteID: number
  source: EvidenceSource
  externalID?: string
  modality: string
  startedAt: string
  elapsedSeconds: number
  distanceMeters?: number
  raw: Record<string, unknown>
}

export interface EvidenceResolution extends ActivityEvidence {
  eligible: boolean
  authoritativeActivityID: number
  confidence: 'low' | 'medium' | 'high'
  reason?: 'exact_provider_identity' | 'probable_garmin_mirror' | 'ambiguous_duplicate'
}
```

Use exact identity first. For cross-provider candidates require matching modality, start within 120 seconds, duration within five percent or 60 seconds, and distance within five percent or 100 meters. Garmin wins only when all required comparable fields agree. Ambiguous groups retain all rows but mark non-authoritative rows ineligible.

Add a shared `enqueueAthleteState` upsert that sets `status='pending'`, stores the newest reason, and moves `next_attempt_at` to `now()` without creating duplicate jobs.

- [ ] **Step 4: Prevent iOS evidence import from creating a competing observation**

Update `TrainingEvidenceImportService` so imported Apple Health evidence retains provider metadata and can be reconciled remotely. Add an XCTest proving a Garmin-linked Apple Health activity does not produce a second goal observation when the authoritative Garmin activity already exists.

- [ ] **Step 5: Run focused Deno and XCTest targets**

```bash
npx --yes deno@2.5.2 test supabase/functions/_shared/training-evidence.test.ts supabase/functions/_shared/garmin-ingest.test.ts
xcodebuild test -project "Runaway iOS.xcodeproj" -scheme "Runaway iOS" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:'Runaway iOSTests/ActivityObservationGeneratorTests'
```

Expected: PASS, including the mirrored-workout regression.

- [ ] **Step 6: Commit in each repository**

```bash
cd ../runaway-edge
git add supabase/functions/_shared/training-evidence.ts supabase/functions/_shared/training-evidence.test.ts supabase/functions/_shared/garmin-ingest.ts
git commit -m "feat: deduplicate Garmin and Apple training evidence"

cd ../Runaway\ iOS
git add "Runaway iOS/Services/TrainingEvidenceImportService.swift" "Runaway iOS/Runaway iOSTests/ActivityObservationGeneratorTests.swift"
git commit -m "feat: avoid mirrored activity observations"
```

---

### Task 3: Modality-Aware Session Load

**Files:**
- Create: `../runaway-edge/supabase/functions/_shared/training-load.ts`
- Create: `../runaway-edge/supabase/functions/_shared/training-load.test.ts`

**Interfaces:**
- Consumes: `ActivityEvidence` from Task 2 and optional athlete heart-rate bounds and recorded effort.
- Produces: `calculateTrainingLoad(input: TrainingLoadInput): TrainingLoadResult` using policy `training-load-v1`.

- [ ] **Step 1: Write failing load-policy tests**

Pin the method hierarchy and review-focus cases:

```ts
Deno.test('prefers user session RPE and retains precision', () => {
  const result = calculateTrainingLoad(base({ durationMinutes: 47.5, sessionRPE: 7 }))
  assertEquals(result.method, 'session_rpe')
  assertEquals(result.value, 332.5)
  assertEquals(result.confidence, 'high')
})

Deno.test('strength load is not erased by low heart rate', () => {
  const result = calculateTrainingLoad(strength({ durationMinutes: 45, averageHR: 82,
    sets: [{ exerciseID: 'barbell-squat', reps: 6, loadKg: 80, rir: 2 }] }))
  assert(result.value > 0)
  assertEquals(result.details.hardSets, 1)
})

Deno.test('missing sensors use a labeled conservative fallback', () => {
  const result = calculateTrainingLoad(base({ modality: 'running', durationMinutes: 30 }))
  assertEquals(result.method, 'modality_duration')
  assertEquals(result.confidence, 'low')
})
```

- [ ] **Step 2: Verify the tests fail**

```bash
npx --yes deno@2.5.2 test supabase/functions/_shared/training-load.test.ts
```

Expected: FAIL because the load policy is absent.

- [ ] **Step 3: Implement the pure load policy**

Use these interfaces and deterministic precedence:

```ts
export const TRAINING_LOAD_POLICY_VERSION = 'training-load-v1'

export interface TrainingLoadResult {
  value: number
  method: 'session_rpe' | 'heart_rate_zones' | 'heart_rate_reserve' | 'modality_duration' | 'excluded'
  confidence: 'low' | 'medium' | 'high'
  details: Record<string, number | string | boolean>
  reasons: string[]
}

export function calculateTrainingLoad(input: TrainingLoadInput): TrainingLoadResult
```

Rules:

- Valid user RPE is finite and within 1...10; load is minutes times RPE.
- Heart-rate zones require zone durations summing within five percent of elapsed duration and use weights 1...5.
- Heart-rate reserve requires credible `restingHR < averageHR < maxHR`, clamps reserve fraction to `0...1`, and records the inferred effort separately from user RPE.
- Strength retains hard sets, total repetitions, external-load volume, average RIR, and exercise identity in details. Its progression evidence is not replaced by heart-rate load.
- Walking and mobility use conservative modality factors and cannot claim a run or strength goal match.
- Invalid duration or excluded duplicate returns method `excluded`, zero load, and a reason.

Do not round `value`. Round only presentation strings outside this module.

- [ ] **Step 4: Add property and boundary tests**

Add tests for zero/negative/NaN duration, implausible heart-rate bounds, RPE boundaries, a 24-hour maximum duration guard, and monotonicity: with all else equal, more duration or effort cannot produce less load.

- [ ] **Step 5: Run tests and type-check**

```bash
npx --yes deno@2.5.2 test supabase/functions/_shared/training-load.test.ts
npx --yes deno@2.5.2 check supabase/functions/_shared/training-load.ts
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/_shared/training-load.ts supabase/functions/_shared/training-load.test.ts
git commit -m "feat: calculate modality aware training load"
```

---

### Task 4: Fitness, Fatigue, and Recovery State

**Files:**
- Create: `../runaway-edge/supabase/functions/_shared/athlete-state.ts`
- Create: `../runaway-edge/supabase/functions/_shared/athlete-state.test.ts`

**Interfaces:**
- Consumes: Daily training loads and normalized biometric rows.
- Produces: `calculateAthleteState(input: AthleteStateInput): AthleteStateResult` using policy `athlete-state-v1`.

- [ ] **Step 1: Write failing state tests**

```ts
Deno.test('uses exact half-life EWMA recurrence', () => {
  const result = calculateLoadState([{ date: '2026-09-22', load: 100 }], zeroSeed)
  assertAlmostEquals(result.fitness, (1 - Math.exp(-Math.LN2 / 42)) * 100)
  assertAlmostEquals(result.fatigue, (1 - Math.exp(-Math.LN2 / 7)) * 100)
})

Deno.test('missing HRV lowers confidence without creating caution', () => {
  const state = calculateAthleteState(fixture({ hrv: undefined, sleepMinutes: 450, restingHR: 52 }))
  assertEquals(state.recoveryDirection, 'neutral')
  assertEquals(state.confidence, 'medium')
  assert(state.missingSignals.includes('hrv'))
})

Deno.test('one abnormal wearable sample cannot force protective recovery', () => {
  const state = calculateAthleteState(fixture({ hrvRobustZ: -2.1 }))
  assertEquals(state.recoveryDirection, 'caution')
  assertNotEquals(state.intensityCap, 'recovery_only')
})
```

- [ ] **Step 2: Verify failure**

```bash
npx --yes deno@2.5.2 test supabase/functions/_shared/athlete-state.test.ts
```

Expected: FAIL because the state policy is absent.

- [ ] **Step 3: Implement robust baselines and state calculation**

Define:

```ts
export const ATHLETE_STATE_POLICY_VERSION = 'athlete-state-v1'

export interface AthleteStateResult {
  fitnessLoad: number
  fatigueLoad: number
  trainingBalance: number
  recoveryDirection: 'supportive' | 'neutral' | 'caution' | 'protective'
  intensityCap: 'maintain' | 'reduce_one' | 'reduce_two' | 'recovery_only'
  confidence: 'low' | 'medium' | 'high'
  contributingSignals: SignalReason[]
  missingSignals: string[]
  sourceCoverage: Record<string, string>
}
```

Use `alpha = 1 - exp(-ln(2)/halfLife)` with half-lives 42 and 7 days. Insert zero-load calendar days rather than skipping them. Use `ln(HRV)` and robust median/MAD baselines over up to 28 valid prior observations, requiring 14 observations for an established baseline. Never substitute a population default.

Classify signals as supportive, neutral, moderate concern, or strong concern. One strong signal yields at most `caution/reduce_one`. Two aligned strong signals or one strong plus two moderate signals may yield `protective/reduce_two`. `recovery_only` requires an explicit safety input such as reported illness/pain/medical restriction or an existing plan rule; wearable data alone does not force it.

- [ ] **Step 4: Add coverage for sparse and pathological inputs**

Test no biometrics, 13 versus 14 baseline days, constant values with zero MAD, extreme outliers, mixed Garmin and Apple metric coverage, VO2 trend that does not directly change intensity, timezone-local dates, DST spring-forward, and travel across time zones.

- [ ] **Step 5: Run tests and type-check**

```bash
npx --yes deno@2.5.2 test supabase/functions/_shared/athlete-state.test.ts
npx --yes deno@2.5.2 check supabase/functions/_shared/athlete-state.ts
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/_shared/athlete-state.ts supabase/functions/_shared/athlete-state.test.ts
git commit -m "feat: derive fitness fatigue and recovery state"
```

---

### Task 5: Automatic Shadow-State Worker

**Files:**
- Create: `../runaway-edge/supabase/functions/recompute-athlete-state/index.ts`
- Create: `../runaway-edge/supabase/functions/recompute-athlete-state/worker.ts`
- Create: `../runaway-edge/supabase/functions/recompute-athlete-state/worker.test.ts`
- Create: `../runaway-edge/supabase/migrations/20260922221000_schedule_athlete_state_refresh.sql`
- Modify: `../runaway-edge/supabase/functions/_shared/garmin-ingest.ts`
- Modify: `../runaway-edge/supabase/functions/refresh-garmin-health/worker.ts`

**Interfaces:**
- Consumes: Due `athlete_state_jobs`, authoritative activities, training profile, and `athlete_biometrics`.
- Produces: Idempotent `activity_training_loads` and `athlete_daily_states`; no production prescription changes.

- [ ] **Step 1: Write failing worker tests with an in-memory repository**

```ts
Deno.test('retries atomically and leaves prior state intact on failure', async () => {
  const repo = failingRepository()
  await processAthleteStateJob(repo, dueJob)
  assertEquals(repo.states.length, 1) // pre-existing last-known-good only
  assertEquals(repo.job.status, 'failed')
  assertEquals(repo.job.attemptCount, 1)
})

Deno.test('reprocessing identical evidence is idempotent', async () => {
  const repo = fixtureRepository()
  await processAthleteStateJob(repo, dueJob)
  await processAthleteStateJob(repo, dueJob)
  assertEquals(uniqueFingerprints(repo.states).length, repo.states.length)
})
```

- [ ] **Step 2: Verify failure**

```bash
npx --yes deno@2.5.2 test supabase/functions/recompute-athlete-state/worker.test.ts
```

Expected: FAIL because the worker does not exist.

- [ ] **Step 3: Implement the worker and authenticated entry point**

Export a testable worker:

```ts
export async function processAthleteStateJob(
  repository: AthleteStateRepository,
  job: AthleteStateJob,
  now = new Date(),
): Promise<ProcessResult>
```

The entry point must use the existing internal-job secret pattern from `_shared/require-internal.ts`. Claim jobs with `for update skip locked`, cap each run, use exponential retry backoff, truncate diagnostics, and upsert by policy/input fingerprint. Write all load rows and the daily state in one transaction or RPC so partial results never become current.

- [ ] **Step 4: Enqueue recalculation from Garmin ingestion**

After a Garmin activity or biometric transaction succeeds, upsert the athlete's state job. Do not enqueue on malformed, duplicate-delivery, or failed ingestion. Add a regression test showing an app-closed Garmin delivery creates a pending job.

- [ ] **Step 5: Add the five-minute internal cron**

Create an idempotent migration that schedules `recompute-athlete-state` through the existing internal caller pattern. The job must be safe to apply twice and must not expose secrets in SQL results.

- [ ] **Step 6: Run focused tests and checks**

```bash
npx --yes deno@2.5.2 test \
  supabase/functions/_shared/training-evidence.test.ts \
  supabase/functions/_shared/training-load.test.ts \
  supabase/functions/_shared/athlete-state.test.ts \
  supabase/functions/recompute-athlete-state/worker.test.ts \
  supabase/functions/_shared/garmin-ingest.test.ts \
  supabase/functions/refresh-garmin-health/worker.test.ts
npx --yes deno@2.5.2 check supabase/functions/recompute-athlete-state/index.ts
```

Expected: PASS.

- [ ] **Step 7: Gate A production verification**

Deploy schema and function, then verify one known Garmin event produces exactly one eligible activity load and one shadow daily state. Confirm no rows in `training_prescription_revisions` have `status='published'` and no existing notification payload changed.

- [ ] **Step 8: Commit**

```bash
git add supabase/functions/recompute-athlete-state supabase/functions/_shared/garmin-ingest.ts supabase/functions/refresh-garmin-health/worker.ts supabase/migrations/20260922221000_schedule_athlete_state_refresh.sql
git commit -m "feat: compute athlete state in shadow mode"
```

---

### Task 6: Complete Goal-Specific Prescription Policy

**Files:**
- Create: `../runaway-edge/supabase/functions/_shared/training-prescription.ts`
- Create: `../runaway-edge/supabase/functions/_shared/training-prescription.test.ts`
- Modify: `../runaway-edge/supabase/functions/recompute-athlete-state/worker.ts`

**Interfaces:**
- Consumes: Athlete state, server-synced `athlete_training_profile_snapshots`, owner-scoped current weekly plan, availability, recent performance, exercise history, and completion reconciliation.
- Produces: `buildPrescription(input: PrescriptionInput): PrescriptionResult` using policy `training-prescription-v1`, initially persisted with `status='shadow'`.

- [ ] **Step 1: Write failing golden-scenario tests**

Create fixtures for established runner/good recovery, aligned recovery concerns, sparse data, strength/RIR history, equal running and strength goals, unplanned long run replacing strength, and app-closed Garmin updates.

```ts
Deno.test('equal running and strength goals both receive minimum effective dose', () => {
  const result = buildPrescription(equalGoalsFixture)
  assert(result.remainingWeek.some(x => x.modality === 'running'))
  assert(result.remainingWeek.some(x => x.modality === 'strength'))
})

Deno.test('recovery can reduce but never promote intensity', () => {
  const result = buildPrescription(cautionFixture({ plannedIntensity: 'easy' }))
  assertEquals(result.today.intensity, 'easy')
  assert(!result.reasons.some(x => x.code === 'recovery_promoted_intensity'))
})

Deno.test('strength prescription contains executable dose', () => {
  const result = buildPrescription(strengthFixture)
  assert(result.today.exercises.every(x => x.sets > 0 && x.repetitions && x.targetRIR))
})

Deno.test('missing server profile blocks rather than inventing goals', () => {
  const result = buildPrescription({ ...equalGoalsFixture, profile: undefined })
  assertEquals(result.kind, 'needs_profile')
})
```

- [ ] **Step 2: Verify failure**

```bash
npx --yes deno@2.5.2 test supabase/functions/_shared/training-prescription.test.ts
```

Expected: FAIL because the prescription policy is absent.

- [ ] **Step 3: Implement typed complete prescriptions**

Define a discriminated union:

```ts
export type CompletePrescription =
  | { kind: 'run'; title: string; durationSeconds: number; distanceMeters?: number;
      intensity: 'easy' | 'steady' | 'tempo' | 'interval'; paceRange?: PaceRange;
      warmupSeconds: number; cooldownSeconds: number }
  | { kind: 'strength'; title: string; durationSeconds: number;
      exercises: StrengthDose[] }
  | { kind: 'cross_training'; modality: 'cycling' | 'swimming' | 'walking' | 'mobility';
      title: string; durationSeconds: number; intensity: 'recovery' | 'easy' | 'steady' }
  | { kind: 'rest'; title: string; recoveryActions: string[] }

export interface PrescriptionResult {
  today: CompletePrescription
  remainingWeek: ScheduledPrescription[]
  confidence: 'low' | 'medium' | 'high'
  reasons: PrescriptionReason[]
  evidenceIDs: string[]
}
```

Use current demonstrated running ability for pace ranges; if absent, omit pace and prescribe duration/conversational effort. Use exercise-specific sets/reps/load convention/RIR history for strength; never invent weight. Apply the recovery intensity cap after goal scheduling. Rebalance future days after completion while preserving completed evidence. A missing or stale server profile returns `needs_profile` and cannot produce a shadow or published workout.

For `training-prescription-v1`, enforce at least 48 hours between hard running sessions and at least 24 hours between demanding lower-body strength and a hard run. Increase only one strength variable at a time: when every work set reaches the top of its repetition range with at least two RIR, use the smallest supported equipment increment; otherwise add repetitions without adding load. Running progression remains at the prior established week when fewer than three valid weeks exist; once established, cap a generated weekly-duration increase at the lesser of 10 percent or 15 minutes. These are explicit versioned product safety limits, not medical or injury-risk claims.

- [ ] **Step 4: Persist shadow prescriptions atomically**

Extend the Task 5 worker to calculate a prescription after state succeeds and upsert it as `shadow`. Store structured reasons and the state/profile/plan fingerprint. Do not supersede or publish the current production prescription.

- [ ] **Step 5: Run golden and worker tests**

```bash
npx --yes deno@2.5.2 test supabase/functions/_shared/training-prescription.test.ts supabase/functions/recompute-athlete-state/worker.test.ts
npx --yes deno@2.5.2 check supabase/functions/recompute-athlete-state/index.ts
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/_shared/training-prescription.ts supabase/functions/_shared/training-prescription.test.ts supabase/functions/recompute-athlete-state/worker.ts supabase/functions/recompute-athlete-state/worker.test.ts
git commit -m "feat: generate complete shadow prescriptions"
```

---

### Task 7: iOS Shadow-State Client and Internal Comparison

**Files:**
- Create: `Runaway iOS/Runaway iOS/Models/AthleteState.swift`
- Create: `Runaway iOS/Runaway iOS/Services/AthleteStateService.swift`
- Create: `Runaway iOS/Runaway iOS/Services/AthleteTrainingProfileRemoteService.swift`
- Create: `Runaway iOS/Runaway iOS/Runaway iOSTests/AthleteStateServiceTests.swift`
- Create: `Runaway iOS/Runaway iOS/Runaway iOSTests/AthleteTrainingProfileRemoteServiceTests.swift`
- Modify: `Runaway iOS/Runaway iOS/Models/AthleteBiometric.swift`
- Modify: `Runaway iOS/Runaway iOS/Services/BiometricService.swift`
- Modify: `Runaway iOS/Runaway iOS/Services/AthleteTrainingProfileStore.swift`
- Modify: `Runaway iOS/Runaway iOS/ViewModels/AthleteTrainingProfileEditorModel.swift`
- Modify: `Runaway iOS/Runaway iOS/Views/BackgroundTaskMonitorView.swift`
- Create: `../runaway-edge/supabase/functions/athlete-training-profile/index.ts`
- Create: `../runaway-edge/supabase/functions/athlete-training-profile/handler.ts`
- Create: `../runaway-edge/supabase/functions/athlete-training-profile/handler.test.ts`

**Interfaces:**
- Consumes: Owner-readable daily state and shadow prescription records plus the local protected `AthleteTrainingProfile`.
- Produces: Secure versioned profile synchronization, `AthleteStateSnapshot`, `TrainingPrescriptionRevision`, and a debug-only comparison view; no Today/Plan behavior change.

- [ ] **Step 1: Write failing decoding and staleness tests**

```swift
func testDecodesGarminExtendedBiometricsWithoutRounding() throws {
    let metric = try decoder.decode(AthleteBiometric.self, from: fixture)
    XCTAssertEqual(metric.hrvMs, 29.125, accuracy: 0.0001)
    XCTAssertEqual(metric.vo2Max, 46.7, accuracy: 0.0001)
    XCTAssertEqual(metric.bodyBattery, 73)
}

func testSnapshotOlderThanPolicyWindowIsStale() {
    XCTAssertTrue(snapshot(calculatedHoursAgo: 25).isStale(reference: now, maximumAge: 24 * 3600))
}

func testProfileSyncRejectsMismatchedAthleteOwnership() async {
    await XCTAssertThrowsErrorAsync {
        try await remote.save(profile(athleteID: 2), activeAthleteID: 1)
    }
}
```

- [ ] **Step 2: Verify focused tests fail**

```bash
xcodebuild test -project "Runaway iOS.xcodeproj" -scheme "Runaway iOS" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:'Runaway iOSTests/AthleteStateServiceTests'
```

Expected: FAIL because models and service are absent.

- [ ] **Step 3: Complete biometric decoding**

Extend `AthleteBiometric` to decode the production columns already stored by Garmin: VO2 max running/cycling, fitness age, Body Battery/high/low/charged/drained, respiration, SpO2, HRV status, sleep qualifier, steps, training status/load, recovery time, body composition, blood pressure, and skin-temperature deviation. Keep numeric types precise; do not round in the model.

- [ ] **Step 4: Implement the shadow client and cache**

```swift
protocol AthleteStateProviding {
    func latestState(athleteID: Int) async throws -> AthleteStateSnapshot?
    func latestPrescription(athleteID: Int, status: PrescriptionStatus) async throws -> TrainingPrescriptionRevision?
}

struct AthleteStateSnapshot: Codable, Equatable {
    let id: UUID
    let stateDate: LocalDate
    let policyVersion: String
    let inputFingerprint: String
    let fitnessLoad: Double
    let fatigueLoad: Double
    let trainingBalance: Double
    let recoveryDirection: RecoveryDirection
    let intensityCap: IntensityCap
    let confidence: EvidenceConfidence
    let reasons: [AthleteStateReason]
    let calculatedAt: Date
}
```

Cache only a fully decoded snapshot. Preserve last-known-good data when refresh fails and expose `isStale` rather than replacing it with defaults.

- [ ] **Step 5: Add secure profile synchronization**

Implement `athlete-training-profile` with the existing authenticated user-endpoint pattern. Resolve the athlete from the JWT, reject a payload whose `athleteID` does not match, validate schema version and required goal/availability fields, fingerprint canonical sorted JSON, and upsert only when `updatedAt` is newer or the fingerprint matches. Enqueue athlete-state recalculation after a successful changed profile.

```swift
protocol AthleteTrainingProfileRemotePersisting {
    func save(_ profile: AthleteTrainingProfile, activeAthleteID: Int) async throws -> ProfileSyncReceipt
    func fetch(activeAthleteID: Int) async throws -> AthleteTrainingProfile?
}
```

Keep the protected local profile authoritative during initial rollout. After every successful local save, queue remote synchronization; retry on the next launch/background opportunity without blocking the local save. Never replace a newer local profile with an older remote snapshot.

- [ ] **Step 6: Add a debug-only comparison surface**

In `BackgroundTaskMonitorView`, show current recommendation versus shadow prescription, input fingerprint, policy version, confidence, missing signals, and structured differences. Compile this section only for internal/debug builds. Do not alter the main UI.

- [ ] **Step 7: Run focused Edge and iOS tests**

```bash
npx --yes deno@2.5.2 test supabase/functions/athlete-training-profile/handler.test.ts
npx --yes deno@2.5.2 check supabase/functions/athlete-training-profile/index.ts
xcodebuild test -project "Runaway iOS.xcodeproj" -scheme "Runaway iOS" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:'Runaway iOSTests/AthleteStateServiceTests' \
  -only-testing:'Runaway iOSTests/AthleteTrainingProfileRemoteServiceTests' \
  -only-testing:'Runaway iOSTests/EdgeFunctionClientTests'
```

Expected: PASS.

- [ ] **Step 8: Gate B review**

Collect at least seven days of shadow comparisons or replay 28 days of production evidence. Confirm mirrored activities are not double counted, missing biometrics never create a negative recovery signal, and each golden scenario produces an executable prescription with structured reasons. Record approval before Task 8.

- [ ] **Step 9: Commit in each repository**

```bash
cd ../runaway-edge
git add supabase/functions/athlete-training-profile
git commit -m "feat: sync protected athlete training profiles"

cd ../Runaway\ iOS
git add "Runaway iOS/Models/AthleteState.swift" "Runaway iOS/Models/AthleteBiometric.swift" "Runaway iOS/Services/AthleteStateService.swift" "Runaway iOS/Services/AthleteTrainingProfileRemoteService.swift" "Runaway iOS/Services/AthleteTrainingProfileStore.swift" "Runaway iOS/Services/BiometricService.swift" "Runaway iOS/ViewModels/AthleteTrainingProfileEditorModel.swift" "Runaway iOS/Views/BackgroundTaskMonitorView.swift" "Runaway iOS/Runaway iOSTests/AthleteStateServiceTests.swift" "Runaway iOS/Runaway iOSTests/AthleteTrainingProfileRemoteServiceTests.swift"
git commit -m "feat: review athlete state and shadow prescriptions"
```

---

### Task 8: Controlled Prescription Activation and Weekly Adaptation

**Files:**
- Create: `../runaway-edge/supabase/rollout/activate_athlete_state_prescriptions.sql`
- Create: `../runaway-edge/supabase/rollout/rollback_athlete_state_prescriptions.sql`
- Modify: `Runaway iOS/Runaway iOS/Services/CoachCoordinator.swift`
- Modify: `Runaway iOS/Runaway iOS/Services/RemainingWeekTrainingPolicy.swift`
- Modify: `Runaway iOS/Runaway iOS/Services/TodayWorkoutDecisionService.swift`
- Test: `Runaway iOS/Runaway iOS/Runaway iOSTests/CoachCoordinatorTests.swift`
- Test: `Runaway iOS/Runaway iOS/Runaway iOSTests/TodayWorkoutDecisionServiceTests.swift`
- Test: `Runaway iOS/Runaway iOS/Runaway iOSTests/ComplementarySchedulingPolicyTests.swift`

**Interfaces:**
- Consumes: Reviewed `training-prescription-v1` revision and current accepted weekly-plan fingerprint.
- Produces: One published prescription, an accepted-plan preview, and a reversible feature-flag activation path.

- [ ] **Step 1: Write failing activation and adaptation tests**

Add cases proving stale fingerprints cannot publish, completed days remain immutable, a substituted long run changes later run/strength spacing, partial completion changes dose rather than erasing the session, and rollback restores the prior policy.

```swift
func testLongRunSubstitutionRebalancesRemainingWeek() throws {
    let result = try coordinator.previewPublishedPrescription(longRunSubstitution, currentPlan: plan)
    XCTAssertFalse(result.proposedPlan.hasConsecutiveHardRunDays)
    XCTAssertTrue(result.changes.contains { $0.kind == .moved || $0.kind == .reduced })
}

func testStaleStateFingerprintCannotPublish() {
    XCTAssertThrowsError(try coordinator.publish(staleRevision, currentPlan: plan))
}
```

- [ ] **Step 2: Verify focused tests fail**

```bash
xcodebuild test -project "Runaway iOS.xcodeproj" -scheme "Runaway iOS" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:'Runaway iOSTests/CoachCoordinatorTests' \
  -only-testing:'Runaway iOSTests/TodayWorkoutDecisionServiceTests' \
  -only-testing:'Runaway iOSTests/ComplementarySchedulingPolicyTests'
```

Expected: FAIL on the new activation contracts.

- [ ] **Step 3: Add guarded publication**

Require matching athlete, local date, input fingerprint, plan revision, and supported policy version before converting a shadow revision to published. Supersede the prior published record and publish the new record in one transaction. Preserve the prior record for rollback.

- [ ] **Step 4: Adapt the accepted weekly plan**

Map the complete prescription into the existing `DailyWorkout` and accepted-prescription types. Reuse `TodayWorkoutDecisionService` and `RemainingWeekTrainingPolicy` for immutable completion and preview/commit semantics, extending them only where complete running or strength doses cannot currently round-trip without loss.

- [ ] **Step 5: Add explicit activation and rollback SQL**

Activation enables publication for selected athlete IDs first. Rollback disables new publication and restores the latest prior stable published prescription without deleting shadow or decision history. Both scripts must be idempotent.

- [ ] **Step 6: Run focused and regression tests**

```bash
xcodebuild test -project "Runaway iOS.xcodeproj" -scheme "Runaway iOS" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:'Runaway iOSTests/CoachCoordinatorTests' \
  -only-testing:'Runaway iOSTests/TodayWorkoutDecisionServiceTests' \
  -only-testing:'Runaway iOSTests/ComplementarySchedulingPolicyTests' \
  -only-testing:'Runaway iOSTests/CommitmentIntegrationTests'
```

Expected: PASS.

- [ ] **Step 7: Commit in each repository**

```bash
cd ../runaway-edge
git add supabase/rollout/activate_athlete_state_prescriptions.sql supabase/rollout/rollback_athlete_state_prescriptions.sql
git commit -m "feat: add athlete state activation controls"

cd ../Runaway\ iOS
git add "Runaway iOS/Services/CoachCoordinator.swift" "Runaway iOS/Services/RemainingWeekTrainingPolicy.swift" "Runaway iOS/Services/TodayWorkoutDecisionService.swift" "Runaway iOS/Runaway iOSTests/CoachCoordinatorTests.swift" "Runaway iOS/Runaway iOSTests/TodayWorkoutDecisionServiceTests.swift" "Runaway iOS/Runaway iOSTests/ComplementarySchedulingPolicyTests.swift"
git commit -m "feat: activate adaptive athlete state prescriptions"
```

---

### Task 9: Unified Notifications, Widgets, App Intents, and Coach History

**Files:**
- Modify: `../runaway-edge/supabase/functions/send-workout-prompts/policy.ts`
- Modify: `../runaway-edge/supabase/functions/send-workout-prompts/policy.test.ts`
- Modify: `../runaway-edge/supabase/functions/send-coach-events/policy.ts`
- Modify: `../runaway-edge/supabase/functions/send-coach-events/policy.test.ts`
- Modify: `Runaway iOS/Runaway iOS/Services/WorkoutPromptService.swift`
- Modify: `Runaway iOS/Runaway iOS/Services/WidgetSyncService.swift`
- Modify: `Runaway iOS/Runaway iOS/AppIntents/RunawayIntents.swift`
- Modify: `Runaway iOS/Runaway iOS/ViewModels/CoachActivityViewModel.swift`
- Test: `Runaway iOS/Runaway iOS/Runaway iOSTests/CoachNotificationTests.swift`
- Test: `Runaway iOS/Runaway iOS/Runaway iOSTests/CoachWidgetSnapshotTests.swift`
- Test: `Runaway iOS/Runaway iOS/Runaway iOSTests/CoachActivityViewModelTests.swift`

**Interfaces:**
- Consumes: One published `TrainingPrescriptionRevision.id` and its complete structured dose.
- Produces: Consistent deep links, notification payloads, widget snapshots, App Intent responses, and Coach journal entries.

- [ ] **Step 1: Write failing cross-surface identity tests**

```swift
func testNotificationWidgetAndCoachUseSamePrescriptionIdentity() throws {
    let published = fixturePublishedPrescription()
    XCTAssertEqual(notification(for: published).prescriptionID, published.id)
    XCTAssertEqual(widget(for: published).prescriptionID, published.id)
    XCTAssertEqual(journalEntry(for: published).prescriptionID, published.id)
}

func testStalePrescriptionCreatesRefreshPromptNotWorkoutAdvice() throws {
    let result = promptPolicy.evaluate(fixture(calculatedHoursAgo: 37))
    XCTAssertEqual(result.kind, .refreshRequired)
}
```

Add Deno equivalents proving scheduled sends load the current published revision immediately before delivery and do not send shadow or superseded revisions.

- [ ] **Step 2: Verify tests fail**

```bash
npx --yes deno@2.5.2 test supabase/functions/send-workout-prompts/policy.test.ts supabase/functions/send-coach-events/policy.test.ts
xcodebuild test -project "Runaway iOS.xcodeproj" -scheme "Runaway iOS" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:'Runaway iOSTests/CoachNotificationTests' \
  -only-testing:'Runaway iOSTests/CoachWidgetSnapshotTests' \
  -only-testing:'Runaway iOSTests/CoachActivityViewModelTests'
```

Expected: FAIL on prescription identity and complete-dose expectations.

- [ ] **Step 3: Make the published revision the single source**

Before every scheduled push, load the current local-day published revision. Include `prescription_id`, policy version, title, complete dose summary, confidence, and deep-link route. If missing, stale, or superseded, send only the existing refresh prompt. Never regenerate training inside the notification function.

- [ ] **Step 4: Synchronize iOS consumers**

Update `WorkoutPromptService`, `WidgetSyncService`, App Intents, and Coach history to cache and compare the same prescription UUID. Format modality-specific detail correctly: running pace only for runs, sets/reps/load for strength, duration/intensity for walking/cross-training, and recovery actions for rest.

- [ ] **Step 5: Preserve deterministic narration boundaries**

Pass only the published structured prescription and reason codes to Apple Foundation Models. Validate the generated response against the prescription identity and dose; if validation fails, show deterministic copy. The model must not alter duration, pace, distance, sets, repetitions, load, RIR, or intensity.

- [ ] **Step 6: Run the full targeted release suite**

```bash
npx --yes deno@2.5.2 test \
  supabase/functions/_shared/training-evidence.test.ts \
  supabase/functions/_shared/training-load.test.ts \
  supabase/functions/_shared/athlete-state.test.ts \
  supabase/functions/_shared/training-prescription.test.ts \
  supabase/functions/recompute-athlete-state/worker.test.ts \
  supabase/functions/send-workout-prompts/policy.test.ts \
  supabase/functions/send-coach-events/policy.test.ts

xcodebuild test -project "Runaway iOS.xcodeproj" -scheme "Runaway iOS" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:'Runaway iOSTests/AthleteStateServiceTests' \
  -only-testing:'Runaway iOSTests/CoachCoordinatorTests' \
  -only-testing:'Runaway iOSTests/CommitmentIntegrationTests' \
  -only-testing:'Runaway iOSTests/CoachNotificationTests' \
  -only-testing:'Runaway iOSTests/CoachWidgetSnapshotTests' \
  -only-testing:'Runaway iOSTests/CoachActivityViewModelTests'
```

Expected: PASS.

- [ ] **Step 7: Gate C production smoke test**

For one explicitly enabled athlete, ingest a Garmin completion while the app is closed, wait for the state worker, and verify: one authoritative load, updated daily state, updated published prescription, correct scheduled push, matching Today/Plan/widget prescription ID, and Coach history receipt. Run rollback once in staging or a disposable branch and prove the prior prescription is restored.

- [ ] **Step 8: Commit in each repository**

```bash
cd ../runaway-edge
git add supabase/functions/send-workout-prompts supabase/functions/send-coach-events
git commit -m "feat: deliver published athlete prescriptions"

cd ../Runaway\ iOS
git add "Runaway iOS/Services/WorkoutPromptService.swift" "Runaway iOS/Services/WidgetSyncService.swift" "Runaway iOS/AppIntents/RunawayIntents.swift" "Runaway iOS/ViewModels/CoachActivityViewModel.swift" "Runaway iOS/Runaway iOSTests/CoachNotificationTests.swift" "Runaway iOS/Runaway iOSTests/CoachWidgetSnapshotTests.swift" "Runaway iOS/Runaway iOSTests/CoachActivityViewModelTests.swift"
git commit -m "feat: unify coach delivery around published prescriptions"
```

## Final Release Verification

- [ ] Apply migrations to the intended Supabase environment and run database tests.
- [ ] Deploy `recompute-athlete-state`, updated Garmin ingestion functions, and updated delivery functions with their existing JWT/internal-auth settings preserved.
- [ ] Confirm cron jobs exist once and invoke only authenticated internal endpoints.
- [ ] Confirm all four new tables have RLS enabled and no anonymous read/write policies.
- [ ] Replay golden fixtures and compare stored fingerprints and outputs against expected snapshots.
- [ ] Build and test the iOS app and widget extension using the supported release Xcode/SDK.
- [ ] Install on physical compatible hardware and test Garmin ingestion while the app is terminated.
- [ ] Verify Today, Plan, notification, widget, App Intent, and Coach Activity share one prescription UUID and status.
- [ ] Verify rollback before widening activation.
