import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { FUSE_SENTINEL, fuseGate, inspectElectronFuses } from "../scripts/lib/electron-fuses.mjs";
import { preflight } from "../scripts/native-lighting-preflight.mjs";

const NODE_OPTIONS = "EnableNodeOptionsEnvironmentVariable";
const INSPECTOR = "EnableNodeCliInspectArguments";

function thin(raw = "010011001", { cpuType = 0x0100000c, version = 1, length = raw.length, littleEndian = true } = {}) {
  const header = Buffer.alloc(32);
  header.writeUInt32BE(littleEndian ? 0xcffaedfe : 0xfeedfacf, 0);
  if (littleEndian) header.writeUInt32LE(cpuType, 4);
  else header.writeUInt32BE(cpuType, 4);
  return Buffer.concat([header, FUSE_SENTINEL, Buffer.from([version, length]), Buffer.from(raw, "ascii")]);
}

function universal(parts, { is64 = false, littleEndian = false } = {}) {
  const stride = is64 ? 32 : 20;
  const header = Buffer.alloc(8 + stride * parts.length);
  const magic = is64 ? littleEndian ? 0xbfbafeca : 0xcafebabf : littleEndian ? 0xbebafeca : 0xcafebabe;
  header.writeUInt32BE(magic, 0);
  const u32 = (value, offset) => littleEndian ? header.writeUInt32LE(value, offset) : header.writeUInt32BE(value, offset);
  const u64 = (value, offset) => littleEndian ? header.writeBigUInt64LE(BigInt(value), offset) : header.writeBigUInt64BE(BigInt(value), offset);
  u32(parts.length, 4);
  let offset = header.length;
  parts.forEach((part, index) => {
    const entry = 8 + index * stride;
    const cpuType = part.readUInt32BE(0) === 0xcffaedfe ? part.readUInt32LE(4) : part.readUInt32BE(4);
    u32(cpuType, entry);
    if (is64) { u64(offset, entry + 8); u64(part.length, entry + 16); }
    else { u32(offset, entry + 8); u32(part.length, entry + 12); }
    offset += part.length;
  });
  return Buffer.concat([header, ...parts]);
}

test("current production pattern disables both reference entry points", () => {
  const result = inspectElectronFuses(thin());
  assert.equal(result.status, "parsed");
  assert.equal(result.slices[0].wires[0].raw, "010011001");
  assert.equal(fuseGate(result, NODE_OPTIONS).state, "disabled");
  assert.equal(fuseGate(result, INSPECTOR).state, "disabled");
});

test("only literal 1 in the recognized schema counts as enabled", () => {
  for (const [raw, expected] of [["011111001", "enabled"], ["01r111001", "unknown"], ["01?111001", "unknown"]]) {
    assert.equal(fuseGate(inspectElectronFuses(thin(raw)), NODE_OPTIONS).state, expected);
  }
  const unknown = inspectElectronFuses(thin("011111001", { version: 2 }));
  assert.equal(unknown.slices[0].wires[0].version, 2);
  assert.equal(unknown.slices[0].wires[0].states[2].raw, "1");
  assert.equal(fuseGate(unknown, NODE_OPTIONS).state, "unknown");
});

test("missing, empty, short, truncated and ambiguous wires never enable an entry point", () => {
  const header = thin().subarray(0, 32);
  const samples = [header, thin(""), thin("01"), thin("011", { length: 9 }), Buffer.concat([header, FUSE_SENTINEL]), Buffer.concat([thin("011111001"), FUSE_SENTINEL, Buffer.from([1, 9]), Buffer.from("011111001")])];
  for (const sample of samples) assert.equal(fuseGate(inspectElectronFuses(sample), NODE_OPTIONS).state, "unknown");
});

test("all architecture slices must explicitly enable the requested fuse", () => {
  for (const is64 of [false, true]) for (const littleEndian of [false, true]) {
    const arm = thin("011111001");
    const intel = thin("011111001", { cpuType: 0x01000007, littleEndian: false });
    const good = inspectElectronFuses(universal([arm, intel], { is64, littleEndian }));
    assert.equal(good.status, "parsed");
    assert.deepEqual(good.slices.map((slice) => slice.architecture), ["arm64", "x86_64"]);
    assert.equal(fuseGate(good, NODE_OPTIONS).state, "enabled");
    const disabled = inspectElectronFuses(universal([arm, thin()], { is64, littleEndian }));
    assert.equal(fuseGate(disabled, NODE_OPTIONS).state, "disabled");
    const unknown = inspectElectronFuses(universal([arm, thin("011111001", { version: 2 })], { is64, littleEndian }));
    assert.equal(fuseGate(unknown, NODE_OPTIONS).state, "unknown");
  }
});

test("corrupt universal ranges, overlap, table, CPU and format are unknown", () => {
  const valid = universal([thin(), thin("011111001", { cpuType: 0x01000007 })]);
  const samples = [Buffer.from("not an executable"), valid.subarray(0, 10)];
  const outside = Buffer.from(valid); outside.writeUInt32BE(0xffffff00, 16); samples.push(outside);
  const overlap = Buffer.from(valid); overlap.writeUInt32BE(48, 36); samples.push(overlap);
  const cpuMismatch = Buffer.from(valid); cpuMismatch.writeUInt32BE(7, 8); samples.push(cpuMismatch);
  const huge = universal([thin()], { is64: true }); huge.writeBigUInt64BE(2n ** 60n, 16); samples.push(huge);
  for (const sample of samples) {
    const result = inspectElectronFuses(sample);
    assert.equal(result.status, "unknown");
    assert.equal(fuseGate(result, NODE_OPTIONS).state, "unknown");
  }
});

test("preflight reads only app metadata and framework; reports scope without execution", async () => {
  const app = await fs.mkdtemp(path.join(os.tmpdir(), "native-lighting-preflight-test-"));
  try {
    const framework = path.join(app, "Contents", "Frameworks", "Codex Framework.framework");
    await fs.mkdir(framework, { recursive: true });
    await fs.writeFile(path.join(app, "Contents", "Info.plist"), '<plist><dict><key>CFBundleIdentifier</key><string>com.example.test</string><key>CFBundleShortVersionString</key><string>26.test</string><key>CFBundleVersion</key><string>123</string></dict></plist>');
    await fs.writeFile(path.join(framework, "Codex Framework"), thin());
    const result = await preflight(app);
    assert.equal(result.readOnly, true);
    assert.equal(result.app.version, "26.test");
    assert.equal(result.status, "unsupported");
    assert.equal(result.referenceRoutes.nativeShim.status, "unsupported");
    assert.equal(result.referenceRoutes.inspectorCompanion.status, "unsupported");
    assert.match(result.scope, /does not rule out other integrations/);
    await fs.writeFile(path.join(framework, "Codex Framework"), thin("011111001"));
    assert.equal((await preflight(app)).status, "unverified");
  } finally { await fs.rm(app, { recursive: true, force: true }); }
});
