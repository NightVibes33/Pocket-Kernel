#!/usr/bin/env python3
import base64
import hashlib
import json
import pathlib
import sys

KNOWN_COMPONENTS = set("text markdown heading caption metric progress image symbol divider spacer badge textField secureField multilineText numberField toggle slider stepper datePicker picker segmentedPicker list grid recordForm detail searchResults chart emptyState button menu shareButton fileImportButton fileExportButton photoPickerButton confirmationButton section verticalStack horizontalStack lazyGrid card group scrollContainer".split())
KNOWN_ACTIONS = set("setValue clearValue createRecord updateRecord deleteRecord sortRecords filterRecords navigate dismiss showAlert showConfirmation showSheet selectRecord copyToClipboard share importFile exportFile selectPhotos scheduleLocalNotification openURL generateText summarizeText extractFields classifyText rewriteText httpGet httpPostJSON".split())
KNOWN_CAPABILITIES = set("clipboardRead clipboardWrite fileImport fileExport photoSelection camera localNotifications network onDeviceModel".split())


def fail(path, message):
    raise ValueError(f"{path}: {message}")


def walk_components(items, depth=1):
    for item in items:
        yield item, depth
        yield from walk_components(item.get("children", []), depth + 1)


def validate(path):
    raw = path.read_bytes()
    if len(raw) > 25 * 1024 * 1024:
        fail(path, "package exceeds 25 MB")
    package = json.loads(raw)
    if package.get("formatVersion") != 1 or package.get("integrity", {}).get("algorithm") != "sha256":
        fail(path, "unsupported package format")
    manifest = package.get("manifest")
    canonical = json.dumps(manifest, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    if hashlib.sha256(canonical).hexdigest() != package["integrity"].get("manifestHash"):
        fail(path, "manifest hash mismatch")
    screens = manifest.get("screens", [])
    actions = manifest.get("actions", [])
    collections = manifest.get("collections", [])
    capabilities = set(manifest.get("capabilities", []))
    if not 1 <= len(screens) <= 20 or len(actions) > 50 or len(collections) > 20:
        fail(path, "manifest count limit exceeded")
    if not capabilities <= KNOWN_CAPABILITIES:
        fail(path, "unknown capability")
    screen_ids = [item.get("id") for item in screens]
    action_ids = [item.get("id") for item in actions]
    collection_ids = [item.get("id") for item in collections]
    for label, values in (("screen", screen_ids), ("action", action_ids), ("collection", collection_ids)):
        if len(values) != len(set(values)) or any(not value or ".." in value or "/" in value or "\\" in value for value in values):
            fail(path, f"invalid {label} identifiers")
    if manifest.get("entryScreenID") not in screen_ids:
        fail(path, "entry screen missing")
    components = list(walk_components([component for screen in screens for component in screen.get("components", [])]))
    if len(components) > 100 or any(depth > 8 for _, depth in components):
        fail(path, "component count or depth exceeded")
    component_ids = [item.get("id") for item, _ in components]
    if len(component_ids) != len(set(component_ids)) or any(item.get("kind") not in KNOWN_COMPONENTS for item, _ in components):
        fail(path, "duplicate component id or unknown component")
    for item, _ in components:
        if item.get("actionID") and item["actionID"] not in action_ids:
            fail(path, "missing action reference")
        if item.get("collection") and item["collection"] not in collection_ids:
            fail(path, "missing collection reference")
    if any(action.get("kind") not in KNOWN_ACTIONS for action in actions):
        fail(path, "unknown action")
    decoded = 0
    asset_ids = set()
    for asset in package.get("assets", []):
        if asset.get("id") in asset_ids or ".." in asset.get("id", "") or "/" in asset.get("id", ""):
            fail(path, "invalid asset id")
        asset_ids.add(asset["id"])
        try:
            data = base64.b64decode(asset["base64Data"], validate=True)
        except Exception as error:
            fail(path, f"malformed asset Base64: {error}")
        decoded += len(data)
        if decoded > 25 * 1024 * 1024 or hashlib.sha256(data).hexdigest() != asset.get("sha256"):
            fail(path, "asset hash or size invalid")


def main():
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "PocketKernel/Templates")
    paths = sorted(root.rglob("*.pocketapp"))
    if len(paths) != 5:
        fail(root, f"expected exactly five built-in templates, found {len(paths)}")
    for path in paths:
        validate(path)
        print(f"validated {path}")


if __name__ == "__main__":
    main()
