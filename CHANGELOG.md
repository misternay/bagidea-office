# Changelog

All notable changes to BagIdea Office. A **release** is a deliberate `VERSION`
bump on `main` (see [RELEASING.md](RELEASING.md)) — that's what triggers the
in-app 🔄 update banner. Versions follow [semver](https://semver.org).

## [0.7.3] — Dogs back on the ground

**Fixed**
- **Dogs (and the cat) no longer look like they're floating.** Their billboards
  were casting a drifting shadow that read as "airborne" (more obvious after the
  v0.7.2 shadow upgrade); they now skip shadow-casting like every other character.

## [0.7.2] — Media, project fixes, a livelier office

**Added**
- **Open chat media in a real window / its folder.** Every image & file in chat
  now has **⤢** (open in a separate, resizable window — the OS viewer/player) and
  **📂** (reveal in the file manager). Click an image for a quick in-app preview,
  or ⤢ for the big window.
- **Search box on the projects list** (OFFICE OPS → Projects) — find a project
  fast as the list grows.
- **Server-room emergencies 🔥.** The server room now occasionally blows up /
  catches fire and an agent **sprints over to put it out** — a little drama that
  finally gives the room a purpose.

**Fixed**
- **Audio & video now play (and seek) in chat** — media is served with HTTP Range,
  which Chromium/WebView2 needs for `<video>`; before, clips often wouldn't play.
- **Project ⏹ Stop now really closes the work window.** It used to leave the
  window lingering so the project looked "still open" and any click re-flagged it
  as active.
- **The 📂 open-folder button works** (it was passing the path to Explorer wrong).
- **Shadows cleaned up** — the hard, jagged, striping/cut-off look is gone
  (orthogonal shadows sized to the room, higher-res map, tuned bias).
- **The projects list stops jumping to the top** every time a status icon
  changes — it remembers your scroll position (and your search).

**Changed**
- **Agents aim for useful work, not junk.** The team now builds genuinely useful
  plugins/apps (no more throwaway-plugin spam), is more selective, and explains
  proposals in enough detail for you to decide.
- **The chase/tag game actually sprints** room-to-room now (you'll see it), with
  effects — instead of a barely-visible shuffle.

**Removed** — nothing.

## [0.7.1] — Voice input fix + audio device settings

**Fixed**
- **Voice dictation now grows the chat box.** A long spoken message used to land
  as multiple lines crammed into one unreadable row (the box only auto-grew while
  *typing*). Dictated text now expands the box exactly like typing does.

**Added**
- **Audio device settings** (⚙ → AGENTS): choose which **microphone** the office
  records your voice from and which **speaker** agent voices + sound effects play
  through — fixes cases where the wrong or too-quiet mic was being used. Your
  choice is remembered. (Speaker selection needs platform support; where it isn't
  available — e.g. macOS — it's disabled with a note pointing to the OS settings.)

## [0.7.0] — Leaner & smarter: Hermes-style memory + native skills

A big efficiency pass. The office is **exactly as capable** — every feature is
still here, agents are as smart, and they keep learning — it just uses far fewer
tokens and stays fast no matter how long it runs. Everything new is reversible
behind a setting (`retrieval`, `nativeSkills`) and falls back to the old
behavior if anything goes wrong.

**Added**
- **Relevance memory (the "Hermes" way).** Instead of pasting an agent's last few
  memories into every prompt, the office now *retrieves only the memories
  relevant to the task at hand* — so answers are better-grounded and cheaper.
- **Per-project memory.** Each project grows its own memory file; agents working
  in a project recall that project's facts specifically.
- **Archive search.** A new `archive-search` skill + a `/recall` lookup let
  agents search past conversations, meetings and notes before answering, instead
  of guessing. Pure on-device keyword search — no extra API cost.
- **Chat timestamps.** Every message now shows its date & time.
- **Click an image to view it full-size**, right inside the chat.

**Changed / Upgraded**
- **Skills are now delivered natively & on demand.** Agents still learn new
  skills automatically (nothing about learning changed), but skill instructions
  are now disclosed only when a skill is actually relevant — they no longer fill
  up every prompt. Same skills, far less overhead. Skills now also reach resumed
  sessions and sub-agents (they didn't before).
- **Lighter team meetings.** Agents discuss using a rolling window of the recent
  exchange instead of re-reading the entire growing transcript each turn (the
  full minutes are still saved). This was the single biggest token drain.
- **Cheaper Director check-ins.** The hourly overview is skipped when nothing has
  changed since the last one, and the default interval moved 30 → 60 minutes.

**Fixed / Performance**
- **The activity log no longer grows forever.** `journal.jsonl` is trimmed to a
  healthy size on startup (it was read in full on every reconnect, which got
  slow over time), and stale chat threads are pruned — your latest thread per
  agent is always kept.
- Overall: dramatically fewer tokens spent during autonomous agent-to-agent
  chatter, delegation and idle check-ins.

**Removed** — nothing. All features are intact.

## [0.6.4] — Director's desk + Thai in the Security Center

- **Fixed — agents stopped stealing the Director's desk.** Freed desks were
  recycled into the shared Ops pool *including the Director's private
  workstation* (`lead_desk`). Since the host session (main) finishes work
  constantly, that desk kept re-entering the pool and other agents would sit at
  it. The Director's desk is now excluded from the pool, so staff reliably use
  the shared Ops desks and only the Director uses the Exec workstation.
- **Fixed — Thai (and other non-ASCII) text rendered as mojibake** in the
  Windows permission card. The `PreToolUse` hook now reads stdin and POSTs its
  body as UTF-8 end-to-end, and the daemon decodes request bodies as UTF-8 in a
  single pass (so multibyte characters that straddle a TCP chunk survive too).

## [0.6.3] — Right Ctrl push-to-talk

- **Changed — Right Ctrl is the default push-to-talk hotkey.** It's rarely typed,
  which makes it ideal for hold-to-talk without clashing with normal typing.

## [0.6.2] — Smooth wallpaper

- **Fixed — wallpaper stutter / idle GPU.** A mis-firing occlusion throttle was
  pinning the renderer at ~2 fps; it's disabled until it can be made reliable.

## [0.6.1] — macOS install & CLI fixes

- **Fixed — macOS installer and path execution** issues (#2, #3) and a stray
  token that broke the `bagidea` CLI on every platform (PR #4 follow-up).
- Groundwork for auto-throttling the wallpaper when it's fully covered.

## [0.6.0] — Usability, office life & cost visibility

- Multiline chat and note inputs; notes can be opened and edited in place.
- More playful ambient life and clearer hotkey discoverability.
- Cost visibility: estimated Claude / Gemini / OpenAI spend surfaced in stats.

## [0.5.0] — First macOS support (beta)

- **First macOS build (beta)** alongside Windows.
- Full internationalization across 14 languages with resilient seed loading and
  atomic i18n cache writes.
- Daemon watchdog so the office never sits brainless after a crash.
- Localized wallpaper agent status plates to match the chosen language.

## [0.4.0] — Translations, sponsors & voices

- Ship UI translations (14 languages).
- Sponsors section (WARRIX as Gold Partner).
- More agent voices and an orb watchdog.

## [0.3.1] — Uninstall & story

- `bagidea uninstall` command.
- Sharpened the product story across README and the website.

## [0.3.0] — Art in the box

- Bundle the free / CC0 art packs (characters, 3D models, sounds) directly in
  the repo, so a fresh install and `bagidea update` carry the full look out of
  the box.

---

*Earlier history predates this changelog — see `git log` for the full record.*

[0.7.3]: https://github.com/bagidea/bagidea-office/releases/tag/v0.7.3
[0.7.2]: https://github.com/bagidea/bagidea-office/releases/tag/v0.7.2
[0.7.1]: https://github.com/bagidea/bagidea-office/releases/tag/v0.7.1
[0.7.0]: https://github.com/bagidea/bagidea-office/releases/tag/v0.7.0
[0.6.4]: https://github.com/bagidea/bagidea-office/releases/tag/v0.6.4
[0.6.3]: https://github.com/bagidea/bagidea-office/releases/tag/v0.6.3
[0.6.2]: https://github.com/bagidea/bagidea-office/releases/tag/v0.6.2
[0.6.1]: https://github.com/bagidea/bagidea-office/releases/tag/v0.6.1
[0.6.0]: https://github.com/bagidea/bagidea-office/releases/tag/v0.6.0
[0.5.0]: https://github.com/bagidea/bagidea-office/releases/tag/v0.5.0
[0.4.0]: https://github.com/bagidea/bagidea-office/releases/tag/v0.4.0
[0.3.1]: https://github.com/bagidea/bagidea-office/releases/tag/v0.3.1
[0.3.0]: https://github.com/bagidea/bagidea-office/releases/tag/v0.3.0
