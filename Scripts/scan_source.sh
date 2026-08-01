#!/usr/bin/env bash
set -euo pipefail
patterns='fatalError\(|preconditionFailure\(|TODO:|FIXME:|example\.com|dlopen\(|dlsym\(|PrivateFrameworks|performSelector'
if rg -n "$patterns" PocketKernel --glob '*.swift'; then echo "Forbidden production source pattern found" >&2; exit 1; fi
if rg -n '(api[_-]?key|secret|token)[[:space:]]*=[[:space:]]*"[^\"]+"' PocketKernel --glob '*.swift'; then echo "Possible hardcoded credential found" >&2; exit 1; fi

