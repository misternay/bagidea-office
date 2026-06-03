# 3. World Layout (Layer 1)

## 3.1 Floor Plan — "The Cross-Section Diorama"

The office reads like a **dollhouse cross-section** (Spiritfarer ship / Octopath town): a wide isometric diorama where every zone is visible at the default camera, walls cut away toward the camera. Designed for a 16:9 wallpaper; safe margins for desktop icons on the left edge (icon-aware layout option).

```
              NORTH (back, elevated — "command" floors)
 ┌────────────┬──────────────────────┬───────────────────────┐
 │  SERVER    │   MISSION CONTROL    │   EXECUTIVE OFFICE    │
 │  ROOM      │   giant ops map,     │   main agent desk,    │
 │  racks,    │   mission queue      │   holo-screens,       │
 │  cold blue │   board              │   world map, warm gold│
 ├────────────┼──────────┬───────────┼───────────────────────┤
 │  SECURITY  │ MEETING  │  TRAINING │   ARCHIVE LIBRARY     │
 │  CENTER    │ ROOM     │  ACADEMY  │   infinite shelves    │
 │  amber     │ glass    │  classrm, │   (parallax depth     │
 │  screens   │ walls    │  sim pods │    illusion), crystals│
 ├────────────┴──────────┴───────────┴───────────────────────┤
 │                    OPERATIONS FLOOR                        │
 │   open-plan desks ▦ ▦ ▦ ▦ ▦   live monitors, task beams   │
 ├──────────────┬───────────────────┬─────────────────────────┤
 │  RESEARCH    │   DEVELOPMENT     │   CREATIVE STUDIO       │
 │  LAB         │   STUDIO          │   easels, tablets,      │
 │  data walls, │   build monitors, │   gallery wall of real  │
 │  float docs  │   CI/CD boards    │   generated images      │
 ├──────────────┼───────────────────┼─────────────────────────┤
 │  DORMITORY   │   MAIN LOBBY      │   CAFETERIA             │
 │  beds, cozy  │   ⟡ front door,   │   coffee bar, tables,   │
 │  night light │   logo, directory,│   plants, idle chatter  │
 │              │   status totem    │                         │
 └──────────────┴───────────────────┴─────────────────────────┘
              SOUTH (front, street level — "life" floors)
```

**Layout logic (readability first):**
- **Vertical = authority/abstraction**: life at the bottom (lobby, cafeteria, dorm), execution in the middle (ops, lab, dev, creative), command at the top (exec, mission control, server). A glance up the building = a glance up the stack.
- **Hot paths are short**: Cafeteria↔Ops (idle→work), Dorm↔Lobby (wake→sign-in), Meeting Room is central (everyone can reach it fast), Security adjoins Server (trust boundary is one wall).
- **Color-keyed zones**: each zone owns a lighting hue (Exec=gold, Lab=teal, Dev=blue, Creative=magenta, Server=cold cyan, Security=amber, Dorm=warm dusk, Cafeteria=cozy orange). Hue alone identifies the zone at minimap scale.

## 3.2 Zone-by-Zone Design

### 1 · Main Lobby — *the system status page, embodied*
- **Status Totem**: a tall holographic pillar by the door showing total/active/sleeping agents and tasks in progress — the literal "shows" list from the spec, as one piece of furniture.
- **Agent Directory wall**: portrait frames light up per online agent (clickable → agent card).
- New agents enter through the front door; results "ship" via a glowing outbox tray.
- *State mapping*: app launch = lights come on lobby-first; daemon disconnected = lobby goes dark, front door closed.

### 2 · Executive Office — *orchestration made visible*
- Main Agent at a large desk; **3 holo-screens** show its actual context: current plan (live), delegation graph (which agents own which subtask), and a world-map flair screen.
- **Mission board behind the desk** mirrors the top-3 priority missions.
- When orchestrating, the Main Agent stands at the delegation graph and "conducts" — lines animate from it to subagent portraits.

### 3 · Operations Floor — *the heartbeat*
- Rows of desks; any agent doing generic task work sits here. Monitors render **real artifacts**: scrolling code, document text, terminal output (shader-faked at distance, real text when zoomed).
- **Task beams**: a thin light thread connects each busy desk up to its mission card in Mission Control — instantly answers "who's working on what."
- Desk count grows with agent count (see 3.6 scaling).

### 4 · Research Lab — *knowledge in motion*
- Floating documents orbit a central data wall; each open source/URL an agent reads appears as a floating page (title legible on zoom).
- Bookshelves pulse when the agent cites stored knowledge ([[Archive Library]] link — a pneumatic tube visibly delivers a "memory" capsule from the Library).

### 5 · Development Studio — *the build floor*
- Workstations with dual monitors; **CI/CD status board** on the wall (green/red pipeline lamps = real test/build results).
- Compile/test runs: the agent leans back, a progress gauge spins above the workstation; failures spark a tiny ⚡ and the agent leans in to debug.

### 6 · Creative Studio — *the gallery*
- Easels and drawing tablets; **generated images literally appear on canvases** and get hung on the gallery wall (latest 6, clickable to open the file).
- Skylight + softer light; particles like paint motes.

### 7 · Meeting Room — *agent-to-agent traffic, dramatized*
- Glass walls (collaboration should be watchable). Long table, wall screen, whiteboard rendering the **actual shared plan/messages** (summarized).
- A2A message exchange = agents seated, speech bubbles with real snippet excerpts; presenting agent stands at the screen.
- Room books itself: a glowing "RESERVED — Mission #41" plate when a collab session starts.

### 8 · Mission Control Center — *the task system, physical*
- **Giant ops map** (stylized world/system map) with pins per running mission; **queue board** with magnetic mission cards in Pending/Running/Done/Failed columns.
- A small "dispatcher" NPC (system-owned, not a user agent) moves cards between columns — the world's stagehand.
- Failed missions: card flips red, a klaxon light (silent by default) rotates once.

### 9 · Training Academy — *future-facing, present from V1 as a place*
- Classroom + 2 simulation pods. V1: agents idle-study here occasionally (flavor). V2+: real fine-tuning of prompts/workflows = agent attends class; completing N missions of a type = visible "certification" diploma on the wall (see [Progression](08-progression.md)).

### 10 · Archive Library — *the vector DB you can walk through*
- Shelves recede with a parallax "infinite" illusion; **knowledge crystals** glow per memory collection; search terminals at the front.
- Real RAG events: a query = a librarian beam scans shelves, a crystal lights, a capsule shoots via pneumatic tube to the requesting zone. Memory writes = a new book slot glows briefly.

### 11 · Server Room — *infra status, ambient*
- Racks per connected provider/endpoint (Anthropic, OpenAI, local llama.cpp, etc.). **Rack LEDs = live API health**; fan speed/heat shimmer = current token throughput; a power meter shows spend rate (optional $ mode).
- Provider outage = that rack goes dark + Security amber pulse if tasks are blocked.

### 12 · Dormitory — *offline with dignity*
- Cozy bunks; sleeping = agent disabled/offline (Zzz particles). Reading in an armchair = standby (enabled, no tasks, low-power). Disabled-by-error = restless sleep + red blanket tint (subtle but legible).
- Waking an agent (summon/new task): lights up, stretch animation, walks out — a 3-second ritual that makes "starting a session" feel alive.

### 13 · Cafeteria — *the idle pool*
- Coffee machine, tables, plants. Idle-but-ready agents gather, sip coffee, hold ambient conversations (procedurally generated small talk — optionally seeded by real recent task topics: "heard you shipped the landing page").
- The cafeteria is the **default spawn for ready agents** — so an empty cafeteria means "everyone is working" (a productivity signal you can feel).

### 14 · Security Center — *trust, spatialized*
- Monitor wall showing recent privileged operations log; **the locked door** between Security and Server Room is the permission metaphor: tools/scopes = keycards.
- All approval flows route here visually: requesting agent waits at the window; approve = green stamp + door opens; deny = polite red stamp, agent leaves.
- Permission config UI is reached by clicking this room — settings as a *place*.

## 3.3 Camera Design

- **Projection**: perspective with a long lens (25–30° FOV) for the Octopath look — near-isometric but with real depth for volumetrics.
- **Default**: whole-office diorama framing (wallpaper hero shot), pitch ~30°, slight yaw 15°.
- **Zoom detents**: ① Office (all zones) → ② Zone (one room fills frame, wall fully cut away) → ③ Agent (over-shoulder of a character; their monitor becomes readable). Smooth scroll between detents with magnetic snapping.
- **Follow mode**: lock to an agent; camera trails them between rooms (great for "watch Rin work").
- **Bookmarks** `1–9` per zone; `0` = default diorama.
- **Idle drift**: in wallpaper mode, a 90-second slow dolly loop across the office (disable-able) — the "screensaver that's real."

## 3.4 Lighting & Time

- **HD-2D recipe**: 3D environment with PBR materials + volumetric god rays through windows + emissive screens; 2D character sprites are billboarded, lit by the 3D lights (normal-mapped sprites so they sit in the scene), tilt-shift depth-of-field at detent ①, gentle bloom, film grain at 2–4%.
- **Day cycle** synced to real local time: morning gold → noon neutral → evening amber → night (interior lamps, blue exterior). Office activity is legible at all times (screens are always readable).
- **Weather flair** (optional): rain on windows synced to real local weather API.
- **System-state lighting**: global mood follows load — heavy compute = warmer/busier light + more particle dust; all-idle night = dimmed, only cafeteria and dorm lit. *Lighting itself is a status display.*

## 3.5 Inhabiting the Wallpaper

- Renders **behind desktop icons** (Windows: WorkerW layer, same approach as Wallpaper Engine; macOS: desktop-level window below icons).
- **Icon-aware layout** option: detect icon grid occupancy and bias the camera framing so the office hero zones avoid icon-dense regions.
- Multi-monitor: office spans monitors as one wide building (each monitor = a wing), or one monitor hosts the office, others get the "exterior street view."

## 3.6 Scaling the World: 1 → 100+ Agents

| Population | Visual strategy |
|---|---|
| **1–5** | Cozy startup: half the desks empty but tidy; unused zones dimmed with dust-sheet props ("not yet unlocked" doubles as progression). Camera defaults tighter. |
| **6–15** | Full single floor as drawn above. Every agent individually visible, named, followed. |
| **16–50** | **Department pods**: Ops/Dev/Lab desks become clustered pods of 4; zones physically extend (the building visibly grows — an east wing slides in with a construction animation, a delightful moment). Nameplates appear only on hover/zoom. |
| **51–100** | **The tower**: office gains floors; the default camera shows a cutaway elevation (Spiritfarer-style stacked rooms). Per-floor = a department. Elevator + stairwell traffic gives life. Minimap becomes the primary "where is everyone" tool. |
| **100+** | **Crowd LOD + representatives**: each department renders up to N=12 individual characters; the rest aggregate into a soft "activity meter" per room (desk rows with silhouette workers + a headcount chip `Ops ×37`). Clicking the chip opens a roster. Any agent the user follows/chats is always promoted to a full character ("camera makes you real"). |

Supporting rules at every scale:
- **Importance promotion**: agents that are blocked, failing, or addressed by the user always render fully and are never aggregated.
- **Traffic shaping**: max simultaneous walkers per hallway; others teleport-with-fade when offscreen (honesty preserved: arrivals are real, journeys are theater).
- **Cluster glyphs** on minimap replace dots above 50.
