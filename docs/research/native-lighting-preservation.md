# Preserve native Codex lighting across Claude layers

## Status: existing button setup retained; dual-layer lighting deferred

On 2026-10-06, after reviewing the live-source limitations, the user chose
**no additional hardware; keep the current button functions**. The working
Codex native session/lighting setup and Claude shortcut mappings remain in place.
No automatic lighting takeover or hardware-proxy deployment is enabled. The
research and bounded test tools below are retained as evidence, not installed
as a daily controller. Further lighting integration requires a new user request.

The requirement is to preserve Codex's six session assignments and color rules,
while showing an independent Claude state frame on the Claude layer. The user
accepts a separate controller if those assignments and rules remain consistent.
This route returns control to the official app; parity under a separate Codex
renderer has not been established.

On 2026-10-06 the installed app was Codex `26.930.61225` (build `13232`), with
Input `1.0.1` and previously tested Micro firmware `0.6.3`.

The compatibility and initial exclusive-access tests did not write lighting.
The later bounded lighting tests each sent one temporary six-color frame. None
of these tests restarted or patched either app, enabled an inspector, injected
code, or changed device keymaps. Native output capture, transparent forwarding,
and automatic physical layer handoff have **not** been verified.

## Compatibility result

Two reference implementations were cloned into ignored `.local/references/`
and inspected without executing their installers or launchers:

| Reference | Inspected revision | Relevant limitation |
| --- | --- | --- |
| [codex-micro-app](https://github.com/maxxspotter/codex-micro-app) | `cf323ada1e9716073d0748caea503f6e0974ba1c` | Its preload depends on `NODE_OPTIONS`. The installed app disables this Electron fuse. |
| [worklouder-input-cli](https://github.com/MarlinDiary/worklouder-input-cli) | `8fdac749826c702f7d505db61c8d19c229aec4bf` | Its live installer uses a `SIGUSR1` inspector and exact app hashes for Codex `26.730.61309` / Input `0.18.0`. These do not match the installed apps. The installed Codex also disables the inspector fuse. |

The inspected Codex Framework has fuse wire version 1, nine settings,
`010011001`. Both `EnableNodeOptionsEnvironmentVariable` and
`EnableNodeCliInspectArguments` are disabled. Electron documents that the latter
also disables initializing the main-process inspector through `SIGUSR1`.
See [Electron fuse documentation](https://www.electronjs.org/docs/latest/tutorial/fuses)
and the [fuse index definitions](https://github.com/electron/fuses/blob/main/src/config.ts).

This rules out directly using these **two specific attachment mechanisms** on
the current build; it does not prove that every possible integration is
impossible. Changing fuses, modifying/re-signing the installed app, downgrading,
and disabling platform protections are not part of this prototype.

Run the read-only check again after an app update:

```sh
npm run lighting:preflight
```

The actual machine result is saved in
[`native-lighting-preflight-20261006.json`](native-lighting-preflight-20261006.json).
Both inspected attachment routes report `unsupported` on this build.

The check reads app metadata and framework fuse bytes. A disabled or unknown
entry point is not permission to attempt injection. Even enabled entry points
would only establish an attachment prerequisite, not compatibility or a working
bridge.

## Why the reference bridges cannot be used unchanged

- The phone shim appends a synthetic Micro alongside the real device. Codex
  could still open the real Micro; a physical proxy must prevent duplicate
  ownership and input delivery.
- Its presentation summary discards native brightness, speed and sync fields,
  and does not interpret the effect field like the measured firmware protocol.
  Preserve original lighting parameters instead of using that summary.
- Its fake-device handshake acknowledges otherwise unsupported requests. A
  physical transport must correlate real acknowledgements and surface failures.
- Static inspection of the current Codex service found that stopping the
  service writes default/off lighting and clears selection-related state. A
  stop/start handoff is not proven to preserve the complete lighting behavior.

Relevant private module paths and hashes were recorded locally under ignored
`.local/compatibility/`. Extracted vendor/app source is not redistributed.

## Implemented offline component

[`native-lighting-state.mjs`](../../scripts/lib/native-lighting-state.mjs)
stores `codex` and `claude` lighting independently. It accepts decoded JSON
parameters for `v.oai.rgbcfg` and `v.oai.thstatus`, without interpreting session
states or choosing colors.

- Copies incoming parameters and preserves unknown JSON fields.
- Replaces the two-zone configuration; merges per-slot partial updates by ID.
- Requires complete known parameters for both zones and all six slots before
  preparing a restore, rather than inventing missing values.
- Prepares `rgbcfg` followed by `thstatus` from the selected source.
- Invalidates the affected cache if a lighting payload cannot be preserved.

This is **parameter preservation**, not byte-for-byte report replay: the cache
merges partial updates into a complete state. Live Codex traffic would need a
separate unmodified forwarding path. Replaying a state can restart a firmware
animation; preserving the precise phase across a layer switch is not established.

`ready` means only that the cache contains complete parameters. It does not
prove delivery, visible rendering, freshness or exclusive ownership. It must
never be used alone to enable writes to hardware.

The tests use synthetic protocol data, not captured Codex session traffic:

```sh
node --test tests/native-lighting-state.test.mjs tests/electron-fuses.test.mjs
```

Validation on 2026-10-06: all 124 repository tests passed (`npm test`), including
the 15 new cache/preflight tests; profile, preset and documentation checks passed
(`npm run validate`). These checks do not claim live hardware compatibility.

## Gates before a live two-layer implementation

1. Obtain a supported way to receive official Codex lighting, or a verified live
   six-slot model with equivalent rendering. Return hardware input without changing
   its session assignment or lighting decisions. Matching a palette alone is not
   sufficient for the separate-controller route accepted by the user.
2. Observe bounded native output and verify it against the existing hardware
   behavior before intercepting or replaying anything.
3. Implement one serialized physical transport, source attribution, real RPC
   acknowledgements, generation checks on reconnect/layer changes, cancellation
   of stale writes, and restoration on failure. Layer changes and immediate key
   presses must not route a Claude press to Codex.
4. On the Codex layer, forward native output or render verified native models with
   matching rules. On the Claude layer, isolate native input, maintain the latest
   Codex state, and write only Claude's state. Restore the complete latest native
   state when switching back, with animation behavior checked on hardware.
5. Only after isolation works, change the Claude six keys from F13–F18 to AG
   codes. Reuse one fixed six-session table for navigation and lights.
6. Validate Claude Desktop local/SSH/cloud status sources separately. Explicit
   running, waiting, completion/unread, error and archive signals are required;
   missing events must not be presented as a successful or idle session.

The previous firmware comparison remains recorded in
[`firmware-0.6.3-layer-lighting-test.json`](firmware-0.6.3-layer-lighting-test.json).
It is a separate hardware test and is not evidence that this new proxy works.

## System virtual HID probe: creation did not succeed

On 2026-10-06, a separate CoreHID probe was compiled and executed outside the
filesystem sandbox on macOS 26.6.2. It used vendor-defined test IDs `FFFF:C0DE`,
not Codex Micro IDs, opened no physical device and dispatched no input reports.
The requested lifetime was ten seconds; creation failed immediately. No probe
interface remained afterwards. App and device configurations were unchanged.

The executable used a compiler-produced ad-hoc signature with **no restricted
entitlements**. This was a negative control, not an authorized positive test.
`HIDVirtualDevice` returned `nil` and the process exited with code 2. Its system
log reported `IOServiceOpen:0xe00002c2` (`kIOReturnBadArgument`). This error is not
a permission-specific diagnosis and does not establish the sole failure cause.

Apple documents the restricted `com.apple.developer.hid.virtual.device`
entitlement as a CoreHID prerequisite. Apple DTS reported that CoreHID had no
development-only entitlement variant; membership, a development certificate,
and Accessibility permission alone do not supply this capability. See
[Apple DTS's CoreHID guidance](https://developer.apple.com/forums/thread/820708)
and [Apple's managed capability provisioning workflow](https://developer.apple.com/help/account/reference/provisioning-with-managed-capabilities/).

An unsandboxed identity check found two valid Apple Development identities.
Neither of the two common provisioning-profile directories inspected contained
profiles. This does not establish whether the user has a paid membership or an
approved capability in their developer account. No account changes were made.

Source: [`probe-virtual-hid.swift`](../../scripts/probe-virtual-hid.swift).
Actual results: [`virtual-hid-probe-20261006.json`](virtual-hid-probe-20261006.json).
The bounded negative control can be reproduced with:

```sh
mkdir -p .local/bin .local/swift-module-cache
xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 \
  -module-cache-path .local/swift-module-cache \
  scripts/probe-virtual-hid.swift -o .local/bin/virtual-hid-probe
.local/bin/virtual-hid-probe --attempt-create --seconds 10
```

Next steps depend on an approved App ID capability and a matching provisioning
profile/signature. First repeat this non-Codex vendor-device test with authorized
signing and verify enumeration and bounded removal. Only after it succeeds can
we test a virtual Micro's RPC responses and native lighting capture. The real
Micro may need to be disconnected temporarily during that later test, because
static inspection shows Codex can retain its already-connected physical device.
Neither Codex discovery nor exclusive physical ownership has been tested by
this probe. No protection bypass or app modification is part of this route.

## Physical HID handoff: bounded transport test passed

A separate route was tested on 2026-10-06: take exclusive access to the actual
Micro's USB vendor interface while using Claude, then release it for the official
Codex app. It creates no virtual device and needs no virtual-HID entitlement.
The test ran as the normal user with Input Monitoring granted, outside the
execution sandbox. It targeted the independent `FF00:01` vendor interface, never
the ordinary keyboard or consumer interfaces.

The first eight-second claim opened and closed successfully. Official lighting
RPCs resumed afterwards, but the user reported abnormal keys or lights and the
device subsequently disappeared from USB enumeration. No test process remained.
After the device reappeared, the user confirmed normal Codex-layer keys and lights.
The cause of the intervening disconnects was not established.

The following test, at 17:13:50–17:13:59 UTC, used a separate shared client that
already had the device open before the exclusive claim:

1. `device.status` succeeded before the claim.
2. While the Swift helper held the device, that same client's write failed with
   `0xe00002c5` (exclusive access). Codex's own log independently recorded the
   same error and its normal reconnect attempts.
3. After eight seconds the helper closed and exited successfully. The original
   shared client completed another status query without reopening its handle.
4. About one second after the helper exited, Codex automatically reconnected and
   received successful responses for `v.oai.rgbcfg`, `v.oai.thstatus` and
   `device.status`.

No test lighting was written. Protocol recovery is confirmed, and the user
confirmed that physical Codex session keys and visible lighting were normal after
this second claim. This does not yet prove recovery after replacing native colors.
The exact test evidence is saved in
[`hid-seize-test-20261006.json`](hid-seize-test-20261006.json).

Reproduction sources:
[`probe-hid-seize.swift`](../../scripts/probe-hid-seize.swift) and
[`test-hid-handoff.mjs`](../../scripts/test-hid-handoff.mjs). Both default to safe
non-test behavior; the shared-writer test requires `--run`. The holder sends no
reports and has an independent process deadline. The shared client only queries
`device.status`; its 45-second watchdog terminates the holder on timeout.

This is evidence for **temporary transport ownership**, not a completed two-layer
controller. Remaining work includes Claude-layer AG rendering, session-state
collection, detecting layer changes, preventing presses during a handoff from
reaching the wrong app, and restoring lighting when Codex never attempted a write
during a short claim. A later implementation must also account for the measured
Codex reconnect delay and the earlier unexplained USB disconnects.

## Single-write lighting handoff: eventual restoration, variable delay

The next bounded experiment used
[`test-lighting-handoff.mjs`](../../scripts/test-lighting-handoff.mjs). Its first
attempt found layer 2 and released without writing lighting. A shared read-only
wait then detected the operator selecting native layer 1. The process opened
that same vendor interface exclusively, checked profile/layer again, and sent
one complete six-slot `v.oai.thstatus` pattern at 65% brightness. It received an
explicit success response and held the claim for 20 seconds without reapplying
the pattern or changing any key mappings.

Codex's own log recorded its write being blocked during the claim. The probe
released at 17:24:16.097 UTC; Codex automatically reconnected and received its
own `rgbcfg` and `thstatus` responses at 17:24:24.149 and 17:24:24.208 UTC.
This is approximately **8.1 seconds to native thread-lighting acknowledgement**,
not an immediate switch. The experiment did not send an `off` command or invent
a replacement native palette.

The operator requested a repeat instead of confirming the first trial's visual
outcome. The repeat held the same single-write pattern for 30 seconds, then
released at 17:28:15.615 UTC. No native write failure or reconnect was observed
during this claim. Native `device.status` responses arrived at 17:28:24.305 and
17:29:24.316 UTC without a lighting refresh. The first subsequent native
`thstatus` acknowledgement arrived at 17:29:31.350 UTC, **75.735 seconds after
release**. The operator confirmed that Codex lighting had automatically returned,
in response to a question specifying no Micro press or manual session switch.
The operator did not time the visible restoration or separately confirm the
exact six-color pattern.

Read-only inspection of this installed build shows two lighting caches: the
renderer sends an update when its serialized model changes, and the device
service skips a thread-lighting frame matching its last applied frame. Releasing
our claim does not itself clear either cache. A successful battery/status poll
does not redraw lighting. A native transport failure during the claim can
invalidate the connection and lead to a reconnect and reapplication, as observed
in the first trial. This is consistent with the different recovery behavior;
the trigger for the repeat's eventual native refresh was not established.

Foreground activation and pressing the already-selected session do not guarantee
a changed lighting model. No supported external force-refresh entry point was
found in this inspection. Waiting for a native poll to fail can take more than
a minute and is unsuitable as an immediate layer-switch mechanism. Before daily
use, this route needs a reliable prompt redraw or a separately verified controller
that preserves the six native assignments and color rules.

The tests establish eventual automatic restoration, not bounded or immediate
handoff. They do not establish operation on the Claude F13–F18 layer. Full
timings, parameters and limitations are in
[`hid-lighting-handoff-test-20261006.json`](hid-lighting-handoff-test-20261006.json).

## Separate renderer: per-key rules match; live model remains unavailable

The user's accepted alternative is to control the lights ourselves while keeping
Codex's six assignments and color rules identical. The original pure implementation
[`codex-thread-lighting.mjs`](../../scripts/lib/codex-thread-lighting.mjs) now turns
an explicit six-slot model into a complete `v.oai.thstatus` frame. It has no device
I/O. Missing status, selection, pulsing or brightness, unknown statuses and invalid
slot IDs are rejected instead of becoming guessed idle/off values.

| Native status | Color |
| --- | --- |
| working | `#304FFE` |
| unread | `#00FF4C` |
| idle | `#FFFFFF` |
| awaiting-approval / awaiting-response | `#FF6D00` |
| error | `#FF0033` |
| off | `#000000` |

Active slots use the model's brightness and breathe when selected or pulsing;
otherwise they are solid. Off slots have zero brightness, effect and speed.
This input is the already-derived native slot status: raw session state still
needs the native priority, focus and unread rules applied upstream.

An independent local-only oracle compared the installed native pure renderer,
palette and SDK serialization against this implementation. Across **201,600
synthetic frames / 1,209,600 slot outputs**, all 720 slot orders, seven statuses,
five brightness values and both boolean flags, there were **zero differences**.
The comparison did not interact with the running app or device. Source hashes,
coverage and limits are saved in
[`codex-lighting-parity-20261006.json`](codex-lighting-parity-20261006.json).
Seven unit tests additionally check rejection of incomplete models and slot
identity preservation. These results do not establish complete zone, timing,
live-state or hardware parity, and must be revalidated after app changes.
After this addition, all 131 repository tests and the profile, preset and
documentation validation checks passed.

The read-only inventory
[`inspect-codex-lighting-inputs.py`](../../scripts/inspect-codex-lighting-inputs.py)
reports counts and schemas of relevant persisted inputs, excluding session titles
and identities from its output. It requires Python 3.11 or newer:

```sh
python3 scripts/inspect-codex-lighting-inputs.py
```

The [local inventory](codex-lighting-inputs-20261006.json) confirms that this
installation uses `pinned` as its Micro agent source. Persistent data includes
pinned chats, pinned projects and ordering hints, but is not the final resolved
six-slot array. Native selection also depends on resolved host/project membership
and live renderer state. A generic list of recent or pinned chats is not evidence
of identical assignments. Logs record RPC acknowledgements without original
lighting parameters. The inspected device SDK offers lighting setters, not a
complete live LED getter or a force-refresh method; local microbridge does not
capture native frames either.

The next prerequisite is a supported live model/parameter source, including
ordered six-slot identity, status, selection and freshness. Until that exists,
the matched renderer is an offline component and hardware writes remain disabled.
No further release-only color test can establish the missing state source or
guarantee prompt native restoration.

## Live source investigation: current attachment route is unavailable

The next read-only investigation checked the installed CLI, native desktop
transport, pin projection and a possible brightness-based redraw trigger.
The [official App Server documentation](https://learn.chatgpt.com/docs/app-server)
describes runtime status reads and Unix WebSocket listeners. Those capabilities
apply to the server actually connected to the client; they do not grant access
to another process's in-memory state.

This desktop instance logs `hostId=local transport=stdio`. Both control socket
paths considered by microbridge are absent. The installed CLI supports `proxy`,
but `app-server daemon version` failed because its control socket did not exist.
Starting a second server would not establish access to the desktop server's live
state. The separate existing `~/.codex/ipc/ipc.sock` implements a private desktop
coordination protocol, not the documented App Server transport; it was not used.

Native pinned projection reads server pin order per host, combines standalone
threads with pinned projects, expands each project's ordered children and then
takes six. It can also depend on the renderer's previous project order. In the
current local database, all 11 pinned rows are archived and no active row is
pinned; remote host inventory is necessary. The two legacy IDs in global state
are not a substitute. An internal global pinned-list helper may migrate pins,
so it was not invoked as a read-only test. A per-host section query candidate
is recorded for future integration with a verified existing server.

Changing the normal Micro brightness preference could change native lighting
parameters through the settings UI, but is not a verified external refresh API.
The settings store reads configuration at startup; no live reload path from
external config-file edits was established. The normal agent settings interface
marks this setting hidden. No configuration was changed. Moreover, all-off slots
can still produce an unchanged six-slot frame after a brightness change.

The inspected software interfaces therefore remain insufficient for a complete
live model or a reliable immediate native redraw. This investigation opened no
device, changed no app settings and started no server. Full evidence is in
[`codex-live-source-investigation-20261006.json`](codex-live-source-investigation-20261006.json).

A possible next architecture is a physical USB proxy with separate USB Host and
USB Device interfaces. The computer would communicate with the proxy; the proxy
would communicate with the Micro. On the Codex layer it would forward native
traffic and retain acknowledged native lighting state. On the Claude layer it
would continue accepting Codex updates into that state while routing Claude
keys and lighting separately. On return it could apply the latest native state
without waiting for Codex's deduplication cache to change.

That architecture still requires hardware, firmware development and validation:
descriptor compatibility, full protocol coverage, honest acknowledgement
semantics, layer/input race handling, and failure recovery. It is not a tested
solution or a reason to change the working keymap now. The user subsequently
declined additional hardware and chose to retain the current button functions;
this hardware route will not be pursued under the current scope.
