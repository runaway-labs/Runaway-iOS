#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

forbidden='RunRecordingView|RunRecordingLayoutPolicy|RunRecorder|HealthKitWorkoutService|StartRunFAB|RunawayWidgetLiveActivity|startWorkout\('
if rg -n "$forbidden" 'Runaway iOS' RunawayWidget Shared; then
  echo "Runaway-owned activity recording is still present" >&2
  exit 1
fi
