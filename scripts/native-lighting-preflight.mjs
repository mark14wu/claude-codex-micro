#!/usr/bin/env node
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { fuseGate, inspectElectronFuses } from "./lib/electron-fuses.mjs";

function plistString(xml, key) {
  // Read only named metadata strings from XML plists; reject duplicate matches.
  // No external entities, DTDs or application code are evaluated.
  const matches = [...xml.matchAll(new RegExp(`<key>\\s*${key}\\s*</key>\\s*<string>([\\s\\S]*?)</string>`, "g"))];
  if (matches.length !== 1) throw new Error(`Missing or ambiguous Info.plist field: ${key}`);
  return matches[0][1].replace(/&(amp|lt|gt|quot|apos);/g, (_, entity) => ({ amp: "&", lt: "<", gt: ">", quot: '"', apos: "'" })[entity]);
}

function referenceRoute(gate, entryPoints) {
  return {
    entryPoints,
    requiredFuse: gate.name,
    fuseState: gate.state,
    status: gate.state === "disabled" ? "unsupported" : gate.state === "enabled" ? "unverified" : "unknown",
    reason: gate.state === "disabled" ? "Required entry point is disabled in at least one architecture"
      : gate.state === "enabled" ? "Fuse gate permits this entry point; runtime compatibility has not been tested"
        : "Cannot establish that every architecture enables the required entry point",
  };
}

export async function preflight(appPath = "/Applications/ChatGPT.app") {
  const app = path.resolve(appPath);
  const plist = await fs.readFile(path.join(app, "Contents", "Info.plist"), "utf8");
  if (!plist.trimStart().startsWith("<?xml") && !plist.trimStart().startsWith("<plist")) {
    throw new Error("Info.plist is not XML; this read-only check does not decode binary plists");
  }
  const metadata = {
    path: app,
    bundleId: plistString(plist, "CFBundleIdentifier"),
    version: plistString(plist, "CFBundleShortVersionString"),
    build: plistString(plist, "CFBundleVersion"),
  };
  const frameworks = ["Codex Framework", "Electron Framework"].map((name) => path.join(app, "Contents", "Frameworks", `${name}.framework`, name));
  const found = [];
  for (const candidate of frameworks) {
    try { if ((await fs.stat(candidate)).isFile()) found.push(candidate); }
    catch (error) { if (error.code !== "ENOENT") throw error; }
  }
  if (found.length !== 1) throw new Error("Expected exactly one recognized Codex/Electron framework binary");
  const inspection = inspectElectronFuses(await fs.readFile(found[0]));
  const nodeOptions = fuseGate(inspection, "EnableNodeOptionsEnvironmentVariable");
  const inspector = fuseGate(inspection, "EnableNodeCliInspectArguments");
  const routes = {
    nativeShim: referenceRoute(nodeOptions, ["NODE_OPTIONS=--require=<preload>"]),
    inspectorCompanion: referenceRoute(inspector, ["--inspect", "--inspect-brk", "SIGUSR1 inspector activation"]),
  };
  const statuses = Object.values(routes).map((route) => route.status);
  return {
    schemaVersion: 1,
    checkedAt: new Date().toISOString(),
    readOnly: true,
    status: statuses.every((status) => status === "unsupported") ? "unsupported"
      : statuses.some((status) => status === "unverified") ? "unverified" : "unknown",
    app: metadata,
    framework: found[0],
    fuseInspection: inspection,
    requiredEntryPoints: { nodeOptions, inspector },
    referenceRoutes: routes,
    scope: "Checks only the two reference entry points above; does not rule out other integrations. No app restart, injection, signal, HID access or app modification was performed.",
    sources: [
      "https://github.com/electron/fuses/blob/main/src/config.ts",
      "https://www.electronjs.org/docs/latest/tutorial/fuses#nodeoptions",
      "https://www.electronjs.org/docs/latest/tutorial/fuses#nodecliinspect",
    ],
  };
}

async function main(args) {
  if (args.includes("--help")) {
    console.log("Usage: node scripts/native-lighting-preflight.mjs [--app /Applications/ChatGPT.app]\nReads app metadata and framework fuse bytes only. JSON output. Exit 2: both reference entry points unsupported; 1: unknown/error; 0: a fuse gate is enabled, runtime still unverified.");
    return;
  }
  if (args.length !== 0 && (args.length !== 2 || args[0] !== "--app" || !args[1])) throw new Error("Expected only --app <path>; use --help");
  const report = await preflight(args[1]);
  console.log(JSON.stringify(report, null, 2));
  process.exitCode = report.status === "unsupported" ? 2 : report.status === "unknown" ? 1 : 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(JSON.stringify({ readOnly: true, status: "unknown", error: error.message }));
    process.exitCode = 1;
  });
}
