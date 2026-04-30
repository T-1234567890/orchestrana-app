# Privacy Policy

**Effective Date:** April 30, 2026  
**Last Updated:** April 30, 2026

---

## Introduction

Orchestrana™ ("we," "our," or "the Service") provides a macOS productivity application, related cloud features, and the website at https://orchestrana.app. This Privacy Policy explains what information we collect, how we use it, when it is shared, and what choices you have.

Because Orchestrana includes open-source client-side code, parts of our implementation can be reviewed publicly at https://github.com/T-1234567890/orchestrana-app. Some backend systems are not public, so this policy also describes the cloud services that support authentication, subscriptions, AI features, and account-based access.

---

## What This Policy Covers

This policy applies to:

- **The website** at https://orchestrana.app
- **The macOS application**
- **The Orchestrana cloud backend** used for authentication-aware features, entitlement checks, subscription verification, and AI-assisted features

This policy does not replace the privacy terms of third-party platforms or providers you choose to use, such as Apple, Google, GitHub, Firebase, or AI model providers.

---

## Information We Collect

## 1. Website Information

When you use our website, we may collect:

- Information you submit through forms, such as waitlist or contact email addresses
- Standard web request data, such as IP address, browser type, referring page, pages visited, and approximate device/network metadata
- Public GitHub data that we display on the website, such as repository statistics, contributor names, avatars, issues, pull requests, and commit activity
- Browser-side preferences such as language choice and cached website state stored in your browser

The website may also rely on third-party services such as Google Fonts, Google Forms, or GitHub APIs, which may process technical request data under their own policies.

## 2. Data Stored Locally on Your Mac

Orchestrana stores a significant amount of data locally on your device, including:

- Timer settings and session preferences
- UI preferences and onboarding state
- Tasks, notes, due dates, completion state, and related planning data
- Session history and usage history stored locally by the app
- Local media or ambient audio preferences
- Calendar and reminders metadata used by local integrations
- Cached entitlement, account, or AI state needed to keep the app responsive

This local data is generally stored in app sandbox locations such as:

- `UserDefaults` entries used for task lists, planning items, preferences, onboarding state, duration settings, reminders sync preferences, Flow Mode background preferences, and cached app state
- Application Support files such as local session history JSON files
- macOS Keychain entries used for persisted authentication session data

Examples reflected in the current app code include:

- Task and planning storage in `UserDefaults`
- Flow Mode background bookmarks and preferences in `UserDefaults`
- Session record storage in Application Support under a `PomodoroApp` directory
- Auth session persistence in Keychain using a generic password entry

## 3. Account and Sign-In Data

If you use account features, we may collect and process account data through Firebase Authentication and related providers.

Depending on the sign-in method you choose, this may include:

- **Email/password sign-in**: email address, encrypted authentication credentials handled by Firebase, Firebase user ID, and session tokens
- **Google Sign-In**: Google account email, display name, profile image URL, provider account identifier, and authentication tokens needed to complete sign-in
- **GitHub sign-in**: GitHub account email or primary email returned by the provider, display name or username, avatar URL, provider account identifier, and authentication tokens needed to complete sign-in
- **Apple Sign-In**: Apple account identifier, display name and email if provided by Apple, and Apple private relay email if you choose to hide your email; Apple Sign-In coverage applies when the provider is offered or enabled in the Service

We also maintain account-linked metadata such as:

- Firebase user ID
- Authentication state
- Current plan or tier
- Feature entitlement state
- Subscription status and expiration metadata
- AI allowance, quota, or reset timing

### Google Sign-In Data Usage

If you choose Google Sign-In, the Service may collect or receive the following Google user data as part of authentication and account functionality:

- email address
- display name
- profile image, if available from Google
- Google account identifier
- authentication tokens

We use this Google user data only to:

- authenticate the user
- create a new account or link an existing account
- maintain login sessions
- personalize basic account display information such as name and avatar

We only access and use the minimum Google user data necessary for authentication and account functionality.

Google authentication is handled securely through Firebase Authentication and Google's OAuth systems. We do not have access to your Google password.

Authentication tokens are used only to verify identity and are not used for any other purpose.

We do not use Google user data for advertising or marketing purposes.
We do not sell or share Google user data with data brokers.
We only use Google user data to provide and improve core app functionality.

Google user data is not used for advertising, is not sold to third parties, and is not used for tracking users across apps.

## 4. Subscription and Billing Data

If you use paid features or subscriptions, we may process:

- Subscription tier and entitlement status
- Transaction identifiers and verification results
- Subscription start/end dates, renewal status, and plan status
- App Store server notification data or equivalent platform verification data
- Quota period metadata, remaining allowance, usage totals, reset dates, and related plan enforcement state

Payments themselves are generally handled by Apple or another platform provider. We do not state that we store your full payment card number because platform billing is typically handled outside our systems.

## 5. AI, Planning, and Scheduling Data

If you use AI-assisted features, we may process content you submit for those features, including:

- Task titles, descriptions, notes, due dates, durations, and planning inputs
- Calendar availability, calendar events, scheduling constraints, and time-block context that you choose to use with AI scheduling or rescheduling features
- Requests for AI task breakdown, AI planning, AI-generated task descriptions, AI schedule generation, AI assistant actions, and productivity insight or summary features
- AI responses, usage totals, quota events, model routing metadata, and safety or debugging logs

We only process this data when you actively use the relevant AI or cloud-assisted feature.
We only send the minimum necessary data required to fulfill each AI request.

The current product includes cloud-backed AI and planning routes for features such as:

- AI task breakdown
- AI task planning
- AI-generated task descriptions
- AI assistant actions
- AI calendar schedule generation and rescheduling
- Productivity insight or summary requests sent through the AI proxy

AI traffic in the current backend is routed through our backend and may be forwarded through **OpenRouter** to supported model families. The current codebase references Standard Models and Frontier Models and tracks quota or allowance usage for those families.

### Third-Party AI Processing

When you use AI features, relevant inputs may be sent to third-party AI providers or routing services, including providers operated by **Google** and services such as **OpenRouter**, but only to the extent needed to generate the requested response or complete the requested AI feature.

We only transmit the data reasonably necessary for the specific request. Depending on the feature, this may include task text, planning context, scheduling constraints, calendar availability, or related prompt content that you chose to submit.

Third-party AI providers may process and temporarily store data when AI features are used. Their handling of that data is subject to their own terms and privacy policies.

We do not sell AI request data, prompt content, or AI-related personal data, and we do not use that data for advertising.

We do not use your data to train our own models.

AI outputs may be inaccurate, incomplete, or unsuitable for your situation. You are responsible for reviewing and verifying AI-generated results before relying on them.

Because AI requests may include the content you submit, you should avoid entering highly sensitive personal information into AI prompts or AI-assisted workflow fields unless you are comfortable with that data being processed to generate a response.

## 6. Device Permissions and Local Integrations

If you grant them, the app may access:

- **Notifications** to send focus alerts and reminders
- **Calendar** to read your events and support planning, display, and optional scheduling features
- **Reminders** to support task/reminder workflows

Some of this information may remain local. However, if you explicitly use cloud-backed planning or AI scheduling features, relevant task or calendar context may be transmitted to our backend and to AI providers acting on our behalf to fulfill your request.

---

## How We Use Information

We use information to:

- Operate the website and app
- Authenticate users and maintain sessions
- Support email/password, Google, GitHub, Apple, and other sign-in methods we make available
- Deliver account-aware features and settings
- Verify subscriptions and determine feature eligibility
- Enforce quotas, rate limits, and fraud/security protections
- Provide AI planning, task breakdown, scheduling, productivity, and assistant features that you choose to use
- Render local and cloud-backed planning, calendar, and task experiences
- Improve reliability, prevent abuse, diagnose errors, and maintain security
- Respond to support requests, legal obligations, and operational needs

We do not sell your personal data to advertisers or data brokers.

We may also use account, quota, and entitlement data to:

- determine whether a feature is available on your current plan
- decide whether AI usage is within your allowance
- verify whether a subscription is active, expired, renewed, or restricted
- prevent abuse, quota bypass, or unauthorized access to paid or limited features

---

## When We Share Information

We may share information in the following situations:

## 1. Service Providers

We use service providers and infrastructure that process data on our behalf, including:

- **Firebase / Google Cloud** for authentication, backend infrastructure, Cloud Functions, and related account, entitlement, quota, and subscription processing
- **Apple** for platform services, subscriptions, Sign in with Apple, App Store billing, and server-side subscription verification where applicable
- **Google** for Google Sign-In and related provider services
- **GitHub** for GitHub sign-in and public repository integrations
- **OpenRouter** as an AI routing/provider layer where configured in the backend
- **AI model providers** used behind OpenRouter or related routing infrastructure to fulfill AI requests you explicitly send through the Service

Only the information reasonably necessary to fulfill the relevant AI request or cloud feature is transmitted to those providers.

Backend systems reflected in the current codebase include Firebase Cloud Functions and related endpoints or callable functions used for:

- `aiProxy`
- `taskBreakdown`
- `taskPlanning`
- `generateTaskDescription`
- `aiAssistant`
- `generateCalendarSchedule`
- `getAllowance`
- `getMe`
- `subscriptionVerify`
- App Store subscription notification handling

The backend also uses Firestore-backed account, quota, or subscription state in current server-side logic.

## 2. Platform and Integration Providers

If you enable integrations or platform-dependent features, information may also be shared with the provider needed to complete that action.

## 3. Legal and Safety Reasons

We may disclose information if required by law, legal process, or a valid governmental request, or if reasonably necessary to protect users, the Service, or our rights.

## 4. Business Transfers

If the Service or project is reorganized, transferred, merged, or sold, relevant data may be transferred as part of that transaction, subject to applicable law.

---

## Third-Party Sign-In Providers

The Service may support the following account providers:

- Email/password through Firebase Authentication
- Google Sign-In
- GitHub sign-in
- Apple Sign-In

Additional providers may be added over time. When you choose a sign-in method, the provider and Firebase may process your information under their own privacy terms in addition to this policy.

We use provider data primarily to:

- Authenticate you
- Create or link your account
- Display basic account profile information in the app
- Secure purchases, entitlements, and cloud-backed features

Depending on the provider and what the provider returns, this may include email address, display name, avatar/profile image URL, provider user identifier, and authentication tokens or assertions needed to complete sign-in.

---

## Data Retention

We retain information for as long as reasonably necessary for the purposes described in this policy, including to:

- Maintain your account
- Provide subscriptions and entitlements
- Support AI usage accounting and quota enforcement
- Keep required logs for security, fraud prevention, and service integrity
- Comply with legal obligations

Local app data generally remains on your device until you delete it, reset the app, sign out, uninstall the app, or remove related local files. Account and backend data may remain until you request deletion, your account is removed, or retention is no longer required for operational or legal purposes.

Retention may also vary based on the category of data, including:

- authentication/account records
- subscription verification records
- quota and allowance records
- security and abuse-prevention logs
- AI request and response metadata
- support and legal compliance records

---

## Your Choices and Rights

Depending on your location and applicable law, you may have rights to access, correct, delete, export, or restrict certain personal data.

You can also:

- Avoid optional sign-in features by using local-only features where available
- Sign out of your account
- Remove local app data from your device
- Revoke Calendar, Reminders, Notifications, or sign-in permissions through system or provider settings
- Contact us to request deletion or account assistance

If you request account deletion, we may delete or de-identify account-linked data unless we need to retain certain records for security, billing, fraud prevention, or legal compliance.

---

## International Processing

Your information may be processed in countries other than your own, including the United States and other locations where our providers operate. By using the Service, you understand that data may be transferred to and processed in those jurisdictions, subject to applicable safeguards and law.

---

## Security

We use reasonable technical and organizational measures to help protect personal information, including HTTPS/TLS, provider-managed authentication systems, app sandboxing, and platform security features. No system is perfectly secure, and we cannot guarantee absolute security.

You are responsible for keeping your device, provider accounts, and credentials secure.

Current implementation details reflected in the codebase include:

- HTTPS-backed requests to backend APIs and Cloud Functions
- Firebase Authentication tokens for authenticated cloud requests
- Keychain-backed persisted auth session storage on device
- provider-managed sign-in flows for Google and GitHub, and Apple provider support in backend/provider handling
- backend quota and entitlement enforcement intended to reduce unauthorized use of paid or limited AI features

---

## Children's Privacy

The Service is not directed to children under 13, and we do not knowingly collect personal information from children under 13. If you believe a child has provided personal information to us, contact us and we will investigate and take appropriate action.

---

## Changes to This Policy

We may update this Privacy Policy as the product, backend, sign-in options, subscriptions, and AI features evolve. The current version will be posted on the website with an updated effective or last-updated date.

---

## Contact

For privacy questions or requests:

**Support:** support@orchestrana.app  
**General:** hello@orchestrana.app  
**GitHub Issues:** https://github.com/T-1234567890/orchestrana-app/issues  
**Website:** https://orchestrana.app

---

**Thank you for using Orchestrana.**
