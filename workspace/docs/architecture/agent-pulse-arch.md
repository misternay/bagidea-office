# Agent Pulse — Architecture Specification

**Version:** 1.0
**Author:** Arthit (System Architect)
**Date:** 2026-06-23
**Status:** Draft
**PRD:** `docs/requirements/agent-pulse-prd.md`

---

## 1. Design Principles

| Principle | Rationale |
|---|---|
| **Reuse existing transport** | Daemon มี WebSocket `/ws` + `broadcast()` + `journal.jsonl` อยู่แล้ว — ไม่ต้องสร้าง event bus ใหม่ |
| **In-memory state, journaled events** | Pulse state คำนวณใหม่ได้จาก journal ทุกครั้ง — ไม่ต้อง persist state แยก |
| **Derived, not stored** | `OfficePulse` (สี/badge) เป็น computed value จาก agent states — ไม่ใช่ first-class entity |
| **No new dependencies** | Daemon เป็น zero-dep Node.js — Pulse module ต้องเป็น pure JS เช่นกัน |

---

## 2. Real-Time Data Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Agent Process                                │
│  (Claude Code session, Godot CLI, or any adapter)                   │
│                                                                      │
│  hook.js ──POST /event──┐                                            │
│  heartbeat (15s) ───────┤                                            │
│  task events ───────────┘                                            │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         Daemon (server.js)                           │
│                                                                      │
│  POST /event                                                         │
│      │                                                               │
│      ▼                                                               │
│  ┌──────────────┐     ┌──────────────────┐     ┌───────────────┐    │
│  │ Event Router │────▶│  Pulse Store      │────▶│ broadcast()   │    │
│  │ (existing)   │     │  (NEW module)     │     │ (existing)    │    │
│  └──────────────┘     │                    │     └───────┬───────┘    │
│                        │  • agentStates{} │             │            │
│                        │  • activityLog[] │             │            │
│                        │  • attentionQ[]  │             │            │
│                        │  • sparkline[]   │             │            │
│                        │  • pulseColor    │             │            │
│                        └──────────────────┘             │            │
│                                                         │            │
│  journal.jsonl ◀────────────────────────────────────────┘            │
│  (all events persisted for replay)                                   │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
                                 ▼ WebSocket frame
┌─────────────────────────────────────────────────────────────────────┐
│                    Frontend (overlay.html)                            │
│                                                                      │
│  ┌───────────┐  ┌──────────────┐  ┌────────────┐  ┌─────────────┐  │
│  │PulseRing  │  │AgentGrid     │  │Attention   │  │Activity     │  │
│  │(Layer 0)  │  │(Layer 1)     │  │Center      │  │Timeline     │  │
│  │           │  │              │  │(Layer 0)   │  │(Layer 1)    │  │
│  └───────────┘  └──────────────┘  └────────────┘  └─────────────┘  │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ AgentDetailPanel (Layer 2 — slide-in on card click)           │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  UI state: debounce 2s, sparkline 24pts, virtual scroll if >50 agents│
└─────────────────────────────────────────────────────────────────────┘
```

### 2.1 Event Flow Details

| Step | What happens | Latency |
|---|---|---|
| 1 | Agent process emits event via `hook.js` → `POST /event` | ~0ms (local HTTP) |
| 2 | Daemon Event Router receives `{type, agent, tool?, task?}` | ~0ms |
| 3 | **Pulse Store** processes event, updates in-memory state | ~0ms |
| 4 | `broadcast()` sends WebSocket frame to all connected clients | ~1-5ms |
| 5 | Frontend receives frame, debounces (2s for rapid changes), re-renders | 0-2s |

### 2.2 Heartbeat Protocol

```
Agent Process                    Daemon (Pulse Store)
     │                                    │
     │──── heartbeat (every 15s) ────────▶│  update lastSeen
     │                                    │
     │         (60s no heartbeat)         │  → mark OFFLINE
     │                                    │  → broadcast pulse.agent.offline
     │                                    │
     │──── heartbeat (resumes) ──────────▶│  → mark ONLINE/IDLE
     │                                    │  → broadcast pulse.agent.online
```

**Heartbeat payload** (POST to `/event`):
```json
{
  "type": "pulse.heartbeat",
  "agent": "arthit",
  "status": "busy",
  "currentTask": { "id": "t42", "title": "Review auth module", "startedAt": 1719158400000 },
  "ts": 1719158415000
}
```

---

## 3. State Model

### 3.1 Agent Status — State Machine

```
                    ┌──────────┐
           ┌───────│  OFFLINE  │◀───────┐
           │       └────┬─────┘         │
           │            │ heartbeat      │ 60s no heartbeat
           │            ▼ received       │ or process exit
           │       ┌──────────┐         │
           │       │  ONLINE   │─────────┘
           │       └────┬─────┘
           │            │
           │    ┌───────┴───────┐
           │    ▼               ▼
           │ ┌──────┐      ┌──────┐
           │ │ IDLE  │      │ BUSY │
           │ └──┬───┘      └──┬───┘
           │    │              │
           │    │ task_start   │ task_complete
           │    │              │ or task_fail
           │    ▼              ▼
           │ ┌──────┐      ┌───────┐
           │ │ BUSY  │      │ IDLE  │
           │ └──────┘      └───────┘
           │                    │
           │              ┌─────┴─────┐
           │              ▼           │
           │         ┌────────┐      │ approval granted
           │         │ BLOCKED │     │ or unblocked
           │         └────┬───┘      │
           │              │──────────┘
           │              │
           │              │ (also: agent_offline from any state)
           │              ▼
           │         ┌──────────┐
           └─────────│  OFFLINE  │
                     └──────────┘
```

### 3.2 Agent State Record

```typescript
// In-memory structure per agent (Pulse Store)
interface AgentPulseState {
  id: string;                    // agent slug (e.g. "arthit", "may")
  status: "online" | "offline" | "idle" | "busy" | "blocked";
  lastHeartbeat: number;         // epoch ms
  currentTask: {
    id: string;
    title: string;
    startedAt: number;           // epoch ms
    elapsed: number;             // ms, computed on read
  } | null;
  tasksCompletedToday: number;   // reset at midnight local
  totalTaskDuration: number;     // ms, for avg computation
  transitionCount: number;       // for EC-10 rapid-change debounce display
  blockedReason: string | null;  // e.g. "awaiting CEO approval"
  blockedSince: number | null;   // epoch ms — triggers Attention after 5min
  offlineSince: number | null;   // epoch ms
}
```

### 3.3 Status → Color + Pulse Rate Mapping

| Status | Color | Pulse Animation | Trigger |
|---|---|---|---|
| `online` + `busy` (≥1 agent) | 🟢 Green | Slow (2s cycle) | At least 1 agent working, no blocked/errors |
| `blocked` (any agent) | 🟡 Yellow/Amber | Fast (1s cycle) | Any agent blocked OR approval pending >5min |
| All `idle`/`offline` >10min | 🔴 Red | Static (no pulse) | No agent working for 10+ minutes |
| No data / daemon just started | ⚫ Gray | Slow (2s cycle) | No heartbeat ever received |
| Quiet hours (midnight) | ⚫ Gray | Slow + text overlay | Configurable quiet window |

### 3.4 Office Pulse (Derived — recomputed on every state change)

```typescript
interface OfficePulse {
  color: "green" | "yellow" | "red" | "gray";
  pulseRate: number;            // ms per cycle (2000=slow, 1000=fast, 0=static)
  attentionCount: number;       // items in Attention Center
  activeAgentCount: number;     // busy agents
  totalAgentCount: number;      // all registered agents
  lastActivityAt: number;       // epoch ms of last task_completed
  sparkline: number[];          // 24 data points (tasks/hour, last 24h)
}
```

---

## 4. Component Breakdown

### 4.1 Daemon Side — New Module: `daemon/pulse.js`

```
daemon/pulse.js  (~200 lines, zero-dep)
├── PulseStore (class)
│   ├── agentStates: Map<string, AgentPulseState>
│   ├── activityLog: ActivityEvent[]           // circular buffer, max 500
│   ├── attentionQueue: AttentionItem[]        // sorted by severity
│   ├── sparkline: number[24]                  // tasks per hour
│   │
│   ├── handleEvent(evt)                       // main entry point from /event
│   │   ├── pulse.heartbeat   → updateAgentHeartbeat()
│   │   ├── pulse.task.started      → setAgentBusy() + logActivity()
│   │   ├── pulse.task.completed    → setAgentIdle() + logActivity() + bumpSparkline()
│   │   ├── pulse.task.blocked      → setAgentBlocked() + addToAttention()
│   │   ├── pulse.task.failed       → setAgentIdle() + logActivity() + addToAttention()
│   │   ├── pulse.approval.requested → addToAttention()
│   │   ├── pulse.approval.granted  → removeFromAttention()
│   │   ├── pulse.agent.online      → setAgentOnline()
│   │   └── pulse.agent.offline     → setAgentOffline()
│   │
│   ├── tick()                                 // called every 30s by server scheduler
│   │   ├── checkHeartbeatTimeouts()           // 60s → offline
│   │   ├── checkBlockedTimeouts()             // 5min → escalate attention
│   │   ├── checkIdleOffice()                  // all idle 10min → red
│   │   └── rotateSparkline()                  // shift window at hour boundary
│   │
│   ├── getSnapshot()                          // → { pulse: OfficePulse, agents: [...], attention: [...], activity: [...] }
│   └── restoreFromJournal(lines[])            // replay journal on daemon restart
│
├── pulseColor(agents)                         // pure function: agents → color
├── severitySort(items)                        // blocked > approval > warning
└── burstGroup(events, windowMs=300000)        // EC-6: group events in 5min window
```

**Integration point** in `server.js`:

```js
// --- existing event handler (POST /event) ---
const pulse = require("./pulse");
const pulseStore = new pulse.PulseStore();

// On daemon start: replay journal
pulseStore.restoreFromJournal(journalTail(REPLAY_COUNT));

// In POST /event handler:
pulseStore.handleEvent(payload);
broadcast({ type: "pulse.update", ...pulseStore.getSnapshot() });

// In 30s scheduler tick:
pulseStore.tick();
broadcast({ type: "pulse.update", ...pulseStore.getSnapshot() });
```

### 4.2 Frontend Side — New Components in `overlay.html`

```
overlay.html (existing)
├── <section id="pulse-panel">              // NEW: Pulse tab content
│   ├── <div class="pulse-ring">            // Layer 0: colored ring + badge
│   │   ├── SVG ring (animated stroke)
│   │   └── <span class="badge">3</span>    // attention count
│   │
│   ├── <div class="pulse-sparkline">       // Layer 0: 24h mini chart
│   │   └── SVG polyline (24 points)
│   │
│   ├── <div class="agent-grid">            // Layer 1: agent cards
│   │   └── <div class="agent-card">*N      // one per registered agent
│   │       ├── avatar + name + role
│   │       ├── status dot (color-coded)
│   │       ├── current task title (truncated)
│   │       └── elapsed time badge
│   │
│   ├── <div class="attention-center">      // Layer 0/1: right sidebar
│   │   └── <div class="attention-item">*N  // sorted by severity
│   │       ├── severity icon + color
│   │       ├── description
│   │       ├── time ago
│   │       └── action button (Approve / View)
│   │
│   ├── <div class="activity-timeline">     // Layer 1: bottom section
│   │   └── <div class="activity-item">*N   // recent completions
│   │       ├── agent avatar (mini)
│   │       ├── task title
│   │       ├── time ago
│   │       └── duration
│   │
│   └── <div class="agent-detail">          // Layer 2: slide-in panel
│       ├── agent header (avatar, name, role)
│       ├── current task + elapsed
│       ├── tasks completed today (count)
│       ├── avg task duration
│       └── recent activity log (5 lines)
│
├── Pulse UI JavaScript (~300 lines)
│   ├── initPulsePanel()                     // create DOM, bind WS events
│   ├── renderPulseRing(pulse)               // update color + animation
│   ├── renderSparkline(data)                // SVG polyline from 24 pts
│   ├── renderAgentGrid(agents)              // card grid, compact mode if >50
│   ├── renderAttention(items)               // severity-sorted list
│   ├── renderActivity(events)               // timeline with burst grouping
│   ├── renderAgentDetail(agent)             // slide-in on card click
│   ├── debounce(fn, ms)                     // 2s debounce for EC-10
│   └── timeAgo(ts)                          // "3m ago", "1h ago"
│
└── Pulse CSS (~150 lines)
    ├── .pulse-ring (SVG animation, color transitions)
    ├── .agent-card (glass card, status dot, hover)
    ├── .attention-item (severity colors, action buttons)
    ├── .activity-item (timeline dot, compact text)
    └── .agent-detail (slide-in panel, backdrop blur)
```

### 4.3 UI Tab Integration

Pulse เป็น tab ใหม่ใน overlay ที่มีอยู่แล้ว (Chat/Brain/Settings):

```
┌──────────────────────────────────────────────┐
│  [Chat]  [Brain]  [Pulse✦]  [Settings]       │  ← tab rail
│                       ▲                       │
│            new tab, badge shows               │
│            attention count when >0            │
└──────────────────────────────────────────────┘
```

Tab badge (✦) เปลี่ยนเป็นสีแดงเมื่อ `attentionCount > 0` — ดึงความสนใจ CEO แม้จะอยู่ tab อื่น

---

## 5. API Endpoints

### 5.1 Existing Endpoints Used (No Changes)

| Endpoint | Method | Usage |
|---|---|---|
| `POST /event` | POST | Agent processes emit pulse events (heartbeat, task lifecycle) |
| `/ws` | WS | Frontend subscribes to `pulse.update` broadcasts |

### 5.2 New Event Types (via POST /event)

| Event Type | Payload | Emitted By |
|---|---|---|
| `pulse.heartbeat` | `{agent, status, currentTask?}` | Agent process (every 15s) |
| `pulse.task.started` | `{agent, task: {id, title}}` | Agent process / hook.js |
| `pulse.task.completed` | `{agent, task: {id, title, duration}}` | Agent process / hook.js |
| `pulse.task.blocked` | `{agent, task: {id}, reason}` | Agent process |
| `pulse.task.failed` | `{agent, task: {id}, error}` | Agent process |
| `pulse.approval.requested` | `{agent, task: {id}, description}` | Agent process |
| `pulse.approval.granted` | `{agent, taskId}` | Overlay UI / CEO action |
| `pulse.agent.online` | `{agent}` | Daemon (on first heartbeat) |
| `pulse.agent.offline` | `{agent}` | Daemon (heartbeat timeout) |

### 5.3 New Broadcast Events (daemon → UI via WS)

| Event Type | Payload | Frequency |
|---|---|---|
| `pulse.update` | Full `PulseSnapshot` (see §3.4) | On every state change + every 30s tick |
| `pulse.attention.action` | `{id, action, by}` | When CEO acts on an attention item |

### 5.4 New REST Endpoint

```
GET /pulse
```

**Response** (200 OK):
```json
{
  "pulse": {
    "color": "green",
    "pulseRate": 2000,
    "attentionCount": 1,
    "activeAgentCount": 2,
    "totalAgentCount": 6,
    "lastActivityAt": 1719158400000,
    "sparkline": [0, 1, 3, 2, 0, 0, 1, 4, 5, 3, 2, 1, 0, 0, 0, 2, 3, 4, 2, 1, 0, 0, 1, 2]
  },
  "agents": [
    {
      "id": "arthit",
      "status": "busy",
      "currentTask": { "id": "t42", "title": "Architecture spec", "startedAt": 1719158400000, "elapsed": 720000 },
      "tasksCompletedToday": 3,
      "blockedReason": null,
      "offlineSince": null
    }
  ],
  "attention": [
    { "id": "a1", "severity": "warning", "agent": "may", "description": "Approval pending: deploy agy-mcp", "since": 1719157800000 }
  ],
  "activity": [
    { "agent": "nida", "task": "Draft PRD", "completedAt": 1719155000000, "duration": 1800000 }
  ]
}
```

**Purpose:** Initial state load เมื่อเปิด Pulse tab (ไม่ต้องรอ WS broadcast ถัดไป). Updates ถัดไปมาผ่าน WS.

---

## 6. Edge Case Handling

| EC# | Case | Architecture Solution |
|---|---|---|
| EC-1 | No agents registered | `getSnapshot()` returns `color: "gray"`, empty agents array. Frontend shows empty state message. |
| EC-2 | Agent offline/disconnected | Heartbeat timeout (60s) → `status: "offline"`, `offlineSince` set. NOT counted as blocked. |
| EC-3 | Agent idle >2h | Status stays `"idle"`, no attention escalation. Frontend shows light blue color. |
| EC-4 | Task running >30min | `tick()` checks `currentTask.elapsed > 30min` → adds warning to Attention Center. |
| EC-5 | Multiple agents blocked | `severitySort()` orders by blocked-since (earliest first). If ALL agents idle/blocked >10min → red. |
| EC-6 | Activity burst | `burstGroup()` collapses events within 5min window into "N tasks completed" entry. |
| EC-7 | Midnight / no activity | `tick()` checks current hour vs configurable quiet window → gray + "Quiet hours" overlay. |
| EC-8 | Daemon restart | `restoreFromJournal()` replays last N events from `journal.jsonl`. UI shows "restarted at HH:MM". |
| EC-9 | >50 agents | Frontend detects `agents.length > 50` → switches to compact list view + search input. |
| EC-10 | Rapid status changes | Frontend debounces card updates at 2s. Shows `transitionCount` badge ("3 tasks today") instead of flickering. |

---

## 7. Data Flow Sequence Diagrams

### 7.1 Normal Task Lifecycle

```
Agent (Arthit)         Daemon                Pulse Store              UI (Pulse Tab)
     │                    │                       │                        │
     │── POST /event ────▶│                       │                        │
     │  {pulse.task.      │── handleEvent() ─────▶│                        │
     │   started,         │                       │ status=busy             │
     │   task:{...}}      │                       │ logActivity()           │
     │                    │◀── snapshot ──────────│                        │
     │                    │── broadcast ──────────────────────────────────▶│
     │                    │  {pulse.update}        │                        │ update card:
     │                    │                       │                        │ "Arthit: busy"
     │                    │                       │                        │
     │  (15s later)       │                       │                        │
     │── heartbeat ──────▶│── handleEvent() ─────▶│ lastHeartbeat=now      │
     │                    │                       │                        │
     │  ...               │                       │                        │
     │                    │                       │                        │
     │── POST /event ────▶│── handleEvent() ─────▶│                        │
     │  {pulse.task.      │                       │ status=idle             │
     │   completed}       │                       │ tasksCompleted++        │
     │                    │◀── snapshot ──────────│ sparkline[idx]++        │
     │                    │── broadcast ──────────────────────────────────▶│
     │                    │                       │                        │ move to timeline
     │                    │                       │                        │ "Arthit completed
     │                    │                       │                        │  Architecture spec"
```

### 7.2 Blocked Agent → Attention Escalation

```
Agent (May)            Daemon                Pulse Store              UI
     │                    │                       │                        │
     │── POST /event ────▶│                       │                        │
     │  {pulse.task.      │── handleEvent() ─────▶│                        │
     │   blocked,         │                       │ status=blocked          │
     │   reason:"..."}    │                       │ blockedSince=now        │
     │                    │                       │ addToAttention()        │
     │                    │◀── snapshot ──────────│                        │
     │                    │── broadcast ──────────────────────────────────▶│
     │                    │                       │                        │ yellow ring
     │                    │                       │                        │ attention badge +1
     │                    │                       │                        │
     │  (5 min later)     │                       │                        │
     │                    │── tick() ────────────▶│                        │
     │                    │                       │ blocked > 5min?         │
     │                    │                       │ → escalate severity     │
     │                    │◀── snapshot ──────────│                        │
     │                    │── broadcast ──────────────────────────────────▶│
     │                    │                       │                        │ attention item
     │                    │                       │                        │ pulses red
     │                    │                       │                        │
CEO  │                    │                       │                        │
     │── click Approve ──────────────────────────────────────────────────▶│
     │                    │◀─ POST /event ────────│                        │
     │                    │  {pulse.approval.      │                        │
     │                    │   granted}             │                        │
     │                    │── handleEvent() ─────▶│                        │
     │                    │                       │ status=idle             │
     │                    │                       │ removeFromAttention()   │
     │                    │◀── snapshot ──────────│                        │
     │                    │── broadcast ──────────────────────────────────▶│
     │                    │                       │                        │ green ring
     │                    │                       │                        │ item disappears
```

---

## 8. File Plan

| File | Type | Size (est.) | Purpose |
|---|---|---|---|
| `daemon/pulse.js` | New | ~200 lines | PulseStore class + helpers |
| `daemon/server.js` | Modified | +15 lines | Wire PulseStore into event handler + scheduler |
| `daemon/hook.js` | Modified | +5 lines | Map existing hook events to `pulse.*` types |
| `daemon/overlay.html` | Modified | +450 lines | Pulse tab HTML/CSS/JS |

**No new dependencies.** No database. No new processes.

---

## 9. ADR: Key Decisions

### ADR-001: WebSocket over SSE for real-time updates

**Decision:** ใช้ WebSocket (existing `/ws`) แทน SSE
**Reason:** Daemon มี WebSocket server อยู่แล้ว, SSE ต้องเพิ่ม HTTP handler ใหม่, WebSocket รองรับ bidirectional (CEO approve actions กลับไป daemon ได้)
**Trade-off:** WebSocket ซับซ้อนกว่า SSE เล็กน้อย แต่ได้ bidirectional + reuse existing infra

### ADR-002: In-memory state over database

**Decision:** เก็บ Pulse state ใน memory เท่านั้น, ใช้ `journal.jsonl` เป็น backup
**Reason:** PRD A4 ระบุชัดว่าไม่ต้องการ persistence >24h. In-memory เร็วกว่า, ไม่ต้อง manage DB connections, journal replay เพียงพอสำหรับ daemon restart
**Trade-off:** ข้อมูลหายถ้า daemon crash + journal ถูก trim — แต่ยอมรับได้สำหรับ monitoring dashboard

### ADR-003: Pulse as tab, not separate page

**Decision:** เพิ่ม Pulse เป็น tab ใน overlay.html (PRD Q4)
**Reason:** Single-page experience, แชร์ WebSocket connection กับ Chat/Brain, CEO ไม่ต้องเปิดหน้าต่างใหม่
**Trade-off:** overlay.html ใหญ่ขึ้น — แต่แยกเป็น section + conditional render (ไม่โหลดถ้าไม่เปิด tab)

### ADR-004: Event prefix `pulse.*` for namespacing

**Decision:** ใช้ prefix `pulse.` สำหรับ event types ทั้งหมด
**Reason:** แยกจาก existing events (`task.started`, `job.started`, `roster.sync`) ชัดเจน, ไม่ชนกับ event types อื่น, ง่ายต่อการ filter
**Trade-off:** Existing `task.*` events ไม่ถูกใช้โดยตรง — ต้อง map ที่ hook.js หรือ agent side

---

## 10. Open Questions → Recommendations

| PRD Question | Recommendation | Rationale |
|---|---|---|
| Q1: Daemon event bus — มีอยู่หรือต้องสร้าง? | **มีอยู่แล้ว** — `broadcast()` + `POST /event` + `journal.jsonl` เพียงพอ | ไม่ต้องสร้างใหม่ |
| Q2: Persistence >24h? | **ไม่จำเป็นสำหรับ MVP** — in-memory + journal เพียงพอ | เพิ่ม SQLite ได้ทีหลังถ้าต้องการ |
| Q3: Push notification OS-level? | **Phase 2** — MVP ใช้ in-app badge + tab highlight พอ | ต้อง native bridge (Electron/Godot) |
| Q4: Tab แยกหรือ embed? | **Tab แยก** — ข้อมูลเยอะเกินจะ embed ใน Chat | ดู §ADR-003 |
| Q5: Mobile view? | **Desktop-first** — overlay เป็น desktop app อยู่แล้ว | Responsive ได้ แต่ไม่ต้อง optimize |

---

*Architecture spec พร้อมสำหรับ implementation estimation โดย May*
