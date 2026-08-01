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

    var body: some View {
        if isVisible {
            switch component.kind {
            case .text: Text(resolved(component.text ?? component.title ?? ""))
            case .markdown: Text(.init(resolved(component.text ?? component.title ?? "")))
            case .heading: Text(resolved(component.text ?? component.title ?? "")).font(.title2.bold())
            case .caption: Text(resolved(component.text ?? component.title ?? "")).font(.caption).foregroundStyle(.secondary)
            case .metric: VStack(alignment: .leading) { Text(component.title ?? "Metric").font(.caption); Text(resolved(component.text ?? bindingText)).font(.title.bold()).monospacedDigit() }
            case .progress: ProgressView(value: numericValue, total: component.maximum ?? 1) { Text(component.title ?? "Progress") }
            case .image: if let data = Data(base64Encoded: component.text ?? ""), let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().accessibilityLabel(component.title ?? "Image") } else { Label(component.title ?? "Image unavailable", systemImage: "photo") }
            case .symbol: Image(systemName: component.text ?? "square.grid.2x2.fill").font(.title).accessibilityLabel(component.title ?? "Symbol")
            case .divider: Divider()
            case .spacer: Spacer(minLength: CGFloat(component.minimum ?? 8))
            case .badge: Text(resolved(component.text ?? component.title ?? "Badge")).font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 4).background(.tint.opacity(0.15), in: Capsule())
            case .textField: TextField(component.title ?? "Text", text: stringBinding).textInputAutocapitalization(.sentences)
            case .secureField: SecureField(component.title ?? "Secure value", text: stringBinding)
            case .multilineText: TextField(component.title ?? "Notes", text: stringBinding, axis: .vertical).lineLimit(3...8)
            case .numberField: TextField(component.title ?? "Number", value: numberBinding, format: .number).keyboardType(.decimalPad)
            case .toggle: Toggle(component.title ?? "Enabled", isOn: boolBinding)
            case .slider: VStack(alignment: .leading) { Text(component.title ?? "Value"); Slider(value: numberBinding, in: (component.minimum ?? 0)...(component.maximum ?? 100)) }
            case .stepper: Stepper(value: numberBinding, in: (component.minimum ?? 0)...(component.maximum ?? 100), step: 1) { LabeledContent(component.title ?? "Value", value: numericValue.formatted()) }
            case .datePicker: DatePicker(component.title ?? "Date", selection: dateBinding)
            case .picker: Picker(component.title ?? "Choose", selection: stringBinding) { ForEach(component.options, id: \.self) { Text($0).tag($0) } }
            case .segmentedPicker: Picker(component.title ?? "Choose", selection: stringBinding) { ForEach(component.options, id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
            case .list, .searchResults:
                if componentRecords.isEmpty { ContentUnavailableView(component.title ?? "No Records", systemImage: "list.bullet.rectangle", description: Text("Add your first record.")) }
                else { ForEach(componentRecords) { record in recordRow(record) } }
            case .grid:
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))]) { ForEach(componentRecords) { record in recordRow(record).padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            case .recordForm: VStack { ForEach(component.children) { child in childRenderer(child) } }
            case .detail: VStack(alignment: .leading) { ForEach(componentRecords.prefix(1)) { record in recordRow(record) } }
            case .chart: VStack(alignment: .leading) { Text(component.title ?? "Records").font(.headline); ProgressView(value: Double(componentRecords.count), total: Double(max(PocketLimits.recordsPerCollection, 1))); Text("\(componentRecords.count) records").font(.caption) }
            case .emptyState: ContentUnavailableView(component.title ?? "Nothing Here", systemImage: component.text ?? "tray", description: Text("This app has no content yet."))
            case .button: Button(component.title ?? "Continue") { if let id = component.actionID { runAction(id) } }.buttonStyle(.borderedProminent)
            case .menu: Menu(component.title ?? "Actions") { ForEach(component.children) { child in if let actionID = child.actionID { Button(child.title ?? "Action") { runAction(actionID) } } } }
            case .shareButton: if let value = shareValue { ShareLink(item: value) { Label(component.title ?? "Share", systemImage: "square.and.arrow.up") } }
            case .fileImportButton: Button(component.title ?? "Import") { importFile() }
            case .fileExportButton: Button(component.title ?? "Export") { exportFile() }
            case .photoPickerButton: PhotosPicker(selection: $selectedPhoto, matching: .images) { Label(component.title ?? "Choose Photo", systemImage: "photo.on.rectangle") }
            case .confirmationButton: Button(component.title ?? "Confirm", role: .destructive) { if let id = component.actionID { runAction(id) } }
            case .section: Section(component.title ?? "") { ForEach(component.children) { childRenderer($0) } }
            case .verticalStack, .group, .scrollContainer: VStack(alignment: .leading) { ForEach(component.children) { childRenderer($0) } }
            case .horizontalStack: HStack { ForEach(component.children) { childRenderer($0) } }
            case .lazyGrid: LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))]) { ForEach(component.children) { childRenderer($0) } }
            case .card: VStack(alignment: .leading) { ForEach(component.children) { childRenderer($0) } }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private var isVisible: Bool {
        guard let expression = component.visibilityExpression else { return true }
        return (try? ExpressionEvaluator().evaluate(expression, context: ["state": .object(runtimeValues)])) == .bool(true)
    }
    private var key: String { component.binding?.replacingOccurrences(of: "state.", with: "") ?? component.id }
    private var bindingText: String { if case .string(let value) = runtimeValues[key] { return value }; return "" }
    private var numericValue: Double { if case .number(let value) = runtimeValues[key] { return value }; return 0 }
    private var shareValue: String? { let value = resolved(component.text ?? bindingText); return value.isEmpty ? nil : value }
    private var componentRecords: [PocketRecord] { component.collection.flatMap { recordsByCollection[$0] } ?? recordsByCollection.values.first ?? [] }
    private var stringBinding: Binding<String> { Binding(get: { bindingText }, set: { runtimeValues[key] = .string($0) }) }
    private var numberBinding: Binding<Double> { Binding(get: { numericValue }, set: { runtimeValues[key] = .number($0) }) }
    private var boolBinding: Binding<Bool> { Binding(get: { if case .bool(let value) = runtimeValues[key] { value } else { false } }, set: { runtimeValues[key] = .bool($0) }) }
    private var dateBinding: Binding<Date> { Binding(get: { if case .date(let value) = runtimeValues[key] { value } else { Date() } }, set: { runtimeValues[key] = .date($0) }) }
    private func resolved(_ source: String) -> String {
        var output = source
        let pattern = #"\{\{\s*([^}]+)\s*\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).reversed()
        for match in matches where match.numberOfRanges == 2 {
            guard let full = Range(match.range(at: 0), in: source), let expression = Range(match.range(at: 1), in: source) else { continue }
            let value = try? ExpressionEvaluator().evaluate(String(source[expression]).trimmingCharacters(in: .whitespaces), context: ["state": .object(runtimeValues), "environment": .object(["currentDate": .date(Date())])])
            output.replaceSubrange(full, with: display(value ?? .null))
        }
        return output
    }
    private func display(_ value: PocketValue) -> String { switch value { case .null: ""; case .bool(let value): value ? "Yes" : "No"; case .number(let value): value.formatted(); case .string(let value): value; case .date(let value): value.formatted(date: .abbreviated, time: .omitted); case .array(let value): "\(value.count) items"; case .object(let value): "\(value.count) fields" } }
    private func childRenderer(_ child: ComponentSpec) -> some View { ComponentRenderer(component: child, recordsByCollection: recordsByCollection, runtimeValues: $runtimeValues, runAction: runAction, importFile: importFile, exportFile: exportFile) }
    private func recordRow(_ record: PocketRecord) -> some View { VStack(alignment: .leading, spacing: 4) { ForEach(record.values.sorted(by: { $0.key < $1.key }), id: \.key) { pair in LabeledContent(pair.key.capitalized, value: display(pair.value)) } } }
}
