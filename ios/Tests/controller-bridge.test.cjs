const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

function makeRuntime() {
  const events = [];
  const log = [];
  const nodes = { loading: null };
  const window = {
    dispatchEvent(event) { events.push([event.type, event.code]); },
    addEventListener() {},
    webkit: { messageHandlers: { gtaDiagnostics: { postMessage(m) { log.push(m); } } } }
  };
  const document = { getElementById: name => nodes[name] || null, pointerLockElement: null };
  class KeyboardEvent {
    constructor(type, options) { this.type = type; this.code = options.code; }
  }
  const context = {
    window, document, SharedArrayBuffer, Atomics, KeyboardEvent,
    console: { warn() {}, info() {} }, Number, Set, Math, Object
  };
  const file = path.join(__dirname, "../Bridge/controller-bridge.js");
  vm.runInNewContext(fs.readFileSync(file, "utf8"), context);
  const memory = new SharedArrayBuffer(512);
  const keys = new Uint8Array(memory, 0, 256);
  const words = new Int32Array(memory, 256, 10);
  window.GTAInputBridge.attach(keys, words);
  return { bridge: window.GTAInputBridge, window, events, log, words, nodes };
}

test("Native analog axes are preserved and right-stick sends actual shared mouse deltas", () => {
  const t = makeRuntime();
  t.bridge.update({ connected: 1, rx: 0.7, ry: 0.5, lx: 0.3, ly: -0.25 });
  assert.equal(t.window.__gtaPadAxes.rx, 0.7);
  assert.equal(t.window.__gtaPadAxes.lx, 0.3);
  assert.ok(Atomics.load(t.words, 2) > 0);
  assert.ok(Atomics.load(t.words, 3) < 0);
  assert.equal(Atomics.load(t.words, 6), 1);
  assert.equal(Atomics.load(t.words, 7), 1);
});

test("Face buttons generate only transitions and release cleanly", () => {
  const t = makeRuntime();
  const active = { connected: 1, y: 1, a: 1 };
  t.bridge.update(active);
  t.bridge.update(active);
  const downs = t.events.filter(e => e[0] === "keydown" && e[1] === "KeyF");
  assert.equal(downs.length, 1);
  t.bridge.update({ connected: 1 });
  assert.ok(t.events.some(e => e[0] === "keyup" && e[1] === "KeyF"));
});

test("Trigger and aim update WASM mouse-button bitfield and disconnect releases it", () => {
  const t = makeRuntime();
  t.bridge.update({ connected: 1, rt: 1, lt: 0.5 });
  assert.equal(Atomics.load(t.words, 5) & 3, 3);
  t.bridge.update({ connected: 0 });
  assert.equal(Atomics.load(t.words, 5) & 3, 0);
});

test("Custom remapping feeds the existing keyboard input ABI", () => {
  const t = makeRuntime();
  t.bridge.setMappings({ a: "KeyE", y: "" });
  t.bridge.update({ connected: 1, a: 1, y: 1 });
  assert.ok(t.events.some(e => e[0] === "keydown" && e[1] === "KeyE"));
  assert.equal(t.events.filter(e => e[0] === "keydown" && e[1] === "KeyF").length, 0);
});

test("Driving and aircraft profiles dispatch distinct bindings", () => {
  const t = makeRuntime();
  t.bridge.setProfile("drive");
  t.bridge.update({ connected: 1, rt: 0.7 });
  assert.ok(t.events.some(e => e[0] === "keydown" && e[1] === "KeyW"));
  t.bridge.setProfile("air");
  t.bridge.update({ connected: 1, ry: 0.9 });
  assert.ok(t.events.some(e => e[0] === "keydown" && e[1] === "Numpad8"));
});

test("Loading UI receives directional and accept input", () => {
  const t = makeRuntime();
  t.nodes.loading = { classList: { contains() { return false; } } };
  t.bridge.update({ connected: 1, up: 1, a: 1 });
  assert.ok(t.events.some(e => e[0] === "keydown" && e[1] === "ArrowUp"));
  assert.ok(t.events.some(e => e[0] === "keydown" && e[1] === "Enter"));
});
