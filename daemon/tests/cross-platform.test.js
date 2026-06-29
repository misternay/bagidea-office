// Unit tests for the cross-platform compatibility work.
// Pure (no daemon required): AppleScript marker escaping, marker extraction
// regex, and the SEP()/platform-default logic. The /platform and
// /fs/native-pick endpoints are integration-tested in api.test.js against a
// running daemon.
const test = require("node:test");
const assert = require("node:assert");

// ── AppleScript double-quoted-string escape ────────────────────────────
// Mirrors the asEsc helper inlined in daemon/server.js (macOS Terminal launch).
// Backslash first (so we don't double-escape the dquotes we inject), then dquote.
const asEsc = (s) => String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"');

test("asEsc: plain string passes through unchanged", () => {
  assert.strictEqual(asEsc("BAGIDEA_PROJ_p123"), "BAGIDEA_PROJ_p123");
});

test("asEsc: double quotes are escaped", () => {
  // A project title like My "Cool" App must not break the AppleScript string.
  assert.strictEqual(asEsc('My "Cool" App'), 'My \\"Cool\\" App');
});

test("asEsc: backslash is escaped first (no double-escape of injected dquotes)", () => {
  // path\with\slash → path\\with\\slash  (NOT path\\with\\slash with dquotes mangled)
  assert.strictEqual(asEsc("path\\with\\slash"), "path\\\\with\\\\slash");
});

test("asEsc: mixed backslash + dquote is safe", () => {
  // Input (real string): C:\dev\"x"
  // Step 1 escape backslash → C:\\dev\\"x"   (each \ becomes \\)
  // Step 2 escape dquote   → C:\\dev\\\"x\"
  // In JS source: 2 real backslashes = \\\\, 1 real backslash = \\\\… count carefully.
  // Real result: C: \\ dev \\ \" x \"
  const input = "C:" + "\\" + "dev" + "\\" + '"' + "x" + '"';   // C:\dev\"x"
  const expected = "C:" + "\\\\" + "dev" + "\\\\" + '\\"' + "x" + '\\"'; // C:\\dev\\\"x\"
  assert.strictEqual(asEsc(input), expected);
});

test("asEsc: empty string and non-string coerce safely", () => {
  assert.strictEqual(asEsc(""), "");
  assert.strictEqual(asEsc(undefined), "undefined");
  assert.strictEqual(asEsc(null), "null");
});

// ── Marker extraction (mirrors server.js macOS launch branch) ──────────
// innerCmd may contain a #BAGIDEA_PROJ_<id> marker comment; we extract it,
// falling back to the caller-supplied title.
function extractMarker(innerCmd, title) {
  return (innerCmd.match(/#(BAGIDEA_PROJ_[\w-]+)/) || [])[1] || title;
}

test("extractMarker: pulls BAGIDEA_PROJ id from trailing comment", () => {
  const inner = 'cd /Users/me/proj && claude #BAGIDEA_PROJ_p1700000000_0';
  assert.strictEqual(extractMarker(inner, "fallback"), "BAGIDEA_PROJ_p1700000000_0");
});

test("extractMarker: falls back to title when no marker present", () => {
  assert.strictEqual(extractMarker("cd /x && claude", "My Project"), "My Project");
});

test("extractMarker: falls back to title on empty command", () => {
  assert.strictEqual(extractMarker("", "T"), "T");
});

test("extractMarker: marker with dashes in id is captured", () => {
  const inner = 'claude #BAGIDEA_PROJ_p-abc-123';
  assert.strictEqual(extractMarker(inner, "x"), "BAGIDEA_PROJ_p-abc-123");
});

test("extractMarker: only the first marker is captured", () => {
  const inner = 'claude #BAGIDEA_PROJ_first #BAGIDEA_PROJ_second';
  assert.strictEqual(extractMarker(inner, "x"), "BAGIDEA_PROJ_first");
});

// ── Shell single-quote escape (mirrors server.js esc()) ────────────────
const esc = (s) => s.replace(/'/g, "'\\''");

test("esc: no single quotes passes through", () => {
  assert.strictEqual(esc("/Users/me/my app"), "/Users/me/my app");
});

test("esc: single quote becomes close-quote-escaped-quote-reopen", () => {
  // O'Brien → O'\''Brien
  assert.strictEqual(esc("O'Brien"), "O'\\''Brien");
});

test("esc: multiple single quotes all escaped", () => {
  assert.strictEqual(esc("a'b'c"), "a'\\''b'\\''c");
});

// ── Platform default + SEP() logic (mirrors overlay.html) ──────────────
// The client guesses platform before /platform resolves. The guess must
// produce a sensible sep for every browser. We model the logic here.
function guessPlat(navigatorPlatform) {
  const guess = /Win/.test(navigatorPlatform) ? "win32" : "darwin";
  return { platform: guess, sep: guess === "win32" ? "\\" : "/" };
}

test("guessPlat: Windows browser → backslash sep", () => {
  const p = guessPlat("Win32");
  assert.strictEqual(p.platform, "win32");
  assert.strictEqual(p.sep, "\\");
});

test("guessPlat: Mac browser → forward slash sep", () => {
  const p = guessPlat("MacIntel");
  assert.strictEqual(p.platform, "darwin");
  assert.strictEqual(p.sep, "/");
});

test("guessPlat: Linux browser → forward slash sep (NOT backslash)", () => {
  // Regression: the first version of the cross-platform change defaulted
  // non-Mac to win32/\\, which gave Linux a backslash sep until /platform
  // resolved. The fix defaults non-Win to darwin//.
  const p = guessPlat("Linux x86_64");
  assert.strictEqual(p.sep, "/");
});

test("guessPlat: empty/deprecated platform still safe", () => {
  // navigator.platform is deprecated and may return "" on some browsers.
  const p = guessPlat("");
  assert.strictEqual(p.sep, "/");  // non-Win default — safe for macOS+Linux
});

// SEP() reads _plat.sep lazily, with "/" as the ultimate fallback.
function makeSEP(plat) { return () => plat.sep || "/"; }

test("SEP: returns server sep when set", () => {
  const SEP = makeSEP({ sep: "\\" });
  assert.strictEqual(SEP(), "\\");
});

test("SEP: falls back to / when sep missing", () => {
  const SEP = makeSEP({});
  assert.strictEqual(SEP(), "/");
});

// ── pickFolder fallback decision (mirrors overlay.html pickFolder) ──────
// The fix distinguishes 404 (no native picker → fall back) from 200 with
// null path (user cancelled → resolve null). We model the decision table.
function pickOutcome(httpStatus, path) {
  if (httpStatus === 404 || httpStatus === 500) return "fallback";
  if (httpStatus === 200) return path ? path : null;  // null = cancelled
  return "fallback";
}

test("pickOutcome: 404 → fallback (e.g. Linux without zenity)", () => {
  assert.strictEqual(pickOutcome(404, null), "fallback");
});

test("pickOutcome: 200 with path → the picked path", () => {
  assert.strictEqual(pickOutcome(200, "/Users/me/proj"), "/Users/me/proj");
});

test("pickOutcome: 200 with null → null (user cancelled, NOT fallback)", () => {
  // Regression: the first version fell back to the in-house picker on
  // cancel, forcing the user to cancel twice.
  assert.strictEqual(pickOutcome(200, null), null);
});

test("pickOutcome: 500 → fallback (server error)", () => {
  assert.strictEqual(pickOutcome(500, null), "fallback");
});
