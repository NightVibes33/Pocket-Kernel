#!/usr/bin/env bash
set -euo pipefail
ipa="${1:?Missing IPA path}"; work_dir="$(mktemp -d)"; trap 'rm -rf "$work_dir"' EXIT
unzip -q "$ipa" -d "$work_dir"; unzip -t "$ipa" >/dev/null
app_count="$(find "$work_dir/Payload" -mindepth 1 -maxdepth 1 -type d -name '*.app' | wc -l | tr -d ' ')"
test "$app_count" -eq 1; app="$(find "$work_dir/Payload" -mindepth 1 -maxdepth 1 -type d -name '*.app')"; plist="$app/Info.plist"; exe="$app/PocketKernel"
test -f "$exe"; test -f "$app/PrivacyInfo.xcprivacy"; plutil -lint "$plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" = "com.nightvibes33.pocketkernel"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")" = "PocketKernel"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$plist")" = "APPL"
test "$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$plist")" = "26.0"
archs="$(lipo -archs "$exe")"; grep -qw arm64 <<<"$archs"; ! grep -qw x86_64 <<<"$archs"
! find "$app" -name embedded.mobileprovision -o -name _CodeSignature | grep -q .
! otool -L "$exe" | grep -E '/PrivateFrameworks/|iphonesimulator'
Scripts/validate_templates.py "$app/Templates"
