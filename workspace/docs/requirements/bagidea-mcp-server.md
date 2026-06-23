# BagIdeaOffice MCP Server — Requirements Document

**เวอร์ชัน:** v0.1 (Draft)  
**ผู้เขียน:** Nida (Business Analyst)  
**วันที่:** 2026-06-23  
**สถานะ:** รอ review จากทีม

---

## 1. Executive Summary

BagIdeaOffice ต้องมี **MCP server ของตัวเอง** ที่ expose ความสามารถภายในของออฟฟิศ
(agent management, task system, feeds, plugin commands) ให้ external AI agents, IDE
plugins, และ automation workflows สามารถเชื่อมต่อและสั่งงานออฟฟิศได้ — โดยไม่ต้องเขียน
adapter แยกสำหรับแต่ละระบบ

MCP server นี้คือ **"MCP bridge"** ที่กล่าวถึงใน architecture doc (`docs/05-technical-architecture.md` §5.5)
— เป็นหน้าประตูเดียวที่ agent ภายนอกใช้คุยกับออฟฟิศผ่าน OEP (Office Event Protocol)
ที่มีอยู่แล้ว

### 1.1 เป้าหมายทางธุรกิจ (Why)

| ข้อ | เป้าหมาย | วัดผลด้วย |
|-----|---------|----------|
| G1 | ให้ external AI tools (Claude Desktop, Codex, Cursor, Continue.dev) ใช้งาน BagIdeaOffice เป็น backend ได้ | จำนวน MCP client ที่ connect ได้ (target: ≥3 platforms) |
| G2 | ลด effort ในการ integrate ระบบภายนอก — adapter ตัวเดียว รองรับทุก MCP-compatible client | เวลาที่ใช้ integrate client ใหม่ ≤ 1 ชั่วโมง |
| G3 | เปิดให้ automation workflows (n8n, Temporal, cron jobs) สั่งงานออฟฟิศผ่าน standard protocol | จำนวน use case automation ที่รองรับ (target: ≥5) |
| G4 | รักษาความปลอดภัยระดับเดียวกับที่ออฟฟิศมีอยู่แล้ว (Permission Broker) | 0 security bypass ใน penetration test |

---

## 2. Use Cases

ดิฉันแบ่ง use cases เป็น 3 กลุ่มหลักตามประเภทของ caller:

### 2.1 External AI Agents (MCP Clients)

```
┌──────────────────┐     MCP (stdio/HTTP)     ┌──────────────────────┐
│ Claude Desktop   │ ──────────────────────→  │                      │
│ Codex            │                          │  BagIdeaOffice       │
│ Cursor           │     tools/resources      │  MCP Server          │
│ Continue.dev     │ ←──────────────────────  │  (port 8787 หรือ     │
│ Zed/Aider/ฯลฯ    │                          │   stdio transport)   │
└──────────────────┘                          └──────┬───────────────┘
                                                     │ internal API
                                              ┌──────▼───────────────┐
                                              │  BagIdeaOffice Daemon │
                                              │  (OEP + Permission    │
                                              │   Broker + Task Store)│
                                              └───────────────────────┘
```

**Key scenarios:**

| # | Use Case | Actor | Flow |
|---|----------|-------|------|
| UC1 | สร้าง task ใหม่ให้ agent ในออฟฟิศ | External AI (เช่น Claude Desktop สั่งให้ Director ทำงาน) | External AI → `create_task` → Director รับงาน → assign → รายงานผลกลับ |
| UC2 | อ่านสถานะ agents และ tasks | External AI อยากรู้ว่าใครทำงานอะไรอยู่ | External AI → `list_agents` / `list_tasks` → ได้ข้อมูลปัจจุบัน |
| UC3 | ขอให้ออฟฟิศ execute code หรือ run command | External AI ต้องการ sandbox execution | External AI → `run_in_office` → ผ่าน permission broker → execute → return output |
| UC4 | อ่าน/เขียน office memory | External AI ต้องการใช้ความรู้ที่ออฟฟิศสะสมไว้ | External AI → `search_memory` / `store_memory` |
| UC5 | ดู feed และ interact กับ agents | External AI อยากอ่านบทสนทนาในออฟฟิศ | External AI → `get_feed` / `post_feed` |

### 2.2 IDE Integration

| # | Use Case | Actor | Flow |
|---|----------|-------|------|
| UC6 | ส่ง code จาก IDE ให้ agent review | Developer ใน VS Code | IDE → MCP → `send_code_review` → agent ในออฟฟิศ review → ผลลัพธ์กลับ IDE |
| UC7 | Query ออฟฟิศจาก IDE chat panel | Developer ถามคำถามผ่าน IDE | IDE chat → MCP → ส่งคำถามให้ agent → ตอบกลับ inline |
| UC8 | Trigger workflow จาก git hook | Git post-commit hook | Git → MCP → `trigger_workflow` → ออฟฟิศ run workflow → แจ้งผล |

### 2.3 Automation Workflows

| # | Use Case | Actor | Flow |
|---|----------|-------|------|
| UC9 | Morning briefing อัตโนมัติ | Cron job / n8n | Scheduler → MCP → `trigger_workflow("morning-briefing")` → post to feed/channels |
| UC10 | Monitor external events → create task | Webhook handler | External webhook → MCP → `create_task` → agent จัดการ |
| UC11 | Health check + alert | Monitoring system | Monitoring → MCP → `get_health` → ถ้าไม่ healthy → alert |
| UC12 | Scheduled maintenance tasks | Cron job | Scheduler → MCP → `run_maintenance` → cleanup/reindex |

---

## 3. Functional Requirements

### 3.1 Core Capabilities (สิ่งที่ MCP server ต้อง expose)

#### FR1: Agent Management

| Tool/Resource | Type | Description |
|---------------|------|-------------|
| `list_agents` | Tool | รายชื่อ agents ทั้งหมดในออฟฟิศ พร้อมสถานะ (online/offline/busy), roles, skills, provider |
| `get_agent` | Tool | ข้อมูลละเอียดของ agent คนเดียว |
| `summon_agent` | Tool | สร้าง/เรียก agent ใหม่ (ผ่าน Permission Broker — ต้อง approval) |

#### FR2: Task System

| Tool/Resource | Type | Description |
|---------------|------|-------------|
| `create_task` | Tool | สร้าง task ใหม่ใน Task Store — ระบุ title, description, assigned agent, priority |
| `list_tasks` | Tool | รายการ tasks — filter ได้ตาม status, agent, project |
| `get_task` | Tool | ดูรายละเอียด task + progress |
| `cancel_task` | Tool | ยกเลิก task (ต้อง permission) |

#### FR3: Communication & Feed

| Tool/Resource | Type | Description |
|---------------|------|-------------|
| `post_feed` | Tool | โพสต์ข้อความลง feed ของออฟฟิศ (ปรากฏใน feed panel) |
| `get_feed` | Tool | อ่าน feed ล่าสุด (pagination) |
| `send_chat` | Tool | ส่งข้อความแชทตรงถึง agent ใดๆ |

#### FR4: Memory & Knowledge

| Tool/Resource | Type | Description |
|---------------|------|-------------|
| `search_memory` | Tool | ค้นหาใน office memory/RAG index |
| `store_memory` | Tool | เก็บบันทึกลง memory |

#### FR5: Plugin & Workflow

| Tool/Resource | Type | Description |
|---------------|------|-------------|
| `list_plugins` | Tool | รายชื่อ plugins ที่ติดตั้งอยู่ |
| `run_plugin_command` | Tool | สั่ง plugin ผ่าน command (เช่น `music.play`, `calculator.calc`) |
| `list_workflows` | Tool | รายชื่อ workflows |
| `trigger_workflow` | Tool | รัน workflow |

#### FR6: Monitoring & Health

| Tool/Resource | Type | Description |
|---------------|------|-------------|
| `get_health` | Tool | สถานะ daemon, renderer, providers |
| `get_stats` | Tool | สถิติการใช้งาน (token usage, cost, tasks completed) |

#### FR7: Office State (Resources)

| Resource URI | Type | Description |
|--------------|------|-------------|
| `bagidea://agents` | Resource | Agent roster (read-only snapshot) |
| `bagidea://tasks/active` | Resource | Active tasks |
| `bagidea://feed/recent` | Resource | Recent feed entries |
| `bagidea://health` | Resource | Health status |

### 3.2 Transport & Protocol

| Requirement | Detail |
|-------------|--------|
| **FR-T1** | รองรับ **stdio transport** (สำหรับ Claude Desktop, Codex, และ MCP clients ส่วนใหญ่) |
| **FR-T2** | รองรับ **HTTP/SSE transport** (สำหรับ remote clients, web-based integrations) |
| **FR-T3** | HTTP transport ต้อง bind localhost เท่านั้น (security — เหมือน daemon ปัจจุบัน) |
| **FR-T4** | ใช้ session token authentication สำหรับ HTTP transport |

### 3.3 Security

| Requirement | Detail |
|-------------|--------|
| **FR-S1** | ทุก tool ที่มีการเปลี่ยนแปลง state (create_task, summon_agent, post_feed) ต้องผ่าน **Permission Broker** |
| **FR-S2** | Permission request ต้องแสดงรายละเอียดเต็ม (ไม่ summarized) — เหมือนนโยบายปัจจุบัน |
| **FR-S3** | MCP server ต้อง respect policy ที่ตั้งไว้ใน Security Center (allow/deny/ask per agent × per tool) |
| **FR-S4** | Input sanitization — ป้องกัน injection ทุกรูปแบบ (ทบทวนรูปแบบที่ใช้ใน agy-mcp `sanitize_prompt.ts`) |
| **FR-S5** | Rate limiting ต่อ client — ป้องกัน abuse |
| **FR-S6** | ไม่ expose internal file paths หรือ credentials ใน error messages |

### 3.4 Non-Functional Requirements

| Requirement | Detail |
|-------------|--------|
| **NFR1** | **Response time:** ≤ 500ms สำหรับ read-only tools (list/get) |
| **NFR2** | **Response time:** ≤ 5s สำหรับ tools ที่ต้องรอ agent response |
| **NFR3** | **Availability:** MCP server ต้องรันคู่กับ daemon — ถ้า daemon ล่ม MCP ก็ล่มตาม (no single-point-of-failure เพิ่ม) |
| **NFR4** | **Test coverage:** ≥ 80% (unit + integration) — เทียบชั้นกับ agy-mcp ที่มี 59 tests (QA phases 1-4) |
| **NFR5** | **Documentation:** README + tool descriptions ต้องชัดเจนพอที่ MCP client จะ auto-discover capability ได้ |
| **NFR6** | **Backward compatibility:** MCP server v1 ต้องไม่ break existing OEP clients (renderer, overlay, plugin panels) |

---

## 4. Data Flow & Entity Mapping

### 4.1 MCP ↔ OEP Mapping

MCP server เป็น translation layer ระหว่าง MCP protocol (tools/resources/prompts) กับ OEP events:

```
MCP Tool Call                    OEP Event / Internal Call
─────────────                    ─────────────────────────
create_task          ──→         cmd.task.create (via WebSocket)
list_tasks           ──→         read Task Store (registry.json / SQLite)
list_agents          ──→         read registry.json
post_feed            ──→         cmd.chat.send (broadcast event)
search_memory        ──→         GET /retrieval?q=... (retrieval.js)
trigger_workflow     ──→         cmd.task.create (special task type)
get_health           ──→         read daemon state + provider status
```

### 4.2 Security Flow

```
MCP Client → MCP Server → Permission Broker → User Approval → Execute
                 ↑                                              │
                 └──────────── result ──────────────────────────┘
```

---

## 5. Edge Cases & Error Handling

### 5.1 Connectivity

| Edge Case | Expected Behavior |
|-----------|-------------------|
| Daemon not running | MCP server returns clear error: "BagIdeaOffice daemon is not running. Start it with `bagidea` or `npx bagidea`." |
| Daemon starts after MCP server | MCP server should reconnect automatically (retry with exponential backoff) |
| WebSocket disconnected mid-request | Return timeout error; do not leave orphan tasks |
| Multiple MCP clients connected | Support concurrent clients; task/agent state must be consistent |

### 5.2 Authorization

| Edge Case | Expected Behavior |
|-----------|-------------------|
| Permission request times out (user away) | Return "Permission request timed out after N seconds" |
| Permission denied by user | Return clear error with user's rejection reason (ถ้ามี) |
| Tool requires agent that doesn't exist | Return "Agent X not found in registry" |
| Policy says "deny" for this tool | Return "Blocked by security policy" — ห้าม bypass |

### 5.3 Data Integrity

| Edge Case | Expected Behavior |
|-----------|-------------------|
| Task store corruption | Return error; do not crash MCP server |
| Registry.json malformed | Return "Registry data error"; log detail to daemon log |
| Memory index unavailable | Return "Memory search unavailable"; fallback to grep-based search |
| Very large feed request | Paginate — max 50 entries per request |
| Unicode/emoji in task titles | Support fully (ออฟฟิศรองรับ 14 ภาษา) |

### 5.4 Concurrency

| Edge Case | Expected Behavior |
|-----------|-------------------|
| Two clients create duplicate tasks | Accept both; dedup is not MCP server's job |
| Client disconnects mid-task | Task continues running; client can poll status when reconnected |
| Race condition on agent assignment | First-come-first-served; return conflict error to latecomer |

---

## 6. Assumptions & Open Questions

### Assumptions

| # | Assumption | Risk if Wrong |
|---|-----------|---------------|
| A1 | Daemon API (port 8787) มี endpoint เพียงพอให้ MCP server เรียกใช้ภายใน | อาจต้องเพิ่ม API endpoints ใน daemon ก่อน |
| A2 | Permission Broker รองรับ programmatic permission request (ไม่ใช่แค่ interactive) | MCP tools ที่ต้องขอ permission จะ block ถาวร |
| A3 | MCP server จะ deploy เป็นส่วนหนึ่งของ daemon (ไม่ใช่ process แยก) | Architecture เปลี่ยน — กระทบ availability |
| A4 | ใช้ Node.js/TypeScript + `@modelcontextprotocol/sdk` เหมือน agy-mcp | มี prior art และความรู้ในทีม |
| A5 | OEP WebSocket API stable และ documented เพียงพอ | ต้อง reverse-engineer จาก server.js |

### Open Questions (ต้องตัดสินใจก่อน implementation)

| # | Question | Options |
|---|----------|---------|
| Q1 | MCP server ควรเป็น process แยก หรือ embed ใน daemon? | A) Embed ใน daemon (ง่าย, แชร์ state) B) Process แยก (crash isolation, deploy อิสระ) C) Plugin (ใช้ plugin framework เดิม) |
| Q2 | Transport หลักควรเป็น stdio หรือ HTTP? | A) stdio (standard สำหรับ MCP clients) B) HTTP/SSE (standard สำหรับ remote/headless) C) รองรับทั้งสอง |
| Q3 | Authentication สำหรับ HTTP transport ใช้ session token แบบเดียวกับ daemon ไหม? | A) ใช้ shared secret จาก daemon B) ใช้ token คนละชุด C) ไม่ต้อง auth (localhost only) |
| Q4 | MCP server ควร expose ทุก OEP capability หรือค่อยๆเพิ่ม? | A) Phase 1: read-only tools → Phase 2: write tools → Phase 3: full OEP B) Release ทุกอย่างทีเดียว |
| Q5 | ต้องการ `prompts` (MCP prompt templates) อะไรบ้าง? | A) ไม่ต้องมีก่อน B) มี templates สำหรับ common workflows (task creation, code review, etc.) |

---

## 7. Success Criteria

### 7.1 Must Have (MVP — Phase 1)

- [ ] MCP server starts/stops with daemon
- [ ] `list_agents`, `list_tasks`, `get_health` — read-only tools ทำงานได้
- [ ] `create_task` — สร้าง task ได้ผ่าน Permission Broker
- [ ] `post_feed` — โพสต์ feed ได้
- [ ] stdio transport ทำงานกับ Claude Desktop ได้
- [ ] All error paths handled (อิงจาก agy-mcp QA phase 4 pattern)
- [ ] Test coverage ≥ 80%
- [ ] 59+ tests passing (อิงมาตรฐาน agy-mcp)

### 7.2 Should Have (Phase 2)

- [ ] `search_memory` / `store_memory`
- [ ] `summon_agent`
- [ ] `run_plugin_command`
- [ ] `trigger_workflow`
- [ ] HTTP/SSE transport
- [ ] Rate limiting

### 7.3 Nice to Have (Phase 3)

- [ ] Resource URIs (`bagidea://agents`, `bagidea://tasks/active`, ฯลฯ)
- [ ] MCP prompts สำหรับ common workflows
- [ ] Streaming tool results (real-time task progress)
- [ ] Multi-office federation (connect หลายออฟฟิศผ่าน MCP)
- [ ] MCP server registry — publish เป็น official MCP server

---

## 8. Risks & Mitigation

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Daemon API ไม่พร้อมให้ MCP server เรียก | High — ต้อง refactor daemon ก่อน | Medium | สำรวจ daemon API ก่อนเขียนโค้ด (Gap Analysis) |
| Permission Broker ไม่รองรับ non-interactive flow | Medium — write tools ใช้ไม่ได้ | Medium | ออกแบบ approval callback pattern ที่ MCP server รอได้ |
| MCP SDK version conflict กับ daemon dependencies | Low — daemon ใช้ Node.js ล้วนๆ ไม่มี MCP SDK | Low | ใช้ dependency isolation ถ้าจำเป็น |
| Performance overhead จาก MCP server บน daemon | Low — MCP เป็น lightweight protocol | Low | แยก process ถ้าพบปัญหา |

---

## 9. References

- [MCP SDK (TypeScript)](https://github.com/modelcontextprotocol/typescript-sdk)
- [BagIdeaOffice Architecture — §5.5 Agent Adapters & MCP Bridge](docs/05-technical-architecture.md)
- [agy-mcp server — prior art ในโปรเจค](mcp-servers/agy-mcp/)
- [agy-mcp QA Report Phase 4 — error handling patterns](mcp-servers/agy-mcp/QA_REPORT_PHASE4.md)
- [OEP Spec — §5.4 Office Event Protocol](docs/05-technical-architecture.md)
- [BagIdeaOffice Plugin Guide](docs/guide/plugins.md)