# Terms of Service

**Effective Date:** April 4, 2026  
**Last Updated:** April 4, 2026

---

## 1. Introduction

Pomodoro App ("we," "our," or "the Service") provides a macOS productivity application, related cloud-backed functionality, and the website at https://pomodoro-app.tech. These Terms of Service ("Terms") govern your use of the website, the app, and related backend services we operate.

By using the Service, you agree to these Terms. If you do not agree, do not use the Service.

---

## 2. What the Service Includes

The Service may include:

- The Pomodoro App macOS application
- The website and related documentation pages
- Account features and authentication
- Subscription and entitlement verification
- Cloud-backed planning, AI, and scheduling features
- Optional integrations and provider-based sign-in flows

The current product may use backend routes or callable cloud functions for tasks such as AI proxying, AI planning, task breakdown, task description generation, calendar schedule generation, allowance checks, account lookup, subscription verification, subscription reconciliation, and related quota or entitlement enforcement.

Features may change over time. Some features may be limited by plan, region, platform, beta status, or account state.

---

## 3. Eligibility and Accounts

You must be legally able to use the Service under applicable law. If you create or use an account, you are responsible for maintaining the security of your credentials and for activity that occurs under your account.

You may use sign-in methods we make available, including:

- Email/password
- Google Sign-In
- GitHub sign-in
- Apple Sign-In

Some sign-in methods may be unavailable in certain builds, regions, or phases of rollout. Third-party providers may impose their own eligibility rules, terms, and privacy requirements.

When you use a third-party sign-in provider, you authorize us and our authentication providers to receive the identity, account, and authentication data reasonably necessary to create, link, maintain, or secure your account.

---

## 4. License and Permitted Use

Subject to these Terms, we grant you a limited, non-exclusive, non-transferable, revocable license to use the Service for personal or internal business productivity purposes in accordance with applicable law and platform rules.

You may not:

- Copy, resell, sublicense, or commercially exploit the Service except as permitted by law or an applicable license
- Reverse engineer or attempt to extract source or backend logic except where applicable law clearly allows it
- Interfere with, probe, overload, or abuse the Service
- Circumvent feature gating, quotas, subscriptions, security checks, or provider restrictions
- Use the Service to violate law or the rights of others

We reserve all rights not expressly granted.

---

## 5. User Content

You may submit or store information through the Service, including tasks, notes, schedules, calendar context, planning inputs, prompts, and related productivity data ("User Content").

You retain your rights in your User Content, but you grant us a limited license to host, process, transmit, store, display, and transform that content as necessary to operate the Service, including cloud-backed planning, scheduling, authentication-aware features, subscriptions, support, and security functions.

You are responsible for ensuring that:

- You have the right to use and submit the content
- Your content does not violate law or the rights of others
- You review AI-generated outputs before relying on them

---

## 6. AI Features and Planning Features

The Service may offer AI-assisted features such as:

- Task breakdown
- Task planning
- Task description generation
- AI assistant workflows
- Calendar scheduling and rescheduling
- Productivity summaries or related insight features

When you use these features, relevant User Content may be transmitted to our backend and to third-party model providers or routing providers acting on our behalf.

This may include task titles, notes, deadlines, estimated hours, calendar events, availability constraints, plan context, prompts, and similar workflow inputs needed to fulfill the request.

The current backend architecture routes AI traffic through backend-controlled endpoints and may use **OpenRouter** to access supported model providers or model families. Current implementation references include **DeepSeek** and **Gemini** model families, along with quota, allowance, and usage enforcement.

Some AI-dependent features rely on third-party AI providers, routing providers, or related infrastructure. Those providers may change, fail, become unavailable, return delayed responses, or alter model behavior over time, and the Service does not guarantee continuous availability of AI features.

AI output may be incomplete, inaccurate, inconsistent, misleading, or otherwise unsuitable for your situation. You are responsible for reviewing, verifying, and independently evaluating AI-generated suggestions, plans, schedules, summaries, or text before acting on them.

The Service is a productivity tool, not a provider of legal, medical, financial, or other professional advice.

AI features may also be subject to usage limits, quotas, rate limits, plan restrictions, or provider-side constraints. Excessive usage, abusive usage, or attempts to bypass those limits may result in throttling, feature restriction, suspension, or other protective measures.

---

## 7. Calendar, Reminders, and Local Integrations

The Service may integrate with Calendar, Reminders, notifications, music, or other local/system services when you enable them. Some integrations operate locally; others may involve cloud-backed requests when you explicitly invoke planning, scheduling, or account-based features.

You remain responsible for verifying any changes, suggested schedules, or calendar actions before relying on them.

We do not guarantee that third-party integrations will always remain available or behave identically over time.

---

## 8. Subscriptions, Paid Features, and Entitlements

Some features may require a paid plan, beta entitlement, or another access tier. We may verify eligibility through platform billing systems, backend entitlement records, subscription verification endpoints, App Store server notifications, or related infrastructure.

If you purchase through Apple or another platform:

- Billing, renewals, cancellations, and refunds may be governed by that platform's terms
- We may receive subscription status, transaction identifiers, expiration data, and entitlement state needed to operate paid features
- Your access may change if billing fails, a subscription expires, or verification fails

### App Store Subscription Terms

For subscriptions purchased through Apple:

- Payment will be charged to your Apple ID account at confirmation of purchase.
- Subscriptions automatically renew unless canceled at least 24 hours before the end of the current billing period.
- Your account may be charged for renewal within 24 hours before the end of the current period.
- You can manage or cancel your subscription through your App Store account settings after purchase.
- Pricing may vary by region, currency, taxes, promotions, introductory offers, or platform rules.
- Access to subscription-gated features depends on your active subscription and verified entitlement status.

We may suspend access to paid features if we reasonably believe there is fraud, abuse, quota manipulation, or an entitlement mismatch.

We may also use backend allowance, quota, and entitlement systems to determine which AI models, AI features, or premium workflows are available to your account.

---

## 9. Third-Party Services and Sign-In Providers

The Service may depend on third-party services, including:

- Apple
- Google
- GitHub
- Firebase / Google Cloud
- OpenRouter
- AI providers and model routing services
- Calendar, reminders, music, or other optional integrations

Your use of those third-party services may also be governed by their separate terms and privacy policies. We are not responsible for third-party services we do not control.

We are not responsible for outages, latency, degraded responses, policy changes, pricing changes, feature removals, or other failures of third-party providers or third-party infrastructure, including providers such as Google, OpenRouter, Apple, GitHub, Firebase, or underlying AI model providers.

This includes sign-in providers such as Google Sign-In, GitHub sign-in, Apple Sign-In, and email/password authentication handled through Firebase Authentication or related providers.

This also includes backend infrastructure and data processors used for:

- Firebase Authentication
- Firebase Cloud Functions
- Firestore-backed account, quota, or subscription state
- App Store subscription verification and server notifications
- OpenRouter-routed AI requests
- AI model providers accessed through our routing or provider stack

---

## 10. Acceptable Use and Security

You agree not to:

- Misuse the Service or attempt unauthorized access
- Circumvent security, monitoring, or abuse-prevention controls
- Try to exhaust quotas or disrupt backend systems
- Attempt to bypass plan restrictions, AI routing controls, billing state, subscription checks, or entitlement logic
- Use the Service to process unlawful, infringing, harmful, or abusive content
- Use bots or automation against the Service in a way that materially harms availability or integrity

We may monitor, rate-limit, suspend, or restrict access when reasonably necessary to protect the Service, users, providers, or infrastructure.

---

## 11. Beta Features and Service Changes

Some parts of the Service may be labeled beta, preview, experimental, or coming soon. Those features may change, be interrupted, or be removed without notice.

We may modify, add, limit, or remove features, providers, routes, models, pricing, UI, or integrations for legal, operational, product, or security reasons.

AI models, AI capabilities, quotas, provider routing, premium features, and product behavior may change over time. Features described in documentation, screenshots, release materials, or marketing content may not all be available in every build, region, plan, or point in time.

We do not guarantee continuous availability of any specific feature, provider, model, or integration.

---

## 12. Disclaimers

To the maximum extent permitted by law, the Service is provided on an "AS IS" and "AS AVAILABLE" basis without warranties of any kind, whether express, implied, or statutory.

We do not guarantee that:

- The Service will always be available, uninterrupted, or error-free
- AI outputs will be correct, safe, or appropriate
- Schedules, task plans, or recommendations will fit your exact needs
- Third-party sign-in providers or integrations will always work without interruption
- Subscription verification, quota counters, or provider APIs will always remain continuously available without delay or incident

You are responsible for maintaining backups and for protecting your own device, credentials, and workflow decisions.

---

## 13. Limitation of Liability

To the maximum extent permitted by law, we are not liable for indirect, incidental, special, consequential, exemplary, or punitive damages, or for loss of data, profits, goodwill, productivity, or business opportunity arising from or related to the Service.

To the maximum extent permitted by law, our total liability for claims arising out of the Service will not exceed the amount you paid us for the Service in the 12 months before the event giving rise to the claim, or the minimum amount permitted by law if you paid nothing.

Some jurisdictions do not allow certain limitations, so parts of this section may not apply to you.

---

## 14. Termination

You may stop using the Service at any time.

We may suspend or terminate access if we reasonably believe you violated these Terms, created legal or security risk, abused quotas or subscriptions, harmed the Service, or if suspension is required for legal or operational reasons.

Sections that should survive by their nature will survive termination, including sections on privacy, licenses, disclaimers, limitations of liability, disputes, and intellectual property.

---

## 15. Privacy

Our data practices are described in the Privacy Policy, which should be read together with these Terms:

- [Privacy Policy](../../website/privacy.html)

If there is a conflict between a product description and the Privacy Policy about data handling, the Privacy Policy controls on that topic.

---

## 16. Intellectual Property

The Service, excluding your User Content and third-party materials, is owned by us or our licensors and is protected by applicable intellectual property laws.

Open-source components are governed by their own licenses, and those licenses control where required.

Third-party trademarks, product names, and provider names belong to their respective owners.

---

## 17. Governing Law

These Terms are governed by applicable law. If you are a consumer, mandatory rights under the law of your place of residence may still apply.

---

## 18. Contact

For questions about these Terms:

**Email:** support@pomodoro-app.tech  
**GitHub Issues:** https://github.com/T-1234567890/pomodoro-app/issues  
**Website:** https://pomodoro-app.tech

---

**Thank you for using Pomodoro App.**
