#!/usr/bin/env python3
"""Compatibility shim for historical PocketKernel automation build attempts.

The automation migration has already been committed to the branch. Older workflow
attempts call this path before validation, so verify the migrated source rather
than rewriting it.
"""

from pathlib import Path

REQUIRED_PATHS = (
    Path("PocketKernel/Runtime/AutomationCore.swift"),
    Path("PocketKernel/Intelligence/FoundationAutomationGenerator.swift"),
    Path("PocketKernel/Shell/RootTabView.swift"),
    Path("PocketKernelUITests/PocketKernelUITests.swift"),
)

missing = [str(path) for path in REQUIRED_PATHS if not path.is_file()]
if missing:
    raise SystemExit("Missing persisted automation source: " + ", ".join(missing))

project = Path("PocketKernel.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
if "FoundationAutomationGenerator.swift in Sources" not in project:
    raise SystemExit("Foundation automation generator is not in the app target")

print("Automation product source is already integrated; no migration required.")
