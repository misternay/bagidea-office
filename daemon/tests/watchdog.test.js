// Bug 1 (issue #15): a main runClaude() call must not sit in the "started"
// state forever when the CLI is stuck retrying a hung upstream. These tests
// pin RunWatchdog's observable contract: fires on idle (no progress), fires
// on total cap, stays quiet while progress flows, and clears cleanly.
const test = require("node:test");
const assert = require("node:assert");
const { RunWatchdog } = require("../watchdog");

// Use tiny millisecond windows so tests are fast. The watchdog treats the
// limits as wall-clock, so we wait just past them to observe the kill.
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

test("RunWatchdog fires onKill when no progress for longer than the idle window", async () => {
  let killed = null;
  const w = new RunWatchdog({ totalMs: 60000, idleMs: 150, onKill: (reason) => { killed = reason; } });
  w.start();
  await wait(280);
  assert.ok(killed, "did not fire onKill after idle window elapsed");
  assert.match(killed, /idle/i);
  w.clear();
});

test("RunWatchdog does NOT fire while progress keeps the run active", async () => {
  let killed = null;
  const w = new RunWatchdog({ totalMs: 60000, idleMs: 150, onKill: (reason) => { killed = reason; } });
  w.start();
  // Touch every 80ms — well inside the 150ms idle window.
  for (let i = 0; i < 5; i++) { await wait(80); w.touch(); }
  assert.strictEqual(killed, null);
  w.clear();
});

test("RunWatchdog fires onKill when totalMs is exceeded even with progress", async () => {
  let killed = null;
  const w = new RunWatchdog({ totalMs: 250, idleMs: 60000, onKill: (reason) => { killed = reason; } });
  w.start();
  for (let i = 0; i < 4; i++) { await wait(70); w.touch(); }   // stay busy
  assert.ok(killed, "did not fire onKill after total cap");
  assert.match(killed, /total/i);
  w.clear();
});

test("RunWatchdog.clear() cancels the timers (no late fire)", async () => {
  let killed = null;
  const w = new RunWatchdog({ totalMs: 100, idleMs: 100, onKill: (reason) => { killed = reason; } });
  w.start();
  w.clear();
  await wait(250);
  assert.strictEqual(killed, null);
});

test("RunWatchdog is a no-op re-fire after onKill already fired", async () => {
  let count = 0;
  const w = new RunWatchdog({ totalMs: 80, idleMs: 60000, onKill: () => { count++; } });
  w.start();
  await wait(150);
  w.touch();                 // late touch should not re-arm
  await wait(150);
  assert.strictEqual(count, 1);
});
