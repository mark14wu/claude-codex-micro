#!/usr/bin/env node
// A single, temporary six-color override while owning the actual vendor HID.
// No keymap/firmware writes and no background installation. Restoration is
// delegated to native Codex after release, and must be independently verified.
import { appendFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { DeviceSession, listInterfaces, loadHid } from "./lib/hid-device.mjs";
import { buildRequest, encodeFrames } from "./lib/hid-frame.mjs";

const params = [0xff0000, 0x00ff00, 0x0000ff, 0xffff00, 0xff00ff, 0x00ffff]
  .map((c, id) => ({ id, c, b: 0.65, e: 1, s: 0.5, sk: 0, sa: 0 }));
const holdSeconds = 30;
const args = process.argv.slice(2);
const waitForNative = args.join(" ") === "--run --wait-for-native";
if (args.join(" ") !== "--run" && !waitForNative) {
  console.log(JSON.stringify({
    usage: "node scripts/test-lighting-handoff.mjs --run [--wait-for-native]",
    expectedProfile: 1, expectedLayer: 1, holdSeconds, hardDeadlineSeconds: 50,
    method: "v.oai.thstatus", params,
    frameCount: encodeFrames(buildRequest({ method: "v.oai.thstatus", params, id: 900 })).length,
    writesOnDescribe: false,
  }, null, 2));
  process.exit(args.length === 0 || args.join(" ") === "--help" ? 0 : 64);
}

const root = fileURLToPath(new URL("../", import.meta.url));
const directory = `${root}.local/diagnostics`;
mkdirSync(directory, { recursive: true });
const logPath = `${directory}/lighting-handoff-${Date.now()}.ndjson`;
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
function record(event, fields = {}) {
  const line = JSON.stringify({ time: new Date().toISOString(), event, ...fields });
  appendFileSync(logPath, `${line}\n`);
  console.log(line);
}

let handle;
let session;
let lightingAcknowledged = false;
let released = false;
const watchdog = setTimeout(() => {
  record("hard_timeout", { seconds: waitForNative ? 180 : 50, restorationVerified: false });
  // Process exit makes macOS release any claim, even if an async HID call stalls.
  process.exit(124);
}, waitForNative ? 180000 : 50000);
for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => {
    record("interrupted", { signal, restorationVerified: false });
    process.exit(signal === "SIGINT" ? 130 : 143);
  });
}

async function status() {
  const response = await session.call("device.status");
  if (response.method !== "device.status" || typeof response.result?.version !== "string") {
    throw new Error("Unexpected status response; aborting rather than inferring a layer.");
  }
  return response.result;
}

try {
  record("start", { logPath, expectedProfile: 1, expectedLayer: 1 });
  const interfaces = await listInterfaces();
  if (interfaces.length !== 1) throw new Error(`Expected one Micro vendor interface, found ${interfaces.length}.`);
  if (interfaces[0].usage !== 1) throw new Error("Unexpected vendor usage; aborting.");
  // The preceding Swift probe verified that this USB path is an independent
  // vendor interface. Bluetooth or an ambiguous device is not an eligible test.
  if (interfaces[0].release % 4 !== 0) throw new Error("Non-USB release marker; aborting.");
  const hid = await loadHid();
  if (waitForNative) {
    handle = await hid.HIDAsync.open(interfaces[0].path, { nonExclusive: true });
    session = new DeviceSession(handle);
    const waitDeadline = Date.now() + 120000;
    let lastLayer;
    let ready = false;
    record("waiting_for_native_layer", { maxSeconds: 120, exclusive: false });
    while (Date.now() < waitDeadline) {
      const current = await status();
      if (current.profile_index !== 1) throw new Error("Profile changed; aborting.");
      if (current.layer_index !== lastLayer) {
        lastLayer = current.layer_index;
        record("observed_layer", { profileIndex: current.profile_index, layerIndex: lastLayer });
      }
      if (lastLayer === 1) { ready = true; break; }
      await sleep(1000);
    }
    await handle.close();
    handle = undefined;
    session = undefined;
    if (!ready) throw new Error("Native layer was not selected before the wait deadline; no lighting sent.");
  }
  handle = await hid.HIDAsync.open(interfaces[0].path, { nonExclusive: false });
  record("seized", { path: interfaces[0].path });
  session = new DeviceSession(handle);
  const before = await status();
  record("initial_status", { version: before.version, profileIndex: before.profile_index, layerIndex: before.layer_index });
  if (before.profile_index !== 1 || before.layer_index !== 1) {
    throw new Error("Not on the expected native AG layer; no test lighting sent.");
  }
  const response = await session.call("v.oai.thstatus", params);
  if (response.method !== "v.oai.thstatus" || response.result?.ok !== 1) {
    throw new Error("Lighting response was not an explicit success; releasing without retry.");
  }
  lightingAcknowledged = true;
  record("pattern_acknowledged", { colors: params.map(p => p.c.toString(16).padStart(6, "0")), holdSeconds });
  // No more RPC calls while holding the frame: a delayed query must not extend
  // the hold. The operator is asked to remain on this layer for this one test.
  await sleep(holdSeconds * 1000);
} catch (error) {
  record("failure", { code: error.code ?? null, message: error.message, lightingAcknowledged });
  process.exitCode = 2;
} finally {
  // Do not use DeviceSession.close(), which intentionally suppresses close
  // errors. For this diagnostic, record whether the underlying close succeeds.
  if (handle) {
    try {
      await handle.close();
      released = true;
      record("released", { lightingAcknowledged, nativeRestorationVerified: false });
    } catch (error) {
      record("close_failed", { message: error.message });
      process.exitCode = 3;
    }
  }
  clearTimeout(watchdog);
  record("finished", { lightingAcknowledged, released, nativeRestorationVerified: false });
}
