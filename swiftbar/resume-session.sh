#!/bin/bash
# Opens a Claude Code session by its session ID.
# Called by the SwiftBar menu item "Resume session".
#
# Usage: resume-session.sh <session_id> [cwd]
set -eu

SID="${1:-}"
CWD="${2:-$HOME}"

if [ -z "$SID" ]; then
  echo "Usage: resume-session.sh <session_id> [cwd]" >&2
  exit 1
fi

cd "$CWD" 2>/dev/null || true

# Prefer the claude CLI on the user's normal PATH; SwiftBar inherits a stripped
# environment so we probe common install locations before falling back.
CLAUDE_BIN=""
for candidate in \
    "$(command -v claude 2>/dev/null)" \
    "$HOME/.claude/local/claude" \
    "/usr/local/bin/claude" \
    "/opt/homebrew/bin/claude"; do
  if [ -x "$candidate" ]; then
    CLAUDE_BIN="$candidate"
    break
  fi
done

if [ -z "$CLAUDE_BIN" ]; then
  echo "claude CLI not found. Make sure Claude Code is installed and on PATH." >&2
  exit 1
fi

exec "$CLAUDE_BIN" --resume "$SID"
