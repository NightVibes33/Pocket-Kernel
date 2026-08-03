#!/usr/bin/env python3
import base64
import subprocess
from pathlib import Path

subprocess.run(["python3", "Scripts/patch_runtime_form_ci.py"], check=True)

root = Path("PocketKernel/Shell/RootTabView.swift")
source = root.read_text()

old_prompt = '@State private var prompt = "Create a car maintenance tracker with mileage, service date, cost, notes, and reminders for the next service."'
new_prompt = '''@State private var prompt = ProcessInfo.processInfo.arguments.contains("-PKUITesting")
    ? "Create a car maintenance tracker with mileage, service date, cost, notes, and reminders for the next service."
    : ""'''
if old_prompt not in source:
    raise SystemExit("Create prompt declaration was not found")
source = source.replace(old_prompt, new_prompt, 1)

old_suggestions = '''    private let suggestions = [
        "Habit tracker with daily check-ins",
        "Inventory manager with quantities and locations",
        "Private journal with dated entries",
        "Task board with status and due dates"
    ]'''
new_suggestions = '''    private let suggestions = [
        "Recipe organizer with ingredients, cook time, rating, and notes",
        "Client CRM with company, contact, status, next follow-up date, and deal value",
        "Workout log with exercise, sets, reps, weight, duration, and notes",
        "Reading tracker with title, author, status, rating, finish date, and review",
        "Trip planner with destination, dates, budget, bookings, and packing notes",
        "Home inventory with item, room, quantity, value, purchase date, and photo"
    ]'''
if old_suggestions not in source:
    raise SystemExit("Suggestion list was not found")
source = source.replace(old_suggestions, new_suggestions, 1)

old_editor = 'TextEditor(text: $prompt).frame(minHeight: 120).accessibilityLabel("App description")'
new_editor = '''ZStack(alignment: .topLeading) {
                TextEditor(text: $prompt)
                    .frame(minHeight: 150)
                    .accessibilityLabel("App description")
                if prompt.isEmpty {
                    Text("Describe any local app: its purpose, records, fields, screens, and optional device capabilities.")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }'''
if old_editor not in source:
    raise SystemExit("Prompt editor was not found")
source = source.replace(old_editor, new_editor, 1)

old_generate = 'else { Label("Generate on Device", systemImage: "apple.intelligence") }'
new_generate = '''else {
                    Label(
                        environment.modelState == .available ? "Generate on Device" : "Build Locally",
                        systemImage: environment.modelState == .available ? "apple.intelligence" : "hammer.fill"
                    )
                }'''
if old_generate not in source:
    raise SystemExit("Generate button label was not found")
source = source.replace(old_generate, new_generate, 1)

old_label = 'Text("AI-generated blueprint—review before installing.").font(.caption).foregroundStyle(.secondary)'
new_label = '''Text(
                environment.modelState == .available
                    ? "Generated privately on this device—review before installing."
                    : "Compiled locally from your prompt—review and edit before installing."
            )
            .font(.caption)
            .foregroundStyle(.secondary)'''
if old_label not in source:
    raise SystemExit("Generated blueprint label was not found")
root.write_text(source.replace(old_label, new_label, 1))

environment = Path("PocketKernel/App/AppEnvironment.swift")
environment_source = environment.read_text().replace(
    "private struct PromptBlueprintGenerator: BlueprintGenerating",
    "struct PromptBlueprintGenerator: BlueprintGenerating",
    1,
)
environment.write_text(environment_source)

tests = Path("PocketKernelTests/PocketKernelTests.swift")
test_source = tests.read_text()
marker = "final class PromptBlueprintGeneratorTests: XCTestCase"
if marker not in test_source:
    test_source += base64.b64decode("CgpmaW5hbCBjbGFzcyBQcm9tcHRCbHVlcHJpbnRHZW5lcmF0b3JUZXN0czogWENUZXN0Q2FzZSB7CiAgICBmdW5jIHRlc3RQcm9tcHRDb21waWxlclByb2R1Y2VzRGlmZmVyZW50VmFsaWRhdGVkQXBwcygpIGFzeW5jIHRocm93cyB7CiAgICAgICAgbGV0IGdlbmVyYXRvciA9IFByb21wdEJsdWVwcmludEdlbmVyYXRvcigpCiAgICAgICAgbGV0IGNvbnRleHQgPSBCdWlsZGVyQ29udGV4dChsb2NhbGVJZGVudGlmaWVyOiAiZW5fVVMiLCByZXF1ZXN0ZWRDYXBhYmlsaXRpZXM6IFsubG9jYWxOb3RpZmljYXRpb25zLCAuZmlsZUV4cG9ydF0pCiAgICAgICAgbGV0IHJlY2lwZSA9IHRyeSBhd2FpdCBnZW5lcmF0b3IuZ2VuZXJhdGVCbHVlcHJpbnQoCiAgICAgICAgICAgIGZyb206ICJDcmVhdGUgYSByZWNpcGUgb3JnYW5pemVyIHdpdGggcmVjaXBlIG5hbWUsIGluZ3JlZGllbnRzLCBjb29rIHRpbWUsIHJhdGluZywgYW5kIG5vdGVzIiwKICAgICAgICAgICAgY29udGV4dDogY29udGV4dAogICAgICAgICkKICAgICAgICBsZXQgY2xpZW50cyA9IHRyeSBhd2FpdCBnZW5lcmF0b3IuZ2VuZXJhdGVCbHVlcHJpbnQoCiAgICAgICAgICAgIGZyb206ICJDcmVhdGUgYSBjbGllbnQgQ1JNIHdpdGggY29tcGFueSwgY29udGFjdCBuYW1lLCBzdGF0dXMsIGRlYWwgdmFsdWUsIGFuZCBuZXh0IGZvbGxvdy11cCBkYXRlIiwKICAgICAgICAgICAgY29udGV4dDogY29udGV4dAogICAgICAgICkKICAgICAgICBsZXQgd29ya291dHMgPSB0cnkgYXdhaXQgZ2VuZXJhdG9yLmdlbmVyYXRlQmx1ZXByaW50KAogICAgICAgICAgICBmcm9tOiAiQ3JlYXRlIGEgd29ya291dCBsb2cgd2l0aCBleGVyY2lzZSwgc2V0cywgcmVwcywgd2VpZ2h0LCBkdXJhdGlvbiwgYW5kIG5vdGVzIiwKICAgICAgICAgICAgY29udGV4dDogY29udGV4dAogICAgICAgICkKCiAgICAgICAgWENUQXNzZXJ0RXF1YWwoU2V0KFtyZWNpcGUubmFtZSwgY2xpZW50cy5uYW1lLCB3b3Jrb3V0cy5uYW1lXSkuY291bnQsIDMpCiAgICAgICAgWENUQXNzZXJ0Tm90RXF1YWwocmVjaXBlLmNvbGxlY3Rpb25zLmZpcnN0Py5maWVsZHMubWFwKFwuaWQpLCBjbGllbnRzLmNvbGxlY3Rpb25zLmZpcnN0Py5maWVsZHMubWFwKFwuaWQpKQogICAgICAgIFhDVEFzc2VydE5vdEVxdWFsKGNsaWVudHMuY29sbGVjdGlvbnMuZmlyc3Q/LmZpZWxkcy5tYXAoXC5pZCksIHdvcmtvdXRzLmNvbGxlY3Rpb25zLmZpcnN0Py5maWVsZHMubWFwKFwuaWQpKQoKICAgICAgICBmb3IgYmx1ZXByaW50IGluIFtyZWNpcGUsIGNsaWVudHMsIHdvcmtvdXRzXSB7CiAgICAgICAgICAgIGxldCBtYW5pZmVzdCA9IEJsdWVwcmludENvbnZlcnRlcigpLmNvbnZlcnQoYmx1ZXByaW50LCBjYXBhYmlsaXRpZXM6IGNvbnRleHQucmVxdWVzdGVkQ2FwYWJpbGl0aWVzKQogICAgICAgICAgICBsZXQgZXJyb3JzID0gTWFuaWZlc3RWYWxpZGF0b3IoKS52YWxpZGF0ZShtYW5pZmVzdCkuZmlsdGVyIHsgJDAuc2V2ZXJpdHkgPT0gLmVycm9yIH0KICAgICAgICAgICAgWENUQXNzZXJ0VHJ1ZShlcnJvcnMuaXNFbXB0eSwgIlwoYmx1ZXByaW50Lm5hbWUpOiBcKGVycm9ycy5tYXAoXC5tZXNzYWdlKSkiKQogICAgICAgICAgICBYQ1RBc3NlcnRHcmVhdGVyVGhhbk9yRXF1YWwobWFuaWZlc3Quc2NyZWVucy5jb3VudCwgMikKICAgICAgICAgICAgWENUQXNzZXJ0RmFsc2UobWFuaWZlc3QuY29sbGVjdGlvbnMuZmxhdE1hcChcLmZpZWxkcykuaXNFbXB0eSkKICAgICAgICAgICAgWENUQXNzZXJ0VHJ1ZShtYW5pZmVzdC5hY3Rpb25zLmNvbnRhaW5zIHsgJDAua2luZCA9PSAuY3JlYXRlUmVjb3JkIH0pCiAgICAgICAgfQogICAgfQoKICAgIGZ1bmMgdGVzdFByb21wdENvbXBpbGVySW5mZXJzRmllbGRUeXBlc0FuZENhcGFiaWxpdGllcygpIGFzeW5jIHRocm93cyB7CiAgICAgICAgbGV0IGdlbmVyYXRvciA9IFByb21wdEJsdWVwcmludEdlbmVyYXRvcigpCiAgICAgICAgbGV0IGJsdWVwcmludCA9IHRyeSBhd2FpdCBnZW5lcmF0b3IuZ2VuZXJhdGVCbHVlcHJpbnQoCiAgICAgICAgICAgIGZyb206ICJCdWlsZCBhIHN1YnNjcmlwdGlvbiB0cmFja2VyIHdpdGggc2VydmljZSBuYW1lLCBtb250aGx5IGNvc3QsIHJlbmV3YWwgZGF0ZSwgYWN0aXZlIHN0YXR1cywgY2F0ZWdvcnksIGFuZCBub3RlczsgcmVtaW5kIG1lIGJlZm9yZSByZW5ld2FsIGFuZCBleHBvcnQgYmFja3VwcyIsCiAgICAgICAgICAgIGNvbnRleHQ6IC5pbml0KGxvY2FsZUlkZW50aWZpZXI6ICJlbl9VUyIsIHJlcXVlc3RlZENhcGFiaWxpdGllczogWy5sb2NhbE5vdGlmaWNhdGlvbnMsIC5maWxlRXhwb3J0XSkKICAgICAgICApCiAgICAgICAgbGV0IGZpZWxkcyA9IHRyeSBYQ1RVbndyYXAoYmx1ZXByaW50LmNvbGxlY3Rpb25zLmZpcnN0KS5maWVsZHMKICAgICAgICBYQ1RBc3NlcnRUcnVlKGZpZWxkcy5jb250YWlucyB7ICQwLmtpbmQgPT0gLm51bWJlciB9KQogICAgICAgIFhDVEFzc2VydFRydWUoZmllbGRzLmNvbnRhaW5zIHsgJDAua2luZCA9PSAuZGF0ZSB9KQogICAgICAgIFhDVEFzc2VydFRydWUoZmllbGRzLmNvbnRhaW5zIHsgJDAua2luZCA9PSAuYm9vbGVhbiB9KQogICAgICAgIFhDVEFzc2VydFRydWUoZmllbGRzLmNvbnRhaW5zIHsgJDAua2luZCA9PSAuY2hvaWNlIH0pCiAgICAgICAgWENUQXNzZXJ0VHJ1ZShmaWVsZHMuY29udGFpbnMgeyAkMC5raW5kID09IC5tdWx0aWxpbmVUZXh0IH0pCiAgICAgICAgWENUQXNzZXJ0VHJ1ZShibHVlcHJpbnQuYWN0aW9ucy5jb250YWlucyB7ICQwLmtpbmQgPT0gLnNjaGVkdWxlTG9jYWxOb3RpZmljYXRpb24gfSkKICAgICAgICBYQ1RBc3NlcnRUcnVlKGJsdWVwcmludC5hY3Rpb25zLmNvbnRhaW5zIHsgJDAua2luZCA9PSAuZXhwb3J0RmlsZSB9KQogICAgfQp9Cg==").decode()
tests.write_text(test_source)

workflow = Path(".github/workflows/build-unsigned.yml")
workflow_source = workflow.read_text()
patch_step = '''      - name: Apply direct runtime form architecture
        shell: bash
        run: |
          set -euo pipefail
          /usr/bin/python3 Scripts/patch_runtime_form_ci.py

'''
if patch_step not in workflow_source:
    raise SystemExit("Runtime patch workflow step was not found")
workflow.write_text(workflow_source.replace(patch_step, "", 1))

for temporary in [
    Path("Scripts/patch_runtime_form_ci.py"),
    Path("Scripts/apply_full_source_upgrade.py"),
    Path(".github/workflows/apply-full-source-upgrade.yml"),
    Path(".github/workflows/apply-full-source-upgrade-pr.yml"),
]:
    if temporary.exists():
        temporary.unlink()
