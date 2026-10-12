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
| Third row, fourth from left | Ctrl+F20 | Fork the current Claude session |
| Wheel clockwise | Ctrl+F18 | Increase Claude effort one level |
| Wheel counterclockwise | Ctrl+F19 | Decrease Claude effort one level |

For this Hammerspoon setup, each wheel direction is a three-step macro: press
Left Ctrl, click F18 (up) or F19 (down), release Left Ctrl. It replaces the
standalone configurator's keyboard-only effort macro on this local profile.
The handler opens the unique visible Effort picker, verifies slider focus,
and sends one arrow. It leaves the picker visible and never sends Escape, so a
failed opening or rapid rotation cannot trigger Claude's double-Escape Rewind.
It only runs with Claude in front; navigation, Archive, Fork and New Session
cancel pending effort changes. Multiple panes, dialogs and unconfirmed changes
are refused. Keep the original Input profile as a backup when importing.

For Fork, assign an Input shortcut/macro that presses Left Ctrl, clicks F20,
then releases Left Ctrl. macOS does not expose F21 through Hammerspoon.

For this Mac's manual layer setup, remove all AppSense application links in Input
and use only Micro's physical layer button to switch between Codex and Claude.

Session selection and session-menu actions request Claude's Electron accessibility
tree once per process, so a Claude restart does not leave visible sessions
unreadable. Session selection allows the tree time to appear on first use.
The accessibility flag can still read false after a successful request; repeated
writes would reset Electron's initialization delay. Hammerspoon still needs its
existing macOS Accessibility permission.

New Session opens Claude's native empty session composer, retaining the app's
project/location selection. It does not send a prompt or start an agent run.
Claude creates the session when the user submits its first prompt. New Session
requires the native menu to be available and enabled; the shortcut is never sent
to another application. A newer session-selection key cancels a pending new-session
action. New-session and session-selection presses are ignored while Archive or
Fork is pending. Archive and Fork cancel pending navigation/new-session actions
and cannot run simultaneously.

Archive verifies the current session's menu and keyboard focus. If Claude asks
for confirmation because archiving would discard changes, the user handles it.
Fork uses the exact `Fork` entry in the current session's menu. Both actions
require Claude in the foreground and a single session pane. Fork never selects
`Fork from here` on a message or submits a prompt. A blank new-session composer
has nothing to fork. `claudeMicro.fork.fork(true)` verifies the menu and dismisses
it without creating a fork.

Offline regression checks (Lua 5.4 or newer):

```sh
lua tests/claude-micro-sidebar.test.lua
lua tests/claude-micro-archive.test.lua
lua tests/claude-micro-new-session.test.lua
lua tests/claude-micro-fork.test.lua
lua tests/claude-micro-accessibility.test.lua
lua tests/claude-micro-effort.test.lua
```
