import assert from "node:assert/strict";
import test from "node:test";
import { createNativeLightingState } from "../scripts/lib/native-lighting-state.mjs";

const RGB = "v.oai.rgbcfg";
const THREADS = "v.oai.thstatus";
const zones = () => ({
  ambient: { c: 0x030201, b: 0.75, e: 5, s: 0.3, m: { future: [1, null] } },
  keys: { c: 0x040506, b: 0.5, e: 4, s: 0.25, m: 7 },
  firmwareExtension: { enabled: false },
});
const slots = () => Array.from({ length: 6 }, (_, id) => ({
  id, c: 0x123400 + id, b: id / 6, e: id + 10, s: 0.2, sk: id % 2, sa: 0,
  future: { values: [id, "unchanged"] },
}));
function populate(cache, source = "codex") {
  cache.observe(source, RGB, zones());
  cache.observe(source, THREADS, slots());
}

test("restore requires both complete zones and all six complete slots; it invents no colors", () => {
  const cache = createNativeLightingState();
  assert.equal(cache.restore("codex"), null);
  cache.observe("codex", RGB, zones());
  cache.observe("codex", THREADS, slots().slice(0, 5));
  assert.equal(cache.snapshot("codex").ready, false);
  assert.equal(cache.restore("codex"), null);
  const { sa, ...partial } = slots()[5];
  cache.observe("codex", THREADS, [partial]);
  assert.equal(cache.restore("codex"), null);
  assert.deepEqual(cache.observe("codex", THREADS, [{ id: 5, sa }]), { accepted: true, ready: true });
  assert.deepEqual(cache.restore("codex"), [
    { method: RGB, params: zones() }, { method: THREADS, params: slots() },
  ]);
});

test("every required native field gates readiness, including zero-valued fields", () => {
  for (const field of ["c", "b", "e", "s", "sk", "sa"]) {
    const cache = createNativeLightingState();
    const entries = slots();
    delete entries[2][field];
    cache.observe("codex", RGB, zones());
    cache.observe("codex", THREADS, entries);
    assert.equal(cache.restore("codex"), null, field);
    cache.observe("codex", THREADS, [{ id: 2, [field]: 0 }]);
    assert.equal(cache.snapshot("codex").ready, true, field);
  }
  for (const side of ["ambient", "keys"]) {
    for (const field of ["c", "b", "e", "s", "m"]) {
      const cache = createNativeLightingState();
      const params = zones();
      delete params[side][field];
      cache.observe("codex", THREADS, slots());
      cache.observe("codex", RGB, params);
      assert.equal(cache.restore("codex"), null, `${side}.${field}`);
    }
  }
});

test("partial slot updates merge by id and preserve unknown fields without deriving a palette", () => {
  const cache = createNativeLightingState();
  populate(cache);
  const update = [{ id: 4, b: 0 }, { id: 1, c: 0xff0011, future: { replacement: true } }, { id: 4, s: 1 }];
  cache.observe("codex", THREADS, update);
  const expected = slots();
  expected[4] = { ...expected[4], b: 0, s: 1 };
  expected[1] = { ...expected[1], c: 0xff0011, future: { replacement: true } };
  assert.deepEqual(cache.restore("codex")[1].params, expected);
});

test("rgbcfg replaces both zones including unknown fields instead of leaking the previous configuration", () => {
  const cache = createNativeLightingState();
  populate(cache);
  const replacement = zones();
  delete replacement.firmwareExtension;
  replacement.keys.m = null;
  cache.observe("codex", RGB, replacement);
  assert.deepEqual(cache.restore("codex")[0].params, replacement);
  cache.observe("codex", RGB, { ambient: {}, keys: {} });
  assert.equal(cache.restore("codex"), null);
});

test("inputs, snapshots, restore commands and shared nested objects never alias the cache", () => {
  const cache = createNativeLightingState();
  const shared = { data: [1] };
  const params = zones();
  params.ambient.extra = shared;
  params.keys.extra = shared;
  const entries = slots();
  const before = structuredClone({ params, entries });
  cache.observe("codex", RGB, params);
  cache.observe("codex", THREADS, entries);
  assert.deepEqual({ params, entries }, before);
  shared.data.push(2);
  entries[0].future.values[0] = 99;
  const snapshot = cache.snapshot("codex");
  assert.deepEqual(snapshot.rgbcfg, before.params);
  assert.deepEqual(snapshot.thstatus, before.entries);
  snapshot.rgbcfg.ambient.extra.data.push(3);
  assert.deepEqual(snapshot.rgbcfg.keys.extra.data, [1]);
  snapshot.thstatus[0].c = 0;
  const commands = cache.restore("codex");
  commands[0].params.keys.c = 0;
  commands[1].params[0].future.values.push("mutated");
  assert.deepEqual(cache.snapshot("codex"), { ready: true, rgbcfg: before.params, thstatus: before.entries });
});

test("Codex continues updating in the background independently of Claude restores", () => {
  const cache = createNativeLightingState();
  populate(cache, "codex");
  populate(cache, "claude");
  cache.observe("claude", THREADS, [{ id: 0, c: 0xabcdef, e: 6 }]);
  const claude = cache.restore("claude");
  cache.observe("codex", THREADS, [{ id: 0, c: 0xfedcba, e: 3 }]);
  assert.deepEqual(cache.restore("claude"), claude);
  assert.equal(cache.restore("codex")[1].params[0].c, 0xfedcba);
  cache.reset("codex");
  assert.equal(cache.restore("codex"), null);
  assert.deepEqual(cache.restore("claude"), claude);
});

test("unsupported methods and sources cannot corrupt valid caches", () => {
  const cache = createNativeLightingState();
  populate(cache);
  const before = cache.snapshot("codex");
  assert.equal(cache.observe("codex", "device.reset", {}).accepted, false);
  assert.equal(cache.observe("other", THREADS, slots()).accepted, false);
  assert.deepEqual(cache.snapshot("codex"), before);
  assert.throws(() => cache.snapshot("other"), /Unknown lighting source/);
});

test("unsupported payloads never throw into the original call and invalidate only their source", () => {
  const cyclic = {}; cyclic.self = cyclic;
  const accessor = { id: 0 };
  Object.defineProperty(accessor, "c", { enumerable: true, get() { throw new Error("must not execute"); } });
  const cases = [
    [RGB, null], [RGB, { ambient: {} }], [RGB, { ambient: [], keys: {} }],
    [THREADS, {}], [THREADS, [null]], [THREADS, [{ id: 6 }]], [THREADS, [{ id: -1 }]],
    [THREADS, [{ id: "0" }]], [THREADS, [{ id: 0, c: 0x1000000 }]],
    [THREADS, [{ id: 0, b: 2 }]], [THREADS, [{ id: 0, sk: true }]],
    [THREADS, [{ id: 0, future: undefined }]], [THREADS, [{ id: 0, future: NaN }]],
    [THREADS, [{ id: 0, future: cyclic }]], [THREADS, [accessor]],
    [THREADS, [{ id: 0, future: new Date() }]], [THREADS, new Array(1)],
  ];
  for (const [method, params] of cases) {
    const cache = createNativeLightingState();
    populate(cache, "codex");
    populate(cache, "claude");
    // An observer must return normally even when the original native payload
    // cannot be cached. Actual forwarding is the separate transport's job.
    let capture;
    assert.doesNotThrow(() => { capture = cache.observe("codex", method, params); });
    assert.equal(capture.accepted, false);
    assert.equal(cache.restore("codex"), null);
    assert.equal(cache.snapshot("claude").ready, true);
    populate(cache, "codex");
    assert.equal(cache.snapshot("codex").ready, true);
  }
});

test("JSON extension properties named __proto__ round trip without changing object prototypes", () => {
  const cache = createNativeLightingState();
  populate(cache);
  const entry = JSON.parse('{"id":0,"__proto__":{"nativeField":1}}');
  cache.observe("codex", THREADS, [entry]);
  const restored = cache.restore("codex")[1].params[0];
  assert.equal(Object.getPrototypeOf(restored), Object.prototype);
  assert.deepEqual(restored.__proto__, { nativeField: 1 });
  assert.equal(Object.hasOwn(restored, "__proto__"), true);
});
