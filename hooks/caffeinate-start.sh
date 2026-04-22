#!/bin/bash
# UserPromptSubmit: mark this session as actively processing.
# Spawns caffeinate if first active session. Updates session metadata.
set -eu

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/caffeinate-lib.sh
. "$HOOK_DIR/lib/caffeinate-lib.sh"

INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
[ -z "$SID" ] && exit 0

claude_ensure_state_dir
claude_acquire_lock || exit 0
trap 'claude_release_lock' EXIT

touch "$MARKERS/$SID"
claude_spawn_caffeinate_if_needed

SFILE="$SESSIONS/$SID.json"
NOW=$(date +%s)
PROJECT=$([ -n "$CWD" ] && basename "$CWD" || echo "unknown")
BRANCH=$(claude_git_branch "$CWD")
TITLE=$(claude_resolve_title "$PPID" "$TRANSCRIPT")

if [ -f "$SFILE" ]; then
  tmp=$(mktemp "$SESSIONS/.update.XXXXXX")
  jq --arg now "$NOW" --arg branch "$BRANCH" --arg cwd "$CWD" --arg project "$PROJECT" \
     --arg ppid "$PPID" --arg title "$TITLE" \
     '.status = "active"
      | .last_activity_at = ($now | tonumber)
      | .turns = ((.turns // 0) + 1)
      | .branch = $branch
      | .parent_pid = ($ppid | tonumber)
      | .cwd = (if ($cwd // "") == "" then .cwd else $cwd end)
      | .project = (if ($project // "") == "" then .project else $project end)
      | .title = (if ($title // "") == "" then (.title // "") else $title end)' \
     "$SFILE" > "$tmp" && mv "$tmp" "$SFILE"
else
  jq -n --arg sid "$SID" --arg cwd "$CWD" --arg project "$PROJECT" \
        --arg branch "$BRANCH" --arg now "$NOW" --arg ppid "$PPID" --arg title "$TITLE" \
    '{
      session_id: $sid,
      cwd: $cwd,
      project: $project,
      branch: $branch,
      title: $title,
      parent_pid: ($ppid | tonumber),
      started_at: ($now | tonumber),
      last_activity_at: ($now | tonumber),
      turns: 1,
      total_input_tokens: 0,
      total_output_tokens: 0,
      status: "active"
    }' > "$SFILE"
fi

exit 0
