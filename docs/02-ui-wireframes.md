# 2. UI Wireframes (Layer 2 Overlay)

Design language: **"Holographic glass"** — translucent frosted panels with thin luminous borders, floating above the world. The world must always bleed through (panels ≤ 65% opacity, blurred backdrop). Rounded 12px corners, one accent color driven by office theme. All panels slide from edges; nothing covers screen center at rest.

## 2.0 Full Screen — Command Mode (everything open)

```
┌────────────────────────────────────────────────────────────────────────────┐
│ ◤ BAGIDEA OFFICE      ⬤ 12 agents · 5 active · 2 idle · 1 ⚠     ▢ ⊟ ✕     │ ← Glance HUD (auto-hide)
│                                                                            │
│ ┌─ AGENT SWITCHER ─┐                                  ┌─ TASK CENTER ────┐ │
│ │ ◉ Main (CEO)     │        ░░ WORLD VISIBLE ░░       │ ▶ RUNNING (3)    │ │
│ │ ○ Rin · Research │      ░ HD-2D office renders ░    │ ▓▓▓▓▓░░ 64%      │ │
│ │ ○ Dev · Coding   │      ░ behind all panels    ░    │  Refactor auth   │ │
│ │ ○ Ava · Design   │        ░░░░░░░░░░░░░░░░░░░       │ ▓▓░░░░░ 31%      │ │
│ │ + Hire Agent     │                                  │  Pricing research│ │
│ └──────────────────┘                                  │ ▓▓▓▓▓▓░ 89%      │ │
│                                                       │  Landing page    │ │
│ ┌─ MAIN CHAT ──────────────────────────┐              │ ◷ QUEUED (2)     │ │
│ │ ◉ Main Agent          ● thinking…    │              │ ✓ DONE (7) ✗ (1) │ │
│ │ ┌──────────────────────────────────┐ │              └──────────────────┘ │
│ │ │ You: Research competitor pricing │ │                                   │
│ │ │ Main: On it. Assigning Rin to    │ │              ┌─ NOTIFICATIONS ──┐ │
│ │ │ deep research, I'll review the   │ │              │ ⚠ Dev needs       │ │
│ │ │ draft before you see it. ▌       │ │              │   approval: push  │ │
│ │ └──────────────────────────────────┘ │              │ ✓ Tests passed    │ │
│ │ [ Type a message…            ] 🎙 ➤ │              └──────────────────┘ │
│ └──────────────────────────────────────┘                                   │
│ ┌─ QUICK ACTIONS ─────────────────┐          ┌─ MINI OFFICE ─┐             │
│ │ ✦New Task ⊕Hire ⌖Summon ▶Flow ⚙│          │ [live minimap │             │
│ └─────────────────────────────────┘          │  w/ agent dots]│            │
└────────────────────────────────────────────────────────────────────────────┘
```

Edge assignments (consistent muscle memory):
- **Left** = WHO (agent switcher, chat)
- **Right** = WHAT (tasks, notifications)
- **Bottom** = DO (quick actions) + WHERE (minimap)
- **Top** = glance HUD (status strip)

## 2.1 Main Chat Panel

```
┌─ CHAT ─────────────────────────────────┐
│ ┌────┐  Main Agent          ⟐ pin  ✕  │
│ │ 🧑‍💼 │  ● Streaming · Executive Office│ ← live status + location
│ └────┘  ───────────────────────────────│
│                                        │
│  ╭ You ─────────────────────────────╮  │
│  │ Build a landing page for the     │  │
│  │ summer campaign                  │  │
│  ╰──────────────────────────────────╯  │
│  ╭ Main Agent ──────────────────────╮  │
│  │ Plan: 1) Ava drafts 3 concepts   │  │
│  │ 2) Dev implements the winner     │  │
│  │ ▸ mission #41 created            │  │ ← inline artifacts: mission
│  │ [View mission] [Watch Ava work]  │  │   links, "watch" = camera jump
│  ╰──────────────────────────────────╯  │
│  ┄┄ Rin joined the conversation ┄┄     │ ← multi-agent threads merge in
│                                        │
│ ┌────────────────────────────────────┐ │
│ │ Message Main Agent…                │ │
│ └────────────────────────────────────┘ │
│  🎙 Voice   📎 Attach   @ Mention   ➤ │
└────────────────────────────────────────┘
```

Behaviors:
- **Streaming text mirrors the world**: while tokens stream, the agent's character visibly types/talks; the speaking agent's avatar gets a glowing ring.
- **@mention any agent** to pull them into the thread (their character physically walks toward the Main Agent / Meeting Room).
- **"Watch" buttons** are the signature move: every long-running reply offers a camera jump to where the work is happening.
- Resizable, dockable left/right, pops out to its own window in Deep Work mode.

## 2.2 Agent Switcher

```
       ┌───────────────────────────────┐
       │  ◉      ○      ○      ○    +  │
       │ Main   Rin    Dev    Ava  Hire│
       │ CEO   Rsrch  Code   Dsgn      │
       │  ●      ◐      ●      ○       │ ← status dots: ●busy ◐idle ○asleep
       └───────────────────────────────┘
```

- Horizontal avatar rail attached to the chat panel; `Ctrl+Tab` cycles.
- Selecting an agent retargets the chat **and** glides the camera to them.
- Overflow at >8 agents: rail groups by department with expandable folders (mirrors zone structure).

## 2.3 Agent Card (click an agent in-world)

```
        ┌──────────────────────────────┐
        │ ┌────┐ Rin — Research Agent  │
        │ │ 👩‍🔬 │ Lv 7 · Research Lab   │
        │ └────┘ ● Working · 31%       │
        │──────────────────────────────│
        │ ▸ Mission #40: Competitor    │
        │   pricing analysis           │
        │   ▓▓▓░░░░░░░ reading 4 srcs  │
        │──────────────────────────────│
        │ Last output (live tail):     │
        │ "…Competitor B uses seat-    │
        │  based pricing at $29/u…"    │
        │──────────────────────────────│
        │ [💬 Chat] [⏸ Pause] [🔍 Logs]│
        │ [⌖ Summon] [⚙ Configure]    │
        └──────────────────────────────┘
```

Anchored to the character with a leader line; follows them if they walk (or pins on demand).

## 2.4 Task Center (missions)

```
┌─ MISSION CONTROL ──────────────── ⌄ ✕ ┐
│ [All] [Running] [Queued] [Done] [Fail]│
│────────────────────────────────────────│
│ ▶ #41 Landing page – summer    ▓▓▓ 64%│
│    Ava → Dev   ETA ~12m    [⌖][⏸][✕] │
│ ▶ #40 Competitor pricing       ▓░░ 31%│
│    Rin         4 sources   [⌖][⏸][✕] │
│ ◷ #42 Weekly report            queued │
│ ✗ #38 Deploy staging      ⚠ retry?    │
│    [View error] [Retry] [Reassign]    │
│────────────────────────────────────────│
│ + New Mission        ⏷ collapse to pill│
└────────────────────────────────────────┘
```

- Collapses to a **pill**: `▶3 ◷2 ✓7 ✗1` in the corner.
- `⌖` on any row = camera jump to the working agent.
- Drag a mission row onto an agent in the world to reassign.
- Mirrors the physical mission board in Mission Control Center 1:1.

## 2.5 Mini Office View (minimap)

```
   ┌─ OFFICE ───────────┐
   │ ┌──┬──────┬─────┐  │
   │ │EX│ OPS  │ LAB │  │   colored dots = agents
   │ │●│ ●● ● │  ●  │  │   zone glow = activity heat
   │ ├──┼──┬───┼──┬──┤  │   ⚠ icon on zones needing
   │ │MT│MC│CRE│SR│SEC⚠ │   attention
   │ ├──┴──┴───┴──┴──┤  │
   │ │LOBBY │CAFE│DORM│  │
   │ │  ●   │ ●● │ ●  │  │
   │ └──────┴────┴────┘  │
   └─────────────────────┘
```

- Click anywhere → camera flies there. Always-on (smallest UI element that survives Hide Mode optionally).
- Doubles as the **scaling answer at a glance**: at 100+ agents the minimap shows density heat, not dots.

## 2.6 Voice Control

```
   Resting:        ( 🎙 )            floating orb, bottom-center

   Push-to-talk:   ( 🎙 ))) "research competitor pricing…"
                    └─ live transcription ribbon above orb

   Continuous:     ( 🎙 ● REC ) — orb ring pulses with input level;
                    wake word "Hey Office" / per-agent "Hey Rin"
```

- While the user speaks, the **targeted agent's character turns to face the camera and nods** — presence feedback that no competitor has.
- Agent voice replies show captions in the chat panel; mute/voice-persona per agent.

## 2.7 Quick Actions

```
┌──────────────────────────────────────────────┐
│  ✦ New Task   ⊕ Hire Agent   ⌖ Summon       │
│  ▶ Workflows   🗺 Bookmarks   ⚙ Settings     │
└──────────────────────────────────────────────┘
```

Radial alternative (hold right-click in world): a ring menu at cursor — contextual to what's under it (on agent: chat/summon/pause; on zone: zone panel; on floor: new task here).

## 2.8 Notification Dock

```
                          ┌─────────────────────────┐
                          │ ⚠ Dev requests: git push│  ← blocking (persists)
                          │   --force   [Allow][Deny]│
                          ├─────────────────────────┤
                          │ ✓ Mission #39 complete  │  ← notable (8s, then logs)
                          └─────────────────────────┘
```

Top-right stack, max 3 visible, oldest collapse into a counter chip. Every toast has a `⌖` to jump to its world source. Approval toasts render the **exact command/diff** inline — security UX is never abstract.

## 2.9 Hide Mode

```
┌────────────────────────────────────────────┐
│                                            │
│         ░░ pure world, no chrome ░░        │
│                                            │
│                                       (🎙) │ ← optional: voice orb only
└────────────────────────────────────────────┘
```

- One hotkey (`Ctrl+\``). Everything slides out with a 250ms ease; world lighting subtly brightens (the office "takes the stage").
- Configurable survivors: none / voice orb / minimap / glance HUD.
- Blocking notifications still surface as **in-world signals only** (Security Center pulse) + OS notification fallback.

## 2.10 Component & Motion System

- **Tokens**: glass panel (bg blur 24px, 55–65% opacity), 1px luminous border in theme accent, 12px radius, 8pt spacing grid.
- **Type**: a humanist sans for UI (e.g., Inter), an optional pixel-flavored display face for headers/nameplates to echo the HD-2D world.
- **Motion**: 200–300ms ease-out slides; panels never fade-in-place (always arrive from their home edge); camera moves use 600ms ease-in-out with focal-point interpolation.
- **Sound**: soft UI ticks; world foley (keyboard clacks, coffee machine) is spatialized and ducked when chat/voice is active.
