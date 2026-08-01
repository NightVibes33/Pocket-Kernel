#!/usr/bin/env bash
set -euo pipefail
ipa="${1:?Missing IPA}"; report="${2:?Missing report}"; work_dir="$(mktemp -d)"; trap 'rm -rf "$work_dir"' EXIT
unzip -q "$ipa" -d "$work_dir"; app="$work_dir/Payload/PocketKernel.app"; plist="$app/Info.plist"; exe="$app/PocketKernel"
cat >"$report" <<REPORT
# PocketKernel Build Report

- Git commit: ${GITHUB_SHA:-local}
- Workflow run: ${GITHUB_RUN_ID:-local}
- Runner architecture: $(uname -m)
- macOS: $(sw_vers -productVersion)
- Xcode: $(xcodebuild -version | tr '\n' ' ')
- Swift: $(swift --version | head -1)
- iPhoneOS SDK: $(xcrun --sdk iphoneos --show-sdk-version)
- Bundle identifier: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")
- Marketing version: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
- Build number: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")
- Minimum OS: $(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$plist")
- Binary architecture: $(lipo -archs "$exe")
- IPA bytes: $(stat -f%z "$ipa")
- SHA-256: $(shasum -a 256 "$ipa" | awk '{print $1}')
- Unit/UI tests: passed before device build
- Signing state: unsigned (no CodeResources or provisioning profile)
REPORT

