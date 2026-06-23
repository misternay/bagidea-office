# Agent Pulse — Feasibility Assessment

**Reviewer:** May (Frontend Developer)
**Date:** 2026-06-23
**PRD Version:** 1.0 (Nida)
**Status:** Review Complete

---

## TL;DR

PRD เขียนมาดีและมี acceptance criteria ชัดเจน แต่ **assumption ใหญ่ (A3: overlay.html มีอยู่แล้ว) ไม่ตรงกับความเป็นจริง** — workspace ปัจจุบันไม่มี daemon, ไม่มี overlay.html, ไม่มี WebSocket, ไม่มี frontend framework เลย ต้อง build จากศูนย์ทั้ง stack

**Bottom line:** ทำได้ แต่ไม่ใช่ "extend existing overlay" — เป็นโปรเจคขนาด **3-4 สัปดาห์สำหรับ MVP** (US-1, US-2, US-4) ถ้า daemon/event bus ยังไม่มี

---

## 1. Dev Effort ต่อ User Story

### ⚠️ Prerequisite Block — Daemon + Event Bus

ก่อนจะนับชั่วโมงต่อ story ได้ ต้องเคลียร์ก่อนว่า:
- Daemon process ยังไม่มีใน workspace
- Event bus / WebSocket API ยังไม่มี
- Agent heartbeat protocol ยังไม่ define
- Overlay HTML (A3) **ไม่มีจริง**

งาน prerequisite นี้เป็น **backend infra** ที่ไม่เกี่ยวกับ UI โดยตรง แต่ UI ทำไม่ได้ถ้าไม่มี

**Backend infra effort (Arthit):**
| งาน | ชั่วโมง | หมายเหตุ |
|---|---|---|
| Daemon process (Node.js long-running) | 8-12h | พร้อม graceful shutdown |
| Event bus (in-memory pub/sub) | 6-8h | schema: AgentEvent, TaskEvent |
| WebSocket server (ws หรือ socket.io) | 4-6h | broadcast + reconnect |
| Heartbeat protocol + offline detection | 4-6h | 15s interval, 60s timeout |
| Agent registration API | 4-6h | REST + persistence |
| **รวม prerequisite** | **26-38h (~4-5 วัน)** | |

### US-1: Pulse Ring — P0
| ด้าน | ชั่วโมง | รายละเอียด |
|---|---|---|
| **Frontend** | 6-8h | SVG ring + CSS animation + debounced color state + badge |
| **Backend** | 3-4h | Compute OfficePulse (derive จาก agent status ทั้งหมด) |
| **รวม** | ~1.5 วัน | รวม test + edge cases EC-7, EC-8 |

### US-2: Agent Status Grid — P0
| ด้าน | ชั่วโมง | รายละเอียด |
|---|---|---|
| **Frontend** | 10-14h | CSS grid, responsive card, avatar, status icon, elapsed timer (requestAnimationFrame), virtual scroll สำหรับ >50 agents (EC-9) |
| **Backend** | 2-3h | GET /agents + WebSocket subscribe |
| **รวม** | ~2 วัน | รวม EC-9 (list compact mode), EC-10 (debounce rapid changes) |

### US-3: Activity Timeline — P1
| ด้าน | ชั่วโมง | รายละเอียด |
|---|---|---|
| **Frontend** | 6-8h | Timeline list, burst grouping (EC-6), relative time formatting |
| **Backend** | 4-6h | In-memory ring buffer (24h window), query API |
| **รวม** | ~1.5-2 วัน | ถ้าต้องการ persistence >24h (Q2) เพิ่มอีก 1-2 วัน |

### US-4: Attention Center — P0
| ด้าน | ชั่วโมง | รายละเอียด |
|---|---|---|
| **Frontend** | 8-10h | Sortable list, action buttons, severity color, approval modal |
| **Backend** | 6-8h | Attention derivation logic (blocked agents + pending approvals), severity ranking, approve API |
| **รวม** | ~2 วัน | เป็น story ที่ backend หนักสุด เพราะ logic ซับซ้อน |

### US-5: Agent Detail Panel — P1
| ด้าน | ชั่วโมง | รายละเอียด |
|---|---|---|
| **Frontend** | 6-8h | Slide-over drawer, stats cards, mini activity log |
| **Backend** | 3-4h | GET /agents/:id/detail (aggregate stats) |
| **รวม** | ~1.5 วัน | |

### สรุป MVP (US-1, US-2, US-4)

| หมวด | ชั่วโมง | วันทำการ |
|---|---|---|
| Backend infra prerequisite | 26-38h | 4-5 วัน |
| US-1 (Pulse Ring) | 9-12h | 1.5 วัน |
| US-2 (Agent Grid) | 12-17h | 2 วัน |
| US-4 (Attention Center) | 14-18h | 2 วัน |
| Integration + polish + test | 8-12h | 1.5 วัน |
| **รวม MVP** | **~69-97h** | **~11-14 วันทำการ** |

Full scope (P0 + P1): เพิ่มอีก ~5-6 วัน → **3-4 สัปดาห์** สำหรับทีม 1 frontend + 1 backend

---

## 2. UI Feasibility

### ✅ ทำได้สบาย
- **Pulse Ring + color states** — SVG circle + CSS animation, ทุก browser รองรับ, ไม่มี performance issue
- **Attention Badge** — trivial
- **Activity Sparkline** — ใช้ inline SVG หรือ library เล็กๆ (uPlot ~30KB, zero-dep) — ไม่ต้องดึง D3 ทั้งชุด
- **Agent Card Grid** — CSS Grid + responsive breakpoints, ง่าย
- **Slide-over Detail Panel** — standard pattern
- **Relative time** — `Intl.RelativeTimeFormat` (built-in, ไม่ต้อง dayjs)

### ⚠️ ต้องระวัง
- **Elapsed timer ที่ tick ทุกวินาที** — ถ้ามี agent 50 คน แล้ว render timer ในทุก card = 50 re-renders/sec → ใช้ `requestAnimationFrame` + update เฉพาะ card ที่ visible (IntersectionObserver) หรือแสดง granularity "5m / 12m" แทน秒
- **EC-9 (>50 agents → compact mode)** — ต้อง virtual scroll (เช่น `@tanstack/virtual` ~15KB) ไม่ใช่ render ทั้งหมด
- **EC-10 (rapid status changes)** — debounce 2s ที่ layer ของ state management ไม่ใช่ debounce ที่ UI

### 🔴 Red flag — PRD assumption ผิด
- **A3: "Overlay HTML UI framework — มีอยู่แล้ว (daemon/overlay.html)"** → **ไม่มีจริง** workspace นี้ไม่มี daemon/ ไม่มี overlay.html ไม่มี web/ folder เลย
- **A2: "Agent ทุกคนส่ง heartbeat ได้"** → ยังไม่ verify — agent ในปัจจุบัน (ถ้ามี) เป็น Godot/CLI จริงไหม? Godot ส่ง HTTP/WS ได้แต่ CLI แบบ short-lived อาจไม่ support

### Tech stack recommendation
เนื่องจาก workspace ยังไม่มี frontend อะไรเลย ขอ suggest **zero-framework approach** สำหรับ overlay:
- **Vanilla TS + Vite** — bundle เล็ก, fast startup, เหมาะกับ overlay
- **Lit (web components)** ถ้าอยากได้ reactivity แต่ไม่ต้องการ React overhead
- **Tailwind CSS** — ถ้าทีม familiar, ถ้าไม่ก็ plain CSS modules
- **ไม่แนะนำ React/Angular** สำหรับ overlay — bundle ใหญ่, startup ช้า, overkill สำหรับ dashboard ที่ CEO เปิดดูแล้วปิด

---

## 3. Five Open Questions

### Q1: Daemon ยังไม่มี — สร้างเองหรือใช้ของที่มี?
PRD สมมติว่ามี daemon + event bus แล้ว แต่ workspace ว่างเปล่า
- **ตัวเลือก A:** สร้าง daemon ใหม่เป็น Node.js process (แนะนำ — control ได้หมด)
- **ตัวเลือก B:** ใช้ BagIdeaOffice MCP server เป็น state holder (แต่มันเป็น MCP — ไม่ใช่ long-running daemon, ต้อง refactor เยอะ)
- **Decision needed from:** Arthit + Shino

### Q2: Activity history เก็บแค่ไหน?
PRD บอก "in-memory, 24h" (A4) แต่ถ้า daemon restart ข้อมูลหาย (EC-8)
- **ตัวเลือก A:** In-memory พอ (ตาม PRD) — ยอมเสียข้อมูลเมื่อ restart
- **ตัวเลือก B:** SQLite file ใน daemon — เก็บได้หลายวัน, query ย้อนหลังได้
- **Decision needed from:** CEO (ต้องการดู "สัปดาห์ที่ผ่านมา" หรือแค่ "วันนี้")

### Q3: UI อยู่ตรงไหน?
PRD บอก overlay.html (A3) แต่ไม่มี overlay
- **ตัวเลือก A:** สร้าง `/pulse` endpoint ใน daemon — เปิดใน browser แยก
- **ตัวเลือก B:** Embed ใน BagIdeaOffice desktop app (ถ้ามี — ต้อง check)
- **ตัวเลือก C:** Plugin ใน BagIdeaOffice plugin system (docs/guide/plugins.md)
- **Decision needed from:** Shino + Arthit

### Q4: Agent คือใคร/อะไรบ้าง?
PRD พูดถึง "Arthit/May/Nida" เป็น agent แต่ในความเป็นจริง agent คือ AI sub-agent (Claude Code agents) หรือคน?
- ถ้าเป็น **Claude Code sub-agents** → emit event จากไหน? (Claude Code ไม่มี native event API)
- ถ้าเป็น **Godot/CLI agents** (ตาม PRD section 8) → ต้อง build agent SDK
- ถ้าเป็น **คน** → ต้องมี UI ให้คน log inงานเอง
- **Decision needed from:** CEO + Arthit (architectural direction)

### Q5: Mobile view หรือ Desktop only?
PRD เป็น open question (Q5 ใน appendix) แล้ว
- **ถ้า desktop-only** → ลด effort ~30% (ไม่ต้อง responsive breakpoint เล็ก, ไม่ต้อง touch gesture)
- **ถ้า mobile** → ต้อง PWA + service worker + push notification (Q3 เชื่อมกับตรงนี้)
- **Recommendation ของ May:** MVP ทำ desktop-only ก่อน, mobile เป็น phase 2

---

## 4. Recommendation

1. **Resolve Q1 + Q4 ก่อนเริ่ม** — daemon + agent identity เป็น architectural decision ที่กระทบทุกอย่าง
2. **MVP scope:** US-1 + US-2 + US-4 (ตาม PRD เสนอ) + Q5 = desktop-only
3. **Phase 1 target:** ~2 สัปดาห์หลังจาก daemon infra พร้อม
4. **Phase 2:** US-3, US-5 + mobile view + persistence
5. **Design system:** สร้าง Figma/Excalidraw mockup ก่อน code — PRD มีแค่ ASCII layout, ต้อง visual mockup ให้ CEO approve ก่อนลงมือ

---

*End of feasibility assessment. พร้อม discuss กับทีมต่อค่ะ* — May
