#!/bin/bash
# <bitbar.title>Claude Code Activity</bitbar.title>
# <bitbar.version>v1.6</bitbar.version>
# <bitbar.author>Thomas Tiotto</bitbar.author>
# <bitbar.desc>Live Claude Code session tracker with caffeinate status</bitbar.desc>
# <bitbar.dependencies>bash, jq, caffeinate</bitbar.dependencies>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>

set -eu

STATE="${CLAUDE_STATE_DIR:-/tmp/claude-caffeinate}"
SESSIONS_DIR="$STATE/sessions"
MARKERS_DIR="$STATE/active"
PIDFILE="$STATE/caffeinate.pid"

# Resolve real location of this script so we can reference sibling files
# (e.g. resume-session.sh) even when SwiftBar accesses us via a symlink.
_SELF="${BASH_SOURCE[0]}"
while [ -L "$_SELF" ]; do
  _lnk=$(readlink "$_SELF")
  case "$_lnk" in
    /*) _SELF="$_lnk" ;;
    *)  _SELF="$(cd "$(dirname "$_SELF")" && pwd)/$_lnk" ;;
  esac
done
PLUGIN_DIR="$(cd "$(dirname "$_SELF")" && pwd)"

human_tokens() {
  local n="${1:-0}"
  [ "$n" -ge 1000000 ] 2>/dev/null && { awk -v n="$n" 'BEGIN{printf "%.1fM", n/1000000}'; return; }
  [ "$n" -ge 1000 ]    2>/dev/null && { awk -v n="$n" 'BEGIN{printf "%.1fk", n/1000}';    return; }
  echo "$n"
}

human_age() {
  local secs="${1:-0}"
  [ "$secs" -lt 60 ]   2>/dev/null && { echo "${secs}s ago"; return; }
  [ "$secs" -lt 3600 ] 2>/dev/null && { echo "$((secs / 60))m ago"; return; }
  [ "$secs" -lt 86400 ] 2>/dev/null && { echo "$((secs / 3600))h ago"; return; }
  echo "$((secs / 86400))d ago"
}

# A process is "truly alive" if kill -0 succeeds AND it's not in Z (zombie)
# or E (being-reaped) state. macOS leaves defunct Claude Code processes in
# state ?Es — comm renamed to "(version)", no controlling terminal — after
# terminal windows get force-closed. kill -0 still returns success for these,
# so we need the ps stat check to catch them.
claude_process_alive() {
  local pid="$1"
  [ -n "$pid" ] && [ "$pid" != "null" ] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  local stat
  stat=$(ps -p "$pid" -o stat= 2>/dev/null | tr -d ' ')
  case "$stat" in
    *Z*|*E*) return 1 ;;
    "")      return 1 ;;
  esac
  return 0
}

# Purge metadata for dead sessions. A session is dead if either:
#   (a) its recorded parent_pid is no longer alive (gone, zombie, or being reaped)
#   (b) it has no parent_pid and hasn't had activity for STALE_THRESHOLD seconds
# Case (a) is the reliable modern path; case (b) handles legacy records from
# older plugin versions AND crashed sessions whose SessionEnd never fired.
# Also kills any orphan caffeinate process if no active markers remain.
STALE_THRESHOLD=1800   # 30 minutes of inactivity
purge_dead_sessions() {
  local f sid ppid last now
  [ -d "$SESSIONS_DIR" ] || return 0
  now=$(date +%s)
  for f in "$SESSIONS_DIR"/*.json; do
    [ -f "$f" ] || continue
    ppid=$(jq -r '.parent_pid // empty' "$f" 2>/dev/null)
    last=$(jq -r '.last_activity_at // 0' "$f" 2>/dev/null)
    local should_purge=0
    if [ -n "$ppid" ] && [ "$ppid" != "null" ] && ! claude_process_alive "$ppid"; then
      should_purge=1
    elif { [ -z "$ppid" ] || [ "$ppid" = "null" ]; } && [ "$((now - last))" -gt "$STALE_THRESHOLD" ]; then
      should_purge=1
    fi
    if [ "$should_purge" -eq 1 ]; then
      sid=$(jq -r '.session_id // empty' "$f" 2>/dev/null)
      rm -f "$f"
      [ -n "$sid" ] && rm -f "$MARKERS_DIR/$sid"
    fi
  done
  if [ -d "$MARKERS_DIR" ] && [ -z "$(ls -A "$MARKERS_DIR" 2>/dev/null)" ] && [ -f "$PIDFILE" ]; then
    local pid; pid=$(cat "$PIDFILE" 2>/dev/null)
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    rm -f "$PIDFILE"
  fi
}

# Resolve a preferred macOS editor app. Priority: CLAUDE_CAFFEINATE_EDITOR env
# override, then common editors detected by .app bundle presence. Empty if none.
resolve_editor_app() {
  if [ -n "${CLAUDE_CAFFEINATE_EDITOR:-}" ]; then
    echo "${CLAUDE_CAFFEINATE_EDITOR}"
    return
  fi
  local app
  for app in "Cursor" "Visual Studio Code" "Zed" "Sublime Text" "Nova"; do
    if [ -d "/Applications/$app.app" ] || [ -d "$HOME/Applications/$app.app" ]; then
      echo "$app"
      return
    fi
  done
}

purge_dead_sessions
EDITOR_APP=$(resolve_editor_app)

total_sessions=0
active_sessions=0
[ -d "$SESSIONS_DIR" ] && total_sessions=$(find "$SESSIONS_DIR" -name '*.json' -type f 2>/dev/null | wc -l | tr -d ' ')
[ -d "$MARKERS_DIR" ]  && active_sessions=$(find "$MARKERS_DIR"  -type f 2>/dev/null | wc -l | tr -d ' ')

caff_on="no"
caff_pid=""
if [ -f "$PIDFILE" ]; then
  caff_pid=$(cat "$PIDFILE" 2>/dev/null || true)
  if [ -n "$caff_pid" ] && kill -0 "$caff_pid" 2>/dev/null; then
    caff_on="yes"
  fi
fi

# Menu-bar icon — three distinct silhouettes so state reads in peripheral vision:
#   active caffeinate → cup (working)
#   sessions open, none active → moon+zzz (sleeping idle)
#   no sessions at all → cup outline, gray (nothing happening)
if [ "$caff_on" = "yes" ]; then
  echo "${active_sessions} | sfimage=cup.and.saucer.fill"
elif [ "$total_sessions" -gt 0 ] 2>/dev/null; then
  echo "${total_sessions} | sfimage=moon.zzz.fill color=#888888"
else
  echo " | sfimage=cup.and.saucer color=#888888"
fi

echo "---"
echo "Claude Code Activity | size=13"
echo "Active turns: ${active_sessions} | size=12"
echo "Open sessions: ${total_sessions} | size=12"
if [ "$caff_on" = "yes" ]; then
  echo "Caffeinate: ON (pid ${caff_pid}) | size=12 color=orange"
else
  echo "Caffeinate: off | size=12 color=gray"
fi
echo "---"

if [ "$total_sessions" -eq 0 ] 2>/dev/null; then
  echo "No Claude Code sessions open | color=gray size=12"
else
  now=$(date +%s)
  # Sort: active first (most recent activity), then idle (most recent activity).
  for sfile in $(find "$SESSIONS_DIR" -name '*.json' -type f 2>/dev/null \
                  | xargs -I{} stat -f "%m %N" "{}" 2>/dev/null \
                  | sort -rn | awk '{print $2}'); do
    [ -f "$sfile" ] || continue

    sid=$(jq -r '.session_id        // "?"'       "$sfile" 2>/dev/null)
    project=$(jq -r '.project       // "unknown"' "$sfile" 2>/dev/null)
    title=$(jq -r '.title           // ""'        "$sfile" 2>/dev/null)
    branch=$(jq -r '.branch         // ""'        "$sfile" 2>/dev/null)
    status=$(jq -r '.status         // "idle"'    "$sfile" 2>/dev/null)
    turns=$(jq -r '.turns           // 0'         "$sfile" 2>/dev/null)
    in_tok=$(jq -r '.total_input_tokens  // 0'    "$sfile" 2>/dev/null)
    out_tok=$(jq -r '.total_output_tokens // 0'   "$sfile" 2>/dev/null)
    last=$(jq -r '.last_activity_at // 0'         "$sfile" 2>/dev/null)
    cwd=$(jq -r '.cwd               // ""'        "$sfile" 2>/dev/null)

    in_fmt=$(human_tokens "$in_tok")
    out_fmt=$(human_tokens "$out_tok")
    age_fmt=$(human_age "$((now - last))")
    branch_fmt=""
    [ -n "$branch" ] && [ "$branch" != "null" ] && branch_fmt=" @ ${branch}"

    # Live-read title from Claude Code's per-PID sessions file if available.
    # This avoids the two-turn lag that happens when an async renamer hook
    # (e.g. one that calls an LLM) completes AFTER the Stop that would
    # otherwise stamp the title into our metadata cache.
    ppid=$(jq -r '.parent_pid // empty' "$sfile" 2>/dev/null)
    if [ -n "$ppid" ] && [ "$ppid" != "null" ] && [ -f "$HOME/.claude/sessions/$ppid.json" ]; then
      live_title=$(jq -r '.name // empty' "$HOME/.claude/sessions/$ppid.json" 2>/dev/null)
      [ -n "$live_title" ] && title="$live_title"
    fi

    # Primary label: session title when set (via /rename or any auto-renamer),
    # otherwise the project directory name.
    if [ -n "$title" ] && [ "$title" != "null" ]; then
      label="$title"
    else
      label="$project"
    fi

    if [ "$status" = "active" ]; then
      dot="● "; color="color=orange"
    else
      dot="○ "; color="color=#888888"
    fi

    # First line: title|project + branch + tokens + age
    echo "${dot}${label}${branch_fmt}  •  ${turns} turns, ${in_fmt} in / ${out_fmt} out  •  ${age_fmt} | ${color} size=12"
    # Submenu: actionable items
    if [ -n "$sid" ] && [ "$sid" != "null" ] && [ "$sid" != "?" ]; then
      RESUME_HELPER="$PLUGIN_DIR/resume-session.sh"
      if [ -x "$RESUME_HELPER" ]; then
        # Opens Terminal.app, cds to project, and runs claude --resume <id>
        echo "--Resume session | bash=$RESUME_HELPER param1=$sid param2=$cwd terminal=true size=11"
      fi
    fi
    if [ -n "$cwd" ] && [ "$cwd" != "null" ]; then
      if [ -n "$EDITOR_APP" ]; then
        echo "--Open in $EDITOR_APP | bash=/usr/bin/open param1=-a param2=$EDITOR_APP param3=$cwd terminal=false size=11"
      else
        echo "--Open in Finder | bash=/usr/bin/open param1=$cwd terminal=false size=11"
      fi
    fi
  done
fi

echo "---"
echo "Open state dir | bash=/usr/bin/open param1=${STATE} terminal=false size=11"
echo "Refresh | refresh=true size=11"
