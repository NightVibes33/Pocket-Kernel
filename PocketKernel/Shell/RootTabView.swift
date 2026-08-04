import SwiftUI

private enum RootTab: Hashable {
    case today, create, automations, activity, connections
}

struct RootTabView: View {
    @AppStorage("PKAutomationOnboardingComplete") private var onboardingComplete = false
    @StateObject private var workspace = PKAutomationWorkspace()
    @State private var selectedTab: RootTab

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let requested = Self.argumentValue("-PKStartTab", arguments: arguments)
        _selectedTab = State(initialValue: requested == "create" ? .create : requested == "connections" ? .connections : .today)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView(create: { selectedTab = .create })
                .tag(RootTab.today)
                .tabItem { Label("Today", systemImage: "checklist") }
            AutomationCreateView()
                .tag(RootTab.create)
                .tabItem { Label("Create", systemImage: "sparkles") }
            AutomationsView()
                .tag(RootTab.automations)
                .tabItem { Label("Automations", systemImage: "point.3.connected.trianglepath.dotted") }
            AutomationActivityView()
                .tag(RootTab.activity)
                .tabItem { Label("Activity", systemImage: "clock.arrow.circlepath") }
            ConnectionsView()
                .tag(RootTab.connections)
                .tabItem { Label("Connections", systemImage: "link") }
        }
        .environmentObject(workspace)
        .fullScreenCover(isPresented: Binding(
            get: { !onboardingComplete && !ProcessInfo.processInfo.arguments.contains("-PKUITesting") },
            set: { if !$0 { onboardingComplete = true } }
        )) {
            AutomationOnboardingView { onboardingComplete = true }
        }
        .alert("PocketKernel", isPresented: Binding(
            get: { workspace.errorMessage != nil },
            set: { if !$0 { workspace.errorMessage = nil } }
        )) {
            Button("OK") { workspace.errorMessage = nil }
        } message: {
            Text(workspace.errorMessage ?? "Unknown error")
        }
    }

    private static func argumentValue(_ key: String, arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: key), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

private struct AutomationOnboardingView: View {
    var complete: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    Spacer(minLength: 40)
                    Image(systemName: "apple.intelligence")
                        .font(.system(size: 74, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                    VStack(spacing: 10) {
                        Text("PocketKernel")
                            .font(.largeTitle.bold())
                        Text("Describe work in plain English. PocketKernel builds a typed automation, shows every step, asks before acting, and runs the approved workflow predictably.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        feature("Build with Apple Intelligence", "apple.intelligence")
                        feature("Connect real services through OAuth", "link.badge.plus")
                        feature("Approve email, posts, events, and document changes", "checkmark.shield.fill")
                        feature("Inspect deterministic runs and failures", "list.bullet.rectangle.portrait")
                    }
                    .frame(maxWidth: 520, alignment: .leading)
                    Text("PocketKernel never sends an external action until its approval policy and service connection permit it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Get Started", action: complete)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    Spacer(minLength: 20)
                }
                .padding(28)
            }
            .navigationTitle("Welcome")
        }
    }

    private func feature(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.headline)
    }
}

private struct TodayView: View {
    @EnvironmentObject private var workspace: PKAutomationWorkspace
    var create: () -> Void

    private var approvals: [PKRunEvent] {
        workspace.runs.filter { $0.state == .waitingForApproval }
    }

    private var failures: [PKRunEvent] {
        workspace.runs.filter { $0.state == .failed }
    }

    private var scheduled: [PKAutomation] {
        workspace.automations.filter { $0.state == .active && $0.trigger.kind != .manual }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    if !approvals.isEmpty {
                        section("Needs your approval", symbol: "checkmark.shield") {
                            ForEach(approvals) { event in runCard(event) }
                        }
                    }
                    if !failures.isEmpty {
                        section("Needs attention", symbol: "exclamationmark.triangle") {
                            ForEach(failures.prefix(5)) { event in runCard(event) }
                        }
                    }
                    section("Upcoming", symbol: "calendar.badge.clock") {
                        if scheduled.isEmpty {
                            emptyCard("No enabled scheduled automations", "Create a schedule, event, condition, webhook, or location trigger.")
                        } else {
                            ForEach(scheduled) { automation in automationCard(automation) }
                        }
                    }
                    section("Recent runs", symbol: "clock.arrow.circlepath") {
                        if workspace.runs.isEmpty {
                            emptyCard("No runs yet", "Test or enable an automation to see step-by-step results here.")
                        } else {
                            ForEach(workspace.runs.prefix(8)) { event in runCard(event) }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Today")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What should happen automatically?")
                        .font(.title2.bold())
                    Text("Create a workflow from a plain-English request.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "apple.intelligence")
                    .font(.title)
                    .foregroundStyle(.tint)
            }
            Button(action: create) {
                Label("Describe an automation", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private func section<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.title3.bold())
            content()
        }
    }

    private func runCard(_ event: PKRunEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: runSymbol(event.state))
                .foregroundStyle(runColor(event.state))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.automationName).font(.headline)
                Text(event.message).font(.subheadline).foregroundStyle(.secondary)
                Text(event.createdAt, style: .relative).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func automationCard(_ automation: PKAutomation) -> some View {
        HStack {
            Image(systemName: triggerSymbol(automation.trigger.kind)).frame(width: 28)
            VStack(alignment: .leading) {
                Text(automation.name).font(.headline)
                Text(triggerDescription(automation.trigger)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(automation.steps.count) steps").font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func emptyCard(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct AutomationCreateView: View {
    @EnvironmentObject private var workspace: PKAutomationWorkspace
    @State private var showingDraft = false

    private let examples = [
        "Every weekday at 8 AM, summarize unread customer emails and post the digest to Slack",
        "When an urgent Gmail arrives, draft a reply and ask me to approve it",
        "Monitor an API price and notify me when it drops below my target",
        "Every Friday, prepare a document from this week's calendar and Slack updates",
        "When I arrive at work, send me today's meetings and important inbox tasks"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Describe the outcome", systemImage: "apple.intelligence")
                            .font(.headline)
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $workspace.prompt)
                                .frame(minHeight: 150)
                                .accessibilityLabel("Automation description")
                            if workspace.prompt.isEmpty {
                                Text("Example: Every weekday at 8 AM, summarize unread customer emails and post the digest to Slack.")
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }
                Section("Try an example") {
                    ForEach(examples, id: \.self) { example in
                        Button(example) { workspace.prompt = example }
                            .foregroundStyle(.primary)
                    }
                }
                Section {
                    Button {
                        workspace.compilePrompt()
                        showingDraft = workspace.draft != nil
                    } label: {
                        Label("Build workflow", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(workspace.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } footer: {
                    Text("The builder produces registered operations and typed inputs. It never generates executable Swift, JavaScript, shell commands, or arbitrary server code.")
                }
            }
            .navigationTitle("Create")
            .navigationDestination(isPresented: $showingDraft) {
                if workspace.draft != nil { DraftWorkflowView() }
            }
        }
    }
}

private struct DraftWorkflowView: View {
    @EnvironmentObject private var workspace: PKAutomationWorkspace
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let draft = workspace.draft {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(draft.name).font(.title2.bold())
                            Text(draft.summary).foregroundStyle(.secondary)
                            Label(triggerDescription(draft.trigger), systemImage: triggerSymbol(draft.trigger.kind))
                                .font(.subheadline)
                        }
                        .padding(.vertical, 6)
                    }
                    if !workspace.validationIssues.isEmpty {
                        Section("Validation") {
                            ForEach(workspace.validationIssues) { issue in
                                Label(issue.message, systemImage: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(issue.severity == .error ? .red : .orange)
                            }
                        }
                    }
                    Section("Workflow") {
                        ForEach(Array(draft.steps.enumerated()), id: \.element.id) { index, step in
                            WorkflowStepRow(number: index + 1, step: step)
                        }
                    }
                    Section("Required connections") {
                        if draft.connections.isEmpty {
                            Label("No OAuth account is required", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            ForEach(draft.connections) { connection in
                                HStack {
                                    Label(connection.service.title, systemImage: connection.service.symbol)
                                    Spacer()
                                    Text(connection.connected ? "Connected" : "Required")
                                        .font(.caption)
                                        .foregroundStyle(connection.connected ? .green : .orange)
                                }
                            }
                        }
                    }
                    Section {
                        Button("Save automation") {
                            workspace.saveDraft()
                            dismiss()
                        }
                        .disabled(workspace.validationIssues.contains { $0.severity == .error })
                    } footer: {
                        Text("New automations are saved paused. Connect services, test the workflow, then explicitly enable it.")
                    }
                }
            } else {
                ContentUnavailableView("No draft", systemImage: "doc.badge.plus")
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WorkflowStepRow: View {
    var number: Int
    var step: PKWorkflowStep

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 28, height: 28)
                .background(.tint.opacity(0.15), in: Circle())
            Image(systemName: step.service.symbol)
                .frame(width: 26, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(step.title).font(.headline)
                Text("\(step.service.title) · \(step.operation)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if step.mutatesExternalState {
                    Label("Approval required", systemImage: "checkmark.shield")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct AutomationsView: View {
    @EnvironmentObject private var workspace: PKAutomationWorkspace

    var body: some View {
        NavigationStack {
            List {
                if workspace.automations.isEmpty {
                    ContentUnavailableView(
                        "No automations",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("Describe an automation, review its generated steps, and save it here.")
                    )
                } else {
                    ForEach(workspace.automations) { automation in
                        NavigationLink {
                            AutomationDetailView(automationID: automation.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(automation.name).font(.headline)
                                    Spacer()
                                    stateBadge(automation.state)
                                }
                                Text(automation.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                HStack {
                                    Label(triggerDescription(automation.trigger), systemImage: triggerSymbol(automation.trigger.kind))
                                    Spacer()
                                    Text("\(automation.steps.count) steps")
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 5)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { workspace.delete(workspace.automations[index]) }
                    }
                }
            }
            .navigationTitle("Automations")
        }
    }
}

private struct AutomationDetailView: View {
    @EnvironmentObject private var workspace: PKAutomationWorkspace
    var automationID: UUID
    @State private var confirmApprovedRun = false

    private var automation: PKAutomation? {
        workspace.automations.first { $0.id == automationID }
    }

    var body: some View {
        Group {
            if let automation {
                List {
                    Section {
                        Text(automation.summary).foregroundStyle(.secondary)
                        Label(triggerDescription(automation.trigger), systemImage: triggerSymbol(automation.trigger.kind))
                    }
                    Section("Workflow") {
                        ForEach(Array(automation.steps.enumerated()), id: \.element.id) { index, step in
                            WorkflowStepRow(number: index + 1, step: step)
                        }
                    }
                    Section("Connections") {
                        if automation.connections.isEmpty {
                            Label("No OAuth account required", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            ForEach(automation.connections) { connection in
                                Label(
                                    "\(connection.service.title): \(connection.connected ? "Connected" : "Not connected")",
                                    systemImage: connection.connected ? "checkmark.circle.fill" : "exclamationmark.circle"
                                )
                                .foregroundStyle(connection.connected ? .green : .orange)
                            }
                        }
                    }
                    Section("Controls") {
                        Button(automation.state == .active ? "Pause" : "Enable") { workspace.toggle(automation) }
                        Button("Test deterministic run") { Task { await workspace.run(automation) } }
                            .disabled(workspace.isWorking)
                        if automation.steps.contains(where: \.mutatesExternalState) {
                            Button("Review and approve test run") { confirmApprovedRun = true }
                                .disabled(workspace.isWorking)
                        }
                    }
                }
                .navigationTitle(automation.name)
                .confirmationDialog("Approve outbound actions?", isPresented: $confirmApprovedRun, titleVisibility: .visible) {
                    Button("Approve this test run") { Task { await workspace.run(automation, approved: true) } }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This approval applies only to this run. It does not grant unrestricted permission to future changed workflows.")
                }
            } else {
                ContentUnavailableView("Automation missing", systemImage: "questionmark.folder")
            }
        }
    }
}

private struct AutomationActivityView: View {
    @EnvironmentObject private var workspace: PKAutomationWorkspace

    var body: some View {
        NavigationStack {
            List {
                if workspace.runs.isEmpty {
                    ContentUnavailableView(
                        "No activity",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Workflow tests, approvals, failures, and successful runs appear here.")
                    )
                } else {
                    ForEach(workspace.runs) { event in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: runSymbol(event.state))
                                .foregroundStyle(runColor(event.state))
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(event.automationName).font(.headline)
                                Text(event.message).font(.subheadline).foregroundStyle(.secondary)
                                HStack {
                                    Text(event.state.rawValue.capitalized)
                                    Text("·")
                                    Text(event.createdAt, style: .relative)
                                }
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Activity")
        }
    }
}

private struct ConnectionsView: View {
    @EnvironmentObject private var workspace: PKAutomationWorkspace
    @State private var selectedService: PKServiceKind?

    private let advertisedServices: [PKServiceKind] = [
        .gmail, .outlook, .googleCalendar, .googleDrive, .googleDocs, .googleSheets, .googleSlides,
        .slack, .discord, .reddit, .linkedIn, .rss, .http
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("OAuth authorization, refresh tokens, webhook secrets, and scheduled execution require the PocketKernel service. The app never fabricates a connected account.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("Services") {
                    ForEach(advertisedServices, id: \.self) { service in
                        Button { selectedService = service } label: {
                            HStack {
                                Label(service.title, systemImage: service.symbol)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if workspace.requiredServices.contains(service) {
                                    Text("Required").font(.caption).foregroundStyle(.orange)
                                }
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                Section("Local operations") {
                    Label("RSS and HTTPS workflows can be compiled without OAuth", systemImage: "network")
                    Label("External mutations still require explicit approval", systemImage: "checkmark.shield")
                }
            }
            .navigationTitle("Connections")
            .sheet(item: $selectedService) { service in
                ConnectionDetailView(service: service)
            }
        }
    }
}

extension PKServiceKind: Identifiable {
    var id: String { rawValue }
}

private struct ConnectionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    var service: PKServiceKind

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(service.title, systemImage: service.symbol).font(.title2.bold())
                    Text(connectionExplanation(service)).foregroundStyle(.secondary)
                }
                if service == .rss || service == .http {
                    Section("Available locally") {
                        Label("No OAuth account required", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("The workflow still validates HTTPS endpoints, response limits, and approval rules.")
                    }
                } else {
                    Section("Connection status") {
                        Label("OAuth service not configured", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                        Text("PocketKernel will use ASWebAuthenticationSession after the backend has a registered client identifier, redirect URI, encrypted token vault, and refresh endpoint for this provider.")
                    }
                    Section {
                        Button("Connect \(service.title)") {}
                            .disabled(true)
                    } footer: {
                        Text("Disabled deliberately: the app will not claim an account is connected until a real OAuth configuration exists.")
                    }
                }
            }
            .navigationTitle("Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private func stateBadge(_ state: PKAutomationState) -> some View {
    Text(state.rawValue.capitalized)
        .font(.caption2.bold())
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(state == .active ? Color.green.opacity(0.16) : Color.secondary.opacity(0.12), in: Capsule())
}

private func triggerSymbol(_ trigger: PKTriggerKind) -> String {
    switch trigger {
    case .manual: "play.circle"
    case .schedule: "calendar.badge.clock"
    case .webhook: "link.badge.plus"
    case .accountEvent: "tray.and.arrow.down"
    case .webCondition: "waveform.path.ecg"
    case .workflowCompleted: "arrow.triangle.branch"
    case .location: "location.fill"
    }
}

private func triggerDescription(_ trigger: PKTrigger) -> String {
    switch trigger.kind {
    case .manual: "Run manually"
    case .schedule:
        let cadence = trigger.configuration["cadence"] ?? "scheduled"
        let time = trigger.configuration["time"] ?? "08:00"
        return "\(cadence.capitalized) at \(time) · \(trigger.timeZoneIdentifier)"
    case .webhook: "Incoming webhook"
    case .accountEvent: "When a connected account changes"
    case .webCondition: "When a monitored condition matches"
    case .workflowCompleted: "After another workflow completes"
    case .location: "Location-aware trigger"
    }
}

private func runSymbol(_ state: PKRunState) -> String {
    switch state {
    case .running: "arrow.triangle.2.circlepath"
    case .waitingForApproval: "checkmark.shield"
    case .succeeded: "checkmark.circle.fill"
    case .failed: "xmark.octagon.fill"
    }
}

private func runColor(_ state: PKRunState) -> Color {
    switch state {
    case .running: .blue
    case .waitingForApproval: .orange
    case .succeeded: .green
    case .failed: .red
    }
}

private func connectionExplanation(_ service: PKServiceKind) -> String {
    switch service {
    case .gmail, .outlook: "Read authorized message context, triage threads, prepare drafts, and send only after approval."
    case .googleCalendar: "Read availability and prepare or create events using the minimum required scopes."
    case .googleDrive, .googleDocs, .googleSheets, .googleSlides: "Find files and prepare or update approved documents and spreadsheets."
    case .slack, .discord: "Read approved channels and prepare or post messages according to each workflow's approval policy."
    case .reddit, .linkedIn: "Prepare social content and publish only after explicit approval."
    case .rss: "Read public RSS and Atom feeds without an account connection."
    case .http: "Call declared HTTPS endpoints with strict redirects, timeouts, and response-size limits."
    default: "Used internally by validated PocketKernel workflows."
    }
}
