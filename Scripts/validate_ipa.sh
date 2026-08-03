#!/usr/bin/env bash
set -euo pipefail
IPA="${1:?Missing IPA path}"
test -f "$IPA"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
unzip -q "$IPA" -d "$WORK_DIR"
unzip -t "$IPA" >/dev/null
shopt -s nullglob
APPS=("$WORK_DIR"/Payload/*.app)
shopt -u nullglob
[ "${#APPS[@]}" -eq 1 ] || { echo "Expected exactly one app in Payload" >&2; exit 1; }
APP="${APPS[0]}"
EXECUTABLE="$APP/PocketKernel"
test -f "$EXECUTABLE"
ARCHS="$(lipo -archs "$EXECUTABLE")"
[[ " $ARCHS " == *' arm64 '* || "$ARCHS" == 'arm64' ]]
[[ " $ARCHS " != *x86_64* ]]
plutil -lint "$APP/Info.plist" >/dev/null
[ "$(plutil -extract CFBundleIdentifier raw "$APP/Info.plist")" = 'com.nightvibes33.pocketkernel' ]
[ "$(plutil -extract CFBundleExecutable raw "$APP/Info.plist")" = 'PocketKernel' ]
[ "$(plutil -extract CFBundlePackageType raw "$APP/Info.plist")" = 'APPL' ]
[ "$(plutil -extract MinimumOSVersion raw "$APP/Info.plist")" = '26.0' ]
plutil -extract CFBundleIcons xml1 -o - "$APP/Info.plist" >/dev/null
[ ! -e "$APP/embedded.mobileprovision" ]
[ ! -d "$APP/_CodeSignature" ]
test -f "$APP/PrivacyInfo.xcprivacy"
plutil -lint "$APP/PrivacyInfo.xcprivacy" >/dev/null
plutil -extract NSPrivacyAccessedAPITypes xml1 -o - "$APP/PrivacyInfo.xcprivacy" | grep -q 'NSPrivacyAccessedAPICategoryUserDefaults'
plutil -extract NSPrivacyAccessedAPITypes xml1 -o - "$APP/PrivacyInfo.xcprivacy" | grep -q 'CA92.1'
test -f "$APP/Assets.car"
if otool -L "$EXECUTABLE" | grep -q '/System/Library/PrivateFrameworks'; then
  echo "Private framework linkage detected" >&2
  exit 1
fi
while IFS= read -r binary; do
  if file "$binary" | grep -q 'Mach-O' && lipo -archs "$binary" | grep -q 'x86_64'; then
    echo "Simulator architecture found: $binary" >&2
    exit 1
  fi
done < <(find "$APP/Frameworks" -type f 2>/dev/null || true)
/usr/bin/python3 "$(dirname "$0")/validate_templates.py" "$APP/Templates"
echo "Validated unsigned ARM64 PocketKernel IPA"
