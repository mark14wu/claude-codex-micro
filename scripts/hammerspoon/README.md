# Claude desktop keys

These modules use Hammerspoon on macOS with Accessibility permission. Copy all
`claude-micro*.lua` files in this directory to `~/.hammerspoon/`, then load:

```lua
claudeMicro = require("claude-micro").start()
```

The Claude hardware layer must send these keys (leave the Codex layer unchanged):

| Physical position | Key | Action |
| --- | --- | --- |
| Six session keys, in order | F13–F18 | Select the first six sidebar sessions across projects |
| Third row, first from left | F20 | Activate Claude and open File → New Session |
| Third row, second from left | F19 | Archive the current Claude session |

New Session opens Claude's native empty session composer, retaining the app's
project/location selection. It does not send a prompt or start an agent run.
Claude creates the session when the user submits its first prompt. New Session
requires the native menu to be available and enabled; the shortcut is never sent
to another application. A newer session-selection key cancels a pending new-session
action. New-session presses are ignored while an archive operation is pending.

Archive verifies the current session's menu and keyboard focus. If Claude asks
for confirmation because archiving would discard changes, the user handles it.

Offline regression checks (Lua 5.4 or newer):

```sh
lua tests/claude-micro-sidebar.test.lua
lua tests/claude-micro-archive.test.lua
lua tests/claude-micro-new-session.test.lua
```
