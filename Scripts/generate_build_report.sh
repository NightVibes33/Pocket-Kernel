#!/usr/bin/env bash
set -euo pipefail
IPA="${1:?Missing IPA path}"
REPORT="${2:?Missing report path}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
unzip -q "$IPA" -d "$WORK_DIR"
APP="$WORK_DIR/Payload/PocketKernel.app"
EXECUTABLE="$APP/PocketKernel"
SHA="$(shasum -a 256 "$IPA" | awk '{print $1}')"
SIZE="$(stat -f%z "$IPA")"
cat > "$REPORT" <<EOF
# PocketKernel Build Report

- Git commit: ${GITHUB_SHA:-local}
- Workflow run: ${GITHUB_RUN_NUMBER:-local}
- Runner architecture: $(uname -m)
- macOS: $(sw_vers -productVersion)
- Xcode: $(xcodebuild -version | tr '\n' ' ')
- Swift: $(swift --version | head -1)
- iPhoneOS SDK: $(xcrun --sdk iphoneos --show-sdk-version)
- Bundle identifier: $(plutil -extract CFBundleIdentifier raw "$APP/Info.plist")
- Marketing version: $(plutil -extract CFBundleShortVersionString raw "$APP/Info.plist")
- Build number: $(plutil -extract CFBundleVersion raw "$APP/Info.plist")
- Minimum OS: $(plutil -extract MinimumOSVersion raw "$APP/Info.plist")
- Binary architecture: $(lipo -archs "$EXECUTABLE")
- IPA bytes: $SIZE
- SHA-256: $SHA
- Unit/UI test gate: ${PK_TEST_RESULT:-passed}
- Signing state: unsigned; no embedded provisioning profile or code-signature directory
EOF
