# Garmin Background Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh every connected athlete's Garmin Health history on the backend without requiring Runaway to open.

**Architecture:** A shared Garmin synchronization module owns token renewal, Garmin API retrieval, normalization, and persistence. The authenticated foreground endpoint and a new internal-only batch worker both call that module. Postgres invokes the worker every six hours through the existing Vault, `pg_cron`, `pg_net`, and internal-secret infrastructure.

**Tech Stack:** Supabase Edge Functions, Deno/TypeScript, Supabase Postgres, Vault, pg_cron, pg_net, Garmin Health OAuth 2.0.

**Spec:** `docs/superpowers/specs/2026-09-22-garmin-background-refresh-design.md`

## Global Constraints

- No UI changes.
- Garmin direct measurements remain authoritative field by field; Apple Health only fills missing values.
- Never log or return OAuth tokens, raw Garmin health payloads, or protected athlete details.
- Scheduled execution requires the existing `X-Runaway-Internal-Secret` constant-time validator.
- Initial history is 90 days; successful subsequent reconciliation is seven days.
- One athlete failure must not stop the batch.
- Do not commit or push unless the user explicitly requests it.

---

### Task 1: Shared Garmin Athlete Synchronization

**Files:**
- Create: `runaway-edge/supabase/functions/_shared/garmin-sync.ts`
- Create: `runaway-edge/supabase/functions/_shared/garmin-sync.test.ts`
- Modify: `runaway-edge/supabase/functions/garmin-stats/index.ts`

**Interfaces:**
- Consumes: `normalizeGarminPayload(athleteId, payload, now)` from `_shared/garmin-health.ts`.
- Produces: `syncGarminAthlete(input: GarminSyncInput): Promise<GarminSyncResult>`.
- Produces: `needsTokenRefresh(expiresAt: string | null, now: Date): boolean`.
- Produces: `GarminSyncResult` with `rowsWritten`, `historyDaysRequested`, `garminUserIdLinked`, and `partialFailures`.

- [ ] **Step 1: Write failing pure tests**

Add tests proving that an absent backfill marker selects 90 days, a completed marker selects seven days, a token expiring within five minutes requires renewal, a distant expiry does not, and snapshot merging retains an old value when the latest record omits it.

- [ ] **Step 2: Run the tests and confirm the new exports are missing**

Run: `npx -y deno test supabase/functions/_shared/garmin-sync.test.ts`

Expected: failure because `_shared/garmin-sync.ts` does not exist.

- [ ] **Step 3: Implement the shared sync module**

Define:

```ts
export interface GarminSyncInput {
  admin: SupabaseClient
  athlete: GarminAthleteCredentialRow
  now?: Date
  fetcher?: typeof fetch
}

export interface GarminSyncResult {
  rowsWritten: number
  historyDaysRequested: 7 | 90
  garminUserIdLinked: boolean
  partialFailures: string[]
}
```

Refresh credentials at `https://diauth.garmin.com/di-oauth2-service/oauth/token` using `grant_type=refresh_token`, `refresh_token`, `client_id`, and `client_secret` when expiry is within five minutes. Persist rotated access token, optional rotated refresh token, and expiration before Garmin Health requests.

Fetch `user/id`, `user/metrics`, `dailies`, `hrv`, `sleeps`, and `training-status`; normalize summary arrays; upsert by `athlete_id,entry_date`; merge only defined snapshot values; and set `garmin_health_backfilled_at` only when every endpoint succeeds and at least one row is written.

- [ ] **Step 4: Replace the body of `garmin-stats` with authenticated athlete lookup plus one shared sync call**

Keep its existing Supabase user JWT validation and response shape. Return only normalized aggregate metadata plus the compatibility snapshot.

- [ ] **Step 5: Run unit tests and type checks**

Run:

```bash
npx -y deno test supabase/functions/_shared/garmin-health.test.ts supabase/functions/_shared/garmin-sync.test.ts
npx -y deno check supabase/functions/garmin-stats/index.ts
```

Expected: all tests pass and type checking exits zero.

---

### Task 2: Internal Batch Worker

**Files:**
- Create: `runaway-edge/supabase/functions/refresh-garmin-health/index.ts`
- Create: `runaway-edge/supabase/functions/refresh-garmin-health/worker.ts`
- Create: `runaway-edge/supabase/functions/refresh-garmin-health/worker.test.ts`

**Interfaces:**
- Consumes: `requireInternal(req)` and `internalAuthErrorResponse(error, headers)` from `_shared/require-internal.ts`.
- Consumes: `syncGarminAthlete(input)` from `_shared/garmin-sync.ts`.
- Produces: `runGarminRefreshBatch(input): Promise<GarminBatchResult>` with aggregate `attempted`, `succeeded`, `failed`, and `skipped` counts.

- [ ] **Step 1: Write failing batch-isolation tests**

Use an injected sync function with three athletes where the middle athlete throws. Assert the first and third complete, the returned counts are `attempted: 3`, `succeeded: 2`, `failed: 1`, and no protected athlete data appears in the result.

- [ ] **Step 2: Implement the bounded worker**

Select at most 20 connected athletes ordered by oldest `garmin_background_last_attempt_at`, excluding rows attempted within the previous five hours. Process with concurrency two. Before each attempt write `garmin_background_last_attempt_at`; on success write `garmin_background_last_success_at`, clear the error, and reset failures; on failure store a sanitized error code and increment `garmin_background_failure_count`.

- [ ] **Step 3: Implement the HTTP entrypoint**

Accept `POST` and `OPTIONS` only. Require internal authentication before creating the service-role client. Return JSON aggregate counts; map `InternalAuthError` through `internalAuthErrorResponse`; return `405` for unsupported methods.

- [ ] **Step 4: Run tests and type checks**

Run:

```bash
npx -y deno test supabase/functions/refresh-garmin-health/worker.test.ts supabase/functions/_shared/require-internal.test.ts
npx -y deno check supabase/functions/refresh-garmin-health/index.ts
```

Expected: all tests pass and type checking exits zero.

---

### Task 3: Scheduling and Operational State

**Files:**
- Create with CLI: `runaway-edge/supabase/migrations/<timestamp>_schedule_garmin_health_refresh.sql`

**Interfaces:**
- Adds athlete columns: `garmin_background_last_attempt_at timestamptz`, `garmin_background_last_success_at timestamptz`, `garmin_background_failure_count integer not null default 0`, and `garmin_background_last_error text`.
- Adds cron job: `runaway-garmin-health-refresh` on `17 */6 * * *` UTC.

- [ ] **Step 1: Generate the migration with the installed Supabase CLI**

Run: `npx -y supabase migration new schedule_garmin_health_refresh`

- [ ] **Step 2: Add the operational columns and named cron schedule**

Use `cron.unschedule` only when the named job already exists, then schedule a `net.http_post` to `/functions/v1/refresh-garmin-health`. Build headers with `Content-Type: application/json` and `X-Runaway-Internal-Secret: private.require_internal_job_secret()`. Read the base URL from Vault key `supabase_url`. Set `timeout_milliseconds` to `120000`.

- [ ] **Step 3: Apply the migration and run Supabase security advisors**

Use the Supabase migration API for project `nkxvjcdxiyjbndjvfmqy`, then run security advisors. No new table is exposed and no new function is executable by public roles.

- [ ] **Step 4: Verify the schedule**

Query `cron.job` for exactly one active `runaway-garmin-health-refresh` row with schedule `17 */6 * * *`.

---

### Task 4: Deploy and Exercise Production

**Files:**
- Deploy: `garmin-stats`
- Deploy: `refresh-garmin-health`

**Interfaces:**
- `garmin-stats` keeps manual user-JWT validation and remains deployed with platform JWT verification disabled.
- `refresh-garmin-health` keeps platform JWT verification disabled because it enforces the existing internal secret itself.

- [ ] **Step 1: Deploy both Edge Functions**

Run:

```bash
npx -y supabase functions deploy garmin-stats --project-ref nkxvjcdxiyjbndjvfmqy --no-verify-jwt
npx -y supabase functions deploy refresh-garmin-health --project-ref nkxvjcdxiyjbndjvfmqy --no-verify-jwt
```

- [ ] **Step 2: Trigger one protected run from Postgres**

Call `net.http_post` using the same Vault URL and `private.require_internal_job_secret()` expression as cron. Capture the request ID without selecting or exposing the decrypted secret.

- [ ] **Step 3: Verify the HTTP result and athlete state**

Inspect `net._http_response` by request ID. Expect HTTP 200. Verify athlete `94451852` has a newer attempt time, success time, zero failures, no last error, a populated Garmin user ID, and a populated initial-backfill timestamp.

- [ ] **Step 4: Verify biometric coverage**

Count Garmin-authored rows and report minimum/maximum dates plus non-null counts for HRV, resting heart rate, sleep, VO2 max, respiration, Pulse Ox, Body Battery, stress, and steps. Missing Garmin-provided metrics remain null rather than fabricated.

- [ ] **Step 5: Verify the app still compiles**

Run the existing iOS simulator build. Expected: `BUILD SUCCEEDED`; unrelated existing warnings may remain.
