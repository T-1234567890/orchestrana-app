# Orchestrana Public Roadmap

This roadmap describes the public product direction for Orchestrana. It is intentionally non-binding and does not include release dates or delivery timelines.

> ### Subscription Disclaimer
> Some planned features may require an active subscription, especially features that depend on managed AI services, advanced context processing, larger note limits, or hosted infrastructure.
> Core focus functionality is intended to remain useful without a subscription.

Orchestrana is evolving from a focus and planning app into an AI-native thinking workspace that connects Focus, AI Jam, Notes, and a Personal Knowledge Base.

## Status Overview

| Area | Status | Public Direction |
| --- | --- | --- |
| Focus, tasks, calendar, and reminders | Available / evolving | Keep improving the core local-first productivity workflow. |
| Flow Mode | Available / evolving | Make focus feel calmer, more immersive, and more system-native. |
| Notes | Planned | Add a lightweight capture layer for ideas, thoughts, and working notes. |
| Phase Notes | Planned | Attach thinking and observations to focus phases, tasks, plans, and sessions. |
| AI Jam | Planned | Add a structured thinking interface for idea generation and transformation. |
| Context System | Planned | Convert selected content into reusable structured context. |
| Workspace Context Processing | Planned | Build summaries from active work, recent notes, tasks, plans, and focus history. |
| Personal Knowledge Base | Planned | Build a portable AI-ready memory layer from notes, plans, and ideas. |
| Export System | Planned | Let users move context into external AI tools and portable formats. |
| Privacy Model | Core requirement | Keep user-generated notes and context local by default. |

## Product Direction

Orchestrana is not intended to become a general-purpose document workspace. The goal is to help users move from focus into understanding:

- Capture what they are thinking.
- Convert rough notes into reusable context.
- Preserve phase-level thinking while work is happening.
- Process current workspace context into useful summaries.
- Build a structured personal memory layer.
- Bring that context into AI tools without losing ownership.
- Continue work from prior context instead of starting over.

The long-term idea is simple:

> Your work should not disappear when a session ends. Orchestrana helps you turn focus, notes, tasks, and ideas into memory you can reuse.

## Core Feature Areas

### Focus Workspace

The existing focus system remains the foundation of Orchestrana.

Planned direction:

- Improve the timer, countdown, stopwatch, and Flow Mode experience.
- Keep Tasks, Calendar, Reminders, and focus sessions connected.
- Make execution feel lightweight and calm.
- Preserve local-first behavior for core productivity data.

### Notes

Notes are the lightweight input layer for thoughts, observations, and working context.

Planned features:

- Quick note capture.
- Markdown-like writing.
- Notes linked to tasks, focus sessions, plans, or days.
- Inline AI assistance.
- Summarize notes.
- Expand rough ideas.
- Convert notes into plans.
- Convert notes into structured context.

Notes should stay fast and low-friction. They are not meant to replace full document tools.

### Phase Notes

Phase Notes connect thinking to the work state where it happened.

Planned features:

- Notes attached to a focus phase.
- Notes attached to a task, plan, or session.
- Quick capture while working.
- Review notes from a completed focus session.
- Preserve decisions, blockers, and follow-up thoughts.
- Convert phase notes into context.
- Convert phase notes into next actions.

Phase Notes should help users remember what changed during work, not force them to maintain a separate documentation system.

### AI Jam

AI Jam is a structured thinking interface, not a chat screen.

Planned inputs:

- Text.
- Images.
- Multimodal input.

Planned AI Jam output structure:

- Idea.
- Breakdown.
- Actions.
- Notes.
- Tags.

AI Jam should help users transform unclear thoughts into useful structure without hiding the reasoning process inside a generic chat transcript.

### Context System

The Context System turns selected content into reusable knowledge.

Planned triggers:

- Select content.
- Choose a Convert to Context action.

Planned processing flow:

- Clean the content.
- Summarize it.
- Structure it.
- Add tags.
- Store it in the Personal Knowledge Base.

The key principle is:

> Everything useful can become context.

### Workspace Context Processing

Workspace Context Processing turns current work into a compact summary that can be reused by the user or AI.

Planned inputs:

- Recent notes.
- Phase notes.
- Active tasks.
- Current plan.
- Focus session history.
- Relevant calendar context.
- User-selected text.

Planned outputs:

- Current workspace summary.
- Active goals.
- Important constraints.
- Recent decisions.
- Open questions.
- Suggested next actions.
- Context ready for AI Jam or export.

This should remain user-controlled. Orchestrana should not silently process or upload private context.

### Personal Knowledge Base

The Personal Knowledge Base is the central memory layer for both the user and AI.

Planned record shape:

```json
{
  "id": "string",
  "content": "string",
  "type": "idea | note | summary | plan",
  "tags": ["string"],
  "source": "AI_JAM | NOTES | MANUAL",
  "createdAt": "timestamp",
  "updatedAt": "timestamp"
}
```

The model can expand as needed, but the first public principle is portability over complexity.

Planned PKB layers:

- Human-readable layer: notes, ideas, plans.
- AI-ready layer: clean summaries, structured content, dense knowledge.
- Portable layer: exportable context for other AI systems.

### Export System

The export system makes Orchestrana's context useful outside the app.

Planned export options:

- Copy as AI Context.
- Export as Markdown.
- Export as JSON.
- Export as plain text.
- Generate context packs for tools such as ChatGPT, Claude, or other AI assistants.

Example context pack sections:

- User goal.
- Key ideas.
- Constraints.
- Current focus.
- Relevant notes.
- Suggested next actions.

### AI Integration

AI should assist thinking, writing, and transformation. It should not silently take control.

Planned AI capabilities:

- Summarize notes and ideas.
- Expand rough thoughts.
- Convert notes into plans.
- Convert selected content into context.
- Generate structured AI Jam outputs.
- Retrieve relevant PKB context for new work.
- Prepare external AI context packs.

Non-goals:

- AI silently modifying calendars, tasks, or notes.
- Fully autonomous scheduling without user approval.
- Replacing user intent or writing style.

### Privacy Model

Privacy is a product requirement, not a later enhancement.

Planned rules:

- User-generated notes stay local by default.
- User context stays local by default.
- Backend storage is reserved for system data such as subscription state, usage limits, and account metadata.
- AI requests should use scoped context, not unrestricted personal data.
- Exports should be user-initiated.

## Roadmap Principles

- Local-first before cloud-first.
- Structure over generic chat.
- User control over silent automation.
- Portability over lock-in.
- Calm focus over feature density.
- AI as a thinking partner, not an operator.

## Public Feature List

- Focus workspace improvements.
- Flow Mode refinements.
- Phase-aware and session-linked notes.
- Task-linked notes.
- Plan-linked notes.
- Focus-session review notes.
- Decision capture.
- Blocker capture.
- Quick notes.
- Markdown-like notes.
- Inline AI for notes.
- AI note summarization.
- AI note expansion.
- Convert note to plan.
- Convert note to context.
- AI Jam text input.
- AI Jam image input.
- AI Jam multimodal input.
- Structured AI Jam outputs.
- Idea extraction.
- Breakdown generation.
- Action generation.
- Supplemental AI notes.
- AI-generated tags.
- Select-to-context action.
- Phase-note-to-context action.
- Context cleaning.
- Context summarization.
- Context structuring.
- Context tagging.
- PKB storage.
- Human-readable PKB views.
- AI-ready PKB summaries.
- Dense knowledge records.
- Portable context records.
- Copy as AI Context.
- Markdown export.
- JSON export.
- Plain text export.
- External AI context packs.
- Workspace context summaries.
- Active-goal summaries.
- Recent-decision summaries.
- Open-question summaries.
- Suggested next-action summaries.
- Local-first note storage.
- Local-first context storage.
- Scoped AI context sharing.
- Subscription-aware feature access.
