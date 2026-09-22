# Garmin Health History Implementation Plan

**Goal:** Make Garmin Health the primary source for historical biometrics and advanced physiology while keeping Apple Health as a safe fallback and leaving the current UI unchanged.

**Architecture:** Garmin webhook and pull responses are normalized into one dated `athlete_biometrics` model. Garmin values win field-by-field; Apple Health may fill missing fields but cannot overwrite a Garmin measurement. Garmin user identity, rather than the currently connected singleton athlete, routes webhook records.

**Tech Stack:** Supabase Postgres/RLS, Supabase Edge Functions (Deno/TypeScript), Swift/SwiftUI, Garmin Health API, HealthKit.

## Tasks

1. Add a pure Garmin Health normalizer with tests for sleep-score objects, daily merging, advanced metrics, malformed records, and Garmin user identity.
2. Extend `athletes` and `athlete_biometrics` for Garmin identity, VO2 max, respiration, Pulse Ox, Body Battery, training status/load, recovery, steps, and source precedence.
3. Capture Garmin user identity during OAuth and route webhook records by that identity.
4. Normalize webhook payloads into daily history while retaining the existing snapshot for compatibility and removing raw health-payload logging.
5. Expand the authenticated Garmin refresh into a bounded initial backfill plus short rolling refresh.
6. Trigger Garmin refresh from the app lifecycle without adding UI, and make HealthKit day uploads resilient so one failed date cannot stop the remaining window.
7. Run targeted tests, deploy the migration and affected Edge Functions, then verify production schema/function state.

## Security ruling

Webhook identity validation and strict payload parsing ship now. A callback secret must not be enforced until the matching value is configured in the Garmin developer portal, because enabling only one side would disable the live feed. The webhook will no longer trust a singleton connected athlete or log full health payloads.
