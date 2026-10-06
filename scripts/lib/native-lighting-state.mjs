// Offline cache of native lighting parameters. No palette, RPC, or device I/O.
// Transport must supply trustworthy source attribution and ordered observations.

const RGB_CONFIG = "v.oai.rgbcfg";
const THREAD_STATUS = "v.oai.thstatus";
const ZONE_FIELDS = ["c", "b", "e", "s", "m"];
const THREAD_FIELDS = ["c", "b", "e", "s", "sk", "sa"];
const own = (value, key) => Object.hasOwn(value, key);

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    && [Object.prototype, null].includes(Object.getPrototypeOf(value));
}

// Reject values a JSON wire call cannot carry without loss. In particular,
// do not execute getters or silently drop undefined/unknown properties.
function cloneJson(value, ancestors = new Set()) {
  if (value === null || typeof value === "string" || typeof value === "boolean") return value;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (!Array.isArray(value) && !isRecord(value)) throw new TypeError("Expected JSON data");
  if (ancestors.has(value)) throw new TypeError("Cyclic payload");
  ancestors.add(value);
  const result = Array.isArray(value) ? [] : {};
  const descriptors = Object.getOwnPropertyDescriptors(value);
  for (const key of Reflect.ownKeys(descriptors)) {
    if (Array.isArray(value) && key === "length") continue;
    const descriptor = descriptors[key];
    if (typeof key !== "string" || !descriptor.enumerable || !own(descriptor, "value")) {
      throw new TypeError("Expected enumerable JSON properties");
    }
    if (Array.isArray(value) && (!/^(0|[1-9][0-9]*)$/.test(key) || Number(key) >= value.length)) {
      throw new TypeError("Unsupported array property");
    }
    Object.defineProperty(result, key, {
      value: cloneJson(descriptor.value, ancestors), enumerable: true, writable: true, configurable: true,
    });
  }
  if (Array.isArray(value) && Object.keys(result).length !== value.length) {
    throw new TypeError("Sparse arrays are unsupported");
  }
  ancestors.delete(value);
  return result;
}

function validateFields(value) {
  if (!isRecord(value)) throw new TypeError("Expected a lighting object");
  for (const key of ["c", "e", "b", "s", "sk", "sa"]) {
    if (!own(value, key)) continue;
    const field = value[key];
    const valid = key === "c" ? Number.isInteger(field) && field >= 0 && field <= 0xffffff
      : key === "e" ? Number.isInteger(field) && field >= 0
      : key === "b" || key === "s" ? typeof field === "number" && field >= 0 && field <= 1
      : field === 0 || field === 1;
    if (!valid) throw new TypeError(`Unsupported lighting field: ${key}`);
  }
}

function emptyState() {
  return { rgbcfg: null, thstatus: Array(6).fill(null) };
}

function ready(state) {
  return state.rgbcfg !== null
    && ["ambient", "keys"].every((zone) => ZONE_FIELDS.every((key) => own(state.rgbcfg[zone], key)))
    && state.thstatus.every((slot) => slot !== null && THREAD_FIELDS.every((key) => own(slot, key)));
}

/**
 * Keep independent `codex` and `claude` parameter caches.
 *
 * observe(source, method, params) never throws. It clones inputs, replaces the
 * whole rgbcfg (both zones), and merges thstatus entries by id, field by field.
 * Nested/unknown field values are preserved, not interpreted or recolored.
 * A rejected lighting payload invalidates that source: the original external
 * call may still have changed the device. Unknown methods leave caches alone.
 *
 * snapshot(source) returns an independent {ready, rgbcfg, thstatus} copy.
 * restore(source) returns null until complete, otherwise two independent
 * {method, params} commands, rgbcfg first. It does not send them or add RPC ids.
 * reset(source) invalidates a source, e.g. after disconnect or lost observation.
 *
 * This cache is NOT a transport gate: source identity, call ordering, failures,
 * device generations, exclusivity, freshness and replay suppression belong in
 * that gate. Never cancel the original call merely because observe rejects it.
 * Inputs must be decoded wire JSON, after undefined fields have been omitted
 * by the sender's serializer, rather than pre-serialization SDK arguments.
 *
 * @returns {{observe: Function, snapshot: Function, restore: Function, reset: Function}}
 * Independent caches and pure restore planning; no hardware writes.
 */
export function createNativeLightingState() {
  const states = new Map([["codex", emptyState()], ["claude", emptyState()]]);
  function get(source) {
    if (!states.has(source)) throw new TypeError("Unknown lighting source");
    return states.get(source);
  }
  return {
    observe(source, method, params) {
      if (!states.has(source)) return { accepted: false, ready: false, error: "Unknown lighting source" };
      if (method !== RGB_CONFIG && method !== THREAD_STATUS) {
        return { accepted: false, ready: ready(get(source)), error: "Unsupported lighting method" };
      }
      try {
        const data = cloneJson(params);
        const previous = get(source);
        let next;
        if (method === RGB_CONFIG) {
          if (!isRecord(data) || !own(data, "ambient") || !own(data, "keys")) {
            throw new TypeError("Expected both lighting zones");
          }
          validateFields(data.ambient);
          validateFields(data.keys);
          next = { ...previous, rgbcfg: data };
        } else {
          if (!Array.isArray(data)) throw new TypeError("Expected a thread update array");
          const slots = previous.thstatus.slice();
          for (const entry of data) {
            validateFields(entry);
            if (!own(entry, "id") || !Number.isInteger(entry.id) || entry.id < 0 || entry.id > 5) {
              throw new TypeError("Expected a thread id from 0 to 5");
            }
            slots[entry.id] = { ...slots[entry.id], ...entry };
          }
          next = { ...previous, thstatus: slots };
        }
        states.set(source, next);
        return { accepted: true, ready: ready(next) };
      } catch {
        states.set(source, emptyState());
        return { accepted: false, ready: false, error: "Unsupported lighting payload; source cache invalidated" };
      }
    },
    snapshot(source) {
      const state = get(source);
      return { ready: ready(state), ...cloneJson(state) };
    },
    restore(source) {
      const state = get(source);
      if (!ready(state)) return null;
      return [
        { method: RGB_CONFIG, params: cloneJson(state.rgbcfg) },
        { method: THREAD_STATUS, params: cloneJson(state.thstatus) },
      ];
    },
    reset(source) {
      get(source);
      states.set(source, emptyState());
    },
  };
}
