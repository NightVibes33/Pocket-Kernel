#!/usr/bin/env python3
from pathlib import Path

path = Path("PocketKernel/Shell/RootTabView.swift")
source = path.read_text()
runtime_start = source.index("struct RuntimeView: View {")
body_start = source.index("    var body: some View {", runtime_start)
body_end = source.index("    @ViewBuilder private var permissionButtons", body_start)

new_body = '''    var body: some View {
        List {
            if let collection = editingCollection {
                ForEach(collection.fields) { field in fieldEditor(field) }
            } else {
                if manifest.screens.count > 1 {
                    Picker("Screen", selection: $selectedScreenID) { ForEach(manifest.screens) { Text($0.title).tag($0.id) } }.pickerStyle(.segmented)
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
        .navigationTitle(editingCollection.map { "Add \\($0.title)" } ?? (screen?.title ?? manifest.name))
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

if ".overlay {" in source[runtime_start:]:
    raise SystemExit("Runtime overlay remained after patch")
if ".fullScreenCover(item: $editingCollection)" in source[runtime_start:]:
    raise SystemExit("Nested record-form cover remained after patch")
if "private func recordForm(" in source[runtime_start:]:
    raise SystemExit("Nested recordForm helper remained after patch")

path.write_text(source)
