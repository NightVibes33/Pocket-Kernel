#!/usr/bin/env bash
set -euo pipefail
patterns='fatalError\(|preconditionFailure\(|TODO:|FIXME:|example\.com|dlopen\(|dlsym\(|PrivateFrameworks|performSelector'
if grep -R -n -E --include='*.swift' "$patterns" PocketKernel; then echo "Forbidden production source pattern found" >&2; exit 1; fi
if grep -R -n -E --include='*.swift' '(api[_-]?key|secret|token)[[:space:]]*=[[:space:]]*"[^\"]+"' PocketKernel; then echo "Possible hardcoded credential found" >&2; exit 1; fi
