# Writing a BagIdea Office plugin

A **plugin** extends the office in real ways — a panel the user opens, HTTP
routes, and **commands agents can drive**. Plugins are plain folders; no build
step, zero dependencies. Drop one in `plugins/` and reload.

This guide is written so a **person** OR an **agent** can build a working plugin
from scratch. The shipped `music` and `calculator` plugins are full examples.

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

- **Local**: drop the folder in `plugins/`, then restart, or `POST /plugins/reload`
  (the 🔄 button on the 🧩 panel).
- **From GitHub**: `bagidea plugin install https://github.com/you/your-plugin`
  (clones into `plugins/`; the repo must contain `plugin.json`).
- **Remove**: `bagidea plugin remove <id>` (or the 🗑 button; core plugins are
  protected).

---

## 7. Two worked examples

- **🎵 `plugins/music`** — playlist with upload/remove, play/pause/next/prev/loop/
  volume, a seek bar, audio streamed with HTTP Range, agent commands, live WS sync.
- **🧮 `plugins/calculator`** — a safe shunting-yard math engine (no `eval`):
  basic arithmetic + trig/logs/powers/roots/factorial/constants, shared by the
  panel UI and the `calc` agent command.

Read those two folders next to this guide — they cover every pattern here.

---

## 8. Checklist

- [ ] `plugin.json` with a unique `id`, `name`, `description`
- [ ] (optional) `index.js` exporting `(ctx) => ({ onCommand?, routes? })`
- [ ] (optional) `panel.html` for a UI
- [ ] commands listed in the manifest so agents can use them
- [ ] private state in `ctx.dataDir`, never hard-coded paths
- [ ] broadcast `plugin.event` so open panels stay live
- [ ] test: `POST /plugin/<id>/cmd` returns what you expect
