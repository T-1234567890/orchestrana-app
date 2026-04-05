# Orchestrana™ — Detailed Roadmap  
**Versions: v1.1.x → v2.0**

This document outlines the development direction of **Orchestrana** from the current 1.1.x releases toward version 2.0.

The roadmap focuses on **experience stability, system coherence, and long-term sustainability**, rather than rapid feature expansion.

>## Notice
> Roadmap, planning, and information might change without announcement

---

## Flow Mode — Core Experience

Flow Mode represents the long-term experiential center of Orchestrana.

Instead of treating focus as a timer-driven workflow, Flow Mode is designed as a **calm, immersive working state** — where time awareness exists without constant pressure.

### Flow Mode Vision

- A large, readable **clock** at the center  
  (time awareness, not countdown anxiety)
- Ambient sound / white noise placed subtly at the bottom
- Optional lightweight countdown for users who prefer structure
- Minimal controls with a clear and intentional exit
- One-click entry from the sidebar — no setup friction

Flow Mode is not meant to replace Tasks or Calendar.  
It is a **state you enter**, not a dashboard you manage.

---

### Planned Flow Mode Evolution

#### Flow Mode v1 (Target: v1.4)

- Clock-centric layout
- Bottom ambient sound strip (player-style, not control-heavy)
- Optional small countdown indicator
- Explicit exit / return button
- Sidebar entry point (“Flow”)

#### Flow Mode v2 (Target: v1.5)

- Optional automatic fullscreen
- Background blur (system wallpaper or custom image)
- Adjustable clock size, typography, and opacity
- Visual simplicity prioritized over feature density

**Design principle:**  
Flow Mode should feel *lighter* than the main app, not more powerful.

---

### Monetization Boundary (Future)

If Flow Mode becomes part of a paid tier in the future:

- Reasonable Pro candidates:
  - Custom backgrounds
  - Theme packs
  - Advanced layout customization
- Avoid restricting:
  - Basic fullscreen access
  - Core Flow entry or exit

The goal is to enhance Flow, not to gate it.

---

## Overall Vision & Constraints

### What 1.x Is About

- Refining a **local-first macOS productivity workflow**
- Making **Tasks, Calendar, Reminders, and Focus** feel like one system
- Delivering something stable enough for daily use

### What 2.0 Represents

- Reflection, insight, and optional intelligence
- Advisory AI (suggestions, not automation)
- Readiness for App Store / TestFlight distribution  
  (Apple is important, but not a blocking dependency)

---

### Development Constraints

- Fast iteration cadence  
  → Minor versions every **1–2 weeks** (max ~1 month)
- Native macOS stack (Swift / SwiftUI)
- Client remains open source
- Cloud / AI features must and will be:
  - Optional
  - Cost-controlled
  - Architecturally separable
- Avoid maintaining multiple logic stacks  
  → Prefer unified interfaces (e.g. DeepSeek / Qwen)

---

## More Information

This roadmap focuses on the open, local-first experience leading up to version 2.0.

Long-term ideas around optional cloud services, AI features, and potential paid plans are **still in the brainstorming stage** and are intentionally kept separate from the core roadmap.

For readers interested in those future directions:

- Future plans and monetization ideas:  
  `docs/Future_Pro_Plan.md`

These plans are **non-binding**, exploratory, and may change significantly based on user feedback and development priorities.

---

## Phase 1 — v1.1.x  
### Stabilization & “Safe to Share” State

**Goal:**  
A non–computer-science user should be able to install the app and use it for 10 minutes without confusion or breakage.

### Focus Areas

- Fix high-impact UX and sync issues:
  - Calendar **Week View** layout and horizontal navigation
  - Stable **Task ↔ Reminders** two-way sync  
    (completion, deletion, conflict handling)
  - Clearer linkage between Tasks, Reminders, and Calendar events

### Technical Improvements

- Basic sync observability:
  - Last sync time
  - Sync duration
  - Read/write counts
- Unified minimal data model:
  - Tasks & Reminders:
    - `title`, `notes`, `dueDate?`, `completed`, `tags?`, `externalId`
  - Calendar events:
    - `title`, `start/end`, `notes/url`, `externalId`

---

## Phase 2 — v1.2  
### Data Model Lock-in & Sync Architecture

**Goal:**  
Define rules early to prevent long-term sync instability.

### Unified External ID Strategy (Required)

To enable reliable two-way sync:

- Local Tasks → UUID
- System Reminders & Calendar Events store references like: <br>
pomodoroapp://task/ <br>
pomodoroapp://event/ <br>

This prevents duplication and mismatch across systems.

---

### Centralized Sync Layer

Introduce a dedicated sync coordinator:

- `SyncEngine`
  - `syncAll()` (one-button global sync)
  - `syncTasksWithReminders()`
  - `syncCalendarEvents()`

Initial conflict strategy:
- “Last modified wins” or “Local preferred”
- Conflicts surface as lightweight notifications

---

## Phase 3 — v1.3  
### Experience Convergence & Local Insights

**Goal:**  
Help users see progress without introducing cloud dependency.

### Features

- Local-only statistics:
  - Today’s focus time
  - Weekly trends
  - Task completion rate
- Calendar views behave like a calendar  
  (Day / Week / Month), not a list
- Completed tasks live in a dedicated tab

### Implementation Notes

- Session records stored locally
- Charts rendered with Swift Charts
- No API or server cost introduced

---

## Phase 4 — v1.4–v1.5  
### Flow Mode Maturity

(See Flow Mode section at top for full details.)

---

## Phase 5 — v1.6  
### Documentation & Public Readability

**Goal:**  
Make the project understandable without prior context.

### Deliverables

- Clean README:
  - Clear one-sentence description
  - Screenshots
  - Download & install instructions
- Expanded `docs/` directory:
  - `Gatekeeper.md`
  - `Roadmap_1.0-2.0.md`

- In progress:
  - `Privacy.md`
  - `FAQ.md`

- Improved GitHub discoverability:
  - Topics
  - Discussions (Ideas / Bugs / Show & Tell)

---

## Phase 6 — v1.7  
### AI Architecture & Closed Beta Foundation

**Goal:**  
Prepare for AI features without breaking openness or cost control.

### Architectural Separation

- Open-source client
- Private server backend

Planned repository structure:

- `pomodoro-app` (client, open source)
- `pomodoro-cloud` (server, private)

The client defines **protocols**, not secrets.

---

### AI Access Modes

- **BYO Key (Free / advanced users)**
  - User supplies own API key
  - Advice-only features
- **Pro Cloud (Optional)**
  - Managed backend
  - Monthly allowance
  - One-click experience

Usage is presented as *allowance*, not *restriction*.

---

## Phase 7 — v1.8–v1.9  
### AI Beta Iteration & Cost Control

- AI advice (non-automated)
- Task drafting from ideas
- Daily / weekly summaries
- Token tracking & graceful fallback
- Heavy users can switch to BYO mode

---

## Phase 8 — v2.0  
### Experience Lock-in & Distribution Readiness

v2.0 is considered ready when:

- Flow Mode feels complete
- Task / Calendar / Reminders feel coherent
- AI is optional and non-intrusive
- Documentation is self-explanatory

App Store / TestFlight preparation can happen around this point.

---

## Key Technical Milestones (Summary)

1. Unified external ID system
2. Central SyncEngine with logging
3. Modular Flow Mode
4. AI client abstraction (BYO + Cloud)
5. Client / server separation
6. Clear usage & allowance UI

---

*Last updated: Jan 25, 2026*
