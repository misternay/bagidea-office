// Bug 4 (issue #15) — runtime hook wiring. The daemon must rewrite the
// workspace settings.json so the PreToolUse hook resolves to THIS install,
// regardless of platform, with no committed hard-coded path.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");
const os = require("os");
const { buildWorkspaceSettings, wireWorkspaceSettings } = require("../wire-hooks-runtime");

test("buildWorkspaceSettings emits node + the absolute perm.js path, no powershell/.ps1", () => {
  const json = buildWorkspaceSettings("/some/where/daemon/perm.js");
  const j = JSON.parse(json);
  const cmd = j.hooks.PreToolUse[0].hooks[0].command;
  assert.match(cmd, /^node\s+"\/some\/where\/daemon\/perm\.js"$/);
  assert.doesNotMatch(cmd, /powershell|\.ps1/i);
  assert.strictEqual(j.hooks.PreToolUse[0].hooks[0].timeout, 60);
});

test("wireWorkspaceSettings writes the resolved settings.json into a workspace dir", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "oep-wh-"));
  const workspaceDir = path.join(tmp, "workspace");
  const daemonDir = path.join(tmp, "daemon");
  fs.mkdirSync(workspaceDir, { recursive: true });
  fs.mkdirSync(daemonDir, { recursive: true });

  const wrote = wireWorkspaceSettings(workspaceDir, daemonDir);
  assert.strictEqual(wrote, true, "first call should write");
  const out = JSON.parse(fs.readFileSync(path.join(workspaceDir, ".claude", "settings.json"), "utf8"));
  const cmd = out.hooks.PreToolUse[0].hooks[0].command;
  assert.strictEqual(cmd, `node ${JSON.stringify(path.join(daemonDir, "perm.js"))}`);

  // Idempotent — second call is a no-op (no rewrite).
  const wrote2 = wireWorkspaceSettings(workspaceDir, daemonDir);
  assert.strictEqual(wrote2, false, "second call should be a no-op");

  fs.rmSync(tmp, { recursive: true, force: true });
});

test("wireWorkspaceSettings overwrites a stale placeholder (hooks: {})", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "oep-wh-"));
  const workspaceDir = path.join(tmp, "workspace");
  const daemonDir = path.join(tmp, "daemon");
  fs.mkdirSync(path.join(workspaceDir, ".claude"), { recursive: true });
  fs.mkdirSync(daemonDir, { recursive: true });
  // Simulate the committed placeholder.
  fs.writeFileSync(path.join(workspaceDir, ".claude", "settings.json"), JSON.stringify({ hooks: {} }, null, 2));

  const wrote = wireWorkspaceSettings(workspaceDir, daemonDir);
  assert.strictEqual(wrote, true);
  const out = JSON.parse(fs.readFileSync(path.join(workspaceDir, ".claude", "settings.json"), "utf8"));
  assert.match(out.hooks.PreToolUse[0].hooks[0].command, /^node\s/);

  fs.rmSync(tmp, { recursive: true, force: true });
});
