# Active Nova login bypass

- PocketKernel launches through `NovaEntryView`.
- The active router now preserves `NovaBootView` and skips `NovaAccountGatewayView`.
- First launch continues to onboarding; later launches continue directly to `NovaRootView`.
- Account implementation remains in source for later reactivation.
- Marketing version: 2.2.1
- Build version: 67
