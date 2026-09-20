# Runaway: Make Effort Visible

**Status:** Product specification for the requested implementation plan. Application changes have not started under this specification.

## Product intent

Opening Runaway should make the athlete feel the value of the work they have already done, then make the next action easy. The restored progress widget is the approved visual reference: earned distance, colorful activity bars, legible goal rings, and generous space.

The user rejected the previous widget redesign because a prominent list of recommendations displaced accomplishment. Preserve that lesson throughout the app. The Becoming Engine can help make decisions without becoming the identity or dominant heading of every screen.

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

## Visual reference

Use `RunawayWidget/AccomplishmentWidgetView.swift` and the approved rendered progress widgets as the reference.

- Large white distance numerals with a smaller, explicit unit.
- Rounded native typography with clear hierarchy, not additional type families.
- Amber for running and modest brand accents, blue for strength, mint for walking and recovery.
- Deep navy surfaces, restrained borders, and fewer containers nested inside containers.
- Progress rings and activity bars communicate real quantities.
- One short explanatory line where useful; avoid generic coaching paragraphs.
- Green or mint checkmarks acknowledge earned completion.
- Use brief number/bar transitions when real data changes; respect Reduce Motion.
- Respect tinted rendering on widgets, Dynamic Type in the app, VoiceOver, contrast, and safe areas.

## Today

**Question answered:** What have I accomplished, and what is my next useful step?

Default vertical order:

1. Compact greeting and date.
2. Weekly progress hero: running distance, run count, and all-activity training time, each explicitly labeled.
3. Seven-day activity chart and weekly goal progress. The chart shares activity colors with the widget.
4. One concise earned highlight when supported by data, such as a completed weekly goal. Otherwise omit this area.
5. Next Up: one workout, its purpose, and clear `Start` and `Adjust` actions appropriate to the activity.
6. A compact readiness and RunCast context area linking to the existing details.
7. Latest activity with a link to Activities.

Keep readiness details and recalibration available. Show severe, current weather guidance near an outdoor Next Up when it affects the decision. A low readiness score must not recolor the entire page as a failure state.

Tapping the progress hero opens the current week's activity history. Tapping Adjust opens the existing choices and explains the actual effect on the remaining week. Show an adjustment receipt and working Undo only after the update succeeds.

On recovery days, show recovery as an intentional plan choice. If activity is complete, acknowledge it without automatically telling the athlete to do more. If the profile or plan is missing, state what needs setup and provide the existing setup route.

## Activities

**Question answered:** What work have I put in, and what is improving?

1. Compact summary for the visible period, initially the current week.
2. Existing activity filters and a clear period selector.
3. Chronological activity list with accurate local dates, distance units, and pace units.
4. Relevant earned highlights attached to their source activities.

For All, show completed sessions and training time across sports, with running distance explicitly labeled. For a single sport, show metrics meaningful to that sport. Never put running pace on strength or mobility.

Replace unexplained improvement percentages with a labeled comparison when an actual comparable baseline is available. Remove the comparison when there is insufficient or incompatible data. A personal best needs a source activity and appropriate distance evidence; do not award records from arbitrary distance buckets or a projected split pace.

Keep filters, refresh, commitment, activity details, and any existing logging routes available. Improvement should enrich the activity list rather than bury it under a second dashboard.

## Plan

**Question answered:** How is the work I have completed moving me toward my goal?

1. Upcoming race or current training focus, retaining the visible race edit action.
2. Weekly timeline showing completed, today, planned, and recovery states with distinct semantics.
3. Actual completed training and remaining sessions, without counting rest days as missed workouts.
4. Today's prescription and Adjust entry.
5. Collapsed baseline and detailed guidance.

After an adjustment, show which remaining sessions changed and a brief explanation. Do not label untouched sessions as changed. The actual saved plan supplies the comparison; do not generate a decorative forecast.

Race progress uses facts such as days remaining and training phase. Do not imply a scientifically measured percentage of race readiness from mileage completion.

Keep manual race creation/editing, race units and equivalent distance, date handling, regeneration, and upcoming/past navigation working. Completing the week's work should feel acknowledged, not trigger a larger target.

## You

**Question answered:** What have I built over time, and how do I make this app fit me?

1. Athlete identity.
2. Earned training totals with their time span explicitly visible.
3. Personal bests with dates and source activity links.
4. A small collection of earned milestones and the next meaningful milestone.
5. The existing settings and account rows in clear groups.

Use complete-history aggregates for any value labeled All time. Until complete history is available, present the existing year-to-date totals labeled This year. Do not calculate a lifetime total from the currently loaded activity page.

Prefer distance, completed sessions, and durable history to an everyday streak. If training consistency is shown, planned recovery is respected and missed days do not erase prior accomplishments.

Keep training profile, goals, unit settings, devices, notification settings, account actions, and sign-out easy to find. Records and milestones must be independently understandable without a model-generated story.

## Data and interaction contract

- The app and widget must agree on athlete, time period, activity classification, quantities, and units.
- Keep stored distances canonical and convert at the presentation boundary once.
- Selected chart activities can change chart composition without changing a running goal's numerator.
- Distinguish missing data, genuine zero activity, refreshing data, partial history, and failed sync.
- Cache by athlete and period. Account changes must invalidate the prior athlete's progress and achievements.
- A new imported or recorded activity refreshes affected totals and visible history without recomputing all records on every view render.
- Repeated imports must not double count an activity or re-award an achievement.
- No personal-best label may treat a pace projection as a completed effort over the target distance.
- Every visible action leads to the represented screen or performs the stated change.

## Completion criteria

- Today gives earned progress the first meaningful viewport on a normal day.
- The four tabs feel related to the approved progress widget without repeating the same dashboard four times.
- A runner who also strength trains sees both forms of effort acknowledged, with running goals remaining accurate.
- Planned rest does not appear as a missed session.
- Real screenshots are readable on a smaller supported phone and a larger phone, including large text.
- Activity import, workout adjustment, and settings changes produce consistent app and widget values.
- Exact record and milestone claims have traceable evidence; missing evidence produces an honest label or no claim.

## Reference and limits

This specification uses the approved widget, the discussed app screens and routes, and the source map captured during planning. The personal-best and milestone services were inspected locally. No production database or deployed function audit was performed while writing the plan.
