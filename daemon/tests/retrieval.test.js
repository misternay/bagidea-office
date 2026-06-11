const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const R = require("../retrieval");

test("tokenize lowercases, drops stopwords + len<2", () => {
  const t = R.tokenize("The QUICK brown fox a");
  assert.ok(t.includes("quick") && t.includes("brown") && t.includes("fox"));
  assert.ok(!t.includes("the") && !t.includes("a"));
});

test("tokenize emits Thai char-bigrams for partial matching", () => {
  const t = R.tokenize("ออฟฟิศ");
  assert.ok(t.includes("ออฟฟิศ"));      // full run
  assert.ok(t.includes("ออ") && t.includes("อฟ")); // bigrams
});

test("search ranks the on-topic doc first and ignores unrelated", () => {
  R.clear();
  R.addDoc("mem", "shino", "mem:shino:0", "The owner prefers the deploy via the update banner on main");
  R.addDoc("mem", "shino", "mem:shino:1", "The office cat likes to nap near the recreation room");
  R.addDoc("mem", "shino", "mem:shino:2", "Right Ctrl is the default push to talk hotkey");
  const hits = R.search("how does deploy and the update banner work", { tiers: ["mem"], refs: { mem: "shino" }, k: 3 });
  assert.ok(hits.length >= 1);
  assert.strictEqual(hits[0].id, "mem:shino:0");
  assert.ok(!hits.some((h) => h.id === "mem:shino:1")); // cat doc shares no terms
});

test("empty query or empty index returns []", () => {
  R.clear();
  assert.deepStrictEqual(R.search("anything"), []);
  R.addDoc("mem", "x", "mem:x:0", "hello world");
  assert.deepStrictEqual(R.search("   "), []);
});

test("tier + ref filtering isolates an agent's memory", () => {
  R.clear();
  R.addDoc("mem", "shino", "mem:shino:0", "shared deploy knowledge here");
  R.addDoc("mem", "sahara", "mem:sahara:0", "shared deploy knowledge here");
  R.addDoc("user", "OFFICE", "user:OFFICE:0", "shared deploy knowledge here");
  const onlyShino = R.search("deploy knowledge", { tiers: ["mem"], refs: { mem: "shino" }, k: 9 });
  assert.deepStrictEqual(onlyShino.map((h) => h.id), ["mem:shino:0"]);
  const memPlusUser = R.search("deploy knowledge", { tiers: ["mem", "user"], refs: { mem: "shino", user: true }, k: 9 });
  assert.deepStrictEqual(memPlusUser.map((h) => h.id).sort(), ["mem:shino:0", "user:OFFICE:0"]);
});

test("addDoc is incremental and removeDocs(prefix) clears a ref", () => {
  R.clear();
  assert.deepStrictEqual(R.search("widget"), []);
  R.addDoc("proj", "p1", "proj:p1:0", "the widget pipeline ships nightly");
  assert.strictEqual(R.search("widget pipeline", { tiers: ["proj"], refs: { proj: "p1" } })[0].id, "proj:p1:0");
  R.removeDocs("proj:p1:");
  assert.deepStrictEqual(R.search("widget pipeline"), []);
});

test("reindexSkill indexes name+description; null removes it", () => {
  R.clear();
  R.reindexSkill("deep-research", { name: "Deep Research", description: "Methodical web research into a sourced brief" });
  assert.strictEqual(R.search("research brief", { tiers: ["skill"] })[0].id, "skill:deep-research");
  R.reindexSkill("deep-research", null);
  assert.deepStrictEqual(R.search("research brief", { tiers: ["skill"] }), []);
});

test("init() indexes memory / OFFICE / project files into the right tiers", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "bagidea-init-"));
  const memDir = path.join(root, "memory");
  const projDir = path.join(root, "projects", "p1");
  fs.mkdirSync(memDir, { recursive: true });
  fs.mkdirSync(projDir, { recursive: true });
  fs.writeFileSync(path.join(memDir, "shino.md"), "# mem\n\n- the owner ships on Fridays via the banner\n- shino likes short replies\n");
  fs.writeFileSync(path.join(memDir, "sahara.md"), "- sahara handles data wrangling tasks\n");
  fs.writeFileSync(path.join(root, "OFFICE.md"), "# Office\n\n- the company is WARRIX\n- prefer Thai in replies\n");
  fs.writeFileSync(path.join(projDir, "MEMORY.md"), "- the widget service deploys nightly at 2am\n");

  R.init({ memDir, officeMd: path.join(root, "OFFICE.md"), projectsDir: path.join(root, "projects"), skills: {} });

  // agent memory is isolated by ref
  const shino = R.search("owner ships banner", { tiers: ["mem"], refs: { mem: "shino" }, k: 5 });
  assert.ok(shino.length && shino[0].ref === "shino");
  assert.ok(!shino.some((h) => h.ref === "sahara"));
  // owner tier
  assert.strictEqual(R.search("WARRIX company", { tiers: ["user"], refs: { user: true } })[0].ref, "OFFICE");
  // project tier
  assert.strictEqual(R.search("widget nightly deploy", { tiers: ["proj"], refs: { proj: "p1" } })[0].ref, "p1");
  // combined query the way memoryNote does it (exact terms — BM25 has no stemming)
  const combo = R.search("banner widget WARRIX", { tiers: ["mem", "proj", "user"], refs: { mem: "shino", proj: "p1", user: true }, k: 6 });
  const tiersHit = new Set(combo.map((h) => h.tier));
  assert.ok(tiersHit.has("mem") && tiersHit.has("proj") && tiersHit.has("user"));

  fs.rmSync(root, { recursive: true, force: true });
});

test("persist + loadPersisted round-trips the corpus", () => {
  R.clear();
  R.addDoc("mem", "shino", "mem:shino:0", "alpha beta gamma delta");
  const f = path.join(os.tmpdir(), `bagidea-index-${process.pid}.json`);
  R.init({ indexFile: f }); // sets persistPath (clears) — re-add after
  R.addDoc("mem", "shino", "mem:shino:0", "alpha beta gamma delta");
  // force a synchronous write by calling the internal persist then waiting via fs
  R.persist();
  return new Promise((resolve) => setTimeout(() => {
    assert.ok(fs.existsSync(f), "index file written");
    R.clear();
    assert.deepStrictEqual(R.search("alpha"), []);
    assert.strictEqual(R.loadPersisted(), true);
    assert.strictEqual(R.search("gamma", { tiers: ["mem"] })[0].id, "mem:shino:0");
    fs.unlinkSync(f);
    resolve();
  }, 1800));
});
