# Agent Pulse — Product Requirements Document

**Version:** 1.0  
**Author:** Nida (Business Analyst)  
**Date:** 2026-06-23  
**Status:** Draft — Pending Review by Director (Shino)  
**Primary Personas:** CEO, Director (Shino)  

---

## 1. Executive Summary

### 1.1 Problem Statement

CEO คนเดียวของ BagIdea Office มี **pain point อันดับ 1 คือ visibility** — ปัจจุบันไม่สามารถรู้ได้ว่าออฟฟิศกำลังทำอะไรอยู่โดยไม่ต้องถามผู้อำนวยการ (Shino) ทุกครั้ง ทุกคำถามที่ CEO อยากรู้ ("ตอนนี้ใครกำลังทำอะไร? งานไหนติด? เมื่อวานทำอะไรเสร็จบ้าง?") ล้วนต้องผ่าน Shino ซึ่งเสียเวลาทั้งสองฝ่าย และถ้า Shino ไม่อยู่ CEO ก็ไม่มีทางรู้เลยว่าออฟฟิศยังเดินอยู่หรือเปล่า

Agent Pulse คือแดชบอร์ดภาพรวมสถานะออฟฟิศแบบ real-time ที่ CEO และ Shino เปิดดูแล้วเข้าใจใน 3 วินาที — ไม่ต้องถามใคร ไม่ต้องอ่านรายงานยาว

### 1.2 Goals

- CEO/Shino เปิดดูหน้าเดียวแล้วรู้ทันทีว่าออฟฟิศทำงานอยู่หรือไม่ มีอะไรต้อง attention
- เข้าใจได้ใน ≤3 วินาที — ใช้สี (เขียว/เหลือง/แดง/เทา) และ sparkline แทนตาราง
- Real-time — สถานะอัพเดทโดยไม่ต้อง refresh
- Click-to-drill — กดที่ภาพรวมเพื่อดูรายละเอียด

### 1.3 Non-Goals (Out of Scope)

- ไม่ใช่ task management tool (ใช้ Linear/Jira ต่างหาก)
- ไม่ใช่ performance monitoring สำหรับ production servers
- ไม่ใช่ real-time chat log viewer (ถึงแม้จะแสดง activity summary ได้)
- ไม่แทนที่การคุยระหว่าง CEO กับ Shino — มันเสริมให้การคุยมีข้อมูล

---

## 2. Personas

| Persona | Need | Usage Pattern |
|---|---|---|
| **CEO** | รู้ภาพรวมสถานะใน ≤3 วินาที | เปิดดูวันละ 2-3 ครั้ง, สแกนสี, เจาะดูเฉพาะสีแดง |
| **Shino (Director)** | รู้ว่าใครทำงานอะไร, งานไหนติด, จัดการ exception | เปิดทิ้งไว้ทั้งวัน, monitor real-time |
| **Arthit (Architect)** | ดู workload ของทีม | เปิดดูเมื่อต้อง assign งานใหม่ |
| **May (Dev)** | ดูว่าตัวเองมีงานอะไรค้าง | เปิดดูเฉพาะ task ของตัวเอง |

---

## 3. Core Concepts

### 3.1 The 3-Second Rule

หน้าหลักของ Agent Pulse ต้องส่งข้อมูลต่อไปนี้ใน ≤3 วินาทีของการมอง:

1. **ออฟฟิศยังทำงานอยู่หรือเปล่า?** → สีพื้นหลังของ Pulse Ring (เขียว=ปกติ, เหลือง=มีบางอย่างต้องดู, แดง=ติดขัด, เทา=ไม่มี activity)
2. **มีอะไรที่ต้อง attention มั้ย?** → จำนวน badge ที่มุม (ตัวเลข)
3. **เทรนด์ activity** → sparkline เล็กๆ แสดง activity ใน 24 ชม.ที่ผ่านมา

### 3.2 Information Hierarchy

```
Layer 0 (0-3s):                    Pulse Ring + Attention Badge
Layer 1 (3-15s):                   Agent Status Grid + Activity Sparkline  
Layer 2 (click):                   Agent Detail Panel + Recent Tasks
Layer 3 (deep click):              Task Timeline + Full Log
```

---

## 4. User Stories

### US-1: Pulse Ring — รู้สถานะในพริบตา
**As a** CEO  
**I want** เห็น Pulse Ring ที่แสดงสถานะออฟฟิศด้วยสีและจังหวะการเต้น  
**So that** ฉันรู้ภายใน 1 วินาทีว่าออฟฟิศทำงานปกติอยู่หรือไม่ โดยไม่ต้องอ่านอะไรเลย

**Priority:** P0 (MVP)

### US-2: Agent Status Grid — ใครกำลังทำอะไร
**As a** Director (Shino)  
**I want** เห็นตารางแสดง agent ทุกคน พร้อมสถานะ (idle/busy/blocked), งานที่กำลังทำ, และเวลาที่ใช้ไป  
**So that** ฉันรู้ว่าใครว่าง ใครติด โดยไม่ต้องถามทีละคน

**Priority:** P0 (MVP)

### US-3: Activity Timeline — เมื่อวานทำอะไรเสร็จ
**As a** CEO  
**I want** เห็นไทม์ไลน์สรุปว่างานอะไรเสร็จไปแล้วใน 24 ชม.ที่ผ่านมา  
**So that** ฉันรู้ว่าออฟฟิศผลิตอะไรออกมาได้บ้างโดยไม่ต้องอ่าน log ยาวๆ

**Priority:** P1

### US-4: Attention Center — อะไรต้องจัดการเดี๋ยวนี้
**As a** Director (Shino)  
**I want** เห็นรายการ "สิ่งที่ต้อง attention" (งานติด, approval ค้าง, error) เรียงตามความสำคัญ  
**So that** ฉันจัดลำดับความสำคัญในการแก้ปัญหาได้ทันที

**Priority:** P0 (MVP)

### US-5: Agent Detail Panel — เจาะลึกรายคน
**As a** Director (Shino)  
**I want** กดที่ agent ใน Grid แล้วเห็น detail: งานที่ทำอยู่, งานที่ทำเสร็จ, เวลาที่ใช้, log ล่าสุด  
**So that** ฉัน troubleshoot ได้เมื่อ agent คนนั้นมีปัญหา

**Priority:** P1

---

## 5. Acceptance Criteria (Given-When-Then)

### AC-1: Pulse Ring สีเขียวเมื่อทุกอย่างปกติ
**Given** มีอย่างน้อย 1 agent กำลังทำงาน และไม่มี error/blocked ใดๆ  
**When** CEO เปิดหน้า Agent Pulse  
**Then** Pulse Ring แสดงสีเขียว เต้นช้าๆ (ประมาณ 1 pulse ต่อ 2 วินาที)

### AC-2: Pulse Ring สีเหลืองเมื่อมีบางอย่างต้องดู
**Given** มีอย่างน้อย 1 agent อยู่ในสถานะ "blocked" หรือมี approval รอเกิน 5 นาที  
**When** CEO เปิดหน้า Agent Pulse  
**Then** Pulse Ring แสดงสีเหลือง/ส้ม เต้นเร็วขึ้น (ประมาณ 1 pulse ต่อ 1 วินาที) และ Attention Badge แสดงจำนวนรายการที่ต้องดู

### AC-3: Pulse Ring สีแดงเมื่อออฟฟิศหยุดทำงาน
**Given** ไม่มี agent ใดทำงานเลยเกิน 10 นาที (ครบทุกคน idle/unresponsive)  
**When** CEO เปิดหน้า Agent Pulse  
**Then** Pulse Ring แสดงสีแดง และแสดงข้อความ "Office Idle — X minutes"

### AC-4: Pulse Ring สีเทาเมื่อไม่มีข้อมูล
**Given** Daemon เพิ่ง start และยังไม่มี activity ใดๆ เลย  
**When** CEO เปิดหน้า Agent Pulse  
**Then** Pulse Ring แสดงสีเทา เต้นช้า

### AC-5: Agent Grid แสดง agent ทุกคน
**Given** มี agent ลงทะเบียนไว้ N คน  
**When** เปิดหน้า Agent Pulse  
**Then** แสดง card ของ agent ทั้ง N คน แต่ละ card แสดง: ชื่อ agent, สถานะ (icon+สี), งานที่กำลังทำ (ถ้ามี), elapsed time

### AC-6: Attention Center แสดงรายการที่ต้องจัดการ
**Given** มี approval requests ค้างอยู่ 3 รายการ และ agent blocked 1 คน  
**When** เปิดหน้า Agent Pulse  
**Then** Attention Center แสดง 4 รายการ เรียงตาม severity (blocked agent > approval ค้าง) พร้อมปุ่ม action (approve / view)

### AC-7: Activity Timeline แสดงงานที่เสร็จใน 24 ชม.
**Given** มีงานที่ agent ทำเสร็จไปแล้ว 5 งานใน 24 ชม.ที่ผ่านมา  
**When** CEO เลื่อนดู Activity Timeline  
**Then** แสดง 5 รายการ เรียงจากล่าสุดไปเก่าสุด แต่ละรายการแสดง: ชื่องาน, ชื่อ agent, เวลาที่เสร็จ, duration

### AC-8: Agent Detail แสดงเมื่อคลิกที่ card
**Given** CEO คลิกที่ card ของ agent "Arthit"  
**When** หน้า Detail Panel เปิดขึ้น  
**Then** แสดง: (a) current task + elapsed, (b) tasks completed today, (c) average task duration, (d) recent activity log (5 บรรทัดล่าสุด)

---

## 6. Edge Cases

| # | Edge Case | Expected Behavior |
|---|---|---|
| EC-1 | **No agents registered** — daemon รันแต่ไม่มี agent ในระบบเลย | Pulse Ring สีเทา, Agent Grid ว่าง แสดงข้อความ "No agents registered yet" |
| EC-2 | **Agent offline/disconnected** — agent process crash หรือ network disconnect | Card ของ agent นั้นแสดงสถานะ "Offline" สีเทา, นับเวลาตั้งแต่ disconnect, ไม่นับเป็น blocked |
| EC-3 | **Agent idle นานมาก** — agent ออนไลน์แต่ไม่ได้รับงานเกิน 2 ชม. | แสดงสถานะ "Idle" สีฟ้าอ่อน ไม่ใช่ blocked (ไม่กวน CEO) |
| EC-4 | **Agent ทำงานเดียวค้างนาน** — task เดียวใช้เวลาเกิน 30 นาที | Card แสดง warning icon ⚠️ พร้อม elapsed time กระพริบ, ขึ้น Attention Center เป็น severity "warning" |
| EC-5 | **Multiple agents blocked พร้อมกัน** — dependency chain ติด | Attention Center แสดงรายการทั้งหมด, เรียงตามลำดับ dependency (ตัวที่ถูก block ก่อน), Pulse Ring สีแดงถ้าไม่มีใครทำงานได้เลย |
| EC-6 | **Activity burst** — มี task เสร็จจำนวนมากในเวลาอันสั้น (เช่น build automation) | Activity Timeline group รายการที่เกิดใน window 5 นาทีเดียวกันเป็นกลุ่ม "N tasks completed in burst" แทนที่จะแสดงทีละรายการ |
| EC-7 | **Midnight / no activity** — ออฟฟิศปิด, ไม่มีใครทำงาน | Pulse Ring แสดงสีเทาพร้อมข้อความ "Quiet hours — last activity at HH:MM" (ไม่อันตราย, ไม่แดง) |
| EC-8 | **Daemon restart** — daemon เพิ่ง restart, ประวัติ activity หาย | Pulse Ring สีเทา, Activity Timeline แสดงเฉพาะข้อมูลตั้งแต่ restart, แสดงข้อความ "Dashboard restarted — showing data since HH:MM" |
| EC-9 | **Very large office** — มี agent >50 คน | Agent Grid เปลี่ยนเป็น list view compact mode อัตโนมัติ, search/filter ปรากฏ, การ์ดเล็กลง |
| EC-10 | **Rapid status changes** — agent เปลี่ยน status เร็วมาก (idle→busy→idle→busy) | UI debounce 2 วินาที — ไม่กระพริบถี่จนอ่านไม่ออก, แสดง transition count แทน ("3 tasks today") |

---

## 7. Data Model (Conceptual)

```
Agent
  - id: string
  - name: string
  - role: string (CEO, Director, Architect, Developer, Analyst, QA, etc.)
  - status: enum (online, offline, idle)
  - currentTask: Task | null
  - avatar: string (emoji or icon)

Task
  - id: string
  - agentId: string
  - title: string
  - status: enum (queued, in_progress, blocked, completed, failed)
  - startedAt: timestamp | null
  - completedAt: timestamp | null
  - blockedReason: string | null
  - duration: number (ms, computed)

ActivityEvent
  - id: string
  - agentId: string
  - type: enum (task_started, task_completed, task_blocked, task_failed, 
               approval_requested, approval_granted, agent_online, agent_offline)
  - taskId: string | null
  - message: string
  - timestamp: timestamp

OfficePulse (derived — computed, not stored)
  - color: green | yellow | red | gray
  - attentionCount: number
  - activeAgentCount: number
  - totalAgentCount: number
  - lastActivityAt: timestamp
  - activitySparkline: number[] (24 data points, 1 per hour)
```

---

## 8. Real-Time Data Flow

```
Agent Process (Godot/CLI)
  │
  ├─ Status change → Daemon WebSocket → Agent Pulse UI (instant)
  │   (online/offline/idle/busy/blocked)
  │
  ├─ Task event → Daemon event bus → Activity Log → Pulse UI (near-instant)
  │   (started/completed/blocked/failed)
  │
  └─ Heartbeat (every 15s) → Daemon → Pulse UI knows agent is alive
      (no heartbeat for 60s → agent marked offline)
```

---

## 9. UI Layout Concept

```
┌─────────────────────────────────────────────────────┐
│  ●  3  │ ← Pulse Ring + Attention Badge (Layer 0)  │
│  🟢      │   สีเขียว = OK, 3 items need attention    │
│  ▁▂▃▄▅  │ ← 24h activity sparkline                │
├──────────┴──────────────────────────────────────────┤
│  AGENTS                          ATTENTION (3)      │
│  ┌─────────┐ ┌─────────┐        ┌─────────────┐    │
│  │ Arthit   │ │ May     │        │ ⚠️ Arthit   │    │
│  │ 🔵 busy  │ │ 🟢 idle │        │ blocked     │    │
│  │ PR review│ │ —       │        │ 25m ago     │    │
│  │ 12m      │ │         │        │ [View]      │    │
│  └─────────┘ └─────────┘        ├─────────────┤    │
│  ┌─────────┐ ┌─────────┐        │ ✋ CEO apprv │    │
│  │ Nida    │ │ ...     │        │ agy deploy  │    │
│  │ ...     │ │         │        │ [Approve]   │    │
│  └─────────┘ └─────────┘        └─────────────┘    │
├─────────────────────────────────────────────────────┤
│  RECENT ACTIVITY (24h)                              │
│  ● May completed "Add login page" — 34m ago        │
│  ● Arthit completed "Fix type error" — 1h ago      │
│  ● Nida completed "Draft PRD" — 2h ago             │
└─────────────────────────────────────────────────────┘
```

---

## 10. Risks & Assumptions

### Assumptions

| # | Assumption | Impact if Wrong |
|---|---|---|
| A1 | Daemon มี event bus ที่ agent ทุกคน emit status change ได้ | ต้องสร้าง event bus ใหม่ทั้งหมด |
| A2 | Agent ทุกคน (Godot/CLI/web) สามารถส่ง heartbeat ได้ | Agent บางประเภทอาจไม่ support |
| A3 | UI จะอยู่ใน web overlay (daemon/overlay.html) | ต้องสร้างหน้าแยก |
| A4 | ข้อมูล activity เก็บใน memory ของ daemon — ไม่ต้องการ persistence | ถ้าอยากดูย้อนหลัง >24h ต้องเพิ่ม DB |

### Risks

| # | Risk | Probability | Mitigation |
|---|---|---|---|
| R1 | Agent ไม่ emit status อย่างสม่ำเสมอ → ข้อมูล stale | Medium | Heartbeat timeout + offline detection |
| R2 | ข้อมูล activity ไม่มี structure → parse ยาก | High | Define event schema ก่อน implementation |
| R3 | CEO ไม่เปิด UI ทิ้งไว้ → real-time ไม่มีประโยชน์ | Medium | เพิ่มสรุปรายวันส่งตอนเย็น (push notification) |
| R4 | Performance: ถ้ามี agent มาก + activity burst → UI lag | Low | Debounce + virtual scroll + data cap |

---

## 11. Dependencies

| Dependency | Status | Owner |
|---|---|---|
| Daemon event bus / WebSocket API | ต้อง verify ว่ามีอยู่แล้วหรือต้องสร้างใหม่ | Arthit |
| Agent status reporting (heartbeat protocol) | ต้อง define schema | Arthit |
| Overlay HTML UI framework | มีอยู่แล้ว (daemon/overlay.html) — ต้อง extend | May |
| i18n strings | ต้องเพิ่ม key ใหม่ | May |

---

## 12. Success Metrics

| Metric | Target |
|---|---|
| "CEO ถาม Shino ว่าออฟฟิศกำลังทำอะไร" ลดลง | ≥50% ใน 2 สัปดาห์แรก |
| Time-to-understand (เปิดหน้าจนเข้าใจสถานะ) | ≤3 วินาที |
| Approval response time (จากที่ approval ปรากฏใน Pulse จนถึง CEO action) | ≤2 นาที (ระหว่าง working hours) |
| Agent Pulse uptime | ≥99% ระหว่าง working hours |

---

## 13. Appendix: Open Questions

1. **Q1:** Daemon event bus — มีอยู่แล้วหรือต้องสร้างใหม่? (Arthit)
2. **Q2:** ต้องการ persistence สำหรับ activity history >24h หรือไม่? (CEO/Shino)
3. **Q3:** ต้องการ push notification (OS-level) เมื่อ Pulse เป็นสีแดง หรือแค่ในแอพก็พอ? (CEO)
4. **Q4:** Agent Pulse ควรเป็น tab แยกใน overlay หรือ embed ในหน้า Brain/Chat ที่มีอยู่แล้ว? (Shino)
5. **Q5:** ต้องการ mobile view หรือ desktop-only ก็พอ? (CEO)

---

*End of PRD. Next step: Architecture Specification by Arthit, then Development Effort Estimation by May.*