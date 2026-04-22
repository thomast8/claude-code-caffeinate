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
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
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

# --- Nudge: add refreshInterval to statusLine (once per plugin install) ---
# Without refreshInterval, idle sessions never redraw the ☕ count. We check
# once whether settings.json has statusLine.command but no refreshInterval,
# and emit a targeted systemMessage with the exact fix. Separate marker from
# the SwiftBar one so each advisory fires independently.
REFRESH_MSG=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  DATA_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.local/state/claude-code-caffeinate}"
  REFRESH_MARKER="$DATA_DIR/statusline-refresh-nudged"
  SETTINGS="$HOME/.claude/settings.json"
  if [ ! -f "$REFRESH_MARKER" ] && [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
    has_cmd=$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null)
    has_ri=$(jq -r '.statusLine.refreshInterval // empty' "$SETTINGS" 2>/dev/null)
    if [ -n "$has_cmd" ] && [ -z "$has_ri" ]; then
      mkdir -p "$DATA_DIR"
      touch "$REFRESH_MARKER"
      REFRESH_MSG='Your statusLine in ~/.claude/settings.json is missing "refreshInterval": 5 — without it, idle Claude Code sessions never redraw the ☕ indicator. Add it inside your statusLine block:
  "statusLine": { "type": "command", "command": "...", "refreshInterval": 5 }
Delete '"$REFRESH_MARKER"' to re-trigger this nudge.'
    fi
  fi
fi

# --- Session metadata (skip if already exists, e.g. on resume) ---
SFILE="$SESSIONS/$SID.json"
if [ ! -f "$SFILE" ]; then
  NOW=$(date +%s)
  PROJECT=$([ -n "$CWD" ] && basename "$CWD" || echo "unknown")
  BRANCH=$(claude_git_branch "$CWD")
  TITLE=$(claude_resolve_title "$PPID" "$TRANSCRIPT")
  jq -n --arg sid "$SID" --arg cwd "$CWD" --arg project "$PROJECT" \
        --arg branch "$BRANCH" --arg now "$NOW" --arg source "$SOURCE" \
        --arg ppid "$PPID" --arg title "$TITLE" \
    '{
      session_id: $sid,
      cwd: $cwd,
      project: $project,
      branch: $branch,
      title: $title,
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

# Emit any advisory messages (SwiftBar setup and/or refreshInterval nudge)
COMBINED_MSG=""
[ -n "$AUTOINSTALL_MSG" ] && COMBINED_MSG="$AUTOINSTALL_MSG"
[ -n "$REFRESH_MSG" ] && COMBINED_MSG="${COMBINED_MSG:+${COMBINED_MSG} | }${REFRESH_MSG}"
if [ -n "$COMBINED_MSG" ]; then
  jq -n --arg msg "$COMBINED_MSG" '{systemMessage: $msg}'
fi

exit 0
