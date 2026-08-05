#!/usr/bin/env bash
set -euo pipefail
app="${1:?app path required}"
out="${2:?output ipa required}"
[[ -d "$app" ]] || { echo "Missing app: $app"; exit 1; }
manifest="${GITHUB_WORKSPACE:-$(pwd)}/PocketKernel/PrivacyInfo.xcprivacy"
if [[ -f "$manifest" ]]; then
  cp "$manifest" "$app/PrivacyInfo.xcprivacy"
fi
rm -rf Payload "$out"
mkdir -p Payload
cp -R "$app" Payload/
/usr/bin/zip -qry "$out" Payload
rm -rf Payload
