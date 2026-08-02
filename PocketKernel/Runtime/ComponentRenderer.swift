import Charts
import SwiftUI
import UIKit

struct ComponentRenderer: View {
    let component: ComponentSpec
    let recordsByCollection: [String: [PocketRecord]]
    let collectionSpecs: [String: CollectionSpec]
    let assetData: [String: Data]
    @Binding var runtimeValues: [String: PocketValue]
    var runAction: (String) -> Void
    var importFile: () -> Void
    var exportFile: () -> Void

    var body: some View {
        if isVisible {
            rendered
                .disabled(isDisabled)
                .accessibilityIdentifier("component-\(component.id)")
        }
    }

    @ViewBuilder private var rendered: some View {
        switch component.kind {
        case .text: Text(resolved(component.text ?? component.title ?? ""))
        case .markdown: Text(.init(resolved(component.text ?? component.title ?? "")))
        case .heading: Text(resolved(component.text ?? component.title ?? "")).font(.title2.bold())
        case .caption: Text(resolved(component.text ?? component.title ?? "")).font(.caption).foregroundStyle(.secondary)
        case .metric:
            VStack(alignment: .leading, spacing: 4) {
                Text(component.title ?? "Metric").font(.caption).foregroundStyle(.secondary)
                Text(resolved(component.text ?? bindingValue.displayString)).font(.title.bold()).monospacedDigit()
            }
        case .progress:
            ProgressView(value: numericValue, total: max(component.maximum ?? 1, 0.0001)) {
                Text(component.title ?? "Progress")
            }
        case .image: imageView
        case .symbol:
            Image(systemName: component.text ?? "square.grid.2x2.fill")
                .font(.title)
                .accessibilityLabel(component.title ?? "Symbol")
        case .divider: Divider()
        case .spacer: Spacer(minLength: CGFloat(component.minimum ?? 8))
        case .badge:
            Text(resolved(component.text ?? component.title ?? "Badge"))
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.tint.opacity(0.15), in: Capsule())

        case .textField:
            TextField(component.title ?? "Text", text: stringBinding).textInputAutocapitalization(.sentences)
        case .secureField:
            SecureField(component.title ?? "Secure value", text: stringBinding)
        case .multilineText:
            TextField(component.title ?? "Notes", text: stringBinding, axis: .vertical).lineLimit(3...8)
        case .numberField:
            TextField(component.title ?? "Number", value: numberBinding, format: .number).keyboardType(.decimalPad)
        case .toggle:
            Toggle(component.title ?? "Enabled", isOn: boolBinding)
        case .slider:
            VStack(alignment: .leading) {
                Text(component.title ?? "Value")
                Slider(value: numberBinding, in: (component.minimum ?? 0)...max(component.maximum ?? 100, component.minimum ?? 0))
            }
        case .stepper:
            Stepper(value: numberBinding, in: (component.minimum ?? 0)...max(component.maximum ?? 100, component.minimum ?? 0), step: 1) {
                LabeledContent(component.title ?? "Value", value: numericValue.formatted())
            }
        case .datePicker:
            DatePicker(component.title ?? "Date", selection: dateBinding)
        case .picker:
            Picker(component.title ?? "Choose", selection: stringBinding) {
                ForEach(component.options, id: \.self) { Text($0).tag($0) }
            }
        case .segmentedPicker:
            Picker(component.title ?? "Choose", selection: stringBinding) {
                ForEach(component.options, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented)

        case .list:
            recordCollectionView(records: componentRecords)
        case .searchResults:
            VStack(alignment: .leading, spacing: 10) {
                TextField(component.title ?? "Search", text: stringBinding).textFieldStyle(.roundedBorder)
                recordCollectionView(records: searchedRecords)
            }
        case .grid:
            if componentRecords.isEmpty { emptyRecords }
            else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(componentRecords) { recordCard($0) }
                }
            }
        case .recordForm:
            recordForm
        case .detail:
            VStack(alignment: .leading, spacing: 8) { ForEach(componentRecords.prefix(1)) { recordRow($0) } }
        case .chart:
            chartView
        case .emptyState:
            ContentUnavailableView(
                component.title ?? "Nothing Here",
                systemImage: component.text ?? "tray",
                description: Text("This app has no content yet.")
            )

        case .button:
            Button(component.title ?? "Continue") { runComponentAction() }.buttonStyle(.borderedProminent)
        case .menu:
            Menu(component.title ?? "Actions") {
                ForEach(component.children) { child in
                    if let actionID = child.actionID { Button(child.title ?? "Action") { runAction(actionID) } }
                }
            }
        case .shareButton:
            if let actionID = component.actionID {
                Button(component.title ?? "Share", systemImage: "square.and.arrow.up") { runAction(actionID) }
            } else if let value = shareValue {
                ShareLink(item: value) { Label(component.title ?? "Share", systemImage: "square.and.arrow.up") }
            }
        case .fileImportButton:
            if component.actionID != nil { Button(component.title ?? "Import") { runComponentAction() } }
            else { Button(component.title ?? "Import", action: importFile) }
        case .fileExportButton:
            if component.actionID != nil { Button(component.title ?? "Export") { runComponentAction() } }
            else { Button(component.title ?? "Export", action: exportFile) }
        case .photoPickerButton:
            Button(component.title ?? "Choose Photo", systemImage: "photo.on.rectangle") { runComponentAction() }
                .disabled(component.actionID == nil)
        case .confirmationButton:
            Button(component.title ?? "Confirm", role: .destructive) { runComponentAction() }

        case .screen, .scrollContainer:
            ScrollView { LazyVStack(alignment: .leading, spacing: 12) { ForEach(component.children) { childRenderer($0) } } }
        case .section:
            Section(component.title ?? "") { ForEach(component.children) { childRenderer($0) } }
        case .verticalStack, .group:
            VStack(alignment: .leading, spacing: 12) { ForEach(component.children) { childRenderer($0) } }
        case .horizontalStack:
            HStack(alignment: .center, spacing: 12) { ForEach(component.children) { childRenderer($0) } }
        case .lazyGrid:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))]) { ForEach(component.children) { childRenderer($0) } }
        case .card:
            VStack(alignment: .leading, spacing: 10) { ForEach(component.children) { childRenderer($0) } }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    @ViewBuilder private var recordForm: some View {
        if let collectionID = component.collection, let collection = collectionSpecs[collectionID] {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(collection.fields) { field in fieldEditor(field) }
                ForEach(component.children) { childRenderer($0) }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) { ForEach(component.children) { childRenderer($0) } }
        }
    }

    @ViewBuilder private func fieldEditor(_ field: FieldSpec) -> some View {
        let fieldKey = "form.\(field.id)"
        switch field.kind {
        case .text:
            TextField(field.title, text: stringBinding(for: fieldKey))
        case .multilineText:
            TextField(field.title, text: stringBinding(for: fieldKey), axis: .vertical).lineLimit(3...8)
        case .number:
            TextField(field.title, value: numberBinding(for: fieldKey), format: .number).keyboardType(.decimalPad)
        case .boolean:
            Toggle(field.title, isOn: boolBinding(for: fieldKey))
        case .date:
            DatePicker(field.title, selection: dateBinding(for: fieldKey))
        case .choice:
            Picker(field.title, selection: stringBinding(for: fieldKey)) {
                ForEach(field.options, id: \.self) { Text($0).tag($0) }
            }
        case .image:
            LabeledContent(field.title, value: runtimeValues[fieldKey] == nil ? "No image selected" : "Image selected")
        }
    }

    @ViewBuilder private var imageView: some View {
        let stateValue = component.assetID.flatMap { runtimeValues["asset.\($0)"] } ?? runtimeValues[key]
        let storedData = component.assetID.flatMap { assetData[$0] }
        let encodedData = string(stateValue).flatMap { Data(base64Encoded: $0) }
        if let data = storedData ?? encodedData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(component.title ?? "Image")
        } else {
            Label(component.title ?? "Image unavailable", systemImage: "photo").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var chartView: some View {
        let points = chartPoints
        if points.isEmpty {
            ContentUnavailableView(
                component.title ?? "No Chart Data",
                systemImage: "chart.bar",
                description: Text("Add numeric records to display a chart.")
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(component.title ?? "Chart").font(.headline)
                Chart(points) { point in
                    switch component.chartStyle ?? .bar {
                    case .bar:
                        BarMark(x: .value("Record", point.label), y: .value("Value", point.value))
                    case .line:
                        LineMark(x: .value("Record", point.label), y: .value("Value", point.value))
                        PointMark(x: .value("Record", point.label), y: .value("Value", point.value))
                    case .area:
                        AreaMark(x: .value("Record", point.label), y: .value("Value", point.value))
                        LineMark(x: .value("Record", point.label), y: .value("Value", point.value))
                    }
                }
                .frame(minHeight: 180)
                .accessibilityLabel("\(component.title ?? "Chart") with \(points.count) values")
            }
        }
    }

    private struct ChartPoint: Identifiable { var id: UUID; var label: String; var value: Double }

    private var chartPoints: [ChartPoint] {
        let field = component.valueField
        return componentRecords.enumerated().compactMap { index, record in
            let candidate = field.flatMap { record.values[$0] }
                ?? record.values.values.first { if case .number = $0 { true } else { false } }
            guard case .number(let value) = candidate else { return nil }
            let label = component.labelField.flatMap { record.values[$0]?.displayString } ?? "\(index + 1)"
            return .init(id: record.id, label: label, value: value)
        }
    }

    private var isVisible: Bool {
        guard let expression = component.visibilityExpression else { return true }
        return (try? ExpressionEvaluator().evaluate(expression, context: expressionContext)) == .bool(true)
    }

    private var isDisabled: Bool {
        guard let expression = component.disabledExpression else { return false }
        return (try? ExpressionEvaluator().evaluate(expression, context: expressionContext)) == .bool(true)
    }

    private var expressionContext: [String: PocketValue] {
        var collections: [String: PocketValue] = [:]
        for (id, records) in recordsByCollection { collections[id] = .array(records.map { .object($0.values) }) }
        return [
            "state": .object(runtimeValues),
            "collections": .object(collections),
            "environment": .object(["currentDate": .date(Date())])
        ]
    }

    private func expressionContext(record: PocketRecord) -> [String: PocketValue] {
        var context = expressionContext
        context["record"] = .object(record.values)
        return context
    }

    private var key: String { component.binding?.replacingOccurrences(of: "state.", with: "") ?? component.id }
    private var bindingValue: PocketValue { runtimeValues[key] ?? .null }
    private var bindingText: String { string(bindingValue) ?? "" }
    private var numericValue: Double { if case .number(let value) = bindingValue { value } else { 0 } }
    private var shareValue: String? { let value = resolved(component.text ?? bindingText); return value.isEmpty ? nil : value }
    private var rawRecords: [PocketRecord] { component.collection.flatMap { recordsByCollection[$0] } ?? [] }

    private var componentRecords: [PocketRecord] {
        var records = rawRecords
        if let expression = component.filterExpression {
            records = records.filter { (try? ExpressionEvaluator().evaluate(expression, context: expressionContext(record: $0))) == .bool(true) }
        }
        if let field = component.sortField {
            records.sort {
                let comparison = compare($0.values[field] ?? .null, $1.values[field] ?? .null)
                return component.sortAscending == false ? comparison > 0 : comparison < 0
            }
        }
        return records
    }

    private var searchedRecords: [PocketRecord] {
        guard !bindingText.isEmpty else { return componentRecords }
        return componentRecords.filter { record in
            record.values.values.contains { $0.displayString.localizedCaseInsensitiveContains(bindingText) }
        }
    }

    private var stringBinding: Binding<String> { stringBinding(for: key) }
    private var numberBinding: Binding<Double> { numberBinding(for: key) }
    private var boolBinding: Binding<Bool> { boolBinding(for: key) }
    private var dateBinding: Binding<Date> { dateBinding(for: key) }

    private func stringBinding(for key: String) -> Binding<String> {
        Binding(get: { string(runtimeValues[key]) ?? "" }, set: { runtimeValues[key] = .string($0) })
    }

    private func numberBinding(for key: String) -> Binding<Double> {
        Binding(get: { if case .number(let value) = runtimeValues[key] { value } else { 0 } }, set: { runtimeValues[key] = .number($0) })
    }

    private func boolBinding(for key: String) -> Binding<Bool> {
        Binding(get: { if case .bool(let value) = runtimeValues[key] { value } else { false } }, set: { runtimeValues[key] = .bool($0) })
    }

    private func dateBinding(for key: String) -> Binding<Date> {
        Binding(get: { if case .date(let value) = runtimeValues[key] { value } else { Date() } }, set: { runtimeValues[key] = .date($0) })
    }

    private var emptyRecords: some View {
        ContentUnavailableView(
            component.title ?? "No Records",
            systemImage: "list.bullet.rectangle",
            description: Text("Add your first record.")
        )
    }

    @ViewBuilder private func recordCollectionView(records: [PocketRecord]) -> some View {
        if records.isEmpty { emptyRecords }
        else { ForEach(records) { recordRow($0) } }
    }

    private func resolved(_ source: String) -> String {
        var output = source
        let pattern = #"\{\{\s*([^}]+)\s*\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).reversed()
        where match.numberOfRanges == 2 {
            guard let full = Range(match.range(at: 0), in: source),
                  let expression = Range(match.range(at: 1), in: source)
            else { continue }
            let value = try? ExpressionEvaluator().evaluate(
                String(source[expression]).trimmingCharacters(in: .whitespaces),
                context: expressionContext
            )
            output.replaceSubrange(full, with: (value ?? .null).displayString)
        }
        return output
    }

    private func childRenderer(_ child: ComponentSpec) -> some View {
        ComponentRenderer(
            component: child,
            recordsByCollection: recordsByCollection,
            collectionSpecs: collectionSpecs,
            assetData: assetData,
            runtimeValues: $runtimeValues,
            runAction: runAction,
            importFile: importFile,
            exportFile: exportFile
        )
    }

    private func recordCard(_ record: PocketRecord) -> some View {
        recordRow(record)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func recordRow(_ record: PocketRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(record.values.sorted(by: { $0.key < $1.key }), id: \.key) { pair in
                LabeledContent(pair.key.capitalized, value: pair.value.displayString)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("record-field-\(pair.key)")
                    .accessibilityLabel("\(pair.key.capitalized), \(pair.value.displayString)")
            }
        }
    }

    private func runComponentAction() {
        if let id = component.actionID { runAction(id) }
    }

    private func string(_ value: PocketValue?) -> String? {
        guard case .string(let string) = value else { return nil }
        return string
    }

    private func compare(_ lhs: PocketValue, _ rhs: PocketValue) -> Int {
        switch (lhs, rhs) {
        case (.number(let left), .number(let right)):
            return left == right ? 0 : left < right ? -1 : 1
        case (.date(let left), .date(let right)):
            return left == right ? 0 : left < right ? -1 : 1
        default:
            let left = lhs.displayString.localizedLowercase
            let right = rhs.displayString.localizedLowercase
            return left == right ? 0 : left < right ? -1 : 1
        }
    }
}
