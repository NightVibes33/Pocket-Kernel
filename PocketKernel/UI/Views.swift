import SwiftUI
import Foundation
import FoundationModels
import AuthenticationServices
import Security
import UserNotifications
import EventKit
import UIKit

// MARK: - Views

struct RootView: View {
    @EnvironmentObject private var chat: ChatController
    @EnvironmentObject private var oauth: OAuthCoordinator

    var body: some View {
        TabView {
            ChatView()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.sparkles") }
            ConnectionsView()
                .tabItem { Label("Services", systemImage: "link.circle") }
            AutomationsView()
                .tabItem { Label("Automations", systemImage: "clock.arrow.2.circlepath") }
            ActivityView()
                .tabItem { Label("Activity", systemImage: "list.bullet.rectangle") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .task { await oauth.refresh() }
    }
}

struct ChatView: View {
    @EnvironmentObject private var chat: ChatController
    @EnvironmentObject private var executor: ActionExecutor
    @State private var input = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                modelBanner
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(chat.messages) { message in
                                MessageBubble(message: message).id(message.id)
                            }
                            ForEach(chat.pending) { proposal in
                                ApprovalCard(proposal: proposal) {
                                    Task { await chat.approve(proposal, executor: executor) }
                                } reject: {
                                    chat.reject(proposal)
                                }
                                .id(proposal.id)
                            }
                            if chat.isThinking {
                                HStack { ProgressView(); Text("Thinking on this iPhone…").foregroundStyle(.secondary); Spacer() }
                                    .padding(.horizontal)
                            }
                            if let error = chat.errorText {
                                Text(error).font(.callout).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                    .onChange(of: chat.messages.count + chat.pending.count) {
                        if let id = chat.pending.last?.id ?? chat.messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                    }
                }
                composer
            }
            .navigationTitle("PocketKernel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New", systemImage: "square.and.pencil") { chat.reset() }
                }
            }
        }
    }

    private var modelBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: chat.modelStatus.contains("ready") ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
            Text(chat.modelStatus).font(.caption.weight(.semibold))
            Spacer()
            Text("No cloud LLM").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal).padding(.vertical, 9)
        .background(.thinMaterial)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask it to do anything…", text: $input, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 19))
                .focused($focused)
            Button {
                let message = input
                input = ""
                Task { await chat.send(message) }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.headline.bold()).frame(width: 42, height: 42)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.isThinking)
        }
        .padding()
        .background(.regularMaterial)
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 42) }
            Text(message.text)
                .textSelection(.enabled)
                .padding(13)
                .background(background, in: RoundedRectangle(cornerRadius: 19))
                .foregroundStyle(message.role == .user ? .white : .primary)
            if message.role != .user { Spacer(minLength: 42) }
        }
        .padding(.horizontal)
    }
    private var background: some ShapeStyle {
        message.role == .user ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(message.role == .system ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.12))
    }
}

struct ApprovalCard: View {
    let proposal: ToolProposal
    let approve: () -> Void
    let reject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: proposal.kind == .service ? "link.badge.plus" : proposal.kind == .schedule ? "calendar.badge.clock" : "iphone.gen3")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Approval required").font(.caption.bold()).foregroundStyle(.orange)
                    Text(proposal.title).font(.headline)
                }
                Spacer()
            }
            Text(proposal.summary).foregroundStyle(.secondary)
            if let provider = proposal.provider {
                Label("\(provider.capitalized) · \(proposal.action)", systemImage: "lock.shield")
                    .font(.caption.weight(.semibold))
            }
            if !proposal.input.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(proposal.input.keys.sorted(), id: \.self) { key in
                        Text("\(key): \(proposal.input[key] ?? "")").font(.caption).lineLimit(3)
                    }
                }
                .padding(10).background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                Button("Cancel", role: .cancel, action: reject).buttonStyle(.bordered)
                Spacer()
                Button("Approve", systemImage: "checkmark", action: approve).buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.orange.opacity(0.35)))
        .padding(.horizontal)
    }
}

struct ConnectionsView: View {
    @EnvironmentObject private var oauth: OAuthCoordinator

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ProviderDescriptor.all) { provider in
                        let connected = oauth.connections.contains { $0.provider == provider.id }
                        HStack(spacing: 14) {
                            Image(systemName: provider.symbol)
                                .font(.title2).foregroundStyle(provider.tint).frame(width: 34)
                            VStack(alignment: .leading) {
                                Text(provider.name).font(.headline)
                                Text(provider.description).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if connected {
                                Menu {
                                    Button("Disconnect", role: .destructive) { Task { await oauth.disconnect(provider.id) } }
                                } label: { Text("Connected").foregroundStyle(.green).font(.subheadline.weight(.semibold)) }
                            } else {
                                Button(oauth.configured[provider.id] == false ? "Unavailable" : "Connect") {
                                    Task { await oauth.connect(provider.id) }
                                }
                                .buttonStyle(.bordered)
                                .disabled(oauth.configured[provider.id] == false)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                } header: {
                    Text("OAuth connections")
                } footer: {
                    Text("Sign-in happens on each service’s official page. PocketKernel never asks for a password. Connections can be revoked here at any time.")
                }
                if let error = oauth.errorText {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Services")
            .refreshable { await oauth.refresh() }
            .overlay { if oauth.isLoading { ProgressView() } }
        }
    }
}

@MainActor
final class AutomationListModel: ObservableObject {
    @Published var items: [SavedAutomation] = []
    @Published var isLoading = false
    @Published var errorText: String?
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do { items = try await BackendClient.shared.automations(); errorText = nil }
        catch { errorText = error.localizedDescription }
    }
}

struct AutomationsView: View {
    @StateObject private var model = AutomationListModel()
    var body: some View {
        NavigationStack {
            Group {
                if model.items.isEmpty && !model.isLoading {
                    ContentUnavailableView("No saved automations", systemImage: "clock.badge.xmark", description: Text("Ask the chat to schedule a connected-service workflow."))
                } else {
                    List(model.items) { item in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack { Text(item.title).font(.headline); Spacer(); Image(systemName: item.enabled ? "checkmark.circle.fill" : "pause.circle").foregroundStyle(item.enabled ? .green : .secondary) }
                            Text(item.prompt).font(.callout).foregroundStyle(.secondary)
                            if let next = item.nextRunAt { Label("Next: \(next)", systemImage: "clock").font(.caption) }
                            if let last = item.lastRunAt {
                                Label(item.lastRunOK == true ? "Last run succeeded · \(last)" : "Last run failed · \(item.lastError ?? last)", systemImage: item.lastRunOK == true ? "checkmark.circle" : "xmark.circle")
                                    .font(.caption).foregroundStyle(item.lastRunOK == true ? .green : .red)
                            }
                        }.padding(.vertical, 5)
                    }
                }
            }
            .navigationTitle("Automations")
            .task { await model.refresh() }
            .refreshable { await model.refresh() }
            .overlay { if model.isLoading { ProgressView() } }
            .safeAreaInset(edge: .bottom) { if let error = model.errorText { Text(error).font(.caption).foregroundStyle(.red).padding() } }
        }
    }
}

struct ActivityView: View {
    @EnvironmentObject private var chat: ChatController
    var body: some View {
        NavigationStack {
            Group {
                if chat.activity.isEmpty {
                    ContentUnavailableView("No activity", systemImage: "checklist", description: Text("Approved actions and their results appear here."))
                } else {
                    List(chat.activity) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(item.succeeded ? .green : .red)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.headline)
                                Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(8)
                                Text(item.date.formatted()).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Activity")
        }
    }
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published var backendURL = UserDefaults.standard.string(forKey: "backendURL") ?? "https://pocketkernel.vercel.app"
    @Published var status = "Not checked"
    func save() { UserDefaults.standard.set(backendURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")), forKey: "backendURL") }
    func check() async {
        do { status = try await BackendClient.shared.health() }
        catch { status = error.localizedDescription }
    }
}

struct SettingsView: View {
    @StateObject private var model = SettingsModel()
    var body: some View {
        NavigationStack {
            Form {
                Section("Private intelligence") {
                    LabeledContent("Planner", value: "Apple on-device model")
                    LabeledContent("Cloud LLM", value: "Never used")
                    LabeledContent("Minimum agent OS", value: "iOS 27")
                }
                Section {
                    TextField("https://…", text: $model.backendURL)
                        .textInputAutocapitalization(.never).keyboardType(.URL).onSubmit { model.save() }
                    LabeledContent("Status", value: model.status)
                    Button("Save and test") { model.save(); Task { await model.check() } }
                } header: {
                    Text("Automation server")
                } footer: {
                    Text("The server handles OAuth and deterministic scheduled actions only. Chat text and Apple model sessions stay on this device.")
                }
                Section("Safety") {
                    Label("Approval before writes", systemImage: "hand.raised.fill")
                    Label("Provider passwords never enter the app", systemImage: "key.slash")
                    Label("Tokens encrypted server-side", systemImage: "lock.shield.fill")
                    Label("No downloaded code or JIT", systemImage: "checkmark.shield.fill")
                }
            }
            .navigationTitle("Settings")
            .task { await model.check() }
        }
    }
}
