# Real-device acceptance

Sign `PocketKernel-unsigned.ipa` with the `com.nightvibes33.pocketkernel` application identifier and run this sequence on the iPhone 16:

1. Complete onboarding and confirm Settings reports the exact Foundation Models availability state.
2. Install and open all five built-in templates.
3. Create a Service Log record, terminate PocketKernel, relaunch, and confirm persistence/recovery.
4. Generate a Car Service Log, review its validation report, install it, and create a record.
5. Export the generated app, delete it, import the `.pocketapp`, and verify its records remain isolated.
6. Deny a notification capability request and confirm the action fails without a crash.
7. Enable airplane mode and confirm on-device generation or deterministic template fallback remains useful.
8. Cold-launch twice and confirm no immediate crash.

Record the device OS/build, IPA SHA-256, signing tool, availability result, and any failed step in the GitHub release notes.
