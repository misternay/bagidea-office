# 8. Game-Like Progression Systems

## 8.1 Design Stance

Progression must **reward real productivity, never gate it**. Two laws:

1. **No pay/grind walls on function** — every agent capability works at level 0. Progression unlocks *expression* (cosmetics, rooms, ceremonies) and *convenience* (bookmarks, themes), never capability.
2. **XP only from truth** — points come from completed real missions, not from leaving the app open. (Anti-gamification of idle time; we are not a clicker.)

## 8.2 The Three Tracks

```
AGENT CAREERS          OFFICE GROWTH            COMPANY PRESTIGE
(per agent)            (per installation)       (meta/seasonal)
─────────────          ──────────────           ────────────────
XP per mission   ──►   Office Level   ──►       Valuation score,
Levels 1–30            unlocks zones,           achievements,
Titles: Intern →       wings, floors,           collections,
Junior → Senior →      decor slots,             seasonal reports
Lead → Principal →     amenities
Director
```

### Agent Careers
- XP per completed mission, weighted by duration/complexity (tool calls, collab depth); failures give small "experience" XP (honest framing: you learn from failure) but break streaks.
- **Level-ups are ceremonies**: confetti at the desk, colleagues gather and applaud (30s, skippable). Title on the nameplate; small cosmetic evolutions (better chair, second monitor, desk plant — the *desk* levels with the agent).
- **Specialization stars** per category (research/code/creative/ops) from mission mix — at a glance, a veteran coder's workstation *looks* veteran.
- Careers are also **useful telemetry**: levels approximate which agents you actually rely on.

### Office Growth
- Office Level = aggregate missions + active-agent diversity. Levels unlock in narrative beats:

| Lv | Unlock | Story beat |
|---|---|---|
| 1 | Lobby, Exec, Ops, Cafeteria, Dorm | "Garage startup" — other rooms dust-sheeted |
| 3 | Research Lab, Dev Studio | first specialists hired |
| 5 | Meeting Room, Mission Control | "we need process now" |
| 8 | Creative Studio, Archive Library | the company finds its memory |
| 11 | Server Room (visible infra), Security Center upgrade | scale-up era |
| 14 | Training Academy | invest in people |
| 17+ | East wing, rooftop, second floor… | the campus era |

  (Note: all *functions* exist from day 1 — locked rooms' features live in plain Layer-2 panels until the room "opens." The unlock celebrates and spatializes a feature, never withholds it.)
- **Renovation moments**: unlocking a zone plays a 10s construction vignette — agents in hard hats, tarp pulled off. Screenshot bait.
- Decor slots grow with level; furniture/plants/posters placed in a simple edit mode.

### Company Prestige
- **Valuation**: a playful composite score (missions shipped, uptime, collab count, knowledge stored). Rendered as a stock-ticker prop in the Lobby. Purely vanity, no resets of real data.
- **Achievements**: "First All-Nighter" (overnight scheduled task), "Department of One" (one agent, 100 missions), "Well-Oiled Machine" (10 collabs without a failure), "Librarian" (1k memories stored).
- **Collections**: gallery wall (creative outputs), trophy case (achievements), diploma wall (Academy), souvenir shelf (seasonal events).

## 8.3 Rituals & Rhythms (retention without dark patterns)

- **Monday kickoff**: Main Agent presents a weekly plan at the Mission Control map (drawn from real queued/scheduled work).
- **Friday retro**: the office gathers in the Meeting Room; a "Week in Review" card (missions, wins, failures, top agent) — shareable image export.
- **Work anniversaries**: an agent's hire-date anniversary = cake in the Cafeteria. (Pure charm; users will screenshot this.)
- **End-of-day report**: optional 1-card digest at a chosen hour.

## 8.4 The Economy (soft currency)

**Coffee Beans ☕** — earned per mission completed (small) and per achievement (large). Spent only on cosmetics: decor, sprite outfits, office themes, pet (an office cat that naps on the warmest server). No purchase of beans with money in the base loop (premium cosmetics are bought directly — keeps the earned currency honest; see [Monetization](09-monetization.md)).

## 8.5 Anti-Patterns Explicitly Banned

- Daily-login streak pressure, FOMO timers on functional features, loot boxes, pay-to-skip levels, idle-time XP, notifications whose only purpose is re-engagement. The office is a calm colleague, not a slot machine.
