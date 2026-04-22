#!/bin/bash
# SessionStart: create session metadata file if absent so the dashboard
# can display idle (just-opened) sessions. Does NOT touch caffeinate.
#
# Also: on the very first SessionStart after the plugin is enabled, fire
# bin/install-swiftbar in the background to bootstrap the optional menu-bar
# dashboard. A persistent marker in ${CLAUDE_PLUGIN_DATA} ensures this
# happens exactly once. User can opt out with CLAUDE_CAFFEINATE_SKIP_AUTOINSTALL=1.
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

# --- Auto-install SwiftBar dashboard on first run ---
# Only active when running as a Claude Code plugin (CLAUDE_PLUGIN_ROOT set) —
# a user-wired copy of this hook in ~/.claude/hooks/ will silently skip.
AUTOINSTALL_MSG=""
if [ "${CLAUDE_CAFFEINATE_SKIP_AUTOINSTALL:-0}" != "1" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  DATA_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.local/state/claude-code-caffeinate}"
  MARKER="$DATA_DIR/setup-attempted"
  INSTALLER="$CLAUDE_PLUGIN_ROOT/bin/install-swiftbar"
  if [ ! -f "$MARKER" ] && [ -x "$INSTALLER" ]; then
    mkdir -p "$DATA_DIR"
    touch "$MARKER"
    LOG="$DATA_DIR/install-swiftbar.log"
    nohup "$INSTALLER" >"$LOG" 2>&1 &
    disown 2>/dev/null || true
    AUTOINSTALL_MSG="Setting up the SwiftBar menu-bar dashboard in the background. One manual step needed: once SwiftBar launches, open its Preferences → General → Plugin Folder and re-pick ~/Library/Application Support/SwiftBar/Plugins/ (Cmd+Shift+G in the picker lets you type the path). That grants the macOS security bookmark SwiftBar needs for its refresh timer. Install log: $LOG. Opt out next time with CLAUDE_CAFFEINATE_SKIP_AUTOINSTALL=1, or delete $MARKER to re-trigger."
  fi
fi

# --- Session metadata (skip if already exists, e.g. on resume) ---
SFILE="$SESSIONS/$SID.json"
if [ ! -f "$SFILE" ]; then
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
fi

# Emit systemMessage if we triggered auto-install so the user knows what's happening
if [ -n "$AUTOINSTALL_MSG" ]; then
  jq -n --arg msg "$AUTOINSTALL_MSG" '{systemMessage: $msg}'
fi

exit 0
