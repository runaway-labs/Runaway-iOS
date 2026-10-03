#!/usr/bin/env bash
set -euo pipefail

progress_root="$(cd "$(dirname "$0")/.." && pwd)"
progress_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/runaway-progress.XXXXXX")"
trap 'rm -rf "$progress_test_dir"' EXIT
cd "$progress_root"

for progress_check in TrainingProgressPolicyChecks ProgressClassificationChecks TrainingProgressMirrorChecks TrainingProgressRemoteChecks; do
  swiftc Shared/TrainingProgressSnapshot.swift Shared/TrainingProgressPolicy.swift \
    RunawayWidget/ProgressWidgetSnapshot.swift "tests/${progress_check}.swift" \
    -o "$progress_test_dir/$progress_check"
  "$progress_test_dir/$progress_check"
done
