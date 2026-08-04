#!/usr/bin/env bash
set -euo pipefail
ipa="${1:?ipa required}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
unzip -q "$ipa" -d "$tmp"
app="$(find "$tmp/Payload" -maxdepth 1 -name '*.app' -type d | head -1)"
[[ -n "$app" ]]
[[ -f "$app/PocketKernel" ]]
file "$app/PocketKernel" | grep -q 'Mach-O 64-bit executable arm64'
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist" | grep -qx 'com.nightvibes33.pocketkernel'
! find "$app" -name '*.mobileprovision' | grep -q .
echo "Validated unsigned ARM64 IPA: $ipa"
