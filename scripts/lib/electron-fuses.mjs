// Read-only Electron fuse inspection. No application code is loaded or executed.
// Schema: https://github.com/electron/fuses/blob/main/src/config.ts
export const FUSE_SENTINEL = Buffer.from("dL7pKGdnNz796PbbjQWNKmHXBZaB9tsX", "ascii");
export const FUSE_V1_NAMES = Object.freeze([
  "RunAsNode",
  "EnableCookieEncryption",
  "EnableNodeOptionsEnvironmentVariable",
  "EnableNodeCliInspectArguments",
  "EnableEmbeddedAsarIntegrityValidation",
  "OnlyLoadAppFromAsar",
  "LoadBrowserProcessSpecificV8Snapshot",
  "GrantFileProtocolExtraPrivileges",
  "WasmTrapHandlers",
]);

function architecture(cpuType) {
  return new Map([[7, "x86"], [0x01000007, "x86_64"], [12, "arm"], [0x0100000c, "arm64"]])
    .get(cpuType) ?? `unknown-cpu-${cpuType}`;
}

function thinHeader(bytes) {
  if (bytes.length < 4) return null;
  const magic = bytes.readUInt32BE(0);
  const littleEndian = magic === 0xcefaedfe || magic === 0xcffaedfe;
  const is64 = magic === 0xfeedfacf || magic === 0xcffaedfe;
  if (![0xfeedface, 0xfeedfacf, 0xcefaedfe, 0xcffaedfe].includes(magic)) return null;
  if (bytes.length < (is64 ? 32 : 28)) throw new Error("Truncated Mach-O header");
  const cpuType = littleEndian ? bytes.readUInt32LE(4) : bytes.readUInt32BE(4);
  return { cpuType, architecture: architecture(cpuType), littleEndian, is64 };
}

function binarySlices(bytes) {
  const thin = thinHeader(bytes);
  if (thin) return { format: "mach-o", slices: [{ ...thin, offset: 0, size: bytes.length }] };
  if (bytes.length < 8) throw new Error("Missing Mach-O or universal binary header");
  const magic = bytes.readUInt32BE(0);
  if (![0xcafebabe, 0xbebafeca, 0xcafebabf, 0xbfbafeca].includes(magic)) {
    throw new Error("Unrecognized binary format; architecture coverage cannot be established");
  }
  const littleEndian = magic === 0xbebafeca || magic === 0xbfbafeca;
  const is64 = magic === 0xcafebabf || magic === 0xbfbafeca;
  const u32 = (offset) => littleEndian ? bytes.readUInt32LE(offset) : bytes.readUInt32BE(offset);
  const u64 = (offset) => {
    const value = littleEndian ? bytes.readBigUInt64LE(offset) : bytes.readBigUInt64BE(offset);
    if (value > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error("Universal slice exceeds safe integer range");
    return Number(value);
  };
  const count = u32(4);
  const stride = is64 ? 32 : 20;
  const tableEnd = 8 + count * stride;
  if (!count || tableEnd > bytes.length) throw new Error("Invalid or truncated universal architecture table");
  const slices = [];
  for (let index = 0; index < count; index += 1) {
    const entry = 8 + index * stride;
    const cpuType = u32(entry);
    const offset = is64 ? u64(entry + 8) : u32(entry + 8);
    const size = is64 ? u64(entry + 16) : u32(entry + 12);
    if (!size || offset < tableEnd || offset > bytes.length || size > bytes.length - offset) {
      throw new Error(`Universal slice ${index} is outside the binary`);
    }
    if (slices.some((slice) => offset < slice.offset + slice.size && slice.offset < offset + size)) {
      throw new Error(`Universal slice ${index} overlaps another slice`);
    }
    const header = thinHeader(bytes.subarray(offset, offset + size));
    if (!header || header.cpuType !== cpuType) throw new Error(`Universal slice ${index} has a mismatched Mach-O header`);
    slices.push({ ...header, offset, size });
  }
  return { format: is64 ? "universal-64" : "universal-32", slices };
}

function readWire(bytes, offset) {
  const header = offset + FUSE_SENTINEL.length;
  if (header + 2 > bytes.length) return { offset, status: "unknown", error: "Truncated fuse header", states: [] };
  const version = bytes[header];
  const length = bytes[header + 1];
  const available = Math.min(length, bytes.length - header - 2);
  const states = Array.from(bytes.subarray(header + 2, header + 2 + available), (byte, index) => {
    const raw = byte >= 0x20 && byte <= 0x7e ? String.fromCharCode(byte) : `0x${byte.toString(16).padStart(2, "0")}`;
    const state = version !== 1 ? "unknown" : raw === "1" ? "enabled" : raw === "0" ? "disabled" : raw === "r" ? "removed" : "unknown";
    return { index, name: version === 1 ? FUSE_V1_NAMES[index] ?? null : null, raw, state,
      enabled: state === "enabled" ? true : state === "disabled" ? false : null };
  });
  const error = length === 0 ? "Empty fuse wire" : available !== length ? "Truncated fuse wire" : version !== 1 ? "Unknown fuse schema version" : null;
  return { offset, version, length, raw: states.map((state) => state.raw).join(""),
    status: error ? "unknown" : "parsed", ...(error ? { error } : {}), states };
}

export function inspectElectronFuses(bytes) {
  if (!Buffer.isBuffer(bytes)) throw new TypeError("Expected a binary Buffer");
  let binary;
  try { binary = binarySlices(bytes); }
  catch (error) { return { format: "unknown", status: "unknown", errors: [error.message], slices: [] }; }
  const slices = binary.slices.map((slice) => {
    const part = bytes.subarray(slice.offset, slice.offset + slice.size);
    const wires = [];
    for (let offset = part.indexOf(FUSE_SENTINEL); offset !== -1; offset = part.indexOf(FUSE_SENTINEL, offset + 1)) {
      wires.push(readWire(part, offset));
    }
    const errors = wires.length === 0 ? ["Fuse sentinel missing"] : wires.length > 1 ? ["Multiple fuse sentinels in one architecture; ambiguous"] : [];
    const parsed = errors.length === 0 && wires[0].status === "parsed";
    return { ...slice, status: parsed ? "parsed" : "unknown", errors, wires };
  });
  return { format: binary.format, status: slices.every((slice) => slice.status === "parsed") ? "parsed" : "unknown", errors: [], slices };
}

// Enable an entry point only when every architecture explicitly enables its fuse.
// Unknown versions, missing bytes, removed fuses and malformed binaries stay unknown.
export function fuseGate(inspection, name) {
  const slices = inspection.slices.map((slice) => {
    const fuse = slice.status === "parsed" ? slice.wires[0].states.find((state) => state.name === name) : null;
    return { architecture: slice.architecture, state: fuse?.state ?? "unknown", raw: fuse?.raw ?? null };
  });
  const state = slices.length === 0 ? "unknown"
    : slices.some((slice) => slice.state === "disabled") ? "disabled"
    : slices.every((slice) => slice.state === "enabled") ? "enabled" : "unknown";
  return { name, state, enabledOnEveryArchitecture: state === "enabled", slices };
}
