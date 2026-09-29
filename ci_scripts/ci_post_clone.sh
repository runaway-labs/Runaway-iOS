#!/bin/sh
# ci_post_clone.sh
# Xcode Cloud runs this script after cloning the repository.
# Writes the gitignored Runaway-iOS-Info.plist from the template.

set -eu

echo "=== Creating config files for Xcode Cloud build ==="

if [ -n "${CI_PRIMARY_REPOSITORY_PATH:-}" ]; then
  cd "$CI_PRIMARY_REPOSITORY_PATH"
else
  script_dir=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
  cd "$script_dir/.."
fi

# Archive actions produce an installable build. Apple's Xcode Cloud
# environment variable reference defines CI_XCODEBUILD_ACTION as the
# xcodebuild action about to run, including in ci_post_clone. Documented
# values: analyze, archive, build, build-for-testing, test-without-building.
#
# CI_APP_STORE_SIGNED_APP_PATH is the TestFlight/App Store export path, but
# it is set only after the archive is exported (ci_post_xcodebuild), which
# is too late to decide whether this plist may contain placeholders.
# CI_WORKFLOW is the workflow display name. Both "Release to TestFlight"
# and "Default" archive, and matching a name would miss a rename. Any
# archive can be installed or uploaded, so a missing Supabase setting fails
# every archive. Other actions keep placeholders so build/test/analyze can
# run without secrets.

archive_build=0
if [ "${CI_XCODEBUILD_ACTION:-}" = "archive" ]; then
  archive_build=1
fi

# True when the argument contains a non-whitespace character.
has_value() {
  [ -n "$(printf '%s' "$1" | tr -d '[:space:]')" ]
}

missing=""
note_missing() {
  echo "error: missing required Xcode Cloud environment variable: $1" >&2
  if [ -n "$missing" ]; then
    missing="$missing $1"
  else
    missing=$1
  fi
}

if has_value "${SUPABASE_URL:-}"; then
  supabase_url=$SUPABASE_URL
elif [ "$archive_build" -eq 1 ]; then
  note_missing SUPABASE_URL
  supabase_url=""
else
  echo "warning: SUPABASE_URL is not set; using a placeholder for this non-archive build"
  supabase_url="https://placeholder.supabase.co"
fi

if has_value "${SUPABASE_KEY:-}"; then
  supabase_key=$SUPABASE_KEY
elif [ "$archive_build" -eq 1 ]; then
  note_missing SUPABASE_KEY
  supabase_key=""
else
  echo "warning: SUPABASE_KEY is not set; using a placeholder for this non-archive build"
  supabase_key="placeholder_key"
fi

if [ -n "$missing" ]; then
  echo "error: archive build refused (CI_XCODEBUILD_ACTION=archive) because required configuration is missing: $missing" >&2
  exit 1
fi

cp Runaway-iOS-Info.plist.template Runaway-iOS-Info.plist

tmp=$(mktemp "${TMPDIR:-/tmp}/runaway-info.XXXXXX")
trap 'rm -f "$tmp"' EXIT

# '|' is not present in a Supabase project URL or anon key. Values are
# never written to the log.
sed \
  -e "s|YOUR_SUPABASE_PROJECT_URL_HERE|${supabase_url}|g" \
  -e "s|YOUR_SUPABASE_ANON_KEY_HERE|${supabase_key}|g" \
  Runaway-iOS-Info.plist > "$tmp"
mv "$tmp" Runaway-iOS-Info.plist
trap - EXIT

if grep -q -e 'YOUR_SUPABASE_PROJECT_URL_HERE' -e 'YOUR_SUPABASE_ANON_KEY_HERE' Runaway-iOS-Info.plist; then
  echo "error: Runaway-iOS-Info.plist still contains unsubstituted Supabase placeholders" >&2
  exit 1
fi

echo "Runaway-iOS-Info.plist created"
echo "=== Config files ready ==="
