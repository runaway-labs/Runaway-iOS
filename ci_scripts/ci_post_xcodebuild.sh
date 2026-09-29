#!/bin/sh
# ci_post_xcodebuild.sh
# Notifies Discord after an Xcode Cloud build.
# A missing webhook or a failed request must not change the build result.

if [ -z "${DISCORD_WEBHOOK:-}" ]; then
  echo "warning: DISCORD_WEBHOOK is not set; skipping Discord notification"
  exit 0
fi

case "${CI_XCODEBUILD_EXIT_CODE:-}" in
  0)
    status="Success ✅"
    color=6750059
    ;;
  *)
    status="Failed ❌"
    color=16724787
    ;;
esac

# Unquoted heredoc so CI_* values expand. Backticks around the commit are
# escaped so they stay literal markdown.
payload=$(cat <<EOF
{
  "embeds": [{
    "title": "Runaway iOS: $status",
    "description": "**Workflow**: ${CI_WORKFLOW:-}\n**Build**: #${CI_BUILD_NUMBER:-}\n**Commit**: \`${CI_COMMIT:-}\`",
    "color": $color,
    "footer": {
      "text": "Xcode Cloud • ${CI_PRODUCT:-}"
    },
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }]
}
EOF
)

# --fail turns HTTP errors into a non-zero curl status. Timeouts bound a
# hung endpoint. stderr is discarded so curl cannot print the webhook URL.
if ! curl --fail --silent \
  --connect-timeout 10 \
  --max-time 30 \
  -o /dev/null \
  -X POST \
  -H "Content-Type: application/json" \
  --data "$payload" \
  -- "$DISCORD_WEBHOOK"
then
  echo "warning: Discord notification failed; build result is unchanged" >&2
fi

exit 0
