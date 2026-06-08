# 1. UX Architecture

## 1.1 The Mental Model

The user is a **CEO/Director**, not an operator. Everything in the UX reinforces this:

| Traditional agent tool | BagIdea Office |
|---|---|
| Session list | Office directory of employees |
| Task queue | Mission board in Mission Control |
| Logs | Watching an agent actually work at their desk |
| Permission prompt | Agent walks to your "door" and asks for approval |
| Agent config | Hiring, training, and assigning an employee |
| Idle system | Office at night — lights dim, agents in the Dormitory |

**Key principle:** the user never "opens a panel to check state." State is *ambient*. Panels exist only to *act* (chat, approve, configure).

## 1.2 The Two-Layer Stack

```
┌──────────────────────────────────────────────┐
│  LAYER 2 — UI OVERLAY (summonable, glassy)   │   acts on the world
│  Chat • Switcher • Tasks • Quick Actions     │
├──────────────────────────────────────────────┤
│  LAYER 1 — WORLD (always on, wallpaper)      │   shows the truth
│  HD-2D office, agents, zones, lighting       │
├──────────────────────────────────────────────┤
│  LAYER 0 — AGENT RUNTIME (invisible daemon)  │   is the truth
│  Adapters: Claude Code, Open Interpreter…    │
└──────────────────────────────────────────────┘
```

Layer 1 is a **pure renderer of Layer 0 state**. Layer 2 is a **command surface into Layer 0**. Neither layer owns truth — this keeps the UX honest and the architecture clean.

## 1.3 Application Modes

The app lives on a spectrum from ambient to focused:

```
WALLPAPER ──── GLANCE ──── INTERACT ──── COMMAND ──── DEEP WORK
(behind icons) (hover/    (click an     (chat panel  (fullscreen
 idle, 30fps    peek HUD)   agent or      open, voice   app mode,
 throttled)                 zone)         active)       all panels)
```

| Mode | Trigger | What's visible |
|---|---|---|
| **Wallpaper** | default | World only, behind desktop icons; notification dock badges only |
| **Glance** | mouse to screen edge / hotkey tap | Mini HUD: agent count, active tasks, alerts (auto-hides in 3s) |
| **Interact** | click into world | Camera focuses, agent/zone inspection cards appear |
| **Command** | hotkey (e.g. `Ctrl+Space`) / voice wake / click chat orb | Chat panel + task center slide in |
| **Deep Work** | "Open Office" from tray | Fullscreen app: world + all panels + detailed views |

**Hide Mode** is reachable from every mode with one keypress (`Esc` cascade or dedicated hotkey) — collapses everything back to pure world.

## 1.4 Information Architecture

```
BagIdea Office
│
├── World (Layer 1)
│   ├── Zones (14) ──── each zone = one system domain
│   │     Lobby=status, Exec=orchestration, Ops=execution,
│   │     Lab=research, Dev=coding, Creative=genAI,
│   │     Meeting=A2A collab, Mission Control=tasks,
│   │     Academy=learning, Library=memory/RAG,
│   │     Server Room=infra/LLM, Dorm=offline,
│   │     Cafeteria=idle, Security=permissions
│   ├── Agents ──── click → Agent Card → chat / assign / inspect
│   └── Objects ──── interactive: mission board, server racks,
│                    bookshelves, security door (each opens a
│                    focused Layer-2 panel for that domain)
│
└── Overlay (Layer 2)
    ├── Main Chat Panel (default target: Main Agent)
    ├── Agent Switcher (carousel of avatars)
    ├── Mini Office View (live minimap)
    ├── Task Center (missions: queued/running/done/failed)
    ├── Voice Control (push-to-talk / continuous)
    ├── Quick Actions (new task, hire agent, summon, workflow, settings)
    └── Notification Dock (toasts → world events)
```

**Rule of two doors:** every function is reachable BOTH spatially (click the thing in the world) and directly (overlay panel / hotkey). Spatial is delightful; direct is fast. Power users never pay a "walk tax."

## 1.5 Core User Journeys

### Journey A — Morning glance (0 clicks)
1. User sits down; wallpaper shows the office at "morning" lighting.
2. Three agents at desks in Ops Floor (overnight tasks ran), one in Dormitory (a failed/disabled agent — bed has a red blanket tint), Mission Control board shows 2 ✅ 1 ⚠️.
3. User reads the entire system state in 3 seconds without touching the mouse.

### Journey B — Delegate a task (1 hotkey + speech)
1. `Ctrl+Space` → chat panel slides in, Main Agent character in the Executive Office turns toward camera (subtle acknowledgment).
2. User: *"Research our top 3 competitors' pricing and draft a comparison doc."*
3. Main Agent walks to Mission Control, pins a new mission card to the board (real task created), then summons a Research Agent — who walks from the Cafeteria to the Research Lab and starts working.
4. The mission card on the world board mirrors the Task Center entry. Closing the panel loses nothing.

### Journey C — Approval interrupt (world-native permission flow)
1. Coding Agent needs `git push --force` (a sensitive op).
2. Agent stands up, walks to the **Security Center**, an amber light strip pulses on that zone; notification dock shows one badge.
3. User clicks the agent (or the toast): approval card shows the exact command, diff context, Allow / Deny / Always-allow.
4. Deny → agent walks back, visibly re-plans (thought bubble), tries an alternative.

### Journey D — Watching a multi-agent collaboration
1. A complex task spawns 3 subagents. They each *walk to the Meeting Room*, gather at the table; the whiteboard renders the actual shared plan (live text).
2. They split to their zones; progress beams connect their desks to the mission card.
3. On completion, they regroup once in the meeting room (synthesis step), then the lead agent delivers the result — chat notification + the agent physically carries a "document" to the Lobby outbox.

### Journey E — Onboarding a new agent ("hiring")
1. Quick Action → "Create Agent" → a short **hiring flow**: choose adapter (Claude Code / Open Interpreter / custom), role, zone assignment, permissions (which doors their keycard opens — literally mapped to Security Center).
2. New character walks in through the Lobby front door, signs in at the directory, gets a desk. First-run = a small ceremony, not a config form.

## 1.6 Interaction Vocabulary

| Input | Effect |
|---|---|
| **Hover** agent | Nameplate + current action ("Refactoring auth module — 64%") |
| **Click** agent | Agent Card (status, current task, recent output, buttons: Chat / Inspect / Pause) |
| **Double-click** agent | Open dedicated chat with that agent |
| **Click** zone object | Zone panel (e.g., click mission board → Task Center) |
| **Scroll** | Smooth zoom (3 detents: Floor → Zone → Agent close-up) |
| **Drag** (middle/right) | Pan camera |
| **Drag task card → agent** | Reassign mission |
| **Drag agent → zone** | Suggest role/relocation ("summon to meeting") |
| `Ctrl+Space` | Command mode (chat) |
| `Ctrl+\`` | Hide Mode toggle |
| Hold `V` / wake word | Voice |
| `1–9` | Camera bookmarks per zone |

## 1.7 Notification Philosophy

Three escalation tiers, all world-first:

1. **Ambient** (no action needed): world animation only — completion confetti puff at a desk, a checkmark stamped on a mission card. No toast.
2. **Notable** (might want to know): notification dock toast + soft chime; agent does a small "done!" stretch. Toast click → focus camera on the source.
3. **Blocking** (needs you): Security Center amber pulse, agent waits visibly, dock badge persists, optional OS-level notification if app is occluded. Never a modal that steals focus.

**Anti-pattern banned:** modal dialogs interrupting other apps. The office is patient; agents *wait at your door*, they don't barge in.

## 1.8 Accessibility & Settings

- **Reduced motion** mode: agents teleport with fades instead of walking; camera cuts instead of glides.
- **Colorblind-safe** state encoding: every color signal pairs with an icon/shape (status rings use shape + color).
- **Text scale** independent of world zoom.
- **Screen-reader path**: Layer 2 is fully accessible standard UI; the world is decorative-redundant by design (rule of two doors guarantees this).
- **Quiet hours**: schedule when the office goes "night shift" — no sounds, dimmed motion.
- **Performance presets**: Cinematic / Balanced / Featherweight (see doc 6).
