# Accomplishment-first implementation status

Implementation pass: September 4, 2026. Local changes only; no commit, push, production data repair, archive, or upload.

## Implemented

- Shared Foundation snapshot and Sunday-based local-calendar aggregation for app and widget. Canonical meters and seconds, explicit athlete identity, period boundaries, and refresh timestamp.
- Complete, paginated year-to-date projection instead of treating the latest 50 feed rows as complete history. Chart includes non-running sessions with zero distance. Running goals exclude other sports.
- Today: earned weekly distance, mixed-activity chart, goal rings with independent saved units, drilldown, explicit Adjust today, compact readiness, accessible RunCast, working latest-activity detail route.
- Activities: explicit This week and Recent scopes, matching filter summary, stable activity IDs, expanded sport filters. Removed unexplained pace-comparison badges. Recent is labeled as loaded history.
- Plan: visible completed/today/planned/recovery timeline. Completed-session denominator excludes rest. Race editing preserved. Successful empty race responses clear stale race cards.
- Adjustment receipts include a before/after disclosure. Existing adjustment and persistence paths retained.
- You: complete year-to-date running totals alongside all-training time and active days, three most recent earned/timestamped milestones, source-linked verified saved records, and direct running-goal settings.
- Personal-best presentation is read-only. Non-runs, flagged activities, projected miles, short half/marathon windows, missing timestamps, and unsupported stored results do not qualify for the record showcase. Production records remain untouched pending a reviewed repair.
- Existing widget layout retained; its adapter now consumes the canonical snapshot when available, with athlete and period checks.

## Evidence

- App and widget arm64 iOS 27 simulator build: passed.
- 16 canonical progress checks: passed.
- 4 activity classification checks: passed. GravelRide classification failed before implementation and passed after it.
- 13 existing widget checks: passed.
- Native SwiftUI hero rendered with illustrative data at regular and larger-text settings. Image: ../previews/accomplishment-first-progress.png.
- Signed full app test target: 297 test definitions passed, 1 failed (302 passing runs when dynamic parameter cases are counted individually).
- Failure: TrainingProfileIntegrationTests.remainingWeekPreservesEveryRunningPrescriptionIncludingFutureTaperDetails(). Expected regenerated.workouts to contain futureRun.id; it did not. Do not dismiss this as flaky without identifying the cause.
- Initial unsigned test attempt failed before test execution: SwiftData could not find its App Group entitlement. Ad-hoc signed test run executed the suite.
- Simulator installation attempted successfully. End-to-end visual navigation is not yet verified; the unsigned interactive launch failed at SwiftData initialization. A later install attempt encountered a device capability error after the test run changed device state.

## Remaining release gates

1. Awaiting requested approval to replace the new Undo guard's raw JSON byte comparison with deterministic, semantic plan comparison, and add regression coverage. The current guard can incorrectly refuse an unchanged plan.
2. Diagnose and fix the failing future-run/taper-preservation test; repeat affected tests and the full target.
3. Complete signed simulator smoke testing: Today week drilldown, all activity filters and detail routes, Adjust today and Undo, race editing, Plan timeline, record links, goal settings, readiness detail/recalibration, RunCast detail.
4. Check real iPhone layouts at small/large sizes, accessibility Dynamic Type, VoiceOver, Reduce Motion, and tab/FAB overlap. The component render does not substitute for those checks.
5. Exercise authenticated progress refresh, cached/offline/error states, day rollover, and account switching in the app. Pure policy tests cover aggregation and widget cache isolation but not the live transport.

## Database inspection

Read-only inspection of runaway-labs confirmed that best_split_pr currently lacks an activity-type restriction and accepts broad distance ranges. The previous iOS implementation projected a mile from a single kilometer split and used 21/42-split windows for half/marathon candidates. No database function, schema, or record was changed in this pass. The iOS service no longer creates those estimates when opening the profile.

## Commands and artifacts

Build log: /tmp/runaway-accomplishment-build.log
Signed test log: /tmp/runaway-accomplishment-signed-tests.log
Test result: /Users/jack.rudelic/Library/Developer/Xcode/DerivedData/Runaway_iOS-dprbaxctxqwkqdfmldjxpkjjswiv/Logs/Test/Test-Runaway iOS-2026.09.04_14-44-29--0500.xcresult
Pure tests: tests/ProgressClassificationChecks.swift and tests/TrainingProgressPolicyChecks.swift

Use Xcode-beta at /Applications/Xcode-beta.app/Contents/Developer. This Xcode exposes simulators through devicectl and Device Hub. Its diagnostic collector still attempts simctl, which is unavailable; that diagnostic error is separate from the failing test assertion.
