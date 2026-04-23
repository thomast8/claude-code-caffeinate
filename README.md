# claude-code-caffeinate

Keep your Mac awake only while Claude Code is actively processing, with a `☕/💤` indicator appended to your Claude Code statusLine.

## What it does

- Holds macOS `caffeinate -i` for the exact window Claude is producing output. Your Mac sleeps normally the rest of the time.
- Tracks every open Claude Code session (project, branch, turn count, total input/output tokens, last activity) for as long as the session is alive.
- Appends a three-state indicator to your Claude Code statusLine:
  - `☕ N` — N sessions actively processing, caffeinate held.
  - `💤 N` — N sessions open but all idle.
  - *(nothing)* — no sessions open.

The active window is defined by two Claude Code hook events: `UserPromptSubmit` (start) and `Stop` (end). Reference-counted across concurrent sessions — caffeinate is held as long as *any* session is mid-turn, released only when the last one finishes.

## Requirements

- macOS (tested on Sonoma and later).
- [Claude Code](https://claude.com/claude-code) — for the hooks.
- `jq` — used by the hooks and the statusLine wrapper.

## Install

Add this repo as a Claude Code marketplace, then install:

```
/plugin marketplace add thomast8/claude-code-caffeinate
/plugin install claude-code-caffeinate@claude-code-caffeinate
/reload-plugins
```

Done. `caffeinate` now holds only while Claude is processing; session metadata lands in `/tmp/claude-caffeinate/`.

On the first `SessionStart` after the plugin is enabled, the hook wraps your existing `statusLine.command` so the `☕/💤` indicator is appended to whatever your statusLine already shows. Your original command is backed up and the wrap is fully reversible (see [Uninstall](#uninstall)).

Opt out of the statusLine wrap by setting `CLAUDE_CAFFEINATE_SKIP_STATUSLINE=1` in your shell rc before enabling the plugin.

## How it works

### Hooks

Four Claude Code hook events are wired:

| Event | What happens |
|---|---|
| `SessionStart` | Creates a session metadata record under `/tmp/claude-caffeinate/sessions/<id>.json` with project, branch, and timestamps. On first run, also wraps the statusLine. |
| `UserPromptSubmit` | Touches a marker file, spawns `caffeinate -i` if no other session already has one running, increments the turn count. |
| `Stop` | Removes this session's marker, kills `caffeinate` when the last marker is gone, re-tallies total input/output tokens from the transcript. |
| `SessionEnd` | Cleans up metadata for this session; crash-safety net in case `Stop` never fires. |

### State directory

Everything lives under `/tmp/claude-caffeinate/`:

```
/tmp/claude-caffeinate/
├── sessions/<session-id>.json      # one file per open Claude session
├── active/<session-id>             # presence = "this session is mid-turn"
├── caffeinate.pid                  # our single shared caffeinate process
└── lock.d/                         # mkdir-based mutex for atomic updates
```

The marker-file ref count is what lets caffeinate be held across *any number* of concurrent sessions with no double-spawn and automatic cleanup on crash.

### Caffeinate flags

Default is `caffeinate -i` (block idle system sleep only). Override via env var if you also want to block display sleep or AC-only sleep:

```bash
export CLAUDE_CAFFEINATE_FLAGS="-i -d"    # also keep display on
```

Set this in your shell rc. The hook scripts read it at invocation time.

### StatusLine wrapper

The wrapper at `statusline/wrapper.sh` runs your original statusLine command (backed up at `${CLAUDE_PLUGIN_DATA}/original-statusline-command`) and appends the `☕/💤` indicator on the same line. If you had no statusLine before the plugin installed, the wrapper emits a minimal `"Claude Code ☕ N"` instead.

The wrap also sets `statusLine.refreshInterval` to 5 seconds if it was unset, so idle sessions don't freeze the indicator.

If you'd rather inline the indicator into a statusLine you're already maintaining (without a wrapper), the snippet is:

```bash
# Paste near the end of your statusline script, before the final echo.
# Assumes you have DIM, YELLOW, RESET ANSI vars defined — tweak to match.
CCAFF_STATE="/tmp/claude-caffeinate"
caff_ind=""
if [ -d "$CCAFF_STATE" ]; then
  ccaff_active=$(find "$CCAFF_STATE/active" -type f 2>/dev/null | wc -l | tr -d ' ')
  ccaff_sessions=$(find "$CCAFF_STATE/sessions" -name '*.json' -type f 2>/dev/null | wc -l | tr -d ' ')
  ccaff_on=0
  if [ -f "$CCAFF_STATE/caffeinate.pid" ] && kill -0 "$(cat "$CCAFF_STATE/caffeinate.pid" 2>/dev/null)" 2>/dev/null; then
    ccaff_on=1
  fi
  if [ "$ccaff_on" -eq 1 ]; then
    caff_ind=" ${DIM}|${RESET} ${YELLOW}☕ ${ccaff_active}${RESET}"
  elif [ "$ccaff_sessions" -gt 0 ] 2>/dev/null; then
    caff_ind=" ${DIM}|${RESET} ${DIM}💤 ${ccaff_sessions}${RESET}"
  fi
fi
# Append $caff_ind to your final output line
```

Then disable the wrapper install via `CLAUDE_CAFFEINATE_SKIP_STATUSLINE=1`.

## Uninstall

Disable the plugin:

```
/plugin disable claude-code-caffeinate
```

Restore your original statusLine command (if the wrapper was installed):

```bash
unwrap-statusline
```

That script reads the backup at `${CLAUDE_PLUGIN_DATA}/original-statusline-command` and patches `~/.claude/settings.json` back. Idempotent; a no-op if the wrap was never applied.

Remove any stray `caffeinate` process that might be orphaned:

```bash
pkill -x caffeinate
rm -rf /tmp/claude-caffeinate
```

## Previous SwiftBar dashboard

Versions ≤1.5.0 shipped an optional SwiftBar menu-bar dashboard. It was removed in v2.0.0 because SwiftBar 2.0.x on recent macOS caused the host app to steal terminal focus when its NSStatusItem refreshed, which is user-hostile for a background indicator. The statusLine wrapper covers the same 3-state display inline and doesn't touch AppKit.

## License

MIT. See [LICENSE](./LICENSE).
