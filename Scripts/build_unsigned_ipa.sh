#!/usr/bin/env bash
set -euo pipefail
app_path="${1:?Missing app path}"; ipa_path="${2:?Missing IPA path}"
test -d "$app_path"; test -f "$app_path/PocketKernel"
work_dir="$(mktemp -d)"; trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$work_dir/Payload"; cp -R "$app_path" "$work_dir/Payload/PocketKernel.app"
find "$work_dir/Payload" -name _CodeSignature -type d -prune -exec rm -rf {} +
find "$work_dir/Payload" -name embedded.mobileprovision -delete
find "$work_dir/Payload" -name .DS_Store -delete
mkdir -p "$(dirname "$ipa_path")"
(cd "$work_dir" && /usr/bin/ditto -c -k --sequesterRsrc --keepParent Payload "$ipa_path")
unzip -t "$ipa_path"

