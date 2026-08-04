# Authentication Architecture

PocketKernel supports three primary account methods:

- Sign in with Apple using the native AuthenticationServices flow and server-side RS256 verification against Apple's published keys.
- Google account sign-in using Authorization Code + PKCE, server-side ID-token verification, and a one-time app exchange code.
- Email sign-up/sign-in using normalized addresses and Node scrypt password hashing.

The iOS app stores only its PocketKernel session and profile in the device Keychain. Connected-service credentials remain separately encrypted on the server. Account login never exposes provider access tokens to the app.
