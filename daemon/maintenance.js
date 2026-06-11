// BagIdea Office — boot housekeeping (P0).
// Pure, dependency-free helpers that keep a long-running office from
// accumulating forever: journal.jsonl rotation + sessions.json pruning.
// The decision logic is split out as pure functions so it is unit-testable
// without booting the daemon; the IO wrappers only read/write files.

const fs = require("fs");

// journal.jsonl is append-only and replay only ever reads the last
// REPLAY_COUNT (80) lines, so keeping the last few thousand is plenty of
// history while bounding the file + the full-file read on every reconnect.
const JOURNAL_MAX = 5000;
// Session threads: drop ones untouched for a month, and cap how many we keep
// per agent — but ALWAYS keep each agent's latest thread (continuous memory).
const SESS_MAX_AGE_DAYS = 30;
const SESS_MAX_THREADS = 40;
const DAY_MS = 86400000;

// Pure: keep at most `max` lines, newest (tail) wins.
function trimLines(lines, max) {
  return lines.length > max ? lines.slice(-max) : lines;
}

// Side-effecting: rotate journal.jsonl in place if it exceeds `max` lines.
// Atomic (tmp + rename) so a crash mid-write never corrupts the journal.
// Returns {rotated, before, kept}. Missing file is a no-op.
function rotateJournal(journalPath, max = JOURNAL_MAX) {
  let raw;
  try {
    raw = fs.readFileSync(journalPath, "utf8");
  } catch (e) {
    if (e.code === "ENOENT") return { rotated: false, before: 0, kept: 0 };
    throw e;
  }
  const lines = raw.split("\n").filter((l) => l.length); // drop blank/trailing
  const before = lines.length;
  if (before <= max) return { rotated: false, before, kept: before };
  const kept = trimLines(lines, max);
  const tmp = journalPath + ".tmp";
  fs.writeFileSync(tmp, kept.join("\n") + "\n");
  fs.renameSync(tmp, journalPath);
  return { rotated: true, before, kept: kept.length };
}

// Pure: prune a sessions map ({agent: [thread,...]}). For each agent keep the
// latest thread unconditionally, plus other threads that are newer than the
// age cutoff, capped to `maxThreads` total (newest first). Never mutates the
// input. Returns {sess, changed, dropped}.
function pruneSessions(sess, opts = {}) {
  const maxAgeDays = opts.maxAgeDays != null ? opts.maxAgeDays : SESS_MAX_AGE_DAYS;
  const maxThreads = opts.maxThreads != null ? opts.maxThreads : SESS_MAX_THREADS;
  const now = opts.now != null ? opts.now : Date.now();
  const cutoff = now - maxAgeDays * DAY_MS;
  const out = {};
  let changed = false;
  let dropped = 0;
  for (const agent of Object.keys(sess || {})) {
    const list = Array.isArray(sess[agent]) ? sess[agent] : [];
    if (list.length <= 1) { out[agent] = list; continue; }
    const sorted = [...list].sort((a, b) => (b.ts || 0) - (a.ts || 0));
    const latest = sorted[0];
    const kept = [];
    for (const t of sorted) {
      if (t === latest) { kept.push(t); continue; }      // latest always survives
      if ((t.ts || 0) >= cutoff && kept.length < maxThreads) kept.push(t);
    }
    if (kept.length !== list.length) { changed = true; dropped += list.length - kept.length; }
    out[agent] = kept;
  }
  return { sess: out, changed, dropped };
}

module.exports = {
  JOURNAL_MAX, SESS_MAX_AGE_DAYS, SESS_MAX_THREADS,
  trimLines, rotateJournal, pruneSessions,
};
