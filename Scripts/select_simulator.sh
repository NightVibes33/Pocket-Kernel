#!/usr/bin/env bash
set -euo pipefail

xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json, re, sys
payload = json.load(sys.stdin)
candidates = []
for runtime, devices in payload.get("devices", {}).items():
    match = re.search(r"iOS-(26)-(\d+)(?:-(\d+))?", runtime)
    if not match:
        continue
    version = tuple(int(value or 0) for value in match.groups())
    for device in devices:
        if not device.get("isAvailable", False):
            continue
        name = device.get("name", "")
        if not name.startswith("iPhone"):
            continue
        candidates.append((version, name, device["udid"]))
if not candidates:
    print("No available iPhone simulator with an iOS 26 runtime was found.", file=sys.stderr)
    sys.exit(1)
candidates.sort(key=lambda item: (item[0], item[1]), reverse=True)
print(candidates[0][2])
'
