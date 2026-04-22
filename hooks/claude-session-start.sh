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

# --- Auto-wrap statusLine on first run (once per plugin install) ---
# Replace user's statusLine.command with our wrapper that calls the original
# AND appends the ☕/💤 indicator. Also sets refreshInterval:5 so idle
# sessions don't freeze. Original command is backed up for clean revert.
# Opt out with CLAUDE_CAFFEINATE_SKIP_STATUSLINE=1. Fully reversible via
# `install-swiftbar --uninstall`.
STATUSLINE_MSG=""
if [ "${CLAUDE_CAFFEINATE_SKIP_STATUSLINE:-0}" != "1" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  DATA_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.local/state/claude-code-caffeinate}"
  STATUSLINE_MARKER="$DATA_DIR/statusline-wrapped"
  ORIG_CMD_BACKUP="$DATA_DIR/original-statusline-command"
  SETTINGS="$HOME/.claude/settings.json"
  WRAPPER="$CLAUDE_PLUGIN_ROOT/statusline/wrapper.sh"
  if [ ! -f "$STATUSLINE_MARKER" ] && [ -f "$SETTINGS" ] && [ -x "$WRAPPER" ] \
     && command -v jq >/dev/null 2>&1; then
    cur_cmd=$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null)
    # Only wrap if user has a command set and it isn't already our wrapper.
    if [ -n "$cur_cmd" ] && ! printf '%s' "$cur_cmd" | grep -q 'statusline/wrapper\.sh'; then
      mkdir -p "$DATA_DIR"
      # Back up original command so uninstall can restore it
      printf '%s' "$cur_cmd" > "$ORIG_CMD_BACKUP"
      # Patch settings.json: point command at wrapper, ensure refreshInterval
      tmp=$(mktemp)
      jq --arg cmd "$WRAPPER" \
         '.statusLine.command = $cmd
          | (if (.statusLine.refreshInterval // null) == null
             then .statusLine.refreshInterval = 5
             else . end)' \
         "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
      touch "$STATUSLINE_MARKER"
      STATUSLINE_MSG='Installed a statusLine wrapper that keeps your existing statusline AND appends the ☕/💤 session-activity indicator. Original command backed up at '"$ORIG_CMD_BACKUP"'. Revert with: install-swiftbar --uninstall. Opt out on new installs with CLAUDE_CAFFEINATE_SKIP_STATUSLINE=1.'
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

# Emit any advisory messages (SwiftBar setup and/or statusLine wrap notice)
COMBINED_MSG=""
[ -n "$AUTOINSTALL_MSG" ] && COMBINED_MSG="$AUTOINSTALL_MSG"
[ -n "$STATUSLINE_MSG" ] && COMBINED_MSG="${COMBINED_MSG:+${COMBINED_MSG} | }${STATUSLINE_MSG}"
if [ -n "$COMBINED_MSG" ]; then
  jq -n --arg msg "$COMBINED_MSG" '{systemMessage: $msg}'
fi

claude_nudge_swiftbar
exit 0
