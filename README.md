<p align="right"><a href="README.md">English</a> · <a href="README.fr.md">Français</a></p>

<h1 align="center">Codex Micro × Claude</h1>

<p align="center">
  <strong>A safe, local configurator for mapping Work Louder Codex Micro controls to Claude Desktop and Claude Code.</strong>
</p>

<p align="center">
  <img alt="Project status: work in progress" src="https://img.shields.io/badge/status-work%20in%20progress-D97757?style=flat-square">
  <img alt="Platform: macOS" src="https://img.shields.io/badge/platform-macOS-2F2927?style=flat-square">
  <img alt="Processing: local only" src="https://img.shields.io/badge/processing-local%20only-5B8C6F?style=flat-square">
  <img alt="Interface languages: EN, FR, ES, DE" src="https://img.shields.io/badge/UI-EN%20%C2%B7%20FR%20%C2%B7%20ES%20%C2%B7%20DE-6D5A7D?style=flat-square">
</p>

![Codex Micro controls mapped to Claude Desktop](docs/assets/readme/hero-configurator.png)

## Latest additions

- six Agent keys can now mirror live Claude Code session state by colour and
  open the selected session;
- navigation covers identifiable terminal sessions and, experimentally,
  sessions hosted by Claude Desktop or an IDE;
- the configurator now includes a calibrated effort wheel, eight-direction
  joystick actions, AppSense controls, and a mobile-friendly layout.

| Live Claude Code session colours | Calibrated effort wheel |
| :---: | :---: |
| ![Six Agent keys showing the Claude Code session state colour legend](docs/assets/readme/agent-key-colours.png) | ![Codex Micro wheel configured to change the Claude effort level](docs/assets/readme/effort-wheel.png) |
| See which session needs you, is working, has finished, or can be resumed. | Move one Claude effort level up or down with each wheel notch. |

## Map Claude to your fingertips

This project turns a real Work Louder Input profile into a dedicated
`Claude macOS` profile—without uploading the backup or overwriting the native
Codex layer.

**Current mapping:** `K1 ⌘N` new session · `K2 ⌘D` voice · `K3 ⌘⇧D` diff ·
`K4 Esc` stop · dial to adjust Claude effort · joystick to navigate.

| Expanded action catalog | AppSense safety review |
| :---: | :---: |
| ![Claude action catalog with next and previous session shortcuts](docs/assets/readme/mapping-wizard.png) | ![Native layer and AppSense preservation report](docs/assets/readme/safety-review.png) |
| Add session navigation, voice, diff, search, window actions, or a safe custom shortcut. | Verify the native layer, AppSense link, other layers, and SHA-256 fingerprint before downloading. |

> [!IMPORTANT]
> This is an actively developed community project. The local configurator and
> profile generator work with the documented fixtures and Input `0.17.3`
> profile flow, but the official `*-layer.json` round-trip and full hardware
> checklist are still in progress.

## What works today

- guided key-editing and profile-export modes with English, French, Spanish,
  and German interfaces;
- visual mapping for all 13 switches, wheel rotation, and the joystick;
- expanded Claude Desktop catalog for sessions, voice, diff, search,
  navigation, settings, window controls, zoom, and two explicit send actions;
- default wheel mode that moves through Claude's available effort levels one
  notch at a time, calibrated at roughly 90 ms per notch;
- safe custom shortcuts with Return/Enter, Delete, and Backspace rejected by
  construction;
- preservation checks for the native layer, other layers, and AppSense link;
- local JSON generation with a SHA-256 fingerprint and no upload.

## Run it locally

```sh
git clone https://github.com/thannous/claude-codex-micro.git
cd claude-codex-micro
npm run configure
```

Node.js 18 or newer is required. The app binds only to `127.0.0.1`.

## Agent key lighting — experimental

For preserving official Codex lighting while switching to a separate Claude
layer, see the [native lighting prototype and compatibility result](docs/research/native-lighting-preservation.md).
That two-app bridge is not operational on the inspected Codex build. The
standalone Claude lighting experiment below has different requirements.

Everything above is the project. This part is an experiment on top of it: the
six Agent keys show the live state of your Claude Code sessions in colour, and
pressing one goes to that session.

| | | |
| --- | --- | --- |
| `#C2483D` | **a decision is waiting for you** | the only colour that asks for you |
| `#D97757` | the session is working | |
| `#5B8C6F` | the turn has finished | |
| `#6D5A7D` | session open, at rest | |
| `#2F2927` | session closed, resumable | |
| unlit | no session on this key | |

**It only runs under three conditions.**

1. **Quit the ChatGPT app.** It rewrites these LEDs every 35 to 40 seconds and
   intercepts Agent key presses. Last write wins, so with it running you will
   see your colours appear and then vanish.
2. `npm install`, so that `node-hid` — an optional dependency — is built.
3. The Agent keycodes have to sit on the Claude layer. Input does not offer
   them in its key picker, so `scripts/enable-agent-keys.mjs` writes a profile
   for you to import through **Input > Import Profile**.

**If this half breaks, the other half does not.** Nothing above depends on it.
When the ChatGPT app takes the LEDs back, when `node-hid` is absent, or when an
app update moves the resume route, your keys keep sending their shortcuts. The
lighting writes nothing persistent either — only volatile HID reports, so no
firmware, no Input storage, and no ChatGPT app state is touched.

```sh
node scripts/thread-status.mjs watch    # reconcile sessions, write slots.json
node scripts/lighting.mjs watch --hold  # push those colours onto the keys
```

`thread-status` reconciles two official sources — `claude agents --json` for
live sessions, and a plugin hook journal for their state — into
`~/.claude/thread-status/slots.json`. `lighting watch` follows that file.
`--hold` reapplies as soon as a foreign write is detected.

```console
$ node scripts/thread-status.mjs doctor
  ✔ claude binary: $HOME/Library/Application Support/Claude/…/claude
  ✔ claude agents --json: 6 live session(s)
  ✔ state directory reachable: $HOME/.claude/thread-status
  ✔ journal: 194 event(s), last UserPromptSubmit 513s ago
  ✔ navigation: 4/6 session(s) in an identifiable terminal — the others are
    hosted by Claude Desktop or an IDE, reached through claude://resume
```

Pressing an Agent key navigates to its session: a terminal session gets its
window focused over AppleScript, and a session hosted by Claude Desktop is
opened through `claude://resume?session=<uuid>`. That route is **not
documented** — it is verified on this machine and can change with an app
update. The URL handler also reports nothing back, so a session whose
transcript has left the disk fails silently on the app side.

The per-key lighting channel is confirmed on hardware and reimplemented in
original code from the observed format. No Work Louder SDK is redistributed.
Protocol, measurements and limits:
[`docs/research/hid-lighting-protocol.md`](docs/research/hid-lighting-protocol.md)
and [`docs/research/thread-status-feasibility.md`](docs/research/thread-status-feasibility.md).

> Independent community project, not affiliated with or endorsed by Work
> Louder or Anthropic. Product names and trademarks belong to their respective
> owners.

---

## Detailed documentation

### Vision

A person must be able to:

1. understand the mapping before touching the keyboard;
2. check its compatibility;
3. back up the existing Input configuration;
4. simulate the change;
5. transform only the existing `Claude` layer, in a local copy;
6. test AppSense and every control;
7. restore the previous state;
8. contribute another preset held to the same standard.

In time, the catalogue can host IDE, browser, search, Figma, Framer, Adobe and
community-workflow layers. Read the [vision](docs/vision.md) and the
[roadmap](docs/roadmap.md).

### Current V1 result

The repository now contains:

- a portable V1 manifest and reusable schemas;
- a Claude physical mapping with colour, dial, joystick and AppSense;
- an original SVG representation of the Codex Micro;
- a local graphical configurator launched by `npm run configure`;
- a Node.js tool for diagnosis, inventory, backup, dry run, sanitisation and
  rollback;
- a local Input `0.17.3` profile generator that preserves the native layer and
  the existing AppSense link;
- transactional tests on isolated copies;
- a reproducible analysis of the Input `0.17.2` sharing mechanism;
- a procedure making it possible to capture the real official export later.

The analysis of the official package confirms **Import layer** and **Export
layer** commands, `*-layer.json` files, and the expected JSON envelope. The real
Claude file is deliberately not fabricated: its internal objects must come from a
real Codex Micro export.

The V1 manifest is `hardware-observed`: the generator was validated on an Input
`0.17.3` export, but the round-trip of a `*-layer.json` artefact and the full
hardware checklist are still open. The logical file `macos.example.json` stays
separately `proposal-not-applied`: it is not a universal preset to import.

### Proposed Claude mapping

The native Codex layer at index `0` is protected. The source profile must contain
exactly one `Claude` layer, different from index `0` and already linked to Claude
Desktop with AppSense.

| Control | Action |
| --- | --- |
| row of four square keys, left | `⌘N` — new conversation |
| same row, second | `⌘D` — voice mode |
| same row, third | `⌘⇧D` — show or hide the diff |
| same row, right | `Esc` — cancel or close, depending on context |
| clickable wheel, upper left corner | `PageUp` / `PageDown`; press configurable |
| non-clickable joystick, upper right corner | four directional arrows |
| other controls | no action; layer sensor reserved |

Proposed colour: `#D97757`. Activation: Claude Desktop in the foreground through
AppSense and `Auto detect`.

![Claude physical mapping](profiles/claude-shortcuts/assets/layout.svg)

Claude's global shortcuts stay outside the AppSense layer: double press on Option
for quick entry, and Caps Lock for global dictation. They have to stay available
when another application is in the foreground.

### What is forbidden by default

- Return/Enter and sending a message;
- approving or refusing a permission;
- deletion;
- `git push`;
- deployment;
- shell commands or destructive actions.

The validators fail if any of these actions appears on an active control.

### Observed compatibility

- macOS `26.5.2` arm64;
- Work Louder Input `0.17.3` for the profile generator;
- Codex Micro firmware `v0.4.1`;
- Claude Desktop `1.24012.9`;
- Claude bundle `com.anthropic.claudefordesktop`;
- Input bundle `it.focusense.input-app`.

See the [compatibility matrix](docs/compatibility.md) to tell facts, fixture
tests and missing hardware validations apart.

### Graphical configurator

```sh
npm run configure
```

The first launch may install the GUI's locked dependencies, then serves the
interface on `127.0.0.1` only and opens the browser.

The interface is available in English (the default language), French, Spanish and
German. The language choice is remembered locally in the browser.

The flow is a three-step wizard: load the official Work Louder Input export (with
built-in help for creating the `Claude` layer and the AppSense link), customise
the controls, then verify and generate. The verification screen shows the
preservation guarantees (native layer, AppSense, other layers) and the SHA-256
fingerprint of the `Claude-macOS-profile.json` produced. The source file, the
native layer, the other layers and the other AppSense links are preserved. The
public logical JSON is never presented as directly importable.

The configurator reads back the mapping already present in the loaded Claude
layer, remembers the current configuration locally, follows the system's light or
dark theme, and offers:

- the 13 physical switches, including the wheel press, along with its rotation
  and the joystick; only the layer-switching touch sensor stays reserved;
- an expanded catalogue of Claude Desktop shortcuts: session, voice, diff,
  search, navigation, settings, window, zoom and two explicit send actions;
- custom shortcuts restricted to safe keys (Return/Enter, Delete and Backspace
  stay forbidden in the custom editor);
- four wheel modes: Claude effort by default, pages, lines, and experimental
  volume.

### Getting started without modifying anything

Prerequisite: Node.js 18 or newer. The validation dependencies are locked in
`package-lock.json`.

```sh
git clone https://github.com/thannous/claude-codex-micro.git
cd claude-codex-micro
npm ci --no-audit --no-fund
npm run check
node scripts/input-layer.mjs doctor --json
node scripts/input-layer.mjs install --dry-run --json
```

The last command stays blocked without a local inventory containing exactly one
`Claude` layer, which is deliberate.

### Safe installation

The real path starts with an official profile export and a verified backup:

```sh
node scripts/input-layer.mjs backup \
  --profile-export "$HOME/Downloads/Mac-profile.json" \
  --json

node scripts/input-layer.mjs inventory \
  --profile-export "$HOME/Downloads/Mac-profile.json" \
  --output .local/inventories/current.json \
  --json

node scripts/input-layer.mjs install \
  --inventory .local/inventories/current.json \
  --profile-export "$HOME/Downloads/Mac-profile.json" \
  --dry-run \
  --json

npm run build:profile -- \
  "$HOME/Downloads/Mac-profile.json" \
  "$HOME/Downloads/Claude-macOS-profile.json"
```

Then import `Claude-macOS-profile.json` with **Add New** in Input. The source
file stays unchanged and no data is uploaded.

Read the [installation and rollback guide](docs/installation.md) before
`--apply`.

### Sharing format

Input `0.17.2` exposes an official flow at the layer and profile level:

- `*-layer.json`: `keyboard`, `language`, `layer`, actions and groups;
- `*-profile.json`: the same envelope with `profile`.

The evidence and its limits are documented in
[`docs/research/input-0.17.2-sharing.md`](docs/research/input-0.17.2-sharing.md).

The community manifest does not imitate that format. The main path transforms a
real `*-profile.json` locally. Any public layer artefact will stay optional and
will have to be tied to its SHA-256, to the canonical mapping and to round-trip
evidence.

### Structure

```text
profiles/
  schema/v1/                reusable schemas
  claude-shortcuts/
    manifest.json           identity, proof and installation
    mapping.json            physical mapping and safety
    assets/layout.svg       original preview
    artifacts/              future sanitised official export
scripts/
  configure.mjs             local launch of the graphical configurator
  prepare-gui.mjs           locked preparation of the GUI's dependencies
  build-input-profile.mjs   local generation of the importable profile
  input-layer.mjs           diagnosis, backup and guided installation
  thread-status.mjs         six Agent keys companion (session states)
  lighting.mjs              lighting control: probe/set/watch/listen/off
  lib/                      validation and preset functions, and the HID channel
  validate-profile.mjs      historical Claude logical contract
  validate-presets.mjs      library invariants
prototype/
  src/                      local configurator interface
shared/
  input-profile.mjs         canonical transformation shared with the GUI
tests/
  input-layer.test.mjs      backup, rollback, sanitisation and idempotence
docs/
  installation.md           complete procedure
  compatibility.md          evidence matrix
  research/                 sanitised Input analysis
  fr/                       French translation of this documentation
ble/                        separate Hardware Buddy track
```

Backups, inventories and sessions are stored under `.local/`, which Git ignores.
`work/` and `outputs/` also stay local.

### Validation

```sh
npm run check
node scripts/check-doc-links.mjs
git diff --check
```

CI runs the same checks. The isolated tests prove the tool's behaviour, not that
of Input or of the real keyboard.

### BLE Hardware Buddy track

This track stays independent. The Codex Micro being present as a BLE HID proves
neither the Nordic UART Service, nor HID + NUS coexistence, nor modifiable
firmware. No firmware, flashing tool or automatic approval is published.

Read [`ble/README.md`](ble/README.md) and
[`ble/feasibility.md`](ble/feasibility.md).

### Key lighting control

See [Agent key lighting — experimental](#agent-key-lighting--experimental)
above: the conditions, the isolation guarantee and the commands are gathered
there.

The full set of subcommands:

```sh
node scripts/lighting.mjs probe              # channel and key mapping
node scripts/lighting.mjs set slot 3 '#C2483D' --effect=breath
node scripts/lighting.mjs set all '#D97757'
node scripts/lighting.mjs zones --keys=#D97757 --ambient=#6D5A7D
node scripts/lighting.mjs listen             # key and joystick events
node scripts/lighting.mjs off
```

Protocol, measurements and bounds:
[`docs/research/hid-lighting-protocol.md`](docs/research/hid-lighting-protocol.md).

### Documentation links

- [Vision](docs/vision.md)
- [Roadmap](docs/roadmap.md)
- [Installation and rollback](docs/installation.md)
- [Compatibility](docs/compatibility.md)
- [Input 0.17.2 mechanism](docs/research/input-0.17.2-sharing.md)
- [Codex Micro HID lighting protocol](docs/research/hid-lighting-protocol.md)
- [Preset conventions](profiles/README.md)
- [Claude preset](profiles/claude-shortcuts/README.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)

### Main sources

- [Work Louder — official Codex Micro setup](https://worklouder.cc/openai-micro-setup)
- [Work Louder — Input releases](https://github.com/worklouder/input-releases/releases)
- [Claude — quick entry on macOS](https://support.claude.com/en/articles/12626668-use-quick-entry-with-claude-desktop-on-mac)
- [Claude — open the application with a link](https://support.claude.com/en/articles/14729294-open-claude-desktop-with-a-link)

### Licence

MIT, copyright 2026 Thanh Chau. See [LICENSE](LICENSE) and
[LICENSING.md](LICENSING.md).
