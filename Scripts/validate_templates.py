#!/usr/bin/env python3
import hashlib
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "PocketKernel/Templates")
files = sorted(root.glob("*.pocketapp"))
if len(files) != 5:
    raise SystemExit(f"Expected exactly five built-in .pocketapp templates, found {len(files)}")
identifier = re.compile(r"^[a-z0-9_-]+$")
for path in files:
    raw = path.read_bytes()
    if len(raw) > 25 * 1024 * 1024:
        raise SystemExit(f"{path}: package exceeds 25 MB")
    package = json.loads(raw)
    if package.get("formatVersion") != 1:
        raise SystemExit(f"{path}: unsupported package version")
    manifest = package.get("manifest", {})
    required = {"formatVersion", "id", "name", "summary", "entryScreenID", "screens", "actions", "collections", "capabilities", "createdAt", "updatedAt"}
    if not required.issubset(manifest):
        raise SystemExit(f"{path}: missing manifest keys {sorted(required - set(manifest))}")
    canonical = json.dumps(manifest, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    expected = hashlib.sha256(canonical).hexdigest()
    if package.get("integrity", {}).get("algorithm") != "sha256" or package.get("integrity", {}).get("manifestHash") != expected:
        raise SystemExit(f"{path}: manifest integrity mismatch")
    screen_ids = [screen["id"] for screen in manifest["screens"]]
    action_ids = [action["id"] for action in manifest["actions"]]
    collection_ids = [collection["id"] for collection in manifest["collections"]]
    for values, label in [(screen_ids, "screen"), (action_ids, "action"), (collection_ids, "collection")]:
        if len(values) != len(set(values)) or any(not identifier.fullmatch(value) for value in values):
            raise SystemExit(f"{path}: invalid or duplicate {label} identifier")
    if manifest["entryScreenID"] not in screen_ids:
        raise SystemExit(f"{path}: entry screen is missing")
    for screen in manifest["screens"]:
        for component in screen.get("components", []):
            if component.get("actionID") and component["actionID"] not in action_ids:
                raise SystemExit(f"{path}: missing action reference")
            if component.get("collection") and component["collection"] not in collection_ids:
                raise SystemExit(f"{path}: missing collection reference")
print(f"Validated {len(files)} built-in Pocket Apps")
