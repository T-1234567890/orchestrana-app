# Orchestrana™ · FAQ

This FAQ answers common questions about Orchestrana’s design choices, scope, and future direction.

---

## What is Orchestrana?

Orchestrana is a **desktop-first macOS focus and planning tool**.

It combines:
- A lightweight Pomodoro / focus timer
- Task management
- Calendar & Reminders integration
- A distraction-reduced Flow Mode

The goal is not to replace existing tools, but to **bring focus, structure, and reflection together** in a calm desktop environment.

---

## Is Orchestrana free?

**Yes.**

Orchestrana is currently **free and open source**, and all core features remain free:
- Timer and focus sessions
- Tasks
- Calendar & Reminders integration
- Menu bar support
- Local-first data storage

There is **no active subscription**, and no paid features today.

---

## Is there a Pro or Plus plan?

No — not at this stage.

You may see documents discussing **future Pro / Plus ideas**, but these are:
- Exploratory
- Long-term
- Not scheduled
- Not implemented

They exist to **share transparent thinking early**, not to announce pricing or lock features behind paywalls.

---

## Why talk about future paid plans at all?

Some future ideas (AI features, cloud services, cross-device sync) involve **ongoing infrastructure costs**.

If such features are ever introduced, a paid plan may exist **only to sustain development**, not to restrict the core app.

Orchestrana aims to avoid:
- Surprise paywalls
- Feature removal
- Breaking existing workflows

---

## Why doesn’t Orchestrana have an iOS or mobile app?

This is an intentional design choice.

Orchestrana is built for **deep work**, which is better supported on a desktop:
- Larger screen
- Keyboard-driven workflows
- Fewer interruptions
- Longer attention spans

Mobile devices are optimized for quick interactions and notifications, which often conflict with focused work.

For this reason, Orchestrana does **not plan to offer a full mobile app** in the foreseeable future.

---

## How do I add tasks or events on my phone?

Mobile workflows are supported through **Apple’s system apps**:

- **Apple Reminders** — quick task capture
- **Apple Calendar** — scheduling and time blocks

Orchestrana syncs with Calendar and Reminders, allowing you to:
1. Capture tasks or events on your phone
2. Review, organize, and focus on them later on your Mac

For best experience, please type this before your task on Apple reminders:
- `#pomodoro`
- `#Pomodoro`
- `#专注`
- `#番茄`
- `#番茄钟`

This keeps mobile usage lightweight while preserving a focused desktop experience.

---

## Can I write tasks from my phone?

**Yes.**

You can:
- Create tasks in Apple Reminders or Calendar
- Sync them back to Orchestrana on macOS

This allows you to capture ideas on the go without using a separate mobile app.

### Task Keywords

Orchestrana supports lightweight **focus intent markers** in task text.  
These keywords help indicate that a task is meant for focused work.  
They do **not** start timers, schedule time, or change tasks automatically.

Supported keywords (type this in your Apple Reminders task):

- `#pomodoro`
- `#Pomodoro`
- `#专注`
- `#番茄`
- `#番茄钟`

---

## Does Orchestrana sync data to the cloud?

Currently:
- Data is stored **locally**
- Calendar and Reminders are synced via Apple’s system frameworks

Future cloud sync ideas (e.g. backups, optional cross-device sync) are **exploratory only** and not implemented.

---

## What is “Bring Your Own AI Key” (BYO)?

In the future, Orchestrana may support a **Bring Your Own AI Key** mode for advanced users.

This would allow users to:
- Use their own AI provider
- Experiment with AI features locally
- Avoid managed services

BYO mode would be:
- Read-only
- Advisory
- User-controlled

System-level automation would remain excluded.

---

## Is Orchestrana open source?

**Yes.**

The client application is open source and developed in the open.

If cloud or AI services are introduced in the future, those components may be separated for security reasons.

---

## Why does Orchestrana use a task ID?

### Q: Why do some tasks sync correctly while others don’t?

Orchestrana uses a unique task ID (UUID) to reliably track tasks across:
- The app itself
- Apple Reminders
- Apple Calendar

This ID allows Orchestrana to know **which task is which**, even if titles or times change.

---

### Q: Why not match tasks by title or date?

Matching by title or date can easily break:
- Two tasks may have the same name
- Titles can change
- Dates can be edited or removed

A unique ID avoids duplication, mismatch, and accidental overwrites.

---

### Q: What happens if a task doesn’t have an ID?

Tasks without an Orchestrana task ID are treated as **external or manual entries**.

That means:
- They are not modified automatically
- They are not re-imported or duplicated
- They remain fully visible and editable in Apple Reminders or Calendar

This behavior is intentional and protects your data.

---

### Q: Do I need to care about IDs as a user?

**No.**

IDs are managed internally by Orchestrana.
You don’t need to create, copy, or understand them.

Just write tasks naturally — the app handles the rest.

## Is Orchestrana available on the Mac App Store?

Not yet.

Current distribution is via **GitHub Releases**.  
The app is unsigned, and macOS Gatekeeper may show a warning on first launch.

A signed App Store or TestFlight release may happen in the future, but it is not a prerequisite for ongoing development.

---

## Is Orchestrana stable?

Orchestrana is under active development.

Minor releases focus on:
- Sync stability
- UI improvements
- Performance and reliability

Feedback and bug reports are welcome.

---

## Where can I learn more about future plans?

- Development roadmap: `docs/Roadmap_1.0-2.0.md`
- Long-term ideas: `docs/Future_Pro_Plan.md`

These documents describe **directional thinking**, not commitments.

---

## How can I contribute?

You can contribute by:
- Reporting bugs
- Sharing feedback
- Suggesting ideas
- Submitting pull requests

Even usage feedback helps guide development.

---

## Final note

Orchestrana is a long-term project.

It prioritizes:
- Focus over feature count
- Sustainability over growth hacks
- Transparency over surprises

Thank you for trying it.
