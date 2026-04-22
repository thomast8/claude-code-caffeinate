#!/bin/bash
# Shared helpers for Claude Code caffeinate + session-tracking hooks.
# Source from hook scripts:  . "$(dirname "$0")/lib/caffeinate-lib.sh"

CLAUDE_STATE_DIR="${CLAUDE_STATE_DIR:-/tmp/claude-caffeinate}"
MARKERS="$CLAUDE_STATE_DIR/active"
SESSIONS="$CLAUDE_STATE_DIR/sessions"
PIDFILE="$CLAUDE_STATE_DIR/caffeinate.pid"
LOCKDIR="$CLAUDE_STATE_DIR/lock.d"
CAFF_FLAGS="${CLAUDE_CAFFEINATE_FLAGS:--i}"

claude_ensure_state_dir() {
  mkdir -p "$MARKERS" "$SESSIONS"
}

claude_acquire_lock() {
  local i age
  for i in $(seq 1 50); do
    if mkdir "$LOCKDIR" 2>/dev/null; then
      return 0
    fi
    if [ -d "$LOCKDIR" ]; then
      age=$(( $(date +%s) - $(stat -f %m "$LOCKDIR" 2>/dev/null || echo 0) ))
      if [ "$age" -gt 30 ]; then
        rmdir "$LOCKDIR" 2>/dev/null || true
      fi
    fi
    sleep 0.1
  done
  return 1
}

claude_release_lock() {
  rmdir "$LOCKDIR" 2>/dev/null || true
}

claude_spawn_caffeinate_if_needed() {
  if [ ! -f "$PIDFILE" ] || ! kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
    nohup caffeinate $CAFF_FLAGS >/dev/null 2>&1 &
    echo $! > "$PIDFILE"
    disown 2>/dev/null || true
  fi
}

claude_kill_caffeinate_if_idle() {
  local count
  count=$(find "$MARKERS" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$count" -eq 0 ] && [ -f "$PIDFILE" ]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
  fi
}

# Tally total input + output tokens across all assistant messages in a
# Claude Code JSONL transcript. Prints "<in> <out>" on stdout.
# Input = input_tokens + cache_read_input_tokens + cache_creation_input_tokens.
claude_tally_transcript_tokens() {
  local transcript="$1"
  if [ -z "$transcript" ] || [ ! -f "$transcript" ]; then
    echo "0 0"
    return
  fi
  jq -sr '
    [.[] | select(.type=="assistant") | .message.usage // {}] as $u
    | [
        ($u | map((.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)) | add // 0),
        ($u | map(.output_tokens // 0) | add // 0)
      ]
    | map(tostring) | join(" ")
  ' "$transcript" 2>/dev/null || echo "0 0"
}

claude_git_branch() {
  local dir="$1"
  [ -z "$dir" ] && return
  GIT_OPTIONAL_LOCKS=0 git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || true
}
