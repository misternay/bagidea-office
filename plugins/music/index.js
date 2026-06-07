// 🎵 Music Player plugin — server side.
// Holds the authoritative player STATE (what to play, paused, volume, loop,
// playlist) and broadcasts it. Actual audio plays in the overlay panel (the
// webview can decode mp3); agents and the UI both mutate state through
// commands, so an agent saying "loop this playlist" really controls the
// panel that's open in front of the user.
const fs = require("fs");
const path = require("path");

module.exports = (ctx) => {
  const TRACKS_DIR = path.join(ctx.pluginDir, "tracks");   // drop .mp3 files here
  fs.mkdirSync(TRACKS_DIR, { recursive: true });
  const STATE_FILE = path.join(ctx.dataDir, "state.json");

  let state = load();
  function load() {
    try { return JSON.parse(fs.readFileSync(STATE_FILE, "utf8")); } catch {}
    return { playing: false, index: 0, volume: 60, loop: true, track: null };
  }
  function save() { fs.writeFileSync(STATE_FILE, JSON.stringify(state)); }

  function playlist() {
    try {
      return fs.readdirSync(TRACKS_DIR)
        .filter((f) => /\.(mp3|ogg|wav|m4a)$/i.test(f))
        .sort();
    } catch { return []; }
  }

  // push state to every open panel + the office feed
  function push(note) {
    const list = playlist();
    state.track = list[state.index] || null;
    save();
    ctx.broadcast({ type: "plugin.event", plugin: "music",
      event: "state", state: { ...state, count: list.length }, note }, false);
  }

  function onCommand(cmd, args, reply) {
    const list = playlist();
    const a = String(args || "").trim();
    switch (cmd) {
      case "play":
        if (a) {
          // by number, or fuzzy filename match
          const n = parseInt(a, 10);
          if (!isNaN(n) && n >= 1 && n <= list.length) state.index = n - 1;
          else {
            const i = list.findIndex((f) => f.toLowerCase().includes(a.toLowerCase()));
            if (i >= 0) state.index = i;
          }
        }
        state.playing = true;
        push("▶ เล่น");
        return reply({ ok: true, track: list[state.index] || null,
          msg: list.length ? "กำลังเล่น: " + (list[state.index] || "") : "ยังไม่มีเพลงในโฟลเดอร์ plugins/music/tracks" });
      case "pause": state.playing = false; push("⏸ หยุด"); return reply({ ok: true });
      case "next": state.index = list.length ? (state.index + 1) % list.length : 0; state.playing = true; push("⏭"); return reply({ ok: true, track: list[state.index] });
      case "prev": state.index = list.length ? (state.index - 1 + list.length) % list.length : 0; state.playing = true; push("⏮"); return reply({ ok: true, track: list[state.index] });
      case "loop": state.loop = a !== "off"; push(state.loop ? "🔁 วนเปิด" : "วนปิด"); return reply({ ok: true, loop: state.loop });
      case "volume": { const v = Math.max(0, Math.min(100, parseInt(a, 10) || state.volume)); state.volume = v; push("🔊 " + v); return reply({ ok: true, volume: v }); }
      case "status": return reply({ ok: true, ...state, count: list.length, track: list[state.index] || null });
      default: return reply({ ok: false, msg: "ไม่รู้จักคำสั่ง: " + cmd });
    }
  }

  return {
    onCommand,
    routes: {
      // GET /plugin/music/state — panel polls this on open
      state(req, res) {
        const list = playlist();
        state.track = list[state.index] || null;
        res.writeHead(200, { "content-type": "application/json; charset=utf-8" });
        res.end(JSON.stringify({ ...state, list, count: list.length }));
      },
      // GET /plugin/music/track?i=N — stream a track to the panel
      track(req, res) {
        const i = parseInt(new URL(req.url, "http://x").searchParams.get("i"), 10) || 0;
        const list = playlist();
        const f = list[i];
        if (!f) { res.writeHead(404); return res.end(); }
        const full = path.join(TRACKS_DIR, f);
        const ext = f.split(".").pop().toLowerCase();
        const mime = { mp3: "audio/mpeg", ogg: "audio/ogg", wav: "audio/wav", m4a: "audio/mp4" }[ext];
        const data = fs.readFileSync(full);
        res.writeHead(200, { "content-type": mime, "cache-control": "max-age=3600" });
        res.end(data);
      },
    },
  };
};
