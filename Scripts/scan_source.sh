#!/usr/bin/env bash
set -euo pipefail

patterns=(
  'fatalError\('
  'preconditionFailure\('
  'TODO:'
  'FIXME:'
  'example\.com'
  'AKIA[0-9A-Z]{16}'
  'AIza[0-9A-Za-z_-]{30,}'
  'dlopen\('
  'dlsym\('
  'PrivateFrameworks'
  'performSelector'
  'UIWebView'
  'WKWebView'
)
status=0
for pattern in "${patterns[@]}"; do
  if grep -RInE --exclude-dir=.git --exclude='scan_source.sh' --include='*.swift' --include='*.m' --include='*.mm' --include='*.h' "$pattern" PocketKernel; then
    echo "Forbidden production-source pattern found: $pattern" >&2
    status=1
  fi
done
if find PocketKernel -type f \( -name '*.swift' -o -name '*.plist' -o -name '*.json' -o -name '*.pocketapp' \) -size 0 | grep -q .; then
  echo "Empty production resource found." >&2
  find PocketKernel -type f -size 0 >&2
  status=1
fi
exit "$status"
