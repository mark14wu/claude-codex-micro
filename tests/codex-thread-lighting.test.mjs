import assert from "node:assert/strict";
import test from "node:test";
import { buildCodexThreadLighting } from "../scripts/lib/codex-thread-lighting.mjs";

function model() {
  return {
    brightness: 0.65,
    slots: ["working", "unread", "idle", "awaiting-approval", "awaiting-response", "error"]
      .map((status, id) => ({ id, status, selected: false, pulsing: false })),
  };
}

test("all active statuses produce the native palette and complete independent slot parameters", () => {
  assert.deepEqual(buildCodexThreadLighting(model()), {
    method: "v.oai.thstatus",
    params: [0x304ffe, 0x00ff4c, 0xffffff, 0xff6d00, 0xff6d00, 0xff0033]
      .map((c, id) => ({ id, c, b: 0.65, e: 1, s: 0, sk: 0, sa: 0 })),
  });
});

test("selection and pulsing independently request breathing; off overrides both flags", () => {
  for (const selected of [false, true]) {
    for (const pulsing of [false, true]) {
      const input = model();
      Object.assign(input.slots[0], { selected, pulsing });
      Object.assign(input.slots[1], { status: "off", selected, pulsing });
      const { params } = buildCodexThreadLighting(input);
      assert.deepEqual(params[0], {
        id: 0, c: 0x304ffe, b: 0.65, e: selected || pulsing ? 4 : 1,
        s: selected || pulsing ? 0.4 : 0, sk: 0, sa: 0,
      });
      assert.deepEqual(params[1], { id: 1, c: 0, b: 0, e: 0, s: 0, sk: 0, sa: 0 });
    }
  }
});

test("brightness is preserved including zero without changing active state or animation", () => {
  for (const brightness of [0, 0.001, 0.3, 0.65, 1]) {
    const input = model();
    input.brightness = brightness;
    input.slots[0].selected = true;
    const { params } = buildCodexThreadLighting(input);
    assert.ok(params.every((slot) => slot.b === brightness));
    assert.equal(params[0].e, 4);
    assert.equal(params[0].c, 0x304ffe);
  }
});

test("arbitrary slot order remains associated with IDs and metadata never reaches the device", () => {
  const input = model();
  input.slots = [4, 0, 5, 1, 3, 2].map((id) => ({
    ...input.slots[id], title: "private title", threadKey: "private identifier",
  }));
  Object.freeze(input);
  Object.freeze(input.slots);
  input.slots.forEach(Object.freeze);
  const result = buildCodexThreadLighting(input);
  assert.deepEqual(result.params.map((slot) => slot.id), [4, 0, 5, 1, 3, 2]);
  assert.deepEqual(result.params.map((slot) => slot.c), [0xff6d00, 0x304ffe, 0xff0033, 0x00ff4c, 0xff6d00, 0xffffff]);
  assert.ok(result.params.every((slot) => Object.keys(slot).join(",") === "id,c,b,e,s,sk,sa"));
  result.params[0].b = 0;
  assert.equal(buildCodexThreadLighting(input).params[0].b, 0.65);
});

test("unknown state and missing live fields cannot silently become idle, off, or unselected", () => {
  for (const key of ["id", "status", "selected", "pulsing"]) {
    const input = model();
    delete input.slots[3][key];
    assert.throws(() => buildCodexThreadLighting(input), TypeError, key);
  }
  for (const status of ["unknown", "running", "", null, undefined, 0, "__proto__", "toString"]) {
    const input = model();
    input.slots[3].status = status;
    assert.throws(() => buildCodexThreadLighting(input), TypeError);
  }
  for (const key of ["selected", "pulsing"]) {
    for (const value of [undefined, null, 0, 1, "false"]) {
      const input = model();
      input.slots[3][key] = value;
      assert.throws(() => buildCodexThreadLighting(input), TypeError);
    }
  }
});

test("invalid brightness and incomplete or duplicate rosters return no partial frame", () => {
  for (const brightness of [undefined, null, NaN, Infinity, -0.01, 1.01, "0.65"]) {
    assert.throws(() => buildCodexThreadLighting({ ...model(), brightness }), TypeError);
  }
  for (const change of [
    (input) => { delete input.brightness; },
    (input) => { delete input.slots; },
    (input) => { input.slots.pop(); },
    (input) => { input.slots.push({ ...input.slots[0] }); },
    (input) => { delete input.slots[2]; },
    (input) => { input.slots[2] = null; },
    (input) => { input.slots[2].id = 0; },
    (input) => { input.slots[2].id = -1; },
    (input) => { input.slots[2].id = 6; },
    (input) => { input.slots[2].id = 2.5; },
    (input) => { input.slots[2].id = "2"; },
  ]) {
    const input = model();
    change(input);
    assert.throws(() => buildCodexThreadLighting(input), TypeError);
  }
  for (const input of [null, [], new Date()]) {
    assert.throws(() => buildCodexThreadLighting(input), TypeError);
  }
});

test("accessor-backed required inputs are rejected without executing code", () => {
  const input = model();
  let called = false;
  Object.defineProperty(input.slots[0], "status", { get() { called = true; return "idle"; } });
  assert.throws(() => buildCodexThreadLighting(input), TypeError);
  assert.equal(called, false);
});
