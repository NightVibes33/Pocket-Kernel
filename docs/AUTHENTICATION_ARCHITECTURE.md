# Authentication Architecture

PocketKernel supports three primary account methods:

- **Sign in with Apple:** native AuthenticationServices UI, a cryptographically random nonce, server-side RS256 verification against Apple's published keys, issuer/audience/expiry validation, and nonce comparison.
- **Google account:** Authorization Code + PKCE, server-side token exchange and ID-token verification, followed by a short-lived one-time ticket returned to the app callback.
- **Email:** passwordless sign-in and sign-up using a six-digit, single-use code delivered by the configured transactional email provider. Codes are salted, hashed, attempt-limited, and expire after ten minutes.

The iOS app stores only its PocketKernel session and basic profile in the device Keychain. Connected-service credentials remain separately encrypted and isolated by account on the server. Account login never returns Google, Apple, Gmail, Slack, or other provider access tokens to the app.
