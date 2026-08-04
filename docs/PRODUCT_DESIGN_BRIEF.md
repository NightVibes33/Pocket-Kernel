# PocketKernel Consumer Product Build Brief

Design and implement PocketKernel as a premium consumer iOS automation product, never as a developer console.

## Experience

- Start with a cinematic but fast launch sequence that communicates private intelligence, security, and readiness.
- Route first-time and signed-out users into a polished account gateway with native Sign in with Apple, Google account sign-in, and email sign-up/sign-in.
- After authentication, land on a personalized command center with natural-language chat, curated automation templates, connected apps, recent activity, and saved routines.
- Hide backend URLs, OAuth language, raw identifiers, tokens, JSON, and implementation diagnostics from normal users.

## Visual direction

- Native SwiftUI only, with layered depth, animated aurora gradients, deterministic particles, orbital logo motion, spring transitions, material surfaces, gradient strokes, shadows, and responsive press states.
- Motion must communicate state and hierarchy, not exist as decoration.
- Support Reduce Motion, Dynamic Type, VoiceOver, dark appearance, iPhone and iPad layouts, and one-handed use.
- Avoid generic dashboard cards, stock template layouts, fake charts, placeholder copy, and unsupported claims.

## Product rules

- Every important action shows what will happen before it runs.
- Apple Foundation Models perform planning on-device; the server never runs an LLM.
- Account sessions and connected-service credentials are isolated per user.
- Email passwords use memory-hard hashing. Apple and Google identity tokens are cryptographically verified.
- Every screen includes loading, empty, success, offline, disabled, and failure behavior.
- Provide account sign-out, in-app data deletion, privacy, terms, support, and reviewer-ready demo guidance.

## Acceptance criteria

- Compiles as an unsigned ARM64 IPA on GitHub Actions.
- No developer-facing setup fields in the production user journey.
- No login button is a visual stub; unavailable providers clearly explain the missing production configuration.
- Launch-to-auth and auth-to-home transitions remain smooth with Reduce Motion disabled and instantaneous with Reduce Motion enabled.
