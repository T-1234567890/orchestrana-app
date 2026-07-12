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
👉  https://orchestrana.app

## Screenshot
<a href="https://apps.apple.com/app/orchestrana/id6758972580">
  <img width="2880" height="1800" alt="App Store Screenshot" src="https://github.com/user-attachments/assets/0aee6a3a-ed9f-45f3-82e9-65dc76f7a6de" />
</a>

## 🚀 Try it now

### Available on the App Store

Orchestrana is now available on the Mac App Store.

👉 Download Orchestrana:  
https://apps.apple.com/app/orchestrana/id6758972580

### Previous GitHub Release
Download the latest release from GitHub and run the app.

- **Gatekeeper warning**: macOS may warn that the app is from an unidentified developer. This is expected while the project awaits Apple Developer Program approval.
- **Bypass Gatekeeper safely**: follow the step‑by‑step guide in `docs/Gatekeeper.md` to open the downloaded app without compromising security.

The App Store build is the recommended signed distribution.

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
> - Any type of abuses
>
>Any unauthorized use may result in access restrictions and may be subject to further action.

## Version status/Release Notes

For full details on updates, see the release notes on the **App Store**.

👉 App Store release notes are the source for current version changes and updates.

### 📌 Update Policy
- Will receive more updates
- Changes may occur without notice
- Feedback, PR, and issue reports are welcome
- Current public distribution is through the App Store

## 🤖 AI Features

AI-powered features are now available in Orchestrana.

Availability depends on the current app version, account state, subscription tier, regional availability, and usage limits. Some AI features require Plus or Pro because they use managed backend services and external AI providers.

## Current UI Direction

The current UI uses a structured glass tile system inspired by macOS 26 (liquid glass). <br>
The goal of upcoming versions is to transition toward a softer, macOS-inspired liquid glass look — with more subtle contrast, improved typography, and refined panel depth.

## 🛠️ Project status

- Stable for daily use
- Design iterations are ongoing
- New features are in development

>**🚧 Distribution Status**
>
>Orchestrana is currently under active development and available on the App Store.
>
>**🚀 App Store Download Available**
>
>The current signed Mac build is available through Apple's App Store.
>
>👉 Download Orchestrana:  
>https://apps.apple.com/app/orchestrana/id6758972580
>
>Thank you for your interest and support ❤️

## 🗺️ Roadmap (Post-1.0.0)

Planned for future versions:

- 🧠 Personal Knowledge Base and AI-ready context
- 📝 Lightweight notes connected to focus, tasks, and plans
- 🧩 AI Jam for structured idea generation and transformation
- 📦 Exportable context packs for external AI tools
- 🎨 More macOS-style liquid glass theme refinements
- 🪄 Smoother button & timer animations
- 💡 Better logic
- 🔔 Advanced reminder scheduling & customization
- ⌨️ More features
- 🛎️ Issue requirements

See: `Docs/Public_Roadmap_3.0.md`, `Docs/Future_Pro_Plan.md`, and `Docs/Roadmap_1.0-2.0.md`

## Pricing

Orchestrana currently uses three public plan levels:

- **Free** — Included
- **Plus** — $4.99/month or $39.99/year
- **Pro** — $7.99/month or $69.99/year

See the public comparison page for the full feature breakdown: https://orchestrana.app/comparison

Prices are shown in USD. App Store regional pricing, taxes, offers, and availability may vary. The App Store and current app build are the source of truth for active subscription terms.

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
- Public roadmap: `Docs/Public_Roadmap_3.0.md`
- Legacy roadmap: `Docs/Roadmap_1.0-2.0.md`
- FAQ & design decisions: `docs/FAQ.md`
- Gatekeeper & installation notes: `docs/Gatekeeper.md`

### Long-term Future Directions

The **Orchestrana client is open source** under the repository license.

Orchestrana is also a commercial product with existing paid plans for hosted services and higher-cost features such as managed AI, subscription-gated capabilities, and backend-supported functionality. The open-source client does not mean every hosted service or production feature is free.

Details: `Docs/Future_Pro_Plan.md` is a legacy planning document and may be outdated compared with the current product and App Store configuration.

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

## ⚠️ Notice

This project is under active development and some features or UI elements may change over time.<br>
If you encounter issues or have suggestions, feel free to open an issue or pull request.

## 📄 Policies

Orchestrana™ is a commercial product. While this client is open-source, the following terms apply:
- **Client License:** The code in this repository is licensed under the **MIT License**.
- **Proprietary Backend:** The server-side infrastructure, database, and production APIs are **closed-source**. Access to this repository does not grant permission to interact with, access, or test any production systems.
- **Contributions:** By submitting a Pull Request or any kind of contributing, you agree to grant the project owner a perpetual, worldwide, non-exclusive license to use your contributions commercially.

Official legal and policy documents for the app and website.<br>
Orchestrana™ is a trademark of Shenzhen Tushengjin Commercial Services Co., Ltd.

[Policies & Legal](https://orchestrana.app/policies.html) <br>
[Repository Additional Terms](https://github.com/T-1234567890/orchestrana-app/blob/main/TERMS.md)

## 📬 Contact

- 📧 Support: support@orchestrana.app
- 📧 General: hello@orchestrana.app
- 🌐 Website: https://orchestrana.app  
- 💬 Issues / PRs / Discussions are welcome

We’re happy to hear feedback, bug reports, and feature ideas.
