# PocketKernel 2.0

PocketKernel is a chat-first automation app for iPhone and iPad. The conversation, planning, and tool selection run with Apple's **on-device iOS 27 Foundation Model**. OAuth is used only to connect external services. The Vercel backend never runs an LLM.

## Product flow

1. The person chats naturally with PocketKernel.
2. `SystemLanguageModel.default` chooses registered `Tool` implementations.
3. Read actions may run directly; write and scheduled actions appear as approval cards.
4. Native actions execute through iOS frameworks. Connected-service actions execute through the deterministic Vercel API.
5. A completed action can be stored as a repeatable server automation.

## Included tools

- Native: notifications, reminders, calendar events, HTTPS links, clipboard, local notes.
- Google: Gmail search/send and Calendar event creation.
- Slack: send channel messages.
- Discord: send through an authorized incoming webhook.
- Reddit: publish self posts.
- Notion: create pages.
- Scheduler: one-time and recurring deterministic service workflows.

## Privacy and safety

- No OpenAI, Anthropic, Gemini, or other cloud LLM is called.
- OAuth passwords never enter PocketKernel.
- Provider tokens are encrypted with AES-256-GCM before storage.
- Every user has an isolated backend identity and connection namespace.
- Sensitive writes require approval in the iOS app before immediate execution.
- Scheduled workflows contain fixed steps; the server does not reinterpret prompts.

## iOS build

The app compiles with Xcode 26.5 and the iOS 26 SDK so GitHub Actions can produce an unsigned ARM64 IPA today. The agent itself is guarded with `@available(iOS 27.0, *)` and refuses to run on earlier systems, ensuring all intelligence comes from the iOS 27 on-device model.

Run **Actions → Build PocketKernel Unsigned IPA**. A successful push uploads and releases `PocketKernel-unsigned.ipa`.

## Vercel backend

The repository root is a Vercel Functions project. Attach an Upstash Redis database and configure the variables in `.env.example`. Provider callback URLs use:

`https://YOUR_DOMAIN/api/oauth/callback?provider=PROVIDER`

Vercel Cron invokes `/api/cron/dispatch` every minute. Vercel Pro is required for per-minute scheduling; Hobby cron is limited to daily execution and hourly precision.

## Required production setup

The code can be deployed immediately, but real OAuth sign-in cannot work until each provider issues a client ID and secret for the production domain. Secrets belong only in Vercel environment variables and must never be committed or embedded in the IPA.
