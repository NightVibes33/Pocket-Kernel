#!/usr/bin/env python3
"""Compatibility shim for historical PocketKernel refinement build attempts."""

from pathlib import Path

shell = Path("PocketKernel/Shell/RootTabView.swift").read_text(encoding="utf-8")
tests = Path("PocketKernelUITests/PocketKernelUITests.swift").read_text(encoding="utf-8")

checks = {
    "five-tab automation shell": all(label in shell for label in ("Today", "Create", "Automations", "Activity", "Connections")),
    "typed workflow UI test": "testBuildReviewSaveAndPersistTypedWorkflow" in tests,
    "resilient direct tap": "XCTAssertTrue(element.isHittable" not in tests,
}

failed = [name for name, passed in checks.items() if not passed]
if failed:
    raise SystemExit("Persisted automation refinements are incomplete: " + ", ".join(failed))

print("Automation refinements are already persisted; no rewrite required.")
