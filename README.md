# 🍅 Orchestrana™
### Plan. Focus. Done.

**Orchestrana** is a macOS productivity app that connects focus sessions, Tasks, Reminders, and Calendar into a single workflow.  
It is not just a timer — it links tasks, time, and focus, adapting to task-driven, time-blocking, or flow-based work styles. Orchestrana is built as a unified time system rather than a rigid productivity method, with a macOS-inspired **glass / liquid glass UI**.

<p align="center">
  <img
    width="240"
    height="240"
    alt="Orchestrana Logo"
    src="https://github.com/user-attachments/assets/2b1b1847-46ed-46e9-8c79-7366f4480794"
  />
</p>


<p align="center">
  <img src="https://img.shields.io/github/license/T-1234567890/orchestrana-app" alt="License" />
  <img src="https://img.shields.io/badge/platform-macOS-blue?logo=apple" alt="Platform" />
  <img src="https://img.shields.io/github/v/release/T-1234567890/orchestrana-app" alt="Release" />
 <a href="https://vps.town">
  <img src="https://img.shields.io/badge/Sponsored%20by-VPS.Town-3DAF7C" alt="Sponsor VPS.Town" />
</a>
</p>

>## ⚠️ Notice
> If the app still ask for calendar & reminders permissions after you activate, please quit and restart the app

## 🌐 Our official website

Explore the project website for design philosophies, documentation, and downloads:<br>
👉  https://pomodoro-app.tech

## Screenshot
<img width="1027" height="728" alt="Screenshot 2026-01-30 at 4 25 25 PM" src="https://github.com/user-attachments/assets/e04529ad-dacf-4675-bb06-88fdf5a2a7cf" />

## 🎁 Giveaway Event

The giveaway has ended. Please check your email if you participated. <br>
Thank you to everyone who participated!

Winners:

- `2*6@qq.com` 
- `c*e@hotmail.com`  
- `m*e@gmail.com`

Winners will receive an email with instructions on how to claim their prize.  
Please reply to the email to confirm and complete the claiming process.

The reward and emails will be sent after confirmation. Additional details about the claiming process will be included in the email.

👉 Full rules & participation details:  
[View Giveaway Rules](Docs/giveaway.md)

## 🚀 Try it now

### Early Access Preview Available

Official Apple preview builds are now available via TestFlight.

This is an **invite-only early access** — please join the waitlist to request an invite before getting access.

👉 Join the waitlist:  
https://forms.gle/hQ7ubqxt39sXca4e9

### Previous GitHub Release
Download the latest release from GitHub and run the app.

- **Gatekeeper warning**: macOS may warn that the app is from an unidentified developer. This is expected while the project awaits Apple Developer Program approval.
- **Bypass Gatekeeper safely**: follow the step‑by‑step guide in `docs/Gatekeeper.md` to open the downloaded app without compromising security.

Signed app is provided on TestFlight currently.

## ✅ Features

- ⏱️ Customizable work, short break, and long break durations
- 🔁 Long-break interval configuration (e.g. every 4 sessions)
- ⚡ Presets for quick switching (25/5, 50/10, 90/15, Custom)
- ▶️ Start / Pause / Resume / Reset with clear state feedback
- ⏳ Dedicated countdown timer mode
- ✅ Tasks with optional Reminders integration and bidirectional sync foundations
- 📅 Calendar views (Day / Week / Month) as a visual layer for planning
- 🔔 Session-end pop-up reminder with optional sound
- 📊 Daily productivity summary (focus time, sessions, breaks)
- 💾 Automatic saving of daily stats
- 🎧 Ambient sound player (white noise, brown noise, rain, wind)
- 🎵 Simple music status support (Apple Music / Spotify)
- 🪟 Glass-panel UI with background blur and depth
- 🌙 macOS dark mode support
- 💻 Real time menubar support on MacBooks

## ✨ Why Orchestrana is different

Orchestrana is designed as a unified time system — not just a timer. It brings together focus sessions, tasks, reminders, and calendar blocks into **one single workflow**, so planning and execution live in the same place.

Instead of forcing a rigid productivity method, Orchestrana **adapts to how you actually work — whether that’s time-blocking, task-driven planning, or flow-based focus**.

## 🧰 Running & Developing

### Running the app

If you prefer not to build from source, download the binary from the latest release (see “Try it now” above). On first launch, macOS may block the app; use the Gatekeeper guide linked above.

### Building from source

Requires Xcode on macOS 14.6 or later.
Clone this repository, open the project in Xcode, and build/run as usual.

**Requirements:** <br>
- Firebase iOS SDK 12.9.0 or later
  (Swift Package Manager should automatically download gRPC, GoogleUtilities, etc. for you)
- Xcode on macOS 14.6 or later

This project uses Swift Package Manager to manage dependencies. <br>
The current version is fully native Swift; legacy Tauri/Svelte/Python versions are archived.

>## ⚠️ Firebase Config File Usage
>
>⚠️ Important
>	- The included GoogleService-Info.plist is for this project only
>	- It is not intended for reuse, modification, or external environments
>
>🚫 Do NOT
>	- Do not use this configuration for your own Firebase projects
>	- Do not modify or overwrite this file in commits
>	- Do not rely on it outside of this repository
>
>✅ If you want to use your own Firebase project
>	1.	Create your own Firebase project
>	2.	Download your own GoogleService-Info.plist
>	3.	Replace the file locally only
>	4.	Add it to your local ignore if needed
> 
>See Example:
>`GoogleService-Info.plist.sample`
> 
>**Legal Notice**
>
>The Firebase configuration contained in this repository is the property of the project owner and is provided strictly for use within this project only.
>
>You are not permitted to:
>	- Use this configuration in any other application or project
>	- Send requests to the associated Firebase project outside of this application
>	- Attempt to access, exploit, or interfere with the backend services
> - Any types of abuses
>
>Any unauthorized use may result in access restrictions and may be subject to further action.

## Version status/Release Notes

For full details on updates, see the release notes on **TestFlight** or **App Store**.

👉 TestFlight & App Store release notes are the new source for version changes and updates.

### 📌 Update Policy
- Will receive more updates
- Changes may occur without notice
- Feedback, PR, and issue reports are welcome
- Will be on TestFlight or App Store

## 🤖 AI Features (Developer Preview)

AI-powered features are currently being deployed and are in **private developer preview**.

At the moment, these features are only available to **authorized developer accounts** for internal testing.  
A small number of additional testers may be invited during this stage.

The full AI feature set is planned to be **officially released in version 2.0.0**.

## Current UI Direction

The current UI uses a structured glass tile system inspired by macOS 26 (liquid glass). <br>
The goal of upcoming versions is to transition toward a softer, macOS-inspired liquid glass look — with more subtle contrast, improved typography, and refined panel depth.

## 🛠️ Project status

- Stable for daily use
- Design iterations are ongoing
- New features are in development

>**🚧 Distribution Status**
>
>Orchestrana is currently under active development and available on TestFlight
>
>**🚀 Preview Access Available**
>
>Official Apple preview builds of Orchestrana are now available via TestFlight. <br>
>This is an **invite-only early access program** — access is managed through a waitlist to prevent spam and ensure quality feedback.
>
>👉 Join the TestFlight waitlist:  
>https://forms.gle/hQ7ubqxt39sXca4e9
>
>Thank you for your interest and support ❤️

## 🗺️ Roadmap (Post-1.0.0)

Planned for future versions:

- 🎨 More macOS-style liquid glass theme refinements
- 🪄 Smoother button & timer animations
- 💡 Better logic
- 🔔 Advanced reminder scheduling & customization
- ⌨️ More features
- 🛎️ Issue requirements

See: `docs/Future_Pro_Plan.md` and `docs/Roadmap_1.0-2.0.md`

## 🤝 Collaboration & Contributions

You’re welcome to help improve:

- 🎨 UI & visual refinement (macOS-style liquid glass direction)
- 🧩 Session logic & customization options
- 🔔 In-app reminder & notification
- 🧪 Bug fixes and stability improvements
- 📝 Documentation
- ✅ Anything else

## Discussions & Suggestions

If you want to:

- propose a feature
- discuss UI / UX direction
- any other things about this project

You can open a Discussion or Issue instead of a PR.

Constructive feedback is especially welcome during the current 1.x.x integration and planning phase.

## 🕰️ Legacy Systems (Archived)

Orchestrana has gone through multiple architectural stages during its development.
All previous implementations are preserved **for reference only** and are no longer
part of the active product direction.

Legacy see: https://github.com/T-1234567890/Pomodoro-legacy

**Status**
- ❌ Deprecated
- ❌ Prototype only
- ❌ No longer representative of the project
- ❌ No longer maintained

The current mainline version of Orchestrana is **fully native Swift (macOS)**.

<details>

### Legacy System A — Tauri + Svelte + Python (0.5.x – 0.7.x)

This version introduced a modern desktop architecture before the move to native Swift.

**Stack**
- Frontend: Svelte
- Desktop shell: Tauri
- Backend: Python (Pomodoro engine)
- IPC: JSON-based bridge between frontend and backend

**Reason for deprecation**
While functional, this architecture:
- Added unnecessary complexity on macOS
- Limited deep system integration
- Did not fully match macOS performance and UX expectations

The project has since migrated to **native Swift** for clarity, performance, and long-term maintainability.

---

### Legacy System B — Python + Tkinter UI (≤ 0.4.x)

This was the **original prototype** used during the earliest stages of development.

**Stack**
- Python
- Tkinter UI
- Single-process desktop app
</details>

## Docs

- Future planning: `docs/Future_Pro_Plan.md`
- Development roadmap: `docs/Roadmap_1.0-2.0.md`
- FAQ & design decisions: `docs/FAQ.md`
- Gatekeeper & installation notes: `docs/Gatekeeper.md`

### Long-term Future Directions

**Orchestrana is free**.

A small number of long-term ideas (AI features, cloud sync, deeper analytics) are being brainstormed.  
**No paid plan exists at this stage.**

Details: `docs/Future_Pro_Plan.md`

## 🤝 Sponsors & Partners

This project is supported by partners who help keep development sustainable.

---

<p align="center">
  <a href="https://vps.town" target="_blank">
    <img
      alt="VPS.Town Sponsor"
      src="https://github.com/user-attachments/assets/f968c79a-0700-4a3b-8d76-5a56911650b2"
      width="900"
    />
  </a>
</p>

<p align="center">
  VPS.Town provides infrastructure support for testing and cloud experimentation.
</p>

---

### 💡 Sponsorship Categories

| Category | Partner |
|----------|---------|
| Infrastructure Sponsor | VPS.Town |
| AI Partner | Available |
| Community Partner | Available |
| Tools / Integration Partner | Available |
| Other | Available |

Interested in sponsoring or partnering with Orchestrana?
Contact us below.

## 📈 Star History

[![Star History Chart](https://api.star-history.com/svg?repos=T-1234567890/orchestrana-app&type=date&legend=top-left)](https://www.star-history.com/#T-1234567890/orchestrana-app&type=date&legend=top-left)

## ⚠️ 说明/Notice
本项目仍在持续改进中，部分功能或界面可能会发生变化。<br>
如在使用过程中发现问题或有改进建议，欢迎提交 Issue 或 PR。

This project is under active development and some features or UI elements may change over time.<br>
If you encounter issues or have suggestions, feel free to open an issue or pull request.

## 📄 Policies
Official legal and policy documents for the app and website.<br>
Orchestrana™ is a trademark of Shenzhen Tushengjin Commercial Services Co., Ltd.

[Policies & Legal](https://pomodoro-app.tech/policies.html)

## 📬 Contact

- 📧 Email: support@pomodoro-app.tech  
- 🌐 Website: https://pomodoro-app.tech  
- 💬 Issues / PRs / Discussions are welcome

We’re happy to hear feedback, bug reports, and feature ideas.
