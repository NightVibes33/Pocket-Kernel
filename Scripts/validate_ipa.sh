#!/usr/bin/env bash
set -euo pipefail
ipa="${1:?ipa required}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
unzip -q "$ipa" -d "$tmp"
app="$(find "$tmp/Payload" -maxdepth 1 -name '*.app' -type d | head -1)"
[[ -n "$app" ]]
plist="$app/Info.plist"
[[ -f "$plist" ]]
identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
[[ "$identifier" == 'com.nightvibes33.pocketkernel' ]]
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")"
[[ -n "$executable" ]] || { echo 'Missing CFBundleExecutable'; exit 1; }
[[ "$executable" != '(null)' ]] || { echo 'Invalid CFBundleExecutable'; exit 1; }
[[ -f "$app/$executable" ]] || { echo "Missing bundle executable: $executable"; exit 1; }
[[ -x "$app/$executable" ]] || { echo "Bundle executable is not executable: $executable"; exit 1; }
file "$app/$executable" | grep -Eq 'Mach-O 64-bit.*arm64|Mach-O 64-bit arm64 executable'
! find "$app" -name '*.mobileprovision' | grep -q .
echo "Validated unsigned ARM64 IPA with executable $executable: $ipa"
