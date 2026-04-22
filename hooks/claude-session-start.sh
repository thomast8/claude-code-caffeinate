#!/bin/bash
# SessionStart: create session metadata file if absent so the dashboard
# can display idle (just-opened) sessions. Does NOT touch caffeinate.
set -eu

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/caffeinate-lib.sh
. "$HOOK_DIR/lib/caffeinate-lib.sh"

INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // "unknown"' 2>/dev/null || true)
[ -z "$SID" ] && exit 0

claude_ensure_state_dir

SFILE="$SESSIONS/$SID.json"
[ -f "$SFILE" ] && exit 0    # never clobber an existing record on resume

NOW=$(date +%s)
PROJECT=$([ -n "$CWD" ] && basename "$CWD" || echo "unknown")
BRANCH=$(claude_git_branch "$CWD")

jq -n --arg sid "$SID" --arg cwd "$CWD" --arg project "$PROJECT" \
      --arg branch "$BRANCH" --arg now "$NOW" --arg source "$SOURCE" \
      --arg ppid "$PPID" \
  '{
    session_id: $sid,
    cwd: $cwd,
    project: $project,
    branch: $branch,
    source: $source,
    parent_pid: ($ppid | tonumber),
    started_at: ($now | tonumber),
    last_activity_at: ($now | tonumber),
    turns: 0,
    total_input_tokens: 0,
    total_output_tokens: 0,
    status: "idle"
  }' > "$SFILE"

exit 0
