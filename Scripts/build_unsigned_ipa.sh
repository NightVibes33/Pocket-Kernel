#!/usr/bin/env bash
set -euo pipefail
APP_PATH="${1:?Missing app path}"
IPA_PATH="${2:?Missing IPA path}"
test -d "$APP_PATH"
test -f "$APP_PATH/PocketKernel"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
mkdir -p "$WORK_DIR/Payload"
cp -R "$APP_PATH" "$WORK_DIR/Payload/PocketKernel.app"
find "$WORK_DIR/Payload" -name '_CodeSignature' -type d -prune -exec rm -rf {} +
find "$WORK_DIR/Payload" -name 'embedded.mobileprovision' -delete
find "$WORK_DIR/Payload" -name '.DS_Store' -delete
mkdir -p "$(dirname "$IPA_PATH")"
(
  cd "$WORK_DIR"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent Payload "$IPA_PATH"
)
unzip -t "$IPA_PATH" >/dev/null
