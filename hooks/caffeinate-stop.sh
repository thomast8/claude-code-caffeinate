#!/bin/bash
# Stop: release this session's active marker, kill caffeinate if last,
# and refresh session token totals from the transcript.
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

[ -n "$SID" ] && rm -f "$MARKERS/$SID"
claude_kill_caffeinate_if_idle

SFILE="$SESSIONS/$SID.json"
if [ -n "$SID" ] && [ -f "$SFILE" ]; then
  NOW=$(date +%s)
  read -r IN_TOK OUT_TOK <<<"$(claude_tally_transcript_tokens "$TRANSCRIPT")"
  IN_TOK="${IN_TOK:-0}"
  OUT_TOK="${OUT_TOK:-0}"
  # Pick up any title that was set mid-turn (e.g. /rename while Claude was working).
  # parent_pid is stored in metadata from start; read it back for title lookup.
  PPID_REC=$(jq -r '.parent_pid // empty' "$SFILE" 2>/dev/null || true)
  TITLE=$(claude_resolve_title "$PPID_REC" "$TRANSCRIPT")
  tmp=$(mktemp "$SESSIONS/.update.XXXXXX")
  jq --arg now "$NOW" --argjson in "$IN_TOK" --argjson out "$OUT_TOK" --arg title "$TITLE" \
     '.status = "idle"
      | .last_activity_at = ($now | tonumber)
      | .total_input_tokens = $in
      | .total_output_tokens = $out
      | .title = (if ($title // "") == "" then (.title // "") else $title end)' \
     "$SFILE" > "$tmp" && mv "$tmp" "$SFILE"
fi

exit 0
