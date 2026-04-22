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

### 2. The SwiftBar dashboard (optional)

If you want the menu bar icon and per-session breakdown, install SwiftBar and wire up the plugin. The plugin ships with an installer script that lands in your `$PATH` automatically when the plugin is enabled:

```bash
install-swiftbar
```

The script is idempotent — re-run any time to re-check state or apply updates. It:

1. Installs SwiftBar via `brew install --cask swiftbar` (user-scope `~/Applications/` to avoid sudo).
2. Creates `~/Library/Application Support/SwiftBar/Plugins/` if missing.
3. Symlinks `claude-activity.5s.sh` from this plugin into that folder.
4. Sets SwiftBar's `PluginDirectory` preference.
5. Launches SwiftBar.

**One manual step:** on first install, SwiftBar needs a user-granted security-scoped bookmark for its plugin folder. Open SwiftBar Preferences → **General** → **Plugin Folder** → re-pick `~/Library/Application Support/SwiftBar/Plugins/`. In the file picker, **Cmd+Shift+G** lets you type the path directly. This is a macOS sandboxing requirement that can't be scripted away.

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

If you want a ☕ indicator inside your Claude Code TUI itself (in addition to or instead of the menu bar), add this snippet to your user-level statusline command (`~/.claude/statusline-command.sh` or equivalent):

```bash
# Append to your statusline output when our hook-managed caffeinate is live
if [ -f "/tmp/claude-caffeinate/caffeinate.pid" ] && \
   kill -0 "$(cat /tmp/claude-caffeinate/caffeinate.pid 2>/dev/null)" 2>/dev/null; then
  printf ' | ☕'
fi
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
