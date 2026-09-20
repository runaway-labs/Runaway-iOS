# Becoming Engine Trust Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make readiness whole-body aware and introduce a private, deterministic Becoming Engine that makes the impact of today's training choice visible.

**Architecture:** Existing recommendation and remaining-week regeneration remain the prescription authority. A pure `BecomingEngine` converts verified readiness, planned demand, profile alternatives, and remaining-week scope into display-safe counterfactual paths. SwiftUI renders those paths inside the existing Next Up decision surface; Foundation Models may later explain verified output but never calculate training prescriptions.

**Tech Stack:** Swift 6, SwiftUI, Observation, Swift Testing, HealthKit-backed readiness, existing `TodayRecommendationPolicy` and `TrainingPlanService`.

**Spec:** Product direction approved in the 2026-09-04 code audit conversation.

## Global Constraints

- Minimum platform remains iOS 27.
- Intelligence must use Apple on-device models only.
- No external LLM API may participate in a user-facing app flow.
- Deterministic code owns load, readiness, safety, and plan mutation.
- Existing four-tab navigation remains unchanged.
- Distance display continues to respect the saved global or race-specific unit.

---

### Task 1: Whole-body readiness eligibility

**Files:**
- Modify: `Runaway iOS/Services/ReadinessService.swift`
- Test: `Runaway iOS/Runaway iOSTests/Runaway_iOSTests.swift`

**Interfaces:**
- Consumes: Imported activity type strings.
- Produces: `ReadinessService.isReadinessActivity(activityType:) -> Bool` covering running, cycling, swimming, strength, walking, hiking, mobility, rowing, elliptical, and mixed cardio.

- [x] **Step 1: Write the failing multisport eligibility test.**
- [ ] **Step 2: Run the focused test and confirm cycling or strength fails.**
- [ ] **Step 3: Implement normalized whole-body activity classification.**
- [ ] **Step 4: Run the focused test and confirm it passes.**

### Task 2: Deterministic counterfactual model

**Files:**
- Create: `Runaway iOS/Models/BecomingEngine.swift`
- Test: `Runaway iOS/Runaway iOSTests/Runaway_iOSTests.swift`

**Interfaces:**
- Consumes: `readinessScore`, `plannedTitle`, `plannedDemand`, profile alternative titles, and remaining session count.
- Produces: `BecomingSnapshot` containing three transparent `BecomingPath` values and one recommended choice.

- [x] **Step 1: Write failing tests for low, moderate, and strong readiness.**
- [ ] **Step 2: Run the focused tests and confirm `BecomingEngine` is missing.**
- [ ] **Step 3: Implement the smallest pure simulator that satisfies the scenarios.**
- [ ] **Step 4: Run the focused tests and confirm they pass.**

### Task 3: Becoming Line interaction

**Files:**
- Create: `Runaway iOS/Components/BecomingLine.swift`
- Modify: `Runaway iOS/Components/WorkoutComponents.swift`

**Interfaces:**
- Consumes: A `BecomingSnapshot` derived from the existing Today recommendation and alternatives.
- Produces: A signature trajectory control that opens the existing Adjust Today sheet and states that the remaining week will be rebalanced.

- [ ] **Step 1: Add a focused rendering policy test for recommended-path labels.**
- [ ] **Step 2: Implement the trajectory visual using semantic blue, mint, and restrained amber.**
- [ ] **Step 3: Place it above the existing training-choice action in Next Up.**
- [ ] **Step 4: Preserve existing accessibility labels and add an outcome-exploration label.**

### Task 4: Local-only intelligence containment

**Files:**
- Modify: `Runaway iOS/Services/QuickWinsService.swift`
- Modify: `Runaway iOS/Services/TwinEngineService.swift`

**Interfaces:**
- Consumes: Legacy callers retained for source compatibility.
- Produces: Explicit local-only unavailability instead of invoking retired cloud intelligence functions.

- [ ] **Step 1: Add source-level containment coverage for retired function slugs.**
- [ ] **Step 2: Remove production invocations of `comprehensive-analysis` and `twin-engine`.**
- [ ] **Step 3: Return actionable local-only migration errors to any dormant caller.**
- [ ] **Step 4: Run the containment and app test targets.**

### Task 5: Build and smoke verification

**Files:**
- No production file changes expected.

**Interfaces:**
- Consumes: Completed Tasks 1-4.
- Produces: A simulator-build and focused-test result suitable for manual Today-flow smoke testing.

- [ ] **Step 1: Run the focused Swift tests.**
- [ ] **Step 2: Build the iOS simulator target.**
- [ ] **Step 3: Launch and confirm Today shows the Becoming Line.**
- [ ] **Step 4: Open Adjust Today from the trajectory and confirm the existing week-change receipt and Undo remain functional.**
