# 4. Agent Behavior Design

## 4.1 The Honesty Contract

Behavior simulation has one law: **real events drive primary behavior; flavor fills the gaps.**

```
PRIMARY (truth)    — driven by Layer 0 events. Never faked, never delayed >1s.
                     working, thinking, blocked, meeting, failed, sleeping…
SECONDARY (flavor) — autonomous life when no event demands anything.
                     coffee, chatting, stretching, watering plants…
```

A flavor behavior is **always interruptible** by a primary event within one animation beat (<800ms). The user must never wonder "is that animation real?" — anything attached to a nameplate/task tag is real; ambient life has no tags.

## 4.2 Architecture: Three Brains per Agent

```
┌─────────────────────────────────────────────────────┐
│ 1. STATE MIRROR (reactive)                          │
│    Maps runtime events → mandatory behavior states  │
│    e.g. task_started → GoTo(desk) → Work            │
├─────────────────────────────────────────────────────┤
│ 2. UTILITY AI (autonomous, only when unconstrained) │
│    Scores desires: coffee, social, rest, wander,    │
│    tidy, study. Picks highest, with cooldowns &     │
│    personality weights.                             │
├─────────────────────────────────────────────────────┤
│ 3. PERFORMER (expressive)                           │
│    Turns the chosen state into animation, pathing,  │
│    emotes, speech bubbles, sounds.                  │
└─────────────────────────────────────────────────────┘
```

## 4.3 Primary State Machine (event-driven)

```
                      task_assigned
   IDLE ──────────────────────────────► COMMUTING ──► WORKING
    ▲                                     (walk to      │ │
    │ task_done/cancelled                  zone desk)   │ │ needs_approval
    │◄──────────────────────────────────────────────────┘ │
    │                                                     ▼
    │            approved/denied                      BLOCKED
    │◄────────────────────────────── (walks to Security, waits)
    │
    │ collab_started                 task_failed
    ├─────────────► MEETING          WORKING ──► FRUSTRATED ──► retry/IDLE
    │               (walk to          (sparks,    (head in
    │                meeting room)     red tint)   hands beat,
    │ user_summons                                 then re-plan
    ├─────────────► REPORTING (walks toward       thought bubble)
    │               camera / lobby, faces user)
    │ disabled/offline
    └─────────────► SLEEPING (walks to Dormitory, lies down)
```

Sub-states of WORKING render the *kind* of work (chosen from task metadata):
`typing` (code/writing), `reading` (research — pages float), `drawing` (creative — easel), `terminal` (ops), `searching` (library terminal), `presenting` (meeting).

**Thinking vs. doing**: while the LLM is generating, the agent types/acts; during tool execution waits, the agent watches the monitor, taps the desk, sips coffee at desk — micro-behaviors that map to real latency so even "waiting" is honest.

## 4.4 Utility AI (flavor layer)

Each agent owns need meters (0–1) that drift over time and are satisfied by activities:

| Need | Builds when | Satisfied by | Where |
|---|---|---|---|
| Energy | long work streaks | coffee, resting | Cafeteria, Dorm |
| Social | long alone time | chatting (2–4 agents) | Cafeteria, hallways |
| Curiosity | idle | reading, browsing shelves | Library, Academy |
| Order | clutter events (failed tasks nearby) | tidying desk, watering plants | own zone |
| Movement | sitting long | wander loop, window gaze | anywhere |

`score(activity) = need_weight × personality_mult × distance_penalty × cooldown`. Highest score wins; ties broken by personality. Scoring runs at 0.5–2 Hz per agent (staggered), not per frame.

## 4.5 Personality System

Personality makes 50 agents readable as *individuals*, derived deterministically from the agent's config (role, model, name hash) so it's stable across sessions:

- **Archetype by role**: Researcher (bookish, walks slower, often in Library), Coder (headphones, energy drinks not coffee, night-owl idle hours), Designer (wanders to gallery, doodles when idle), Ops (brisk walk, clipboard), Main/CEO (rarely idles publicly; paces in Exec office when orchestrating).
- **Trait dials** (per agent, 0–1): pace, sociability, tidiness, expressiveness. These multiply utility weights and animation choices.
- **Signature quirk**: one per agent (stretches every 20 min, always takes the long route past the gallery, double-checks the door). Quirks are the detail players screenshot.

## 4.6 Emotion Display

Emotions are **state-derived, not simulated feelings** — a glanceable telemetry skin:

| System condition | Emotion display |
|---|---|
| Task progressing well | content; relaxed posture, occasional nod |
| High token throughput / deep generation | focused; leaned in, typing fast, 💭 particles |
| Tool error / retry loop | frustrated; ⚡ spark, scratches head |
| Task failed | dejected walk for 10s, then recovers (never sulks forever) |
| Task completed | mini celebration: fist pump / stretch / high-five if collaborators near |
| Waiting on approval | anxious idle at Security window, checks watch |
| Rate-limited / provider down | confused; stares at dead monitor, shrugs to neighbor |
| User addresses them | perks up, faces camera, attentive ears/eyes |

Renderer: emote icons above head (Stardew-style) + posture changes + eye/brow frames on the sprite. Color-and-shape coded for colorblind safety.

## 4.7 Collaboration Choreography

Multi-agent work is the showpiece. Real A2A protocol events choreograph scenes:

1. **Summon**: orchestrator event → invited agents path to Meeting Room (staggered arrival, 2–6s).
2. **Session**: seated; the *actual* shared context/plan renders on the whiteboard (summarized). Speaking turn = whoever's message is streaming gets the talk animation + bubble with a real excerpt.
3. **Handoff**: artifact passes as a glowing folder between characters (file/artifact reference is real, clickable).
4. **Dissolve**: agents return to zones; a faint "team thread" line links their desks for the mission's duration.
5. **Pairing** (2 agents): skip the room — one walks to the other's desk, leans over the shoulder (e.g., a reviewer agent on a coder agent).

If collaboration events arrive faster than walking allows (rapid A2A chatter), the room "catches up": agents already seated, the whiteboard backfills — choreography compresses, never lies about *what*, only about *travel time*.

## 4.8 Movement & Navigation

- **Navmesh** over the floor plan; doorways as choke metadata; per-zone seat/anchor slots (desk chairs, sofa spots, meeting chairs) claimed via reservation to prevent overlap.
- Sprites are 8-directional (or 4 + mirroring) with walk/run/sit/sleep/type/talk/celebrate/dejected sets; run is reserved for urgent states (blocked→security, critical failure) so speed itself carries meaning.
- **Crowd rules**: hallway lane offsets, polite yield animation when two paths cross (one steps aside — free charm), max N concurrent walkers per corridor (overflow teleports offscreen with door-transition fades).

## 4.9 The Living-Office Scheduler (no tasks running)

A global "stage manager" keeps the world alive within a calm budget:

- Targets **1 noticeable motion every 4–8 seconds** somewhere in frame at detent ① (less is dead, more is noisy).
- Schedules vignettes: two agents coffee-chat (45s), one waters plants, dispatcher tidies mission cards, librarian re-shelves a book, dorm agent turns in sleep.
- Time-of-day scripts: morning arrivals through the lobby, lunch wave to cafeteria, evening wind-down, night skeleton crew (only agents with scheduled/cron tasks stay at desks — *real* schedules drive who works nights).
- Deterministic seeded RNG per day → behavior is varied but reproducible (debuggable, and players notice "routines," which reads as character).

## 4.10 Behavior at Scale

- **Simulation LOD** (independent from render LOD):
  - **Hero** (on-screen, followed, or user-relevant): full FSM + utility + pathing, 60 Hz anim.
  - **Mid** (on-screen background): utility at 0.2 Hz, simplified paths, shared anim clock.
  - **Statistical** (off-screen / aggregated crowds): no individuals — a per-zone occupancy model (counts in/out); when the camera arrives, individuals are *instantiated from the statistics* (Hero-promoted agents keep continuity; flavor agents may differ — allowed, they're untagged).
- Primary (truth) events always process regardless of LOD — a blocked agent off-screen still raises the Security pulse and is promoted to Hero on camera arrival.
