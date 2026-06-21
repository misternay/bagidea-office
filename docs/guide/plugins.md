# Writing a BagIdea Office plugin

A **plugin** extends the office in real ways — a panel the user opens, HTTP
routes, and **commands agents can drive**. Plugins are plain folders; no build
step, zero dependencies. Drop one in `plugins/` and reload.

![แผง PLUGINS — ติดตั้ง/รีโหลด/ลบ + ติดตั้งจาก GitHub](../img/plugins.png)

> ⚙ → **PLUGINS**: ดูปลั๊กอินที่ติดตั้ง, เปิดแผงของแต่ละตัว, ลบ, หรือ
> **ติดตั้งจาก GitHub repo ใดก็ได้** — วาง URL แล้วกดติดตั้ง (เริ่มจาก
> template ทางการได้: `github.com/bagidea/bagidea-office-template`)

This guide is written so a **person** OR an **agent** can build a working plugin
from scratch. The `music` and `calculator` plugins (§7) are full examples to read.

> 📦 **ออฟฟิศติดตั้งมาแบบว่างเปล่า — ไม่มีปลั๊กอินติดมาให้** เลย (ดู `.gitignore`:
> `plugins/*`). เจ้าของออฟฟิศเป็นคนเลือกติดตั้งเองจาก **Plugins Hub** ทีละตัว
> (แต่ละตัวคือ GitHub repo ที่ clone เข้ามา) ดูวิธีใช้ในหัวข้อ **"ใช้ปลั๊กอินสำเร็จรูป"** ด้านล่าง

## ใช้ปลั๊กอินสำเร็จรูป (เริ่มจาก 🎵 Music Player)

ครั้งแรกที่เปิดออฟฟิศจะ **ยังไม่มีปลั๊กอินสักตัว** ติดเองได้จาก ⚙ → **🧩 PLUGINS**:

1. เปิดแผง **🧩 PLUGINS** แล้วไปแท็บ **Hub** (แคตาล็อกทางการอยู่ที่ `web/plugins.json`)
2. กดติดตั้ง **🎵 Music Player** (ปลั๊กอินทางการตัวแรก) — ออฟฟิศจะ clone จาก repo ให้อัตโนมัติ
3. (หรือวาง URL ของ GitHub repo ใดก็ได้ที่มี `plugin.json` แล้วกดติดตั้ง)

**ใช้งาน 🎵 Music Player** — เปิดแผงของมันแล้ว:
- **เพิ่มเพลง** — อัปโหลดไฟล์เสียงเข้าเพลย์ลิสต์ (รองรับชื่อไฟล์ภาษาไทย/หลายภาษา)
- **เล่น/หยุด/เพลงถัดไป-ก่อนหน้า** — ปุ่มควบคุม + แถบ seek เลื่อนตำแหน่งได้
- **วนเพลย์ลิสต์ (loop) + ปรับเสียง (volume)**
- **ลบหลายเพลงพร้อมกัน** — เลือกหลายรายการ (multi-select) แล้วลบทีเดียว
- **agents สั่งได้ด้วย** — คำสั่งในมือ agent: `play / pause / next / prev / loop / volume / remove / status`
  (เช่นพิมพ์สั่งว่า "เปิดเพลง" ทีมก็เปิดให้ และแผงที่เปิดอยู่หน้าจอจะอัปเดตสด)

ลบปลั๊กอินได้จากปุ่ม 🗑 บนแผง 🧩 (ดูหัวข้อ §6 ติดตั้ง/ลบ)

---

## 1. Anatomy

```
plugins/<id>/
  plugin.json     ← manifest (required)
  index.js        ← server-side logic (optional)
  panel.html      ← an overlay UI the user opens (optional)
  data/           ← your plugin's private storage (gitignored, auto-created)
  static/...      ← any files panel.html loads (served at /plugin/<id>/static/…)
```

A plugin needs **only** `plugin.json`. Add `index.js` for server power, and/or
`panel.html` for a UI.

---

## 2. `plugin.json`

```json
{
  "id": "calculator",
  "name": "🧮 Calculator",
  "version": "1.0.0",
  "description": "What it does, in one line.",
  "panel": "panel.html",
  "window": { "w": 420, "h": 560, "resizable": true },
  "commands": [
    { "name": "calc", "args": "<expression>", "desc": "Evaluate a math expression" }
  ],
  "needsKeys": [],
  "enabled": true
}
```

| field | meaning |
|---|---|
| `id` | unique slug (defaults to the folder name) |
| `name` | shown in the UI / `bagidea plugins` |
| `panel` | the HTML file to open as a panel (omit for headless plugins) |
| `window` | *(optional)* default size when the panel is **popped out into its own window** (see §4): `{ "w": <px>, "h": <px>, "resizable": true|false }`. Defaults to `900×680`, resizable. Pick a size that fits your UI; set `resizable: false` for a fixed-size tool. |
| `commands` | what **agents** can call — each `{name, args, desc}` |
| `needsKeys` | main API key names this plugin needs (informational) |
| `enabled` | set `false` to ship-but-disable |

---

## 3. `index.js` — the server side

`index.js` exports a factory that receives `ctx` and returns handlers:

```js
module.exports = (ctx) => ({
  // Called when an agent or the panel POSTs /plugin/<id>/cmd {cmd, args}.
  onCommand(cmd, args, reply) {
    if (cmd === "calc") return reply({ ok: true, result: 42 });
    return reply({ ok: false, msg: "unknown command" });
    // async is fine: return a Promise, or call reply() later.
  },
  // Custom HTTP routes at /plugin/<id>/<name>
  routes: {
    eval(req, res, { readBody, readBodyRaw }) {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ ok: true }));
    },
  },
});
```

### `ctx` — what a plugin can reach
| field | use |
|---|---|
| `ctx.broadcast(event, persist?)` | push a live event to every panel + the office feed (WS). Use `{type:"plugin.event", plugin:"<id>", ...}` |
| `ctx.feed(text, agentId?)` | post a visible line to the office feed stream (defaults to the `main` agent) |
| `ctx.reg` | the office registry (agents, roles, settings) — read it freely |
| `ctx.saveReg()` | persist registry changes you made (after mutating `ctx.reg`) |
| `ctx.workspace` | absolute path to the agents' workspace |
| `ctx.daemonDir` | the daemon folder — read office data files (`registry.json`, `projects.json`, …) |
| `ctx.dataDir` | `plugins/<id>/data` — your private storage |
| `ctx.pluginDir` | your plugin's folder (for `static/`, bundled files) |
| `ctx.manifest` | your parsed `plugin.json` |
| `ctx.log(msg)` | write to the daemon log |
| `ctx.runClaude(agentId, prompt, opts?)` | run a real Claude Code turn as that agent — the same engine the office uses (advanced) |

### Built-in HTTP routes (free, no code)
- `GET /plugin/<id>/panel` → serves your `panel.html`
- `GET /plugin/<id>/static/<file>` → serves files from the plugin folder
- `POST /plugin/<id>/cmd` `{cmd,args}` → calls your `onCommand`

`reply(data)` sends JSON back. For binary/streaming, write to `res` directly in a
custom route (see `music`'s `track` route — it streams audio with HTTP Range; and
its `upload` route accepts a raw file body via `readBodyRaw`).

> **Non-ASCII args (Thai/Chinese/emoji words):** when an agent drives a command from
> the shell, do **not** put non-English text inline (`-d "{...}"`) — on Windows the shell
> codepage corrupts it to `?` before `curl` even runs. Write the JSON body to a UTF-8 file
> and send it: `curl ... --data-binary @body.json`. The daemon and panels handle UTF-8
> fine; only the inline command line is unsafe.

> **Don't ASCII-strip filenames or text (the office speaks 14 languages):** a
> sanitizer like `name.replace(/[^\w.\- ]/g, "_")` deletes every Thai/Chinese/Arabic
> character (`\w` is ASCII-only) — that turned Thai song names into `____` in the Music
> Player. Strip only what's unsafe and keep all letters:
> ```js
> const safe = raw.split(/[\\/]/).pop()        // basename → blocks ../ traversal
>   .replace(/[\x00-\x1f<>:"|?*]/g, "_")        // control + Windows-reserved → _
>   .replace(/^\.+/, "").trim();                // no leading dots
> ```
> In `panel.html`, give `font-family` a multilingual fallback (e.g.
> `system-ui,"Segoe UI","Leelawadee UI",Tahoma,"Noto Sans Thai","Noto Sans CJK",sans-serif`)
> so non-Latin text renders instead of blank glyphs.

---

## 4. `panel.html` — the UI

A normal HTML file. It runs in the overlay webview and can call your routes:

```js
// read state
const s = await (await fetch("/plugin/<id>/state")).json();
// send a command (the SAME path agents use)
await fetch("/plugin/<id>/cmd", { method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ cmd: "play", args: "1" }) });
// live updates when an AGENT changes things
const ws = new WebSocket("ws://127.0.0.1:8787/ws");
ws.onmessage = (m) => { const e = JSON.parse(m.data);
  if (e.type === "plugin.event" && e.plugin === "<id>") refresh(); };
```

Keep the dark theme (`background:#0c1322; color:#dbe7ff; accent #5ec8ff`) so it
matches the office.

**Pop-out window.** Besides opening inside the overlay, the user can pop your
panel out into its **own resizable OS window** (the ⤢ button). It opens inside a
custom dark title-bar frame — your `panel.html` is the body. Two things to design
for: (1) make the layout **fluid** (use `%`/`vh`/flex, not a hard-coded size) so
it looks right at any window size; (2) set a sensible default + `resizable` via
the `window` field in `plugin.json` (above). The same panel serves both the
in-overlay view and the window, so build it once. Each plugin opens **one**
window at a time (re-clicking ⤢ just focuses it); different plugins open side by
side. This is how a plugin can grow into a real, standalone app under BagIdea
Office.

---

## 5. Agents and plugins

Every plugin's `commands` are injected into agent prompts automatically (see
`plugins.js → agentNote()`), so an agent can drive your plugin with a Bash call:

```bash
curl -s -X POST http://127.0.0.1:8787/plugin/calculator/cmd \
  -H "content-type: application/json" -d '{"cmd":"calc","args":"2*(3+4)^2"}'
```

Because the panel and agents both go through `/cmd`, an agent saying *"loop the
playlist"* really controls the panel open in front of the user.

**An agent can also CREATE a plugin**: write the folder + files under `plugins/`,
then `curl -s -X POST http://127.0.0.1:8787/plugins/reload -H "x-bagidea-ui: 1"`.
Point the agent at this guide and it has everything it needs.

---

## 6. Installing / removing

> **Fastest start:** fork the template repo
> [`bagidea/bagidea-office-template`](https://github.com/bagidea/bagidea-office-template)
> — a working plugin (`hello`) that reads live office data, posts to the feed and
> shows every pattern here, plus a `CLAUDE.md` so an agent can extend it. Then
> `bagidea plugin install <your-fork-url>`.

- **Local**: drop the folder in `plugins/`, then restart, or `POST /plugins/reload`
  (the 🔄 button on the 🧩 panel).
- **From GitHub**: `bagidea plugin install https://github.com/you/your-plugin`
  (clones into `plugins/`; the repo must contain `plugin.json`).
- **Remove**: `bagidea plugin remove <id>` (or the 🗑 button; core plugins are
  protected).

---

## 7. Two worked examples

These are reference folders to **read while building** (they cover every pattern
here). Only the Music Player is published to the Hub; the calculator is an example.

- **🎵 `plugins/music`** — the official Music Player (install it from the 🧩 Hub):
  playlist with upload/multi-select-remove, play/pause/next/prev/loop/volume, a seek
  bar, audio streamed with HTTP Range, agent commands, live WS sync.
- **🧮 `plugins/calculator`** — a safe shunting-yard math engine (no `eval`):
  basic arithmetic + trig/logs/powers/roots/factorial/constants, shared by the
  panel UI and the `calc` agent command.

---

## 8. Checklist

- [ ] `plugin.json` with a unique `id`, `name`, `description`
- [ ] (optional) `index.js` exporting `(ctx) => ({ onCommand?, routes? })`
- [ ] (optional) `panel.html` for a UI
- [ ] commands listed in the manifest so agents can use them
- [ ] private state in `ctx.dataDir`, never hard-coded paths
- [ ] broadcast `plugin.event` so open panels stay live
- [ ] test: `POST /plugin/<id>/cmd` returns what you expect
