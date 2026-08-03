from pathlib import Path

path = Path("PocketKernel/Shell/RootTabView.swift")
source = path.read_text()

old_body = '''    var body: some View {
        Group {
            if let collection = editingCollection {
                recordForm(collection)
            } else {
                runtimeContent
            }
        }
        .task { await startRuntime() }
'''
new_body = '''    var body: some View {
        runtimeContent
            .task { await startRuntime() }
'''
if old_body in source:
    source = source.replace(old_body, new_body, 1)
elif new_body not in source:
    raise SystemExit("RuntimeView stable body insertion point not found")

old_content = '''    private var runtimeContent: some View {
        List {
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
        .navigationTitle(screen?.title ?? manifest.name)
        .toolbar {
            if !previewOnly {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { undoLast() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                        .disabled(!canUndo)
                    Button("Done") { environment.lifecycle.markRuntimeClosed(); dismiss() }
                }
            }
        }
    }
'''
new_content = '''    private var runtimeContent: some View {
        List {
            if let collection = editingCollection {
                Section("Add \\(collection.title)") {
                    ForEach(collection.fields) { field in fieldEditor(field) }
                }
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
            if !previewOnly {
                if let collection = editingCollection {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editingCollection = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveRecord(collection) }
                    }
                } else {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { undoLast() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                            .disabled(!canUndo)
                        Button("Done") { environment.lifecycle.markRuntimeClosed(); dismiss() }
                    }
                }
            }
        }
    }
'''
if old_content in source:
    source = source.replace(old_content, new_content, 1)
elif new_content not in source:
    raise SystemExit("RuntimeView content insertion point not found")

old_form = '''    private func recordForm(_ collection: CollectionSpec) -> some View {
        Form { ForEach(collection.fields) { field in fieldEditor(field) } }
            .navigationTitle("Add \\(collection.title)")
            .toolbar {
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
            }
    }

'''
new_form = '''    private func saveRecord(_ collection: CollectionSpec) {
        guard let action = manifest.actions.first(where: { $0.kind == .createRecord && $0.target == collection.id }) else { return }
        editingCollection = nil
        execute(action.id, form: formValues)
    }

'''
if old_form in source:
    source = source.replace(old_form, new_form, 1)
elif new_form not in source:
    raise SystemExit("recordForm replacement point not found")

path.write_text(source)
