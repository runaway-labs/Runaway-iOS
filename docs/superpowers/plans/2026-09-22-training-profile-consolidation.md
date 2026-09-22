# Training Profile Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Runaway's competing goal editors with one remote-backed Training Profile organized around Marathon Ready, Lean + Strong, and Strong, Durable Core.

**Architecture:** `AthleteTrainingProfile` becomes the sole writable profile contract and Supabase remains authoritative across devices. The legacy `TrainingProfileStore` is read once for migration only; the unified store reconciles protected local and remote revisions, and the recommendation engine projects outcomes into training responsibilities while treating lift numbers as optional benchmarks.

**Tech Stack:** Swift 6, SwiftUI, XCTest, iOS protected file storage, Supabase Swift, Supabase Edge Functions, TypeScript, Deno tests.

**Spec:** `docs/superpowers/specs/2026-09-22-training-profile-consolidation-design.md`

## Global Constraints

- The app remains iOS 27-only and uses no external LLM APIs.
- Supabase `athlete_training_profile_snapshots` is authoritative; protected local storage is an offline cache.
- At least one outcome must remain active.
- Bench and pull-up values are optional benchmarks, never mandatory outcome goals.
- Marathon Ready must work without a race date or finish-time target.
- Existing schedule, body, equipment, and limitation data must survive migration.
- A save is not presented as complete until the remote write succeeds.
- Shadow prescriptions remain unpublished to Today and Plan in this workload.

---

### Task 1: Define outcomes and benchmark migration

**Files:**
- Modify: `Runaway iOS/Models/AthleteTrainingProfile.swift`
- Modify: `Runaway iOS/ViewModels/AthleteTrainingProfileEditorModel.swift`
- Modify: `Runaway iOS/Runaway iOSTests/TrainingProfileTests.swift`
- Modify: `Runaway iOS/Runaway iOSTests/TrainingProfileIntegrationTests.swift`

**Interfaces:**
- Produces: outcome identifiers `marathonReady`, `leanStrong`, and `durableCore` in the protected profile.
- Produces: optional strength benchmark values retained independently from active outcomes.
- Consumes: existing goals, availability, measurements, equipment, and limitations.

- [ ] **Step 1: Write failing model tests**

Add tests proving that the three outcomes round-trip through Codable, Marathon Ready validates without a race date, Lean + Strong validates without a lift benchmark, and zero active outcomes returns a user-facing validation error.

- [ ] **Step 2: Run the focused tests and verify RED**

Run the `TrainingProfileTests` and `TrainingProfileIntegrationTests` targets with `xcodebuild test`. Expect failures because the outcome contract and migration do not yet exist.

- [ ] **Step 3: Implement the minimal model contract**

Add a stable outcome representation to `AthleteTrainingProfile`, preserve unknown future values during decoding when possible, and expose derived engine priorities without converting benchmark targets into outcomes.

- [ ] **Step 4: Implement legacy goal migration**

Map running-distance/race goals to Marathon Ready, strength/bodyweight goals to Lean + Strong, and enable Durable Core for the seeded athlete and for profiles that already request core-focused strength. Retain existing numeric lift values as benchmarks. Never infer a race date or finish time.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run the same focused XCTest targets. Expect all new and existing profile tests to pass.

- [ ] **Step 6: Commit**

Commit the model and migration as `feat: model athlete outcomes and benchmarks`.

### Task 2: Make remote reconciliation authoritative

**Files:**
- Modify: `Runaway iOS/Services/AthleteTrainingProfileRemoteService.swift`
- Modify: `Runaway iOS/Services/AthleteTrainingProfileStore.swift`
- Modify: `Runaway iOS/Runaway iOSTests/AthleteTrainingProfileRemoteServiceTests.swift`
- Modify: `Runaway iOS/Runaway iOSTests/TrainingProfileIntegrationTests.swift`

**Interfaces:**
- Produces: `load()` behavior that renders local cache, fetches remote, and selects the newer revision.
- Produces: explicit `saved`, `saving`, and `unsynced` states.
- Consumes: authenticated GET/PUT behavior from the existing `athlete-training-profile` Edge Function.

- [ ] **Step 1: Write failing reconciliation tests**

Cover remote-only first load, newer remote replacing local, newer unsynced local surviving a stale remote response, identical revision idempotence, remote failure retaining local data, and save failure remaining visibly unsynced.

- [ ] **Step 2: Run focused tests and verify RED**

Run `AthleteTrainingProfileRemoteServiceTests` and `TrainingProfileIntegrationTests`. Expect failures because load currently does not fetch and reconcile the remote snapshot.

- [ ] **Step 3: Implement remote-first reconciliation**

Fetch after protected local load, compare revision/update metadata, persist accepted remote data back into protected storage, and prevent stale remote responses from overwriting unsynced local edits.

- [ ] **Step 4: Implement truthful save state**

Keep local protection, but expose success only after remote acknowledgement. Preserve failed edits, surface retry, and prevent an empty-outcome profile from reaching the network.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run both focused test targets and confirm reconciliation and failure-state coverage passes.

- [ ] **Step 6: Commit**

Commit as `fix: reconcile protected profiles with Supabase`.

### Task 3: Consolidate the two profile destinations

**Files:**
- Modify: `Runaway iOS/Views/AthleteView.swift`
- Modify: `Runaway iOS/Views/SettingsView.swift`
- Modify: `Runaway iOS/Views/AthleteTrainingProfileView.swift`
- Modify: `Runaway iOS/Components/TrainingProfileComponents.swift`
- Modify: `Runaway iOS/Views/TrainingProfileView.swift`
- Modify: `Runaway iOS/Services/TrainingProfileStore.swift`
- Modify: `Runaway iOS/Runaway iOSTests/TrainingProfileIntegrationTests.swift`

**Interfaces:**
- Produces: exactly one visible navigation row titled `Training Profile`.
- Produces: outcome cards, weekly rhythm, body/equipment, optional benchmarks, and considerations in one editor.
- Consumes: unified editor/store behavior from Tasks 1 and 2.

- [ ] **Step 1: Write failing navigation and migration tests**

Assert one profile destination, one writable store, and one-time migration of legacy schedule/activity preferences without duplicate outcomes.

- [ ] **Step 2: Run focused tests and verify RED**

Run `TrainingProfileIntegrationTests`. Expect failures while both destinations remain active.

- [ ] **Step 3: Build the unified information hierarchy**

Make the top section three plain-language outcome cards. Move scheduling into Weekly Rhythm, measurements/equipment into Body & Equipment, numeric performance evidence into a collapsed optional Benchmarks section, and limitations into Considerations. Do not expose raw metric or priority enum names.

- [ ] **Step 4: Remove competing navigation and writes**

Replace both legacy rows with one Training Profile row. Keep `TrainingProfileStore` only as a migration reader and route all future changes through `AthleteTrainingProfileStore`.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run `TrainingProfileIntegrationTests` and confirm migration and single-destination assertions pass.

- [ ] **Step 6: Commit**

Commit as `feat: unify training profile experience`.

### Task 4: Project outcomes into complete prescriptions

**Files:**
- Modify: `supabase/functions/_shared/training-profile-projection.ts`
- Modify: `supabase/functions/_shared/training-profile-projection.test.ts`
- Modify: `supabase/functions/_shared/training-prescription.ts`
- Modify: `supabase/functions/_shared/training-prescription.test.ts`

**Interfaces:**
- Produces: running/strength priorities and durable-core requirement derived from outcomes.
- Produces: strength sessions with executable core work even when no lift benchmarks exist.
- Consumes: optional benchmarks as starting evidence only.

- [ ] **Step 1: Write failing Edge tests**

Cover Marathon Ready without a race, Lean + Strong without benchmarks, Durable Core adding measurable core work, optional bench/pull-up evidence seeding doses, and legacy metric profiles remaining compatible during migration.

- [ ] **Step 2: Run focused Deno tests and verify RED**

Run the projection and prescription test files. Expect the new outcome fixtures to fail until projection supports them.

- [ ] **Step 3: Implement outcome projection**

Translate active outcomes into equal running/strength responsibilities, expose the core requirement, and continue accepting the legacy metric-shaped profile during rollout.

- [ ] **Step 4: Implement complete core dosing**

Add conservative bodyweight core exercises when Durable Core is active and no recent core history exists. Prefer demonstrated history when available and never invent external load.

- [ ] **Step 5: Run focused and full Edge suites**

Run focused tests, then all `_shared`, recompute worker, and profile handler tests. Expect zero failures.

- [ ] **Step 6: Replay production evidence**

Run the existing 28-day replay and verify no unsafe hard prescription on protective days, no empty strength sessions, and nonzero core coverage on prescribed strength days.

- [ ] **Step 7: Commit**

Commit as `feat: prescribe from durable athlete outcomes`.

### Task 5: Migrate production profile and release safely

**Files:**
- Modify: production row in `athlete_training_profile_snapshots` through an explicit transactional data update.
- Deploy: `recompute-athlete-state` only after Edge tests and replay pass.

**Interfaces:**
- Produces: three active outcomes with existing schedule/body/equipment/limitations preserved.
- Produces: bench and pull-up baselines stored as optional benchmarks.
- Consumes: deployed backward-compatible projection from Task 4.

- [ ] **Step 1: Verify the current production profile fingerprint and revision**

Read the current snapshot and abort if it changed unexpectedly since this workload began.

- [ ] **Step 2: Apply a transactional profile update**

Replace metric-shaped top-level goals with Marathon Ready, Lean + Strong, and Strong, Durable Core. Retain the 20-mile weekly reference and known strength baselines as supporting evidence; do not retain inferred bench/pull-up targets as user-confirmed goals.

- [ ] **Step 3: Deploy the recompute function**

Deploy with the existing internal authentication configuration. Do not alter JWT behavior or secrets.

- [ ] **Step 4: Enqueue and execute one recomputation**

Queue `profile_changed`, invoke the existing protected cron path, and verify zero pending/failed jobs.

- [ ] **Step 5: Verify the shadow result**

Confirm current modality, complete exercises, remaining week, confidence, reason codes, and core coverage. Do not publish the shadow result.

- [ ] **Step 6: Build and test the iOS app**

Run focused tests, build for the available simulator/device, and verify one Training Profile destination, remote profile loading, truthful save state, and retained protected storage.

- [ ] **Step 7: Merge only verified commits**

Fast-forward the approved iOS and Edge branches into local main. Do not push or archive unless explicitly requested.
