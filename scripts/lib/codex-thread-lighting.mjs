// Pure per-key rendering for the inspected Codex 26.930.61225 behavior.
// This does not discover sessions, infer missing state, or communicate with HID.
const COLORS = Object.freeze({
  working: 0x304ffe,
  unread: 0x00ff4c,
  idle: 0xffffff,
  "awaiting-approval": 0xff6d00,
  "awaiting-response": 0xff6d00,
  error: 0xff0033,
  off: 0,
});

function record(value, name) {
  if (value === null || typeof value !== "object" || Array.isArray(value)
    || ![Object.prototype, null].includes(Object.getPrototypeOf(value))) {
    throw new TypeError(`${name} must be a plain object`);
  }
}

function field(value, key, name) {
  const descriptor = Object.getOwnPropertyDescriptor(value, key);
  if (!descriptor || !Object.hasOwn(descriptor, "value")) {
    throw new TypeError(`${name}.${key} must be explicit data`);
  }
  return descriptor.value;
}

/**
 * Render a complete, explicit six-slot model to one v.oai.thstatus command.
 *
 * Input: {brightness: number 0..1, slots: [{id: 0..5, status, selected, pulsing}]}.
 * All six IDs must occur exactly once. Both flags must be explicit booleans;
 * collectors must distinguish known false from unavailable live state.
 * Unknown or incomplete inputs throw before any command is returned.
 * Additional metadata is ignored; it is never copied into the wire parameters.
 * Slot order is preserved, as in the native renderer. Inputs are not mutated.
 *
 * A successful return establishes per-key rendering only. It does not establish
 * roster accuracy, freshness, origin, transport ownership, zone state, inactivity
 * timing, or permission to send a frame. In particular, missing live state must
 * never be replaced with synthetic idle/off values to call this function.
 */
export function buildCodexThreadLighting(model) {
  record(model, "model");
  const brightness = field(model, "brightness", "model");
  if (typeof brightness !== "number" || !Number.isFinite(brightness)
    || brightness < 0 || brightness > 1) {
    throw new TypeError("model.brightness must be a finite number from 0 to 1");
  }
  const slots = field(model, "slots", "model");
  if (!Array.isArray(slots) || slots.length !== 6) {
    throw new TypeError("model.slots must contain exactly six slots");
  }
  const ids = new Set();
  const params = [];
  for (let index = 0; index < 6; index += 1) {
    const name = `model.slots[${index}]`;
    const slot = field(slots, String(index), "model.slots");
    record(slot, name);
    const id = field(slot, "id", name);
    const status = field(slot, "status", name);
    const selected = field(slot, "selected", name);
    const pulsing = field(slot, "pulsing", name);
    if (!Number.isInteger(id) || id < 0 || id > 5 || ids.has(id)) {
      throw new TypeError(`${name}.id must be a unique integer from 0 to 5`);
    }
    if (typeof status !== "string" || !Object.hasOwn(COLORS, status)) {
      throw new TypeError(`${name}.status is unknown`);
    }
    if (typeof selected !== "boolean" || typeof pulsing !== "boolean") {
      throw new TypeError(`${name}.selected and pulsing must be explicit booleans`);
    }
    ids.add(id);
    const off = status === "off";
    const breathing = !off && (selected || pulsing);
    params.push({
      id,
      c: COLORS[status],
      b: off ? 0 : brightness,
      e: off ? 0 : breathing ? 4 : 1,
      s: breathing ? 0.4 : 0,
      sk: 0,
      sa: 0,
    });
  }
  return { method: "v.oai.thstatus", params };
}
