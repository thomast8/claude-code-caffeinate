# claude-code-caffeinate

Keep your Mac awake only while Claude Code is actively processing, with a SwiftBar menu bar dashboard showing per-session activity and token usage.

## What it does

- Holds macOS `caffeinate -i` for the exact window Claude is producing output. Your Mac sleeps normally the rest of the time.
- Tracks every open Claude Code session (project, branch, turn count, total input/output tokens, last activity) for as long as the session is alive.
- Optional **SwiftBar** menu bar dashboard — a ☕ icon showing "busy now", a 💤 moon when sessions are open but idle, a faint ○ when nothing's happening. Click for a live breakdown per session.

The active window is defined by two Claude Code hook events: `UserPromptSubmit` (start) and `Stop` (end). Reference-counted across concurrent sessions — caffeinate is held as long as *any* session is mid-turn, released only when the last one finishes.

## Requirements

- macOS (tested on Sonoma and later).
- [Claude Code](https://claude.com/claude-code) — for the hooks.
- [Homebrew](https://brew.sh) — for the SwiftBar side (optional).
- `jq` — auto-installed by the SwiftBar installer if missing.

## Install

### 1. The Claude Code plugin (hooks only)

Add this repo as a Claude Code marketplace, then install:

```
/plugin marketplace add thomast8/claude-code-caffeinate
/plugin install claude-code-caffeinate@claude-code-caffeinate
/reload-plugins
```

That's it for the hook side. `caffeinate` now holds only while Claude is processing; session metadata lands in `/tmp/claude-caffeinate/`.

### 2. The SwiftBar dashboard (auto-installed on first session)

When you start your first Claude Code session after enabling the plugin, the SessionStart hook **automatically fires `install-swiftbar` in the background** — installs SwiftBar via brew, creates the symlink, sets SwiftBar's plugin-folder preference, launches the app. You'll see a systemMessage in Claude Code confirming this and pointing at the install log.

**One unavoidable manual step:** when SwiftBar launches for the first time, open its Preferences → **General** → **Plugin Folder** and re-pick `~/Library/Application Support/SwiftBar/Plugins/`. In the file picker, **Cmd+Shift+G** lets you type the path directly. This is a macOS sandboxing requirement (security-scoped bookmark) that can't be scripted away.

**Opt out** of auto-install by setting `CLAUDE_CAFFEINATE_SKIP_AUTOINSTALL=1` in your shell rc before enabling the plugin. To re-trigger it later, delete the marker at `${CLAUDE_PLUGIN_DATA}/setup-attempted`.

If you want to run the installer manually (to re-check state after upgrades, etc.), it's on your PATH while the plugin is enabled:

```bash
install-swiftbar          # idempotent, safe to re-run
install-swiftbar --status # diagnostic only
```

The script:

1. Installs SwiftBar via `brew install --cask swiftbar` (user-scope `~/Applications/` to avoid sudo).
2. Creates `~/Library/Application Support/SwiftBar/Plugins/` if missing.
3. Symlinks `claude-activity.5s.sh` from this plugin into that folder.
4. Sets SwiftBar's `PluginDirectory` preference.
5. Launches SwiftBar.

Useful flags:

```bash
install-swiftbar --status       # diagnose current state
install-swiftbar --uninstall    # remove the SwiftBar pref + symlink
install-swiftbar --uninstall --remove-app   # also uninstall the SwiftBar cask
```

## How it works

### Hooks

Four Claude Code hook events are wired:

| Event | What happens |
|---|---|
| `SessionStart` | Creates a session metadata record under `/tmp/claude-caffeinate/sessions/<id>.json` with project, branch, and timestamps. |
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

## Optional: statusline indicator

If you want a mini-dashboard inside your Claude Code TUI itself (in addition to or instead of the menu bar), add this snippet to your user-level statusline command (`~/.claude/statusline-command.sh` or equivalent). It mirrors the menu bar's 3-state display:

- `☕ N` — N sessions actively processing, caffeinate held
- `💤 N` — N sessions open but all idle
- `(empty)` — no sessions open

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

The plugin itself does not ship a statusline — plugin-level statuslines override the user's full statusline, which is too intrusive for a small indicator. The snippet above is a drop-in add for whatever custom statusline you already use.

## Uninstall

Disable the plugin via `/plugin` menu, or remove it entirely:

```
/plugin disable claude-code-caffeinate
```

For the SwiftBar side:

```bash
install-swiftbar --uninstall              # just the plugin folder + symlink
install-swiftbar --uninstall --remove-app # also uninstall SwiftBar.app
```

Remove any stray `caffeinate` process that might be orphaned:

```bash
pkill -x caffeinate
rm -rf /tmp/claude-caffeinate
```

## License

MIT. See [LICENSE](./LICENSE).
