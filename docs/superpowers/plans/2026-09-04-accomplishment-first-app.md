# Accomplishment Across Runaway Implementation Plan

> **For agentic workers:** Use the executing-plans skill to implement these tasks sequentially, retaining the screen and data checkpoints. Steps use checkbox syntax for tracking.

**Goal:** Carry the satisfying progress-widget experience into Today, Activities, Plan, and You while preserving truthful metrics and working training decisions.

**Architecture:** Reuse existing activity, goal, record, readiness, weather, and adaptive-plan services. Introduce one shared progress presentation model and a small set of native SwiftUI components, with the app writing the same snapshot for its widget. The Becoming Engine remains behind Next Up and adjustment details.

**Tech Stack:** SwiftUI, Swift, WidgetKit/App Groups, existing Supabase services, existing Apple on-device intelligence, Swift Testing/XCTest and simulator visual checks.

**Spec:** `docs/superpowers/specs/2026-09-04-accomplishment-first-app.md`

## Global constraints

- Keep the four tab names: Today, Activities, Plan, You.
- Minimum platform: iOS 27 on the app's supported Apple hardware.
- Use Apple on-device models only; introduce no external LLM API calls.
- Progress, records, achievements, and workout changes must work without model availability.
- Default activity distance display to miles; honor the setting in You.
- Preserve the units saved on each goal and race independently of activity display preferences.
- Count only running activities toward running distance and run counts; include other selected activities in the activity chart and training time.
- Use local calendar days for activity labels and date-only semantics for races.
- Weather and readiness remain available and actionable.
- Rest and recovery must not be portrayed as failure or a broken achievement streak.
- Preserve completed workouts and the user's explicitly chosen workout when adapting the remaining week.
- Keep the existing progress widget focused on accomplishment. Keep optional planning widgets separate.
- Do not rename tabs, add a chatbot, add social rankings, or introduce arbitrary points.

## Delivery order

1. Shared progress rules and a concrete Today-screen preview.
2. Today implementation.
3. Record accuracy prerequisite, then Activities implementation.
4. Plan implementation.
5. You implementation.
6. Cross-screen checks and a reviewable build.

Each screen is a separately reviewable deliverable. Keep a rendered reference for the finished screen before proceeding to the next. Do not replace the approved widget again as part of this work.

## Existing source map

| Responsibility | Existing source |
| --- | --- |
| Today screen | `Runaway iOS/Views/TrainingView.swift` |
| Today data and training phase | `Runaway iOS/ViewModels/TrainingViewModel.swift` |
| Next Up and Adjust Today | `Runaway iOS/Components/WorkoutComponents.swift` |
| Becoming path logic and presentation | `Runaway iOS/Models/BecomingEngine.swift`, `Runaway iOS/Components/BecomingLine.swift` |
| Activity list | `Runaway iOS/Views/ActivitiesView.swift` |
| Plan screen and prescriptions | `Runaway iOS/Views/WeeklyTrainingPlanView.swift`, `Runaway iOS/Models/WeeklyTrainingPlan.swift` |
| Athlete/settings screen | `Runaway iOS/Views/AthleteView.swift` |
| Shared activity and plan ownership | `Runaway iOS/Managers/DataManager.swift` |
| Activity aggregates | `Runaway iOS/Services/ActivityService.swift` |
| Personal bests | `Runaway iOS/Models/PersonalBest.swift`, `Runaway iOS/Services/PersonalBestService.swift` |
| Milestone notification boundary | `Runaway iOS/Services/MilestoneService.swift` |
| Theme and units | `Runaway iOS/Utils/Theme.swift`, `Runaway iOS/Utils/UnitPreferences.swift` |
| Goal units and targets | `Runaway iOS/Models/GoalSettings.swift` |
| Race editing | `Runaway iOS/Components/ManualRaceSheet.swift`, `Runaway iOS/Services/GoalService.swift` |
| Widget reference | `RunawayWidget/AccomplishmentWidgetView.swift`, `RunawayWidget/ProgressWidgetSnapshot.swift` |
| Widget writes | `Runaway iOS/Services/WidgetSyncService.swift` |
| Test membership and app/widget targets | `Runaway iOS.xcodeproj/project.pbxproj` |

The file map identifies integration points; read their current relevant implementations at execution time before patching. Do not assume the names of private helpers or change deployed database contracts from this document alone.

## Task 1: Shared progress contract and Today preview

**Files:**

- Create `Shared/TrainingProgressSnapshot.swift` for app/widget quantities, periods, coverage, and day summaries.
- Create `Shared/TrainingProgressPolicy.swift` for pure aggregation and period rules.
- Create `Runaway iOS/Components/Progress/TrainingProgressHero.swift`.
- Create `Runaway iOS/Components/Progress/TrainingActivityChart.swift`.
- Create `Runaway iOS/Components/Progress/TrainingGoalRing.swift`.
- Modify `Runaway iOS/Utils/Theme.swift` only to add the minimum reusable progress tokens.
- Modify `Runaway iOS/Services/WidgetSyncService.swift` and `RunawayWidget/ProgressWidgetSnapshot.swift` to map the shared contract while preserving the approved widget view.
- Register shared code in both app and extension in `Runaway iOS.xcodeproj/project.pbxproj`.
- Add policy cases to the existing `Runaway iOS/Runaway iOSTests/Runaway_iOSTests.swift` test target.

**Contract:** The shared snapshot identifies the athlete and period and contains running distance in meters, run count, all-activity duration, daily activity summaries, goal progress, data coverage, and the source refresh time. Keep formatted strings out of canonical quantities. Goals retain their saved display unit.

- [ ] Define current-week boundaries using the app's Sunday-through-Saturday convention and the athlete's local calendar.
- [ ] Consolidate the running classifier and conversion rules used by app progress and the widget; keep chart filtering independent from running goal totals.
- [ ] Preserve the existing database-backed annual/monthly aggregate path; attach complete versus partial coverage explicitly.
- [ ] Reuse and migrate the current widget snapshot fields, keeping existing widget kinds and their visible progress design intact.
- [ ] Build the three progress components with the approved palette, typography, and spacing, using representative SwiftUI preview fixtures.
- [ ] Compose one Today preview in the new hierarchy before changing live routes. Render it for small and large phones, including one large-text sample.
- [ ] Check quantities with concrete fixtures: a 3 mi run, a 2 mi walk, a 20 mi ride, and a 45-minute strength workout yield 3 running miles and one run; all valid durations appear in the activity chart.
- [ ] Check that changing activity display to kilometers changes 3 mi to approximately 4.83 km while a goal saved in miles retains its miles label and identical completion fraction.
- [ ] Check midnight, Sunday rollover, month/year rollover, missing data, account change, duplicate activity import, and partial-history states before the shared contract is adopted by more screens.

**Acceptance:** Today and the existing widget can render from the same quantities; the approved widget is visually unchanged. The new Today preview puts effort first and keeps Next Up reachable.

## Task 2: Today

**Files:**

- Modify `Runaway iOS/Views/TrainingView.swift`.
- Modify `Runaway iOS/ViewModels/TrainingViewModel.swift`.
- Modify `Runaway iOS/Components/WorkoutComponents.swift` and `Runaway iOS/Components/BecomingLine.swift` for the compact decision entry.
- Reuse `Runaway iOS/Components/ReadinessComponents.swift` for the existing detail route and recalibration.
- Reuse the Task 1 progress components and snapshot.
- Extend `Runaway iOSUITests/Runaway_iOSUITests.swift` for the changed entry routes.

- [ ] Reorder the screen to greeting, progress hero/chart/goals, earned highlight when available, Next Up, compact readiness/RunCast context, and latest activity.
- [ ] Keep the earned-highlight slot absent when there is no supported achievement; do not fill it with generic praise.
- [ ] Reduce the always-visible Becoming branch controls to one clear Adjust entry; retain actual alternatives, selected-path handoff, receipt, and Undo in the decision flow.
- [ ] Preserve supported workout-start behavior. Running may use the existing recorder; do not label a button Start for strength unless it opens a real supported strength action.
- [ ] Show a short weather advisory near outdoor Next Up only when current conditions require attention. Preserve the full forecast/detail route.
- [ ] Preserve readiness breakdown and recalibration. Use neutral recovery language and keep earned totals visible even with low readiness.
- [ ] Refresh the snapshot when an activity, goal, unit setting, readiness result, weather result, or saved plan changes. Avoid work triggered repeatedly from SwiftUI body evaluation.
- [ ] Exercise profile missing, plan missing, planned recovery, workout completed, empty history, offline cache, and failed adjustment states.
- [ ] Tap progress, latest activity, Start, Adjust, readiness, recalibrate, and RunCast in the simulator. Confirm each opens or performs its advertised action.

**Acceptance:** A normal Today viewport leads with progress. Every existing critical route still works. A plan adjustment updates the saved plan, visible Next Up, and affected widget data and offers a valid undo.

## Task 3: Record accuracy, then Activities

**Files:**

- Modify `Runaway iOS/Services/PersonalBestService.swift` and `Runaway iOS/Models/PersonalBest.swift` for record evidence and eligibility.
- Modify `Runaway iOS/Views/ActivitiesView.swift`.
- Create `Runaway iOS/Models/ActivityAchievementPresentation.swift` for evidence-backed record and comparison labels.
- Reuse shared progress policy and existing activity-detail routes.
- Add behavioral cases to `Runaway iOS/Runaway iOSTests/Runaway_iOSTests.swift`.

**Known local prerequisites:** `bestActivity` currently filters distance and elapsed time without restricting the query to running. `bestMileFromSplits` projects a mile from the fastest 1 km split. Broad activity-distance buckets and 21/42 whole-kilometer windows also cannot independently establish an exact half/full marathon effort.

- [ ] Inspect the linked database definitions of `best_split_pr` and `athlete_personal_bests` read-only before changing query contracts. Trace record candidates back to source activity type, measured distance, time basis, and timestamp.
- [ ] Require a running activity for a running record. Treat whole-distance efforts, covered split efforts, and pace projections as different evidence categories.
- [ ] Exclude projected mile times and insufficient split windows from completed-distance record claims. Show them only as labeled estimates if a useful existing surface needs them.
- [ ] Do not publish an achievement from an old stored record whose evidence cannot be established. Any repair of stored records requires a reviewed candidate report before production writes.
- [ ] Add a compact visible-period summary above the existing list, defaulting to the current week.
- [ ] Make All show sessions and time across sports plus explicitly labeled running distance. Make sport-specific summaries use meaningful measures for that sport.
- [ ] Preserve existing filters, refresh, commitment, and activity-detail interactions. Ensure the summary's period and the list's period match.
- [ ] Place record/milestone labels on the source activity row. Use the existing detail route for evidence, keeping rows compact.
- [ ] Replace or hide unexplained improvement percentages. Only display a comparison when activity type, distance, timing basis, and relevant conditions support it; identify the comparison in words.
- [ ] Test a short ride in a 5K distance range cannot become a running PR, a fast 1 km split cannot become a completed mile PR, and duplicate imports cannot award the same record twice.
- [ ] Check an activity near local midnight, a metric pace view, a strength activity with no distance, and a paginated history with incomplete totals.

**Acceptance:** The list remains quick to browse. Every accomplishment label is attributable to actual work, and changing filters never turns strength or cycling into running totals.

## Task 4: Plan

**Files:**

- Modify `Runaway iOS/Views/WeeklyTrainingPlanView.swift`.
- Create `Runaway iOS/Components/Progress/TrainingWeekTimeline.swift`.
- Create `Runaway iOS/Models/PlanProgressPresentation.swift` for completed/today/future/recovery states and saved-plan differences.
- Reuse `Runaway iOS/Models/WeeklyTrainingPlan.swift`, `Runaway iOS/Services/TrainingPlanService.swift`, and `Runaway iOS/Managers/DataManager.swift` as the existing persistence/adaptation authority.
- Preserve `Runaway iOS/Components/ManualRaceSheet.swift` and `Runaway iOS/Services/GoalService.swift` behavior.
- Extend `Runaway iOS/Runaway iOSTests/TrainingProfileIntegrationTests.swift` for completed/rest states and plan-change presentation.

- [ ] Put the upcoming race or training focus first, keeping the race edit action visible.
- [ ] Replace visually uniform daily cards with a clear weekly timeline using complete, today, upcoming, and recovery states.
- [ ] Count completed prescribed training sessions against prescribed training sessions. Rest days are neutral planned states, and unrelated extra activities do not automatically fulfill the prescription.
- [ ] Put today's details and Adjust close to the timeline; collapse baseline and long explanatory sections.
- [ ] Compute changed-session indicators from the actual before/after saved plans. Summarize real changes using their days and session titles.
- [ ] Keep the existing adaptive update and Undo behavior; preserve completed work, manual choices, progression, and taper prescriptions.
- [ ] Use race date, distance in its saved unit, optional equivalent distance, and training phase. Do not invent a race-readiness percentage.
- [ ] Exercise a mixed running/strength week, a recovery day, a changed session, undo, no race, manual race edit, and next-week transition.
- [ ] Run the relevant remaining-week and taper-preservation integration cases with a controlled test date so results do not depend on the day tests happen to run.

**Acceptance:** Athletes can see what they have done, what remains, and exactly what an adjustment changed. Existing race and adaptive-plan behavior remains functional.

## Task 5: You

**Files:**

- Modify `Runaway iOS/Views/AthleteView.swift`.
- Create `Runaway iOS/Components/Progress/AthleteAchievementSummary.swift`.
- Create `Runaway iOS/Components/Progress/PersonalBestCollection.swift`.
- Reuse `Runaway iOS/Services/PersonalBestService.swift` and `Runaway iOS/Services/MilestoneService.swift`.
- Reuse `Runaway iOS/Services/ActivityService.swift` for complete aggregates and the existing account/settings routes.
- Extend existing UI tests for profile, records, and settings navigation.

- [ ] Lead with athlete identity and a concise earned-total summary, initially the reliable This year period.
- [ ] If adding All time, implement an ownership-scoped complete-history aggregate before exposing that label. Never sum just the in-memory activity page.
- [ ] Present record cards using Task 3's evidence rules, with achievement date and a source activity link where available.
- [ ] Inspect the existing `check-milestones` function and stored milestone definition before reusing its results. Show only earned definitions supported by the user's data; deduplicate repeated notifications.
- [ ] Limit the initial milestone display to three recent meaningful accomplishments and one factual next milestone. Omit unearned filler and do not create a points system.
- [ ] Keep training profile, distance goals, units, devices, notifications, and account controls in clearly named groups directly below the achievement content.
- [ ] Clear prior-athlete achievement data on account change and represent partial sync as partial sync, not a lower lifetime total.
- [ ] Check no-history, no-record, mixed-sport, missing-source-activity, offline, and account-change cases.
- [ ] Verify every existing settings row and record/source link still routes correctly.

**Acceptance:** You feels like a history of earned effort while remaining a useful settings screen. Recovery never erases accomplishment, and totals have an explicit scope.

## Task 6: Cross-screen checks and reviewable build

**Files:**

- Extend existing test targets only where new behavior needs coverage; confirm target membership before adding a test file.
- Store final screen captures in `docs/superpowers/specs/assets/` with the date and screen name.
- Update this plan's checkboxes as tasks finish.

- [ ] Compare the same athlete and time period across Today, Activities, Plan, You, and the progress widget. Reconcile any differences before release.
- [ ] Verify activity classification, goal unit preservation, calendar dates, imported-activity deduplication, completed/rest session semantics, and partial-history labels.
- [ ] Confirm caches and queries are scoped to athlete and period, aggregate work does not run on each render, and record recomputation does not block screen entry.
- [ ] Render actual SwiftUI screens on small and large supported phones. Check long race names, long activity names, metric settings, large text, VoiceOver labels, Reduce Motion, and tab-bar overlap.
- [ ] Recheck all affected buttons and deep links, including the main widget and the optional decision widget, without treating an app launch as proof an action succeeded.
- [ ] Run the existing focused policies and the training-plan integration suites; run the whole app test target once at the cross-screen gate. Investigate failures with their actual assertions rather than assuming isolated success means a flake.
- [ ] Build the app and embedded widget extension and retain screenshots plus a short list of changes for review.
- [ ] Archive and upload only when requested for this implementation. The current request is to produce this plan.

Useful existing test command, with the project's known target naming:

```bash
DEVELOPER_DIR='/Applications/Xcode-beta.app/Contents/Developer' xcodebuild test \
  -project 'Runaway iOS.xcodeproj' \
  -scheme 'Runaway iOS' \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  '-only-testing:Runaway iOSTests'
```

Resolve a current available simulator at execution time if that destination is unavailable. Keep tests independent of real account credentials and the live production date.

## Definition of finished

The four tabs match the approved specification, shared progress quantities agree with the widget, verified achievements have source evidence, all preserved routes work, affected behavioral tests pass, and actual screen captures demonstrate that progress remains the main visual focus. Completing the plan does not mean promising improved race performance or treating a model-generated statement as an earned achievement.
