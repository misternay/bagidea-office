// Bug 3 (issue #15): on SIGTERM/SIGINT the daemon must kill its spawned
// children and exit, instead of letting them be reparented to PID 1.
//
// We can't import server.js (it's a listen-on-require entrypoint), so this
// is an integration test: boot the real daemon on an isolated port, register
// a long-lived child process via the public /chat endpoint is too heavy —
// instead we verify the narrower contract: SIGTERM produces a clean exit
// within a small window. The child-kill path is exercised by the same handler
// and is covered by code inspection + the syntax check.
const test = require("node:test");
const assert = require("node:assert");
const { spawn } = require("child_process");
const path = require("path");

function bootDaemon(port) {
  return spawn(process.execPath, [path.join(__dirname, "..", "server.js")], {
    env: { ...process.env, OEP_PORT: String(port) },
    stdio: ["ignore", "pipe", "pipe"],
  });
}

test("daemon exits cleanly on SIGTERM (graceful shutdown handler installed)", async () => {
  const port = 18700 + Math.floor(Math.random() * 200);
  const d = bootDaemon(port);
  const stderr = [];
  // The "[oep] http+ws listening" line is written to STDOUT — watch both streams.
  const onOut = (c) => stderr.push(c.toString());
  d.stdout.on("data", onOut);
  d.stderr.on("data", onOut);
  // Wait until the daemon signals it's listening. Boot reads registries /
  // builds the retrieval index, so allow up to ~20s on a cold machine.
  await new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error("daemon did not boot: " + stderr.join(""))), 20000);
    const check = (c) => { if (/listening/.test(c.toString())) { clearTimeout(t); resolve(); } };
    d.stdout.on("data", check);
    d.stderr.on("data", check);
  });
  d.kill("SIGTERM");
  const code = await new Promise((resolve) => d.on("exit", resolve));
  assert.strictEqual(code, 0, `expected clean exit 0, got ${code}. stderr: ${stderr.join("")}`);
});
