#!/usr/bin/env node
// bagidea — command line for the BagIdea AI Agents Office.
// Zero dependencies. Talks to the daemon on :8787; can launch the suite.

const http = require("http");
const fs = require("fs");
const path = require("path");
const { spawn, execFileSync } = require("child_process");

const ROOT = path.join(__dirname, "..");
const BASE = "http://127.0.0.1:8787";

// ---- tiny http ---------------------------------------------------------------
function req(method, p, body, asBuffer) {
  return new Promise((resolve, reject) => {
    const data = body ? Buffer.from(JSON.stringify(body)) : null;
    const r = http.request(BASE + p, {
      method,
      headers: {
        "x-bagidea-ui": "1",
        ...(data ? { "content-type": "application/json", "content-length": data.length } : {}),
      },
    }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        const buf = Buffer.concat(chunks);
        if (asBuffer) return resolve({ status: res.statusCode, buf });
        try { resolve(JSON.parse(buf.toString("utf8"))); }
        catch { resolve(buf.toString("utf8")); }
      });
    });
    r.setTimeout(method === "POST" && (p === "/chat" || p === "/tts" || p === "/gen/image")
      ? 11 * 60000 : 8000, () => r.destroy(new Error("timeout")));
    r.on("error", reject);
    if (data) r.write(data);
    r.end();
  });
}
async function daemonUp() {
  try { return !!(await req("GET", "/health")); } catch { return false; }
}

// ---- looks --------------------------------------------------------------------
const C = { dim: "\x1b[90m", cyan: "\x1b[96m", green: "\x1b[92m", yellow: "\x1b[93m",
  red: "\x1b[91m", mag: "\x1b[95m", bold: "\x1b[1m", off: "\x1b[0m" };
const ok = (s) => console.log(`${C.green}✓${C.off} ${s}`);
const bad = (s) => console.log(`${C.red}✗${C.off} ${s}`);
const hr = () => console.log(C.dim + "─".repeat(46) + C.off);
function banner() {
  console.log(`${C.cyan}${C.bold}
  ┌─────────────────────────────────────┐
  │  🏢  BagIdea AI Agents Office       │
  │      your wallpaper went to work    │
  └─────────────────────────────────────┘${C.off}`);
}

const HELP = `${C.cyan}${C.bold}🏢 bagidea${C.off} — BagIdea AI Agents Office CLI

${C.bold}โปรแกรม${C.off}
  ${C.cyan}start${C.off}                       เปิดออฟฟิศ (ถ้ายังไม่เปิด)
  ${C.cyan}stop${C.off}                        ปิดทั้งชุด (shell + วอลเปเปอร์ + daemon)
  ${C.cyan}status${C.off}                      ภาพรวมระบบ + agents + โปรเจค
  ${C.cyan}stats${C.off}                       📊 สถิติงาน 7 วัน + ค่าใช้จ่าย
  ${C.cyan}update${C.off}                      อัปเดตเวอร์ชันล่าสุด + รีสตาร์ท
  ${C.cyan}version${C.off}                     เวอร์ชันปัจจุบัน

${C.bold}คุยกับออฟฟิศ${C.off}
  ${C.cyan}ask "<ข้อความ>"${C.off}              สั่งงานในนาม CEO และรอคำตอบจบ
  ${C.cyan}chat <agent> "<msg>"${C.off}        ส่งงานให้ agent ระบุตัว (ไม่รอ)
  ${C.cyan}feed${C.off}                        ดูเหตุการณ์สดในเทอร์มินัล (Ctrl+C ออก)
  ${C.cyan}note "<ข้อความ>"${C.off}             แปะโน้ตบนกระดานกลาง

${C.bold}ทีมและงาน${C.off}
  ${C.cyan}agents${C.off}                      รายชื่อพนักงาน + เสียง + เครื่องมือ
  ${C.cyan}projects${C.off}                    รายชื่อโปรเจค + ใครกำลังทำงาน
  ${C.cyan}open "<โปรเจค>"${C.off}              เปิดหน้าต่างโปรเจค (= ปุ่ม ▶)
  ${C.cyan}editor${C.off}                      เปิด 3D Office Editor (จัดออฟฟิศ)
  ${C.cyan}memory <agent>${C.off}              อ่านสมุดความจำของ agent
  ${C.cyan}office${C.off}                      อ่าน OFFICE.md (ข้อมูลกลาง)

${C.bold}AI features${C.off} ${C.dim}(ใช้ main API keys)${C.off}
  ${C.cyan}say "<ข้อความ>" [preset]${C.off}     ให้เสียง TTS พูด (default: sunny)
  ${C.cyan}image "<prompt>"${C.off}            สร้างภาพ AI → ได้ path ไฟล์
  ${C.cyan}keys${C.off}                        ดูรายชื่อ key ที่ตั้งไว้ (ไม่โชว์ค่า)
  ${C.cyan}channels${C.off}                    สถานะ Telegram / Discord / LINE

${C.bold}ซ่อมบำรุง${C.off}
  ${C.cyan}fixmic${C.off}                      รีเซ็ตแผงพิมพ์ด้วยเสียงของ Windows ที่ค้าง
  ${C.cyan}help${C.off}                        หน้านี้ (หรือ --help / -h)`;

function findShellExe() {
  const exe = path.join(ROOT, "shell", "target", "release", "bagidea-office-shell.exe");
  return fs.existsSync(exe) ? exe : null;
}

async function main() {
  const [cmd, ...rest] = process.argv.slice(2);

  if (!cmd || ["help", "--help", "-h"].includes(cmd)) {
    banner();
    console.log(HELP);
    return;
  }

  if (cmd === "version") {
    try {
      const sha = execFileSync("git", ["rev-parse", "--short", "HEAD"], { cwd: ROOT }).toString().trim();
      const date = execFileSync("git", ["log", "-1", "--format=%cd", "--date=short"], { cwd: ROOT }).toString().trim();
      console.log(`bagidea office ${C.cyan}${sha}${C.off} (${date})`);
    } catch { console.log("bagidea office (git not available)"); }
    return;
  }

  if (cmd === "start") {
    if (await daemonUp()) return ok("โปรแกรมเปิดอยู่แล้ว");
    const exe = findShellExe();
    if (!exe) return bad("ไม่พบ shell exe — รัน: cargo build --release ใน shell/");
    spawn(exe, [], { cwd: path.dirname(exe), detached: true, stdio: "ignore" }).unref();
    process.stdout.write("กำลังเปิดออฟฟิศ");
    for (let i = 0; i < 30; i++) {
      await new Promise((r) => setTimeout(r, 1000));
      process.stdout.write(".");
      if (await daemonUp()) { console.log(""); return ok("ออฟฟิศพร้อมทำงานแล้ว 🏢"); }
    }
    console.log("");
    return console.log(`${C.yellow}!${C.off} เปิดแล้วแต่ daemon ยังไม่ตอบ — ดูที่หน้าจอ`);
  }

  if (cmd === "stop") {
    spawn("powershell", ["-NoProfile", "-Command",
      "Get-CimInstance Win32_Process | Where-Object { ($_.Name -eq 'node.exe' -and $_.CommandLine -match 'server\\.js') -or $_.Name -eq 'bagidea-office-shell.exe' -or $_.Name -like 'Godot*' } | ForEach-Object { taskkill /PID $_.ProcessId /T /F } | Out-Null"],
      { stdio: "ignore" }).on("close", () => ok("ปิดออฟฟิศแล้ว"));
    return;
  }

  if (cmd === "editor") {
    if (!(await daemonUp())) return bad(`โปรแกรมยังไม่เปิด — สั่ง ${C.cyan}bagidea start${C.off} ก่อน`);
    await req("POST", "/editor/open", {});
    return ok("เปิด 3D Office Editor แล้ว (หน้าต่างแยก) — จัดของเสร็จกดบันทึก");
  }

  if (cmd === "fixmic") {
    spawn("powershell", ["-NoProfile", "-Command",
      "Get-Process TextInputHost -ErrorAction SilentlyContinue | Stop-Process -Force"],
      { stdio: "ignore" }).on("close", () =>
      ok("รีเซ็ตแผงพิมพ์ด้วยเสียงแล้ว (Windows เปิดตัวใหม่ให้เอง)"));
    return;
  }

  if (cmd === "update") {
    const ps = path.join(ROOT, "installer", "update.ps1");
    if (!fs.existsSync(ps)) return bad("ไม่พบ installer/update.ps1");
    console.log("เริ่มอัปเดต… (โปรแกรมจะรีสตาร์ทเอง)");
    spawn("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ps],
      { cwd: ROOT, detached: true, stdio: "inherit" });
    return;
  }

  // ---- everything below needs the daemon --------------------------------------
  if (!(await daemonUp()))
    return bad(`โปรแกรมยังไม่เปิด — สั่ง ${C.cyan}bagidea start${C.off} ก่อน`);

  if (cmd === "status") {
    const h = await req("GET", "/health");
    const pr = await req("GET", "/projects");
    const reg = await req("GET", "/registry");
    const f = await req("GET", "/features");
    banner();
    console.log(`  ${C.green}● online${C.off}  clients ${h.clients} · WT ${h.wt ? "✓" : "✗"} · perms ค้าง ${h.pendingPerms}` +
      `  ·  keys: OpenAI ${f.openai ? "✅" : "—"} Gemini ${f.gemini ? "✅" : "—"}`);
    hr();
    for (const [id, a] of Object.entries(reg.agents || {}).filter(([i]) => i !== "ceo"))
      console.log(`  ${C.bold}${a.name}${C.off} ${C.dim}(${id} · ${a.role}${a.voice ? " · 🗣" : ""})${C.off}`);
    hr();
    if (!(pr.projects || []).length) console.log(`  ${C.dim}(ยังไม่มีโปรเจค)${C.off}`);
    for (const p of pr.projects || []) {
      const st = p.ai ? `${C.cyan}🤖 ${(p.agents || []).join(",")} กำลังทำงาน${C.off}`
        : p.open ? (p.visible ? `${C.green}🖥 เปิดอยู่${C.off}` : `${C.yellow}🫥 เบื้องหลัง${C.off}`)
        : `${C.dim}ปิด${C.off}`;
      console.log(`  📁 ${p.name} ${C.dim}${p.dir}${C.off} — ${st}`);
    }
    return;
  }

  if (cmd === "stats") {
    const s = await req("GET", "/stats");
    const today = s.days[s.days.length - 1];
    banner();
    console.log(`  วันนี้: ${C.bold}${today.runs}${C.off} งาน  ${C.green}✓${today.done}${C.off} ${C.red}✗${today.failed}${C.off}` +
      `  💰 $${(today.cost || 0).toFixed(2)}  ⏱ uptime ${Math.floor(s.uptimeSec / 3600)}h${Math.floor((s.uptimeSec % 3600) / 60)}m`);
    hr();
    const maxR = Math.max(1, ...s.days.map((d) => d.runs));
    for (const d of s.days) {
      const bar = "█".repeat(Math.round((d.runs / maxR) * 24)) || "·";
      console.log(`  ${d.day.slice(5)}  ${C.cyan}${bar}${C.off} ${d.runs}`);
    }
    const ag = Object.entries(today.agents || {}).sort((a, b) => b[1] - a[1]);
    if (ag.length) {
      hr();
      for (const [id, n] of ag.slice(0, 6)) console.log(`  🏆 ${id}: ${n} งาน`);
    }
    return;
  }

  if (cmd === "ask") {
    const q = rest.join(" ").trim();
    if (!q) return console.log('ใช้: bagidea ask "<ข้อความ>"');
    console.log(`${C.dim}→ ส่งคำสั่งในนาม CEO… (Director เดินมารับ + รอคำตอบจบ)${C.off}`);
    const r = await req("POST", "/chat", { agent: "ceo", prompt: q, wait: true });
    hr();
    console.log((r && r.text) || "(ไม่มีคำตอบ)");
    return;
  }

  if (cmd === "chat") {
    const agent = rest[0];
    const q = rest.slice(1).join(" ").trim();
    if (!agent || !q) return console.log('ใช้: bagidea chat <agent_id> "<ข้อความ>"');
    const r = await req("POST", "/chat", { agent, prompt: q });
    return ok(`ส่งให้ ${agent} แล้ว (task ${r.task}) — ดูผลใน feed / หน้าโปรแกรม`);
  }

  if (cmd === "agents") {
    const reg = await req("GET", "/registry");
    for (const [id, a] of Object.entries(reg.agents || {})) {
      if (id === "ceo") continue;
      console.log(`${C.bold}${a.name}${C.off} ${C.dim}(${id})${C.off}` +
        `  ${a.role} · tier ${a.tier || 3}${a.voice ? ` · 🗣 ${a.voice}` : ""}`);
      console.log(`  ${C.dim}🎯 ${(a.skills || []).length} skills · 🔧 ${(a.tools || []).join(", ") || "read-only"}${C.off}`);
    }
    return;
  }

  if (cmd === "projects") {
    const pr = await req("GET", "/projects");
    for (const p of pr.projects || [])
      console.log(`📁 ${C.bold}${p.name}${C.off} ${C.dim}${p.dir}${C.off}` +
        `${p.ai ? ` ${C.cyan}🤖 ${(p.agents || []).join(",")}${C.off}` : ""}` +
        `${p.open ? (p.visible ? ` ${C.green}🖥${C.off}` : ` ${C.yellow}🫥${C.off}`) : ""}`);
    if (!(pr.projects || []).length) console.log(`${C.dim}(ยังไม่มีโปรเจค)${C.off}`);
    return;
  }

  if (cmd === "open") {
    const name = rest.join(" ").trim().toLowerCase();
    const pr = await req("GET", "/projects");
    const p = (pr.projects || []).find((x) => x.name.toLowerCase() === name);
    if (!p) return bad("ไม่พบโปรเจคชื่อนั้น — ดู: bagidea projects");
    await req("POST", "/projects/open", { id: p.id, mode: "play" });
    return ok(`เปิด ${p.name} แล้ว`);
  }

  if (cmd === "note") {
    const t = rest.join(" ").trim();
    if (!t) return console.log('ใช้: bagidea note "<ข้อความ>"');
    await req("POST", "/notes", { text: t });
    return ok("แปะโน้ตแล้ว 📝");
  }

  if (cmd === "memory") {
    const agent = (rest[0] || "main").replace(/[^\w-]/g, "_");
    const f = path.join(ROOT, "workspace", "memory", agent + ".md");
    try { console.log(fs.readFileSync(f, "utf8")); }
    catch { console.log(`${C.dim}(ยังไม่มีความจำของ ${agent})${C.off}`); }
    return;
  }

  if (cmd === "office") {
    const t = await req("GET", "/office-md");
    console.log(typeof t === "string" ? t : "");
    return;
  }

  if (cmd === "keys") {
    const reg = await req("GET", "/registry");
    const f = await req("GET", "/features");
    console.log(`MAIN: OpenAI ${f.openai ? C.green + "✅ ตั้งแล้ว" + C.off : C.yellow + "ยังไม่ตั้ง" + C.off}` +
      ` · Gemini ${f.gemini ? C.green + "✅ ตั้งแล้ว" + C.off : C.yellow + "ยังไม่ตั้ง" + C.off}`);
    const extras = Object.keys(reg.apiKeys || {})
      .filter((n) => n !== "OPENAI_API_KEY" && n !== "GEMINI_API_KEY");
    console.log("เพิ่มเติม: " + (extras.join(", ") || C.dim + "(ไม่มี)" + C.off));
    return;
  }

  if (cmd === "channels") {
    const ch = await req("GET", "/channels/status");
    for (const [k, v] of Object.entries(ch))
      console.log(`${k.padEnd(9)} ${v === "on" ? C.green + "● on" + C.off
        : v === "off" ? C.dim + "○ off" + C.off : C.yellow + "● " + v + C.off}`);
    return;
  }

  if (cmd === "say") {
    const text = rest.filter((x) => !x.startsWith("--")).join(" ").trim();
    const preset = (rest.find((x) => x.startsWith("--preset=")) || "").split("=")[1] ||
      rest[rest.length - 1] && ["sunny","sweet","cool","genki","boyish","warm","serious","polite"].includes(rest[rest.length - 1])
        ? rest[rest.length - 1] : "sunny";
    const sayText = ["sunny","sweet","cool","genki","boyish","warm","serious","polite"].includes(rest[rest.length - 1])
      ? rest.slice(0, -1).join(" ").trim() : text;
    if (!sayText) return console.log('ใช้: bagidea say "<ข้อความ>" [preset]');
    console.log(`${C.dim}🗣 กำลังสังเคราะห์เสียง (${preset})…${C.off}`);
    const r = await req("POST", "/tts", { preset, text: sayText }, true);
    if (r.status !== 200) return bad(r.buf.toString("utf8"));
    const wav = path.join(require("os").tmpdir(), "bagidea_say.wav");
    fs.writeFileSync(wav, r.buf);
    spawn("powershell", ["-NoProfile", "-Command",
      `(New-Object Media.SoundPlayer '${wav}').PlaySync()`], { stdio: "ignore" })
      .on("close", () => ok("พูดจบแล้ว"));
    return;
  }

  if (cmd === "image") {
    const prompt = rest.join(" ").trim();
    if (!prompt) return console.log('ใช้: bagidea image "<prompt>"');
    console.log(`${C.dim}🖼 กำลังสร้างภาพ… (อาจใช้เวลาครู่ใหญ่)${C.off}`);
    const r = await req("POST", "/gen/image", { prompt });
    if (r && r.path) return ok(`ได้ภาพแล้ว → ${r.path}`);
    return bad(String(r));
  }

  if (cmd === "feed") {
    const J = path.join(ROOT, "daemon", "journal.jsonl");
    let pos = 0;
    try { pos = fs.statSync(J).size; } catch {}
    console.log(`${C.dim}📡 ดูเหตุการณ์สด… (Ctrl+C ออก)${C.off}`);
    setInterval(() => {
      let size = 0;
      try { size = fs.statSync(J).size; } catch { return; }
      if (size <= pos) return;
      const fd = fs.openSync(J, "r");
      const buf = Buffer.alloc(size - pos);
      fs.readSync(fd, buf, 0, buf.length, pos);
      fs.closeSync(fd);
      pos = size;
      for (const line of buf.toString("utf8").split("\n")) {
        if (!line.trim()) continue;
        let e;
        try { e = JSON.parse(line); } catch { continue; }
        const t = new Date(e.ts).toLocaleTimeString();
        if (e.type === "chat.message")
          console.log(`${C.dim}${t}${C.off} ${C.cyan}${e.sub || e.agent}${C.off}: ${String(e.text).split("\n")[0].slice(0, 110)}`);
        else if (e.type === "task.started")
          console.log(`${C.dim}${t}${C.off} ${C.green}▶${C.off} ${e.agent}: ${e.title || ""}`);
        else if (e.type === "task.completed") console.log(`${C.dim}${t} ✓ ${e.agent} เสร็จ${C.off}`);
        else if (e.type === "task.failed") console.log(`${C.dim}${t}${C.off} ${C.red}✗ ${e.agent} ล้มเหลว${C.off}`);
        else if (e.type === "perm.requested")
          console.log(`${C.dim}${t}${C.off} ${C.yellow}🛡 ${e.agent} ขอใช้ ${e.tool} — กด allow ในหน้าโปรแกรม${C.off}`);
        else if (e.type === "task.delegated") console.log(`${C.dim}${t}${C.off} 📋 main → ${e.target}`);
        else if (e.type === "channel.message")
          console.log(`${C.dim}${t}${C.off} 📨 [${e.channel}] ${e.from}: ${e.text}`);
        else if (e.type === "voice.say")
          console.log(`${C.dim}${t}${C.off} ${C.mag}🗣 ${e.agent}: ${e.text}${C.off}`);
        else if (e.type === "proposal.created")
          console.log(`${C.dim}${t}${C.off} ${C.yellow}💡 ข้อเสนอใหม่: ${e.name}${C.off}`);
      }
    }, 800);
    return;
  }

  console.log(`ไม่รู้จักคำสั่ง "${cmd}" — ดู: ${C.cyan}bagidea help${C.off}`);
}

main().catch((e) => { console.error(`${C.red}✗${C.off} ${e.message}`); process.exit(1); });
