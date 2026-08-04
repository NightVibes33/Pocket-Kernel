#!/usr/bin/env bash
set -euo pipefail
app="${1:?app path required}"
out="${2:?output ipa required}"
[[ -d "$app" ]] || { echo "Missing app: $app"; exit 1; }
rm -rf Payload "$out"
mkdir -p Payload
cp -R "$app" Payload/
/usr/bin/zip -qry "$out" Payload
rm -rf Payload
