import Charts
import PhotosUI
import SwiftUI
import UIKit

struct ComponentRenderer: View {
    let component: ComponentSpec
    let recordsByCollection: [String: [PocketRecord]]
    @Binding var runtimeValues: [String: PocketValue]
    var runAction: (String) -> Void
    var importFile: () -> Void
    var exportFile: () -> Void
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoError: String?

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
            ProgressView(value: numericValue, total: max(component.maximum ?? 1, 0.0001)) { Text(component.title ?? "Progress") }
        case .image:
            imageView
        case .symbol:
            Image(systemName: component.text ?? "square.grid.2x2.fill").font(.title).accessibilityLabel(component.title ?? "Symbol")
        case .divider: Divider()
        case .spacer: Spacer(minLength: CGFloat(component.minimum ?? 8))
        case .badge:
            Text(resolved(component.text ?? component.title ?? "Badge")).font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 4).background(.tint.opacity(0.15), in: Capsule())

        case .textField: TextField(component.title ?? "Text", text: stringBinding).textInputAutocapitalization(.sentences)
        case .secureField: SecureField(component.title ?? "Secure value", text: stringBinding)
        case .multilineText: TextField(component.title ?? "Notes", text: stringBinding, axis: .vertical).lineLimit(3...8)
        case .numberField: TextField(component.title ?? "Number", value: numberBinding, format: .number).keyboardType(.decimalPad)
        case .toggle: Toggle(component.title ?? "Enabled", isOn: boolBinding)
        case .slider:
            VStack(alignment: .leading) { Text(component.title ?? "Value"); Slider(value: numberBinding, in: (component.minimum ?? 0)...max(component.maximum ?? 100, component.minimum ?? 0)) }
        case .stepper:
            Stepper(value: numberBinding, in: (component.minimum ?? 0)...max(component.maximum ?? 100, component.minimum ?? 0), step: 1) { LabeledContent(component.title ?? "Value", value: numericValue.formatted()) }
        case .datePicker: DatePicker(component.title ?? "Date", selection: dateBinding)
        case .picker:
            Picker(component.title ?? "Choose", selection: stringBinding) { ForEach(component.options, id: \.self) { Text($0).tag($0) } }
        case .segmentedPicker:
            Picker(component.title ?? "Choose", selection: stringBinding) { ForEach(component.options, id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)

        case .list:
            recordCollectionView(records: componentRecords)
        case .searchResults:
            VStack(alignment: .leading, spacing: 10) {
                TextField(component.title ?? "Search", text: stringBinding).textFieldStyle(.roundedBorder)
                recordCollectionView(records: filteredRecords)
            }
        case .grid:
            if componentRecords.isEmpty { emptyRecords }
            else { LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) { ForEach(componentRecords) { recordCard($0) } } }
        case .recordForm:
            VStack(alignment: .leading, spacing: 12) { ForEach(component.children) { childRenderer($0) } }
        case .detail:
            VStack(alignment: .leading, spacing: 8) { ForEach(componentRecords.prefix(1)) { recordRow($0) } }
        case .chart:
            chartView
        case .emptyState:
            ContentUnavailableView(component.title ?? "Nothing Here", systemImage: component.text ?? "tray", description: Text("This app has no content yet."))

        case .button:
            Button(component.title ?? "Continue") { if let id = component.actionID { runAction(id) } }.buttonStyle(.borderedProminent)
        case .menu:
            Menu(component.title ?? "Actions") { ForEach(component.children) { child in if let actionID = child.actionID { Button(child.title ?? "Action") { runAction(actionID) } } } }
        case .shareButton:
            if let value = shareValue { ShareLink(item: value) { Label(component.title ?? "Share", systemImage: "square.and.arrow.up") } }
        case .fileImportButton: Button(component.title ?? "Import") { importFile() }
        case .fileExportButton: Button(component.title ?? "Export") { exportFile() }
        case .photoPickerButton:
            VStack(alignment: .leading) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) { Label(component.title ?? "Choose Photo", systemImage: "photo.on.rectangle") }
                if let photoError { Text(photoError).font(.caption).foregroundStyle(.red) }
            }
            .task(id: selectedPhoto) { await loadSelectedPhoto() }
        case .confirmationButton:
            Button(component.title ?? "Confirm", role: .destructive) { if let id = component.actionID { runAction(id) } }

        case .section:
            Section(component.title ?? "") { ForEach(component.children) { childRenderer($0) } }
        case .verticalStack, .group:
            VStack(alignment: .leading, spacing: 12) { ForEach(component.children) { childRenderer($0) } }
        case .horizontalStack:
            HStack(alignment: .center, spacing: 12) { ForEach(component.children) { childRenderer($0) } }
        case .lazyGrid:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))]) { ForEach(component.children) { childRenderer($0) } }
        case .card:
            VStack(alignment: .leading, spacing: 10) { ForEach(component.children) { childRenderer($0) } }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        case .scrollContainer:
            ScrollView { LazyVStack(alignment: .leading, spacing: 12) { ForEach(component.children) { childRenderer($0) } } }
        }
    }

    @ViewBuilder private var imageView: some View {
        let source = component.assetID.flatMap { runtimeValues["asset.\($0)"] } ?? runtimeValues[key]
        let encoded = string(source) ?? component.text
        if let encoded, let data = Data(base64Encoded: encoded), let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityLabel(component.title ?? "Image")
        } else {
            Label(component.title ?? "Image unavailable", systemImage: "photo").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var chartView: some View {
        let points = chartPoints
        if points.isEmpty {
            ContentUnavailableView(component.title ?? "No Chart Data", systemImage: "chart.bar", description: Text("Add numeric records to display a chart."))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(component.title ?? "Chart").font(.headline)
                Chart(points) { point in
                    BarMark(x: .value("Record", point.label), y: .value("Value", point.value))
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
            let candidate: PocketValue? = field.flatMap { record.values[$0] } ?? record.values.values.first { if case .number = $0 { true } else { false } }
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
        return ["state": .object(runtimeValues), "collections": .object(collections), "environment": .object(["currentDate": .date(Date())])]
    }

    private var key: String { component.binding?.replacingOccurrences(of: "state.", with: "") ?? component.id }
    private var bindingValue: PocketValue { runtimeValues[key] ?? .null }
    private var bindingText: String { string(bindingValue) ?? "" }
    private var numericValue: Double { if case .number(let value) = bindingValue { value } else { 0 } }
    private var shareValue: String? { let value = resolved(component.text ?? bindingText); return value.isEmpty ? nil : value }
    private var componentRecords: [PocketRecord] { component.collection.flatMap { recordsByCollection[$0] } ?? [] }
    private var filteredRecords: [PocketRecord] {
        guard !bindingText.isEmpty else { return componentRecords }
        return componentRecords.filter { record in record.values.values.contains { $0.displayString.localizedCaseInsensitiveContains(bindingText) } }
    }
    private var stringBinding: Binding<String> { Binding(get: { bindingText }, set: { runtimeValues[key] = .string($0) }) }
    private var numberBinding: Binding<Double> { Binding(get: { numericValue }, set: { runtimeValues[key] = .number($0) }) }
    private var boolBinding: Binding<Bool> { Binding(get: { if case .bool(let value) = bindingValue { value } else { false } }, set: { runtimeValues[key] = .bool($0) }) }
    private var dateBinding: Binding<Date> { Binding(get: { if case .date(let value) = bindingValue { value } else { Date() } }, set: { runtimeValues[key] = .date($0) }) }

    private var emptyRecords: some View {
        ContentUnavailableView(component.title ?? "No Records", systemImage: "list.bullet.rectangle", description: Text("Add your first record."))
    }

    @ViewBuilder private func recordCollectionView(records: [PocketRecord]) -> some View {
        if records.isEmpty { emptyRecords }
        else { ForEach(records) { recordRow($0) } }
    }

    private func resolved(_ source: String) -> String {
        var output = source
        let pattern = #"\{\{\s*([^}]+)\s*\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).reversed() where match.numberOfRanges == 2 {
            guard let full = Range(match.range(at: 0), in: source), let expression = Range(match.range(at: 1), in: source) else { continue }
            let value = try? ExpressionEvaluator().evaluate(String(source[expression]).trimmingCharacters(in: .whitespaces), context: expressionContext)
            output.replaceSubrange(full, with: (value ?? .null).displayString)
        }
        return output
    }

    private func childRenderer(_ child: ComponentSpec) -> some View {
        ComponentRenderer(component: child, recordsByCollection: recordsByCollection, runtimeValues: $runtimeValues, runAction: runAction, importFile: importFile, exportFile: exportFile)
    }

    private func recordCard(_ record: PocketRecord) -> some View {
        recordRow(record).padding().frame(maxWidth: .infinity, alignment: .leading).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
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

    private func loadSelectedPhoto() async {
        guard let selectedPhoto else { return }
        do {
            guard let data = try await selectedPhoto.loadTransferable(type: Data.self), data.count <= PocketLimits.assetBytes else { throw HostServiceError.invalidInput }
            runtimeValues[key] = .string(data.base64EncodedString())
            photoError = nil
        } catch { photoError = error.localizedDescription }
    }

    private func string(_ value: PocketValue?) -> String? {
        guard case .string(let string) = value else { return nil }
        return string
    }
}
