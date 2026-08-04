# PocketKernel Nova redesign

Validated scope for the complete product redesign:

- Replaced the launch experience with the new animated PocketKernel orbit identity.
- Rebuilt account entry, Apple sign-in, Google sign-in, and passwordless email verification UI.
- Added live account-service capability checks so unavailable providers are never presented as functioning.
- Rebuilt onboarding, command center, chat, approval cards, starter workflows, and custom navigation.
- Rebuilt Automations, Activity, Profile, and Connections using the same Nova visual system.
- Added a matching 1024 px app icon materialized from an embedded Base64 SVG during CI.

The unsigned ARM64 IPA workflow remains the release gate.
