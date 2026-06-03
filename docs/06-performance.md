# 6. Performance Considerations

A wallpaper app is judged by a brutal standard: **it must cost almost nothing while you work**. Beauty that steals battery gets uninstalled in a day. Performance is therefore a *product feature with a UI*, not an afterthought.

## 6.1 Budgets (the contract with the user)

| Mode | GPU | CPU (daemon excl.) | RAM (renderer) | Target |
|---|---|---|---|---|
| Wallpaper, idle office | ≤ 3–5% of a mid GPU | < 1% | ≤ 400 MB | 24/30 fps |
| Wallpaper, busy office | ≤ 8% | < 3% | ≤ 500 MB | 30 fps |
| Interact / Command | ≤ 15% | < 5% | ≤ 600 MB | 60 fps |
| Occluded by fullscreen app | ~0% (paused) | < 0.5% | resident | 0–1 fps |
| On battery (laptop) | auto-drop one preset | — | — | 24 fps cap |

Daemon budget: idle < 0.3% CPU, < 150 MB; it must be invisible in Task Manager culture.

## 6.2 Adaptive Rendering Ladder

The renderer continuously selects a rung based on: focus state, occlusion, power source, thermal headroom, user preset (Cinematic / Balanced / Featherweight).

```
RUNG 5  Interact/Deep-Work: 60fps, full volumetrics, SDFGI, DoF, all particles
RUNG 4  Wallpaper-visible:   30fps, volumetrics half-res, baked GI + few realtime lights
RUNG 3  Battery/Featherweight: 24fps, no volumetrics (billboard god-rays), baked lighting only
RUNG 2  Glance-only (user inactive >10m): 10fps, animation keyframe skipping
RUNG 1  Occluded/locked screen: render paused; state machine still consumes OEP (cheap)
```

Transitions are hysteretic (no oscillation) and visually masked by a 300ms exposure fade.

## 6.3 GPU Techniques

- **Bake everything static**: GI lightmaps per time-of-day keyframe (6 baked sets, blended) — "dynamic lighting" reads as dynamic while costing a blend, not realtime GI. True realtime lights only for: screens (emissive, cheap), security pulse, server LEDs, hero spotlight.
- **Volumetrics on a card**: god rays = animated shader quads at Rungs ≤4; real volumetric fog only at Rung 5.
- **One draw call per crowd**: characters are sprite atlases rendered via MultiMesh instancing; animation = UV offset per instance (vertex shader), so 100 agents ≈ 1–3 draw calls.
- **Monitor content**: distant screens use a scrolling-glyph shader (zero text cost); real text rendered to a small RT only for the 1–3 screens near camera at detent ②/③.
- **Resolution scale** decouples from desktop res: render at 0.66–0.75× with FSR-style upscale in wallpaper modes — invisible at wallpaper viewing distance.
- Half-res bloom/DoF; film grain in the final composite pass (free-ish).

## 6.4 CPU & Simulation

- Behavior LOD as designed in [Agent Behavior §4.10](04-agent-behavior.md): Hero (full sim) / Mid (0.2 Hz utility ticks) / Statistical (per-zone counters). 100+ agents = ~12 full sims + arithmetic.
- Pathfinding: navmesh queries amortized (≤2 path requests/frame, queued); paths cached per (from-zone, to-zone) with local jitter.
- Utility AI staggered across frames (time-sliced scheduler); zero allocations in the hot loop (pooled events, pooled emotes).
- OEP ingestion: `llm.stream_delta` throttled at source to 5 Hz per agent; renderer coalesces by latest-wins per (agent, field).

## 6.5 Process & Power Hygiene

- **Occlusion detection** (Win: `DwmGetWindowAttribute`/occlusion APIs; mac: `occlusionState`) → Rung 1. Fullscreen game detected → also mute world audio.
- **Lid close / display sleep** → renderer fully suspends; daemon continues tasks; on wake, world fast-forwards via journal replay (agents "already moved" — honest and cheap).
- Timer coalescing in daemon (batch polls; no sub-second timers when idle).
- GPU watchdog: if frame time spikes (driver contention with a game), auto-drop a rung and toast once: "Office stepped aside for your game."

## 6.6 Memory & Assets

- Texture atlases per zone; zones outside camera at detent ② demote mips. Total VRAM target ≤ 350 MB.
- Sprite sheets: 8-dir × ~10 anims at 128px — ~2 MB per character archetype; agents share archetype sheets + palette-swap shader for identity (hair/clothes tint masks) → 100 unique-looking agents from ~8 sheets.
- Audio: short foley loops, positional, hard-capped voice count (8); all ambient audio off in wallpaper mode by default.

## 6.7 Startup & Resilience

- Cold start to first frame < 3s (show lobby first, stream in other zones).
- Renderer crash → auto-restart, replays last 60s of journal to reconstruct scene; daemon crash → renderer shows "office after-hours, doors locked" state + reconnect loop (the failure state is itself diegetic).

## 6.8 The Performance UI

Settings page shows a live meter: *"Office is using 4% GPU · 0.8% CPU · est. +6 min battery/hr"* with the three presets and per-feature toggles (volumetrics, particles, idle drift, fps cap). Transparency converts skeptics — make the cost visible and controllable.
