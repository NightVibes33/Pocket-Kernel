#!/usr/bin/env bash
set -euo pipefail
xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json, re, sys
d=json.load(sys.stdin)["devices"]
r=[]
for runtime, devices in d.items():
 m=re.search(r"iOS-(26(?:-[0-9]+)*)$", runtime)
 if m: r.append((tuple(map(int,m.group(1).split("-"))), devices))
for _, devices in sorted(r, reverse=True):
 for device in devices:
  if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
   print(device["udid"]); raise SystemExit(0)
print("No available iOS 26 iPhone simulator", file=sys.stderr); raise SystemExit(1)'

