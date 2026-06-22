// Bug 2 (issue #15): the proxy must not hold a connection open forever when
// the upstream hangs. These tests pin fetchWithTimeout's observable contract:
// aborts on timeout, resolves when upstream answers, and still honors an
// external abort (client drop) faster than the timeout.
const test = require("node:test");
const assert = require("node:assert");
const http = require("http");
const { fetchWithTimeout } = require("../proxy");

function hangServer() {
  return new Promise((r) => {
    const srv = http.createServer(() => { /* never respond */ });
    srv.listen(0, "127.0.0.1", () => r(srv));
  });
}

function echoServer(body, status = 200) {
  return new Promise((r) => {
    const srv = http.createServer((req, res) => {
      res.writeHead(status, { "content-type": "application/json" });
      res.end(body);
    });
    srv.listen(0, "127.0.0.1", () => r(srv));
  });
}

test("fetchWithTimeout aborts when the upstream hangs past the timeout", async () => {
  const srv = await hangServer();
  const url = `http://127.0.0.1:${srv.address().port}/v1/chat/completions`;
  const start = Date.now();
  await assert.rejects(
    () => fetchWithTimeout(url, { method: "POST", body: "{}" }, 300),
    /aborted|timeout/i,
  );
  const elapsed = Date.now() - start;
  assert.ok(elapsed >= 250 && elapsed < 2000, `timeout fired too early/late: ${elapsed}ms`);
  srv.close();
});

test("fetchWithTimeout returns the response when the upstream answers in time", async () => {
  const srv = await echoServer(JSON.stringify({ ok: true }));
  const url = `http://127.0.0.1:${srv.address().port}/v1/chat/completions`;
  const r = await fetchWithTimeout(url, { method: "POST", body: "{}" }, 5000);
  assert.strictEqual(r.status, 200);
  const j = await r.json();
  assert.strictEqual(j.ok, true);
  srv.close();
});

test("fetchWithTimeout respects an external abort signal (client drop)", async () => {
  const srv = await hangServer();
  const url = `http://127.0.0.1:${srv.address().port}/v1/chat/completions`;
  const external = new AbortController();
  const p = fetchWithTimeout(url, { method: "POST", body: "{}", signal: external.signal }, 30000);
  setTimeout(() => external.abort(), 100);
  await assert.rejects(() => p, /aborted/i);
  srv.close();
});
