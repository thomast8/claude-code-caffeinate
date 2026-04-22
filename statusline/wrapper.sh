#!/bin/bash
# Claude Code statusLine wrapper.
#
# On first plugin install, claude-session-start.sh backs up the user's
# original statusLine.command (stashed at ${CLAUDE_PLUGIN_DATA}/original-
# statusline-command) and points settings.json at this wrapper. The
# wrapper runs the original command, then appends a ☕/💤 indicator on
# the same line.
#
# Fully reversible via `install-swiftbar --uninstall` which restores the
# user's original statusLine config.
set -u

INPUT=$(cat)

DATA_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.local/state/claude-code-caffeinate}"
ORIG_CMD_FILE="$DATA_DIR/original-statusline-command"

# Run the user's original statusline (if we backed one up) and capture output.
ORIG_OUT=""
if [ -f "$ORIG_CMD_FILE" ]; then
  ORIG_CMD=$(cat "$ORIG_CMD_FILE")
  if [ -n "$ORIG_CMD" ]; then
    ORIG_OUT=$(printf '%s' "$INPUT" | bash -c "$ORIG_CMD" 2>/dev/null || true)
  fi
fi

# Build the ☕/💤 indicator — mirrors the menu bar's 3-state display.
DIM='\033[2m'
YELLOW='\033[33m'
RESET='\033[0m'
STATE="${CLAUDE_STATE_DIR:-/tmp/claude-caffeinate}"
caff_ind=""
if [ -d "$STATE" ]; then
  active=$(find "$STATE/active" -type f 2>/dev/null | wc -l | tr -d ' ')
  sessions=$(find "$STATE/sessions" -name '*.json' -type f 2>/dev/null | wc -l | tr -d ' ')
  caff_on=0
  if [ -f "$STATE/caffeinate.pid" ] && kill -0 "$(cat "$STATE/caffeinate.pid" 2>/dev/null)" 2>/dev/null; then
    caff_on=1
  fi
  if [ "$caff_on" -eq 1 ]; then
    caff_ind=" ${DIM}|${RESET} ${YELLOW}☕ ${active}${RESET}"
  elif [ "$sessions" -gt 0 ] 2>/dev/null; then
    caff_ind=" ${DIM}|${RESET} ${DIM}💤 ${sessions}${RESET}"
  fi
fi

# Output: original statusline output (ANSI-processed already) + our indicator
# on the same line. Use echo -e so our backslash escapes get interpreted.
if [ -n "$ORIG_OUT" ]; then
  echo -e "${ORIG_OUT}${caff_ind}"
else
  # No backup available (fresh install without prior statusLine, or the
  # plugin was installed on a system that never had one). Output just the
  # indicator so the user at least sees it.
  echo -e "Claude Code${caff_ind}"
fi
