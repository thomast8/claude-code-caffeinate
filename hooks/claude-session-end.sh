#!/bin/bash
# SessionEnd: final tally from transcript, then remove session metadata
# and release any stray active marker. Crash-safe.
set -eu

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/caffeinate-lib.sh
. "$HOOK_DIR/lib/caffeinate-lib.sh"

INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)

[ -d "$CLAUDE_STATE_DIR" ] || exit 0

claude_acquire_lock || exit 0
trap 'claude_release_lock' EXIT

if [ -n "$SID" ]; then
  rm -f "$MARKERS/$SID"
  rm -f "$SESSIONS/$SID.json"
fi
claude_kill_caffeinate_if_idle

claude_nudge_swiftbar
exit 0
