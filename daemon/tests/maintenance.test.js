const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { trimLines, rotateJournal, pruneSessions } = require("../maintenance");

test("trimLines keeps the newest N", () => {
  assert.deepStrictEqual(trimLines([1, 2, 3, 4, 5], 3), [3, 4, 5]);
  assert.deepStrictEqual(trimLines([1, 2], 5), [1, 2]); // under cap = untouched
});

test("rotateJournal trims an oversized file to the tail, atomically", () => {
  const f = path.join(os.tmpdir(), `bagidea-journal-${process.pid}.jsonl`);
  const lines = Array.from({ length: 100 }, (_, i) => JSON.stringify({ n: i }));
  fs.writeFileSync(f, lines.join("\n") + "\n");
  const r = rotateJournal(f, 10);
  assert.strictEqual(r.rotated, true);
  assert.strictEqual(r.before, 100);
  assert.strictEqual(r.kept, 10);
  const kept = fs.readFileSync(f, "utf8").split("\n").filter(Boolean);
  assert.strictEqual(kept.length, 10);
  assert.deepStrictEqual(JSON.parse(kept[0]), { n: 90 }); // last 10 = 90..99
  assert.deepStrictEqual(JSON.parse(kept[9]), { n: 99 });
  fs.unlinkSync(f);
});

test("rotateJournal is a no-op under the cap and for a missing file", () => {
  const f = path.join(os.tmpdir(), `bagidea-journal-small-${process.pid}.jsonl`);
  fs.writeFileSync(f, "a\nb\nc\n");
  assert.strictEqual(rotateJournal(f, 10).rotated, false);
  assert.strictEqual(fs.readFileSync(f, "utf8"), "a\nb\nc\n"); // untouched
  fs.unlinkSync(f);
  assert.deepStrictEqual(rotateJournal(f, 10), { rotated: false, before: 0, kept: 0 });
});

test("pruneSessions drops stale threads but always keeps the latest", () => {
  const now = 1_000 * 86400000; // a fixed 'now' in ms
  const day = 86400000;
  const sess = {
    shino: [
      { key: "old", ts: now - 60 * day },   // stale → dropped (not latest)
      { key: "mid", ts: now - 10 * day },    // fresh → kept
      { key: "new", ts: now - 1 * day },     // latest → kept
    ],
    sahara: [
      { key: "ancient", ts: now - 365 * day }, // sole thread, stale → KEPT (latest)
    ],
  };
  const { sess: out, changed, dropped } = pruneSessions(sess, { now, maxAgeDays: 30, maxThreads: 40 });
  assert.strictEqual(changed, true);
  assert.strictEqual(dropped, 1);
  assert.deepStrictEqual(out.shino.map((t) => t.key).sort(), ["mid", "new"]);
  assert.deepStrictEqual(out.sahara.map((t) => t.key), ["ancient"]); // latest survives even if ancient
});

test("pruneSessions caps thread count, newest first, latest always in", () => {
  const now = 1_000 * 86400000;
  const day = 86400000;
  const list = Array.from({ length: 50 }, (_, i) => ({ key: `t${i}`, ts: now - i * 60 * 1000 }));
  const { sess: out } = pruneSessions({ a: list }, { now, maxAgeDays: 3650, maxThreads: 40 });
  assert.strictEqual(out.a.length, 40);
  assert.ok(out.a.some((t) => t.key === "t0")); // newest kept
});

test("pruneSessions leaves a single-thread / empty agent alone", () => {
  const r = pruneSessions({ a: [{ key: "only", ts: 1 }], b: [] }, { now: 9e15 });
  assert.strictEqual(r.changed, false);
  assert.deepStrictEqual(r.sess.a.map((t) => t.key), ["only"]);
});
