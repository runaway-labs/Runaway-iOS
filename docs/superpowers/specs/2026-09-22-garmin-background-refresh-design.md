# Garmin Background Refresh Design

**Date:** 2026-09-22

## Objective

Collect and reconcile Garmin Health data without requiring the athlete to open Runaway. The existing app-triggered refresh remains a secondary repair path, and Garmin webhooks remain the near-real-time path.

## Architecture

Postgres `pg_cron` invokes a protected `refresh-garmin-health` Edge Function through `pg_net` every six hours. The request carries Runaway's existing `X-Runaway-Internal-Secret`, loaded from Vault by the database and compared in constant time by the Edge Function.

The worker selects a bounded batch of connected Garmin athletes whose last background attempt is stale. It refreshes expired OAuth credentials, requests Garmin Health summaries, normalizes records by athlete and calendar date, and upserts `athlete_biometrics`. Garmin values remain authoritative field by field; Apple Health may fill fields Garmin did not provide.

## Components

### Shared Garmin sync module

The Garmin API request, token refresh, date-window selection, normalization, biometric upsert, snapshot merge, and completion-marker logic move into a shared server module. Both `garmin-stats` and the scheduled worker call this module so foreground and background behavior cannot drift.

### Scheduled worker

`refresh-garmin-health` accepts only `POST`, requires the internal secret, and uses the service-role client. It processes a small bounded batch with limited concurrency. One athlete's failure is captured and does not stop other athletes.

### Scheduling and observability

New athlete fields record background attempt time, success time, failure count, and a sanitized last error. A named cron job runs every six hours and calls the worker with the existing project URL and internal secret stored in Vault. Reapplying the migration replaces the named schedule rather than creating duplicates.

## Data flow

1. Cron sends an authenticated request to `refresh-garmin-health`.
2. The worker claims eligible connected athletes.
3. Expired access tokens are refreshed with the stored refresh token and Garmin client credentials.
4. Athletes without a completed initial backfill request 90 days; established athletes request seven days.
5. Garmin endpoint responses are normalized and merged by date.
6. Daily rows are upserted into `athlete_biometrics`.
7. The compatibility snapshot and sync status fields are updated.
8. The initial-backfill marker is set only when every required endpoint succeeds and at least one row is written.

## Failure handling

- Endpoint failures are isolated and reported without logging tokens or raw health payloads.
- Partial initial pulls do not set the backfill marker and are retried later.
- Expired-token refresh failures increment the athlete failure count and preserve existing data.
- A successful run clears the stored error and resets the failure count.
- The worker returns aggregate counts rather than protected athlete data.
- The seven-day rolling window repairs delayed or missed webhook deliveries.

## Security

- The worker has no user-facing or anonymous execution path.
- Service-role credentials remain inside Supabase.
- The existing constant-time internal-secret validator protects the endpoint.
- Database helper functions are not executable by `public`, `anon`, or `authenticated`.
- Stored errors are sanitized and never contain OAuth tokens or Garmin response bodies.

## Testing and rollout

- Unit-test backfill-window selection, snapshot preservation, token-expiry decisions, and per-athlete failure isolation.
- Type-check both Edge Functions.
- Apply additive schema and cron migrations.
- Deploy the shared module, `garmin-stats`, and `refresh-garmin-health`.
- Manually invoke the protected cron path from Postgres.
- Verify cron registration, request status, athlete sync status, Garmin identity, backfill marker, and biometric date range in production.

## Non-goals

- No UI changes.
- No readiness-formula changes.
- No removal of HealthKit or Garmin webhooks.
- No generalized job platform beyond the existing Runaway internal-job pattern.
