// BagIdea AI Agents Office — daemon v3 (Layer 0).
// Zero-dependency event hub + Claude Code adapter + permission broker:
//   HTTP :8787  GET  /              → Layer-2 overlay (chat panel web app)
//   WS   :8787  GET  /ws (upgrade)  → event stream for renderers + overlays
//                                      (new clients get a journal replay first)
//               POST /chat          → spawn a real Claude Code session
//               POST /event         → adapters push events (hooks, tests)
//               POST /perm/request  → PreToolUse hook long-polls for a decision
//               POST /perm/respond  → overlay/user answers {id, decision}
//               GET  /health
//
// Every event is journaled to journal.jsonl — the seed of Replay Theater.

const http = require("http");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { spawn } = require("child_process");

const WORKSPACE = path.join(__dirname, "..", "workspace");
const OVERLAY = path.join(__dirname, "overlay.html");
const JOURNAL = path.join(__dirname, "journal.jsonl");
const REPLAY_COUNT = 80;

const wsClients = new Set();
const pendingPerms = new Map(); // id -> {res, timer, agent, tool}
let taskCounter = 0;

// ---------------------------------------------------------------- registry
// Persistent staff roster + roles (skills/tools libraries ride along).
// main = Claude, the undeletable Director; ceo = the human owner's avatar.

const REGISTRY = path.join(__dirname, "registry.json");
let reg;

function loadReg() {
  try { reg = JSON.parse(fs.readFileSync(REGISTRY, "utf8")); } catch { reg = {}; }
  reg.agents = reg.agents || {};
  reg.roles = reg.roles || ["Director", "Founder", "Researcher", "Engineer",
    "Designer", "Analyst", "Operator", "Specialist"];
  reg.skills = reg.skills || {};
  reg.tools = reg.tools || ["Read", "Glob", "Grep", "Edit", "Write", "Bash",
    "WebSearch", "WebFetch", "Task", "TodoWrite", "NotebookEdit"];
  if (!reg.agents.main) reg.agents.main = {
    name: "Claude", role: "Director", avatar: 7, protected: true,
    prompt: "You are Claude, the Director of this AI agents office. You run " +
      "operations, make the calls the owner has not reserved for themselves, " +
      "and delegate to the team when that serves the work better.",
    skills: [], tools: ["Read", "Glob", "Grep", "Edit", "Write", "Bash"],
  };
  if (!reg.agents.ceo) reg.agents.ceo = {
    name: "CEO", role: "Founder", avatar: 8, protected: true, isUser: true,
    prompt: "", skills: [], tools: [],
  };
  saveReg();
}
function saveReg() { fs.writeFileSync(REGISTRY, JSON.stringify(reg, null, 2)); }
loadReg();

// Live (not journaled): registry.json is the persistence; every WS client
// also gets a fresh snapshot on connect.
function rosterEvt() {
  return { type: "roster.sync", agents: reg.agents, roles: reg.roles,
    tools: reg.tools, skills: reg.skills, autoSkills: reg.autoSkills !== false };
}
function pushRoster() { broadcast(rosterEvt(), false); }

function slugId(name) {
  const s = String(name).toLowerCase().replace(/[^a-z0-9ก-๙]+/g, "-")
    .replace(/^-+|-+$/g, "").slice(0, 24);
  return s || "agent" + Date.now() % 10000;
}

// Hermes-style auto-skills: after a real multi-tool task, a quick
// reflection call decides whether the work distills into a reusable skill.
// New skills land in the registry, auto-assigned to the agent that earned
// them, and the office hears about it (skill.created).
async function maybeLearnSkill(agent, task, prompt, acts, finalText) {
  if (reg.autoSkills === false || acts.length < 3) return;
  const existing = Object.values(reg.skills).map((s) => s.name).join(", ") || "(none)";
  const out = await claudeText(
    `An AI office agent "${agent}" just completed a task.\n` +
    `Task prompt: ${String(prompt).slice(0, 600)}\n` +
    `Tools used in order: ${acts.join(" -> ")}\n` +
    `Final report: ${String(finalText).slice(0, 800)}\n\n` +
    `Existing skills: ${existing}\n\n` +
    `If this work contains a REUSABLE, GENERALIZABLE procedure not already ` +
    `covered by an existing skill, distill it. Output STRICT JSON only:\n` +
    `{"name":"short-kebab-name","description":"one line","content":"imperative ` +
    `step-by-step instructions, max 12 lines"}\n` +
    `If nothing is worth saving, output exactly: NONE`);
  const m = out.match(/\{[\s\S]*\}/);
  if (!m) return;
  try {
    const sk = JSON.parse(m[0]);
    if (!sk.name || !sk.content) return;
    const id = slugId(sk.name);
    if (reg.skills[id]) return;
    reg.skills[id] = {
      name: String(sk.name).slice(0, 60),
      description: String(sk.description || "").slice(0, 200),
      content: String(sk.content).slice(0, 4000),
      auto: true, by: agent,
    };
    const a = reg.agents[agent];
    if (a && !a.skills.includes(id)) a.skills.push(id);
    saveReg();
    pushRoster();
    broadcast({ type: "skill.created", agent, task, skill: reg.skills[id].name });
  } catch {}
}

// ---------------------------------------------------------------- sessions
// Named chat sessions per agent. Default behavior: every /chat continues
// the agent's latest session (continuous memory); "new" starts a thread;
// an explicit key resumes that thread and makes it the latest again.

const SESSIONS = path.join(__dirname, "sessions.json");
let sess = {};
try { sess = JSON.parse(fs.readFileSync(SESSIONS, "utf8")); } catch {}
function saveSess() { fs.writeFileSync(SESSIONS, JSON.stringify(sess, null, 2)); }
function latestSession(agent) {
  const l = sess[agent] || [];
  return l.length ? l.reduce((a, b) => (a.ts > b.ts ? a : b)) : null;
}

// Plain headless claude call → final text (prompt drafting, reflections).
function claudeText(prompt) {
  return new Promise((resolve) => {
    const child = spawn("claude", ["-p"], {
      cwd: WORKSPACE, shell: true,
      env: { ...process.env, OFFICE_ADAPTER: "1" },
    });
    child.stdin.write(prompt);
    child.stdin.end();
    let out = "";
    child.stdout.on("data", (c) => (out += c));
    child.on("close", () => resolve(out.trim()));
    child.on("error", () => resolve(""));
  });
}

// ---------------------------------------------------------------- websocket

function wsAccept(key) {
  return crypto
    .createHash("sha1")
    .update(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
    .digest("base64");
}

// Server→client text frame (we never need to parse client frames).
function wsFrame(str) {
  const b = Buffer.from(str, "utf8");
  let head;
  if (b.length < 126) head = Buffer.from([0x81, b.length]);
  else if (b.length < 65536) {
    head = Buffer.alloc(4);
    head[0] = 0x81;
    head[1] = 126;
    head.writeUInt16BE(b.length, 2);
  } else {
    head = Buffer.alloc(10);
    head[0] = 0x81;
    head[1] = 127;
    head.writeBigUInt64BE(BigInt(b.length), 2);
  }
  return Buffer.concat([head, b]);
}

function journalTail(n) {
  try {
    const lines = fs.readFileSync(JOURNAL, "utf8").trim().split("\n");
    return lines.slice(-n);
  } catch {
    return [];
  }
}

// ---------------------------------------------------------------- bus

function broadcast(evt, journal = true) {
  evt.ts = Date.now();
  const json = JSON.stringify(evt);
  if (journal) fs.appendFile(JOURNAL, json + "\n", () => {});
  const frame = wsFrame(json);
  for (const s of wsClients) s.write(frame);
  if (evt.type !== "world.pos") console.log("[oep] →", json);
}

// ---------------------------------------------------------------- replay theater

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let replaying = false;

// Re-enacts a journal slice: events re-broadcast time-compressed with a
// `theater` flag. The world acts them out; the mission board stays real.
async function runReplay(minutes = 10, speed = 8) {
  if (replaying) return false;
  replaying = true;
  const since = Date.now() - minutes * 60000;
  const slice = journalTail(4000)
    .map((l) => { try { return JSON.parse(l); } catch { return null; } })
    .filter((e) => e && e.ts >= since && !e.theater &&
      !String(e.type).startsWith("theater."));
  console.log(`[theater] replaying ${slice.length} events over ${minutes}m at ${speed}x`);
  broadcast({ type: "theater.started", events: slice.length, speed });
  try {
    let prev = null;
    for (const e of slice) {
      if (prev !== null) await sleep(Math.min((e.ts - prev) / speed, 2500));
      prev = e.ts;
      broadcast({ ...e, theater: true, src_ts: e.ts });
    }
  } finally {
    broadcast({ type: "theater.ended" });
    replaying = false;
  }
  return true;
}

// ---------------------------------------------------------------- adapter

// Spawns a headless Claude Code session, translating stream-json → OEP.
// Dangerous tools route through the Security Center: the PreToolUse hook in
// workspace/.claude/settings.json long-polls /perm/request and we hold it
// until the user stamps Allow/Deny.
function runClaude(agent, prompt, opts = {}) {
  const task = "t" + ++taskCounter;
  broadcast({ type: "task.started", agent, task });

  // Session resolution: explicit key > latest > fresh.
  let entry = null;
  if (opts.session && opts.session !== "new")
    entry = (sess[agent] || []).find((e) => e.key === opts.session);
  else if (!opts.session) entry = latestSession(agent);

  // Persona + assigned skills ride in a stdin preamble (robust across
  // Windows shell quoting); resumed sessions already carry it in context.
  const a = reg.agents[agent];
  const tools = a && a.tools && a.tools.length ? a.tools.join(",") : "Read,Glob,Grep";
  let preamble = "";
  if (!entry && a && (a.prompt || (a.skills || []).length)) {
    preamble = `<persona>\nYou are "${a.name}" (${a.role}).\n${a.prompt || ""}\n`;
    for (const sid of a.skills || []) {
      const sk = reg.skills[sid];
      if (sk) preamble += `\n<skill name="${sk.name}">\n${sk.content}\n</skill>\n`;
    }
    preamble += "</persona>\n\n";
  }

  const args = ["-p", "--output-format", "stream-json", "--verbose",
    "--allowedTools", tools];
  if (entry && entry.sid) args.push("--resume", entry.sid);
  const child = spawn("claude", args, {
    cwd: WORKSPACE,
    shell: true,
    env: { ...process.env, OFFICE_ADAPTER: "1", OFFICE_AGENT: agent, OFFICE_TASK: task },
  });
  child.stdin.write(preamble + prompt);
  child.stdin.end();

  let buf = "";
  const acts = [];      // tool trail — feeds the auto-skill reflection
  let lastText = "";
  child.stdout.on("data", (c) => {
    buf += c;
    let i;
    while ((i = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, i).trim();
      buf = buf.slice(i + 1);
      if (!line) continue;
      let m;
      try { m = JSON.parse(line); } catch { continue; }

      if (m.type === "assistant" && m.message && Array.isArray(m.message.content)) {
        for (const b of m.message.content) {
          if (b.type === "tool_use") {
            acts.push(b.name);
            broadcast({ type: "task.progress", agent, task, tool: b.name });
          } else if (b.type === "text" && b.text.trim()) {
            lastText = b.text;
            const out = opts.filterText ? opts.filterText(b.text) : b.text;
            if (out) broadcast({ type: "chat.message", agent, task, text: out });
          }
        }
      } else if (m.type === "result") {
        // Session bookkeeping: remember the thread we just extended.
        if (m.session_id) {
          if (entry) { entry.sid = m.session_id; entry.ts = Date.now(); }
          else {
            sess[agent] = sess[agent] || [];
            sess[agent].push({ key: "s" + Date.now(), sid: m.session_id,
              title: String(prompt).replace(/\s+/g, " ").slice(0, 48), ts: Date.now() });
          }
          saveSess();
        }
        broadcast({ type: m.is_error ? "task.failed" : "task.completed", agent, task });
        if (!m.is_error) maybeLearnSkill(agent, task, prompt, acts, lastText);
      }
    }
  });
  child.stderr.on("data", (c) => console.error("[claude]", c.toString().trim()));
  child.on("error", (e) => {
    broadcast({ type: "task.failed", agent, task });
    broadcast({ type: "chat.message", agent, task, text: "adapter error: " + e.message });
  });
  return task;
}

// ---------------------------------------------------------------- ceo flow
// Talking to the CEO is the gimmick chain-of-command: the Director (main)
// walks over, takes the order, replies with a plan, and may delegate via
// `DELEGATE: <agent_id> :: <instruction>` lines — each spawns a real
// session for that agent (plus a little walk in the world).
function ceoFlow(prompt) {
  broadcast({ type: "ceo.summon", agent: "main" });
  const team = Object.entries(reg.agents)
    .filter(([id]) => id !== "ceo" && id !== "main")
    .map(([id, a]) => `- ${id}: ${a.name}, ${a.role}` +
      (a.prompt ? ` — ${a.prompt.replace(/\s+/g, " ").slice(0, 100)}` : ""))
    .join("\n") || "(no other staff yet)";
  const wrapped =
    `The owner (CEO) has called you over and given this order in person:\n` +
    `"""${prompt}"""\n\n` +
    `Your team:\n${team}\n\n` +
    `Decide how to execute. For anything a team member should own, include a line:\n` +
    `DELEGATE: <agent_id> :: <clear instruction for them>\n` +
    `(exact format, one per assignment — these are dispatched automatically). ` +
    `Anything not delegated you handle yourself. Reply to the owner with a short ` +
    `plan in the language they used.`;
  return runClaude("main", wrapped, {
    filterText: (text) => {
      const keep = [];
      for (const ln of String(text).split("\n")) {
        const m = ln.match(/^\s*DELEGATE:\s*([\w฀-๿-]+)\s*::\s*(.+)$/);
        if (m && reg.agents[m[1]] && m[1] !== "ceo") {
          broadcast({ type: "task.delegated", agent: "main", target: m[1] });
          setTimeout(() => runClaude(m[1], m[2]), 4500);  // after the walk
        } else keep.push(ln);
      }
      return keep.join("\n").trim();
    },
  });
}

// ---------------------------------------------------------------- discussion
// Agents talk to each other: round-robin claude calls sharing a transcript,
// staged in the meeting room (collab.* events drive seats + whiteboard).
let discussing = false;

async function runDiscussion(ids, topic, rounds) {
  discussing = true;
  const task = "disc" + (Date.now() % 100000);
  broadcast({ type: "collab.started", agents: ids, task, text: topic });
  let transcript = "";
  try {
    for (let r = 0; r < rounds; r++) {
      for (const id of ids) {
        const a = reg.agents[id] || { name: id, role: "Staff", prompt: "" };
        const text = await claudeText(
          `You are "${a.name}" (${a.role}) in a team meeting at the office.\n` +
          (a.prompt ? `Your persona: ${a.prompt}\n` : "") +
          `Meeting topic: ${topic}\n` +
          (transcript ? `Discussion so far:\n${transcript}\n` : "You open the meeting.\n") +
          `Give YOUR next contribution as ${a.name}: concrete, build on the others, ` +
          `max 3 sentences, plain text only, in the same language as the topic.`);
        const line = text.split("\n").filter(Boolean).join(" ").slice(0, 500);
        if (line) {
          transcript += `${a.name}: ${line}\n`;
          broadcast({ type: "chat.message", agent: id, task, text: line });
        }
      }
    }
  } finally {
    broadcast({ type: "collab.ended", agents: ids, task });
    discussing = false;
  }
}

// ---------------------------------------------------------------- http

function readBody(req, cb) {
  let body = "";
  req.on("data", (c) => (body += c));
  req.on("end", () => cb(body));
}

function readBodyRaw(req, cb) {
  const chunks = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", () => cb(Buffer.concat(chunks)));
}

const MAPBG = path.join(__dirname, "map_bg.png");

const server = http.createServer((req, res) => {
  if (req.method === "GET" && (req.url.split("?")[0] === "/" || req.url.split("?")[0] === "/index.html")) {
    res.writeHead(200, {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
    });
    res.end(fs.readFileSync(OVERLAY));

  } else if (req.method === "GET" && /^\/brand\/logo[a-z_]*\.png$/.test(req.url)) {
    const f = path.join(__dirname, "..", "godot", "assets", "brand", req.url.split("/").pop());
    fs.readFile(f, (e, data) => {
      if (e) { res.writeHead(404); res.end(); return; }
      res.writeHead(200, { "content-type": "image/png", "cache-control": "max-age=3600" });
      res.end(data);
    });

  } else if (req.method === "GET" && /^\/char\/npc([1-9]|1[0-2])\.png$/.test(req.url)) {
    // Character sheets for overlay portraits (404 → CSS falls back to initials)
    const f = path.join(__dirname, "..", "godot", "assets", "characters", "npc",
      req.url.split("/").pop());
    fs.readFile(f, (e, data) => {
      if (e) { res.writeHead(404); res.end(); return; }
      res.writeHead(200, { "content-type": "image/png", "cache-control": "max-age=3600" });
      res.end(data);
    });

  } else if (req.method === "POST" && req.url === "/chat") {
    readBody(req, (body) => {
      try {
        const { agent = "main", prompt, session } = JSON.parse(body);
        if (!prompt) throw new Error("no prompt");
        // Orders to the CEO route through the Director — chain of command.
        const task = agent === "ceo" ? ceoFlow(prompt) : runClaude(agent, prompt, { session });
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({ task }));
      } catch (e) {
        res.writeHead(400);
        res.end(String(e.message));
      }
    });

  } else if (req.method === "GET" && req.url.startsWith("/sessions")) {
    const agent = new URL(req.url, "http://x").searchParams.get("agent") || "main";
    const list = (sess[agent] || []).slice().sort((a, b) => b.ts - a.ts).slice(0, 20);
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ sessions: list }));

  } else if (req.method === "POST" && req.url === "/discuss") {
    readBody(req, (body) => {
      try {
        const p = JSON.parse(body);
        const ids = (p.agents || []).filter((id) => id !== "ceo").slice(0, 4);
        if (ids.length < 2) throw new Error("need at least 2 agents");
        if (!p.topic) throw new Error("no topic");
        if (discussing) { res.writeHead(409); return res.end("discussion in progress"); }
        runDiscussion(ids, String(p.topic), Math.min(Math.max(Number(p.rounds) || 2, 1), 3));
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({ ok: true }));
      } catch (e) {
        res.writeHead(400);
        res.end(String(e.message));
      }
    });

  } else if (req.method === "POST" && req.url === "/replay") {
    readBody(req, (body) => {
      let p = {};
      try { p = JSON.parse(body || "{}"); } catch {}
      const ok = !replaying;
      if (ok)
        runReplay(
          Math.min(Number(p.minutes) || 10, 240),
          Math.max(Number(p.speed) || 8, 1)
        );
      res.writeHead(ok ? 200 : 409, { "content-type": "application/json" });
      res.end(JSON.stringify({ replaying: ok }));
    });

  } else if (req.method === "POST" && req.url === "/map/bg") {
    // Godot ships a one-shot orthographic floorplan render at boot.
    readBodyRaw(req, (buf) => {
      fs.writeFile(MAPBG, buf, () => {});
      broadcast({ type: "ui.mapbg" }, false);  // overlays refresh the image
      res.writeHead(200);
      res.end("ok");
    });

  } else if (req.method === "GET" && req.url.startsWith("/map/bg")) {
    fs.readFile(MAPBG, (e, data) => {
      if (e) { res.writeHead(404); res.end(); return; }
      res.writeHead(200, { "content-type": "image/png", "cache-control": "no-store" });
      res.end(data);
    });

  } else if (req.method === "POST" && req.url === "/pos") {
    // 1 Hz live positions from the renderer → overlay map (never journaled).
    readBody(req, (body) => {
      try {
        broadcast({ type: "world.pos", agents: JSON.parse(body).agents }, false);
        res.writeHead(200);
        res.end("ok");
      } catch {
        res.writeHead(400);
        res.end("bad json");
      }
    });

  } else if (req.method === "GET" && req.url === "/registry") {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify(reg));

  } else if (req.method === "POST" && req.url === "/registry/agent") {
    // Create or update an agent. Protected rows (main/ceo) accept edits but
    // never deletion; id is derived from the name on first save.
    readBody(req, (body) => {
      try {
        const p = JSON.parse(body);
        const id = p.id || slugId(p.name);
        const cur = reg.agents[id] || { skills: [], tools: [] };
        reg.agents[id] = {
          ...cur,
          name: String(p.name || cur.name || id).slice(0, 40),
          role: String(p.role || cur.role || "Specialist").slice(0, 40),
          avatar: Math.min(Math.max(Number(p.avatar) || cur.avatar || 1, 1), 12),
          prompt: String(p.prompt !== undefined ? p.prompt : cur.prompt || "").slice(0, 8000),
          skills: Array.isArray(p.skills) ? p.skills : cur.skills || [],
          tools: Array.isArray(p.tools) ? p.tools : cur.tools || [],
        };
        saveReg();
        pushRoster();
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({ id }));
      } catch (e) {
        res.writeHead(400);
        res.end(String(e.message));
      }
    });

  } else if (req.method === "POST" && req.url === "/registry/agent/delete") {
    readBody(req, (body) => {
      try {
        const { id } = JSON.parse(body);
        const a = reg.agents[id];
        if (!a) { res.writeHead(404); return res.end("unknown agent"); }
        if (a.protected) { res.writeHead(403); return res.end("protected agent"); }
        delete reg.agents[id];
        saveReg();
        broadcast({ type: "roster.removed", agent: id }, false);
        pushRoster();
        res.writeHead(200);
        res.end("ok");
      } catch (e) {
        res.writeHead(400);
        res.end(String(e.message));
      }
    });

  } else if (req.method === "POST" && req.url === "/registry/skill") {
    // Create, update or remove a skill in the library. Removal also strips
    // the skill from every agent that had it assigned.
    readBody(req, (body) => {
      try {
        const p = JSON.parse(body);
        if (p.remove) {
          delete reg.skills[p.id];
          for (const a of Object.values(reg.agents))
            a.skills = (a.skills || []).filter((s) => s !== p.id);
        } else {
          const id = p.id || slugId(p.name);
          reg.skills[id] = {
            ...(reg.skills[id] || {}),
            name: String(p.name || id).slice(0, 60),
            description: String(p.description || "").slice(0, 200),
            content: String(p.content || "").slice(0, 4000),
          };
        }
        saveReg();
        pushRoster();
        res.writeHead(200);
        res.end("ok");
      } catch (e) {
        res.writeHead(400);
        res.end(String(e.message));
      }
    });

  } else if (req.method === "POST" && req.url === "/registry/tool") {
    readBody(req, (body) => {
      try {
        const { name, remove } = JSON.parse(body);
        const n = String(name || "").trim().slice(0, 60);
        if (!n) throw new Error("no name");
        if (remove) {
          reg.tools = reg.tools.filter((t) => t !== n);
          for (const a of Object.values(reg.agents))
            a.tools = (a.tools || []).filter((t) => t !== n);
        } else if (!reg.tools.includes(n)) reg.tools.push(n);
        saveReg();
        pushRoster();
        res.writeHead(200);
        res.end("ok");
      } catch (e) {
        res.writeHead(400);
        res.end(String(e.message));
      }
    });

  } else if (req.method === "POST" && req.url === "/registry/autoskills") {
    readBody(req, (body) => {
      try {
        reg.autoSkills = !!JSON.parse(body).enabled;
        saveReg();
        pushRoster();
        res.writeHead(200);
        res.end("ok");
      } catch {
        res.writeHead(400);
        res.end("bad json");
      }
    });

  } else if (req.method === "POST" && req.url === "/registry/role") {
    readBody(req, (body) => {
      try {
        const { name, remove } = JSON.parse(body);
        const n = String(name || "").trim().slice(0, 40);
        if (!n) throw new Error("no name");
        if (remove) reg.roles = reg.roles.filter((r) => r !== n);
        else if (!reg.roles.includes(n)) reg.roles.push(n);
        saveReg();
        pushRoster();
        res.writeHead(200);
        res.end("ok");
      } catch (e) {
        res.writeHead(400);
        res.end(String(e.message));
      }
    });

  } else if (req.method === "POST" && req.url === "/assist/prompt") {
    // ✨ Prompt copilot: the owner types a one-line brief ("UI designer who
    // sweats microcopy") and a quick claude call drafts the system prompt.
    readBody(req, async (body) => {
      try {
        const { name = "Agent", role = "Specialist", brief = "" } = JSON.parse(body);
        const draft = await claudeText(
          `Draft a system prompt for an AI agent that works in a software office.\n` +
          `Agent name: ${name}\nJob title: ${role}\nOwner's brief: ${brief}\n\n` +
          `Rules: 4-8 sentences. Second person ("You are..."). Cover: mission, ` +
          `expertise, working style, what good output looks like. Match the ` +
          `language of the owner's brief (Thai brief → Thai prompt). ` +
          `Output ONLY the prompt text - no preamble, no quotes, no markdown.`);
        res.writeHead(200, { "content-type": "application/json; charset=utf-8" });
        res.end(JSON.stringify({ prompt: draft }));
      } catch (e) {
        res.writeHead(500);
        res.end(String(e.message));
      }
    });

  } else if (req.method === "POST" && req.url === "/ui/daylight") {
    // Manual atmosphere override for the world ("auto" follows the clock).
    // Journaled, so the choice survives renderer restarts via replay.
    readBody(req, (body) => {
      try {
        const { hour = "auto" } = JSON.parse(body || "{}");
        broadcast({ type: "ui.daylight", hour });
        res.writeHead(200);
        res.end("ok");
      } catch {
        res.writeHead(400);
        res.end("bad json");
      }
    });

  } else if (req.method === "POST" && req.url === "/event") {
    readBody(req, (body) => {
      try {
        broadcast(JSON.parse(body));
        res.writeHead(200);
        res.end("ok");
      } catch {
        res.writeHead(400);
        res.end("bad json");
      }
    });

  } else if (req.method === "POST" && req.url === "/perm/request") {
    // PreToolUse hook long-polls here; we answer when the user decides.
    readBody(req, (body) => {
      let p;
      try { p = JSON.parse(body); } catch { res.writeHead(400); return res.end(); }
      const { id, agent = "claude", task = "", tool = "?", input = "" } = p;
      broadcast({ type: "perm.requested", agent, task, tool, perm: id, input });
      const timer = setTimeout(() => {
        // No human around — deny safely and let the agent re-plan.
        finishPerm(id, "deny", "timeout");
      }, 50000);
      pendingPerms.set(id, { res, timer, agent, task, tool });
    });

  } else if (req.method === "POST" && req.url === "/perm/respond") {
    readBody(req, (body) => {
      try {
        const { id, decision } = JSON.parse(body);
        const ok = finishPerm(id, decision === "allow" ? "allow" : "deny", "user");
        res.writeHead(ok ? 200 : 404);
        res.end(ok ? "ok" : "unknown id");
      } catch {
        res.writeHead(400);
        res.end("bad json");
      }
    });

  } else if (req.url === "/health") {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ clients: wsClients.size, pendingPerms: pendingPerms.size }));

  } else {
    res.writeHead(404);
    res.end();
  }
});

function finishPerm(id, decision, why) {
  const p = pendingPerms.get(id);
  if (!p) return false;
  pendingPerms.delete(id);
  clearTimeout(p.timer);
  p.res.writeHead(200, { "content-type": "application/json" });
  p.res.end(JSON.stringify({ decision }));
  broadcast({
    type: decision === "allow" ? "perm.approved" : "perm.denied",
    agent: p.agent, task: p.task, tool: p.tool, perm: id, via: why,
  });
  return true;
}

// WS upgrade — renderers (Godot) and overlays share one stream.
server.on("upgrade", (req, sock) => {
  if (!req.url.startsWith("/ws")) return sock.destroy();
  const key = req.headers["sec-websocket-key"];
  if (!key) return sock.destroy();
  sock.write(
    "HTTP/1.1 101 Switching Protocols\r\n" +
      "Upgrade: websocket\r\nConnection: Upgrade\r\n" +
      `Sec-WebSocket-Accept: ${wsAccept(key)}\r\n\r\n`
  );
  wsClients.add(sock);
  console.log("[oep] ws client connected", `(${wsClients.size})`);
  sock.on("close", () => wsClients.delete(sock));
  sock.on("error", () => wsClients.delete(sock));
  sock.on("data", () => {}); // inbound frames (pings/close) — TCP close is enough
  // Journal replay so a restarted renderer/overlay rebuilds its state.
  for (const line of journalTail(REPLAY_COUNT)) {
    try {
      const evt = JSON.parse(line);
      evt.replay = true;
      sock.write(wsFrame(JSON.stringify(evt)));
    } catch {}
  }
  // Fresh roster snapshot last — registry.json is the truth, not the journal.
  sock.write(wsFrame(JSON.stringify({ ...rosterEvt(), ts: Date.now() })));
});

server.listen(8787, "127.0.0.1", () =>
  console.log("[oep] http+ws listening :8787")
);
