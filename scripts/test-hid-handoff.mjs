#!/usr/bin/env node
// Bounded hardware experiment: only device.status queries, never lighting,
// keymap writes or input injection. The Swift child holds a vendor-only claim.
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { mkdirSync, appendFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { DeviceSession, listInterfaces } from "./lib/hid-device.mjs";

if (process.argv.slice(2).join(" ") !== "--run") {
  console.log("Usage: node scripts/test-hid-handoff.mjs --run");
  console.log("Tests shared access before, during and after an 8-second exclusive claim. No lighting or keymap writes.");
  process.exit(process.argv.length === 2 || process.argv[2] === "--help" ? 0 : 64);
}

const root = fileURLToPath(new URL("../", import.meta.url));
const directory = `${root}.local/diagnostics`;
mkdirSync(directory, { recursive: true });
const logPath = `${directory}/hid-handoff-${Date.now()}.ndjson`;
function record(event, fields = {}) {
  const line = JSON.stringify({ time: new Date().toISOString(), event, ...fields });
  appendFileSync(logPath, `${line}\n`);
  console.log(line);
}
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
let session;
let child;
const watchdog = setTimeout(() => {
  child?.kill("SIGKILL");
  record("hard_timeout", { seconds: 45 });
  process.exit(124);
}, 45000);
process.on("exit", () => child?.kill("SIGKILL"));
for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => {
    child?.kill("SIGKILL");
    process.exit(signal === "SIGINT" ? 130 : 143);
  });
}

async function status(phase) {
  try {
    const response = await session.call("device.status");
    const result = response.result;
    if (response.method !== "device.status" || !result || typeof result.version !== "string") {
      throw new Error("Unexpected response shape; no success inferred.");
    }
    record("shared_query_success", {
      phase, version: result.version, profileIndex: result.profile_index,
      layerIndex: result.layer_index,
    });
    return { success: true };
  } catch (error) {
    record("shared_query_failure", { phase, code: error.code ?? null, message: error.message });
    return { success: false, code: error.code ?? null };
  }
}

try {
  record("start", { logPath, changesLighting: false, changesKeymap: false });
  const interfaces = await listInterfaces();
  if (interfaces.length !== 1) throw new Error(`Expected one vendor interface, found ${interfaces.length}.`);
  session = await DeviceSession.open({ path: interfaces[0].path });
  if (!(await status("before_seize")).success) throw new Error("Shared baseline failed; exclusive test skipped.");

  child = spawn(`${root}.local/bin/probe-hid-seize`, ["--seize", "--seconds", "8"], {
    stdio: ["ignore", "pipe", "pipe"],
  });
  let wasSeized = false;
  let wasReleased = false;
  let during;
  let failedWhileHeld = false;
  let wakeSeized;
  const seizedOrExited = new Promise(resolve => { wakeSeized = resolve; });
  const ended = new Promise((resolve, reject) => {
    child.once("error", error => { wakeSeized(false); reject(error); });
    child.once("exit", (code, signal) => {
      record("holder_exit", { code, signal });
      wakeSeized(false);
      resolve(code);
    });
  });
  for (const [label, stream] of [["holder", child.stdout], ["holder_stderr", child.stderr]]) {
    createInterface({ input: stream }).on("line", line => {
      let value;
      try { value = JSON.parse(line); } catch { value = { message: line }; }
      record(label, value);
      if (label === "holder" && value.event === "seized") {
        wasSeized = true;
        wakeSeized(true);
      }
      if (label === "holder" && value.event === "released" && value.result === "0x00000000") wasReleased = true;
    });
  }
  if (await seizedOrExited) {
    await sleep(250);
    during = await status("during_seize_same_handle");
    failedWhileHeld = !wasReleased && child.exitCode === null && during.code === "WRITE_FAILED";
  }
  const holderExit = await ended;
  await sleep(250);
  const after = await status("after_release_same_handle");
  const pass = wasSeized && wasReleased && holderExit === 0 && failedWhileHeld && after.success;
  record("summary", {
    seized: wasSeized, released: wasReleased, holderExit,
    sameHandleQuerySucceededDuring: during?.success ?? null,
    sameHandleWriteFailedWhileHeld: failedWhileHeld,
    sameHandleQuerySucceededAfter: after.success,
    transportHandoffPassed: pass,
    nativeCodexRecoveryVerified: false,
  });
  process.exitCode = pass ? 0 : 2;
} catch (error) {
  record("failure", { message: error.message });
  process.exitCode = 1;
} finally {
  child?.kill("SIGKILL");
  if (session) await session.close();
  clearTimeout(watchdog);
}
