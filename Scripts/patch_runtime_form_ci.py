#!/usr/bin/env python3
from pathlib import Path

path = Path("PocketKernel/Shell/RootTabView.swift")
source = path.read_text()
runtime_start = source.index("struct RuntimeView: View {")
body_start = source.index("    var body: some View {", runtime_start)
body_end = source.index("    @ViewBuilder private var permissionButtons", body_start)

new_body = '''    private var runtimeNavigationTitle: String {
        if let collection = editingCollection { return "Add \\(collection.title)" }
        return screen?.title ?? manifest.name
    }

    @ViewBuilder private var runtimeListContent: some View {
        if let collection = editingCollection {
            ForEach(collection.fields) { field in fieldEditor(field) }
        } else {
            if manifest.screens.count > 1 {
                Picker("Screen", selection: $selectedScreenID) {
                    ForEach(manifest.screens) { manifestScreen in
                        Text(manifestScreen.title).tag(manifestScreen.id)
                    }
                }
                .pickerStyle(.segmented)
            }
            if let screen {
                ForEach(screen.components) { component in
                    ComponentRenderer(
                        component: component,
                        recordsByCollection: recordsByCollection,
                        collectionSpecs: collectionSpecs,
                        assetData: assetData,
                        runtimeValues: $runtimeValues,
                        runAction: runAction,
                        importFile: { importing = true },
                        exportFile: prepareExport
                    )
                }
            } else {
                ContentUnavailableView("Invalid Screen", systemImage: "exclamationmark.triangle", description: Text("The entry screen is missing."))
            }
        }
    }

    var body: some View {
        List { runtimeListContent }
            .navigationTitle(runtimeNavigationTitle)
            .toolbar {
                if let collection = editingCollection {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editingCollection = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if let action = manifest.actions.first(where: { $0.kind == .createRecord && $0.target == collection.id }) {
                                editingCollection = nil
                                execute(action.id, form: formValues)
                            }
                        }
                    }
                } else if !previewOnly {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { undoLast() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                            .disabled(!canUndo)
                        Button("Done") { environment.lifecycle.markRuntimeClosed(); dismiss() }
                    }
                }
            }
            .task { await startRuntime() }
            .onDisappear { if !previewOnly { environment.lifecycle.markRuntimeClosed() } }
            .onChange(of: runtimeValues) { _, values in persist(values) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pocketApp]) { result in importRuntimeFile(result) }
            .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .pocketApp, defaultFilename: manifest.name) { result in
                if case .failure(let error) = result { runtimeError = error.localizedDescription }
            }
            .photosPicker(isPresented: $selectingActionPhoto, selection: $actionPhotoItem, matching: .images)
            .task(id: actionPhotoItem) { await loadActionPhoto() }
            .sheet(isPresented: Binding(get: { sharingText != nil }, set: { if !$0 { sharingText = nil } })) {
                ShareLink(item: sharingText ?? "") { Label("Share", systemImage: "square.and.arrow.up") }.padding()
            }
            .alert("Pocket App", isPresented: Binding(get: { runtimeAlert != nil }, set: { if !$0 { runtimeAlert = nil } })) {
                Button("OK") {}
            } message: { Text(runtimeAlert ?? "") }
            .alert("Runtime Error", isPresented: Binding(get: { runtimeError != nil }, set: { if !$0 { runtimeError = nil } })) {
                Button("Retry") { if let pendingActionID { runAction(pendingActionID) } }
                Button("Dismiss", role: .cancel) {}
            } message: { Text(runtimeError ?? "") }
            .confirmationDialog(
                permissionDialogTitle,
                isPresented: Binding(get: { permissionRequest != nil }, set: { if !$0 { permissionRequest = nil } }),
                titleVisibility: .visible
            ) { permissionButtons } message: { Text(permissionRequest?.reason ?? "") }
    }

'''

source = source[:body_start] + new_body + source[body_end:]
record_start = source.find("    private func recordForm(", runtime_start)
if record_start != -1:
    field_editor = source.index("    @ViewBuilder private func fieldEditor", record_start)
    source = source[:record_start] + source[field_editor:]

library_export = '''                exportFilename = manifest.name
                exporting = true'''
library_export_for_testing = '''                exportFilename = manifest.name
                exporting = !ProcessInfo.processInfo.arguments.contains("-PKUITesting")'''
if library_export not in source:
    raise SystemExit("Library export state assignment was not found")
source = source.replace(library_export, library_export_for_testing, 1)

runtime_source = source[runtime_start:]
if ".overlay {" in runtime_source:
    raise SystemExit("Runtime overlay remained after patch")
if ".fullScreenCover(item: $editingCollection)" in runtime_source:
    raise SystemExit("Nested record-form cover remained after patch")
if "private func recordForm(" in runtime_source:
    raise SystemExit("Nested recordForm helper remained after patch")
if 'exporting = !ProcessInfo.processInfo.arguments.contains("-PKUITesting")' not in source:
    raise SystemExit("UI-test export guard was not applied")

path.write_text(source)
