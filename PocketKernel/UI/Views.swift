import SwiftUI
import Foundation
import FoundationModels
import AuthenticationServices
import Security
import UserNotifications
import EventKit
import UIKit

// MARK: - Navigation

enum MainTab: Hashable {
    case home
    case automations
    case activity
    case profile
}

struct RootView: View {
    @EnvironmentObject private var oauth: OAuthCoordinator
    @EnvironmentObject private var account: AccountController
    @AppStorage("didCompleteOnboarding.v2") private var didCompleteOnboarding = false
    @State private var selectedTab: MainTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tag(MainTab.home)
                .tabItem { Label("Home", systemImage: "sparkles") }

            AutomationsView {
                selectedTab = .home
            }
            .tag(MainTab.automations)
            .tabItem { Label("Automations", systemImage: "clock.arrow.2.circlepath") }

            ActivityView()
                .tag(MainTab.activity)
                .tabItem { Label("Activity", systemImage: "checkmark.circle") }

            ProfileView {
                didCompleteOnboarding = false
            }
            .tag(MainTab.profile)
            .tabItem { Label("You", systemImage: "person.crop.circle") }
        }
        .tint(.accentColor)
        .task { await oauth.refresh() }
        .fullScreenCover(
            isPresented: Binding(
                get: { !didCompleteOnboarding },
                set: { isPresented in
                    if !isPresented { didCompleteOnboarding = true }
                }
            )
        ) {
            OnboardingView {
                didCompleteOnboarding = true
            }
        }
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    let completion: () -> Void
    @State private var page = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.indigo.opacity(0.22), Color.blue.opacity(0.08), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip") { completion() }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal)
                        .opacity(page == 2 ? 0 : 1)
                }
                .frame(height: 52)

                TabView(selection: $page) {
                    onboardingPage(
                        tag: 0,
                        symbol: "bubble.left.and.sparkles.fill",
                        title: "Say what you want done",
                        detail: "Describe a task naturally. PocketKernel turns it into a clear action or repeatable automation.",
                        tint: .indigo
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("You")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("Every weekday morning, summarize the emails that need my attention.")
                                .font(.body.weight(.medium))
                                .padding(16)
                                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 20))
                                .foregroundStyle(.white)
                            HStack(spacing: 10) {
                                PocketLogoMark(size: 28)
                                Text("I’ll prepare the workflow and show you exactly what will happen before anything is saved.")
                                    .font(.callout)
                            }
                            .padding(16)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                        }
                    }
                    .tag(0)

                    onboardingPage(
                        tag: 1,
                        symbol: "link.circle.fill",
                        title: "Connect the apps you use",
                        detail: "Sign in on each app’s official page. PocketKernel never asks for your passwords.",
                        tint: .blue
                    ) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(ProviderDescriptor.all.prefix(4)) { provider in
                                HStack(spacing: 10) {
                                    Image(systemName: provider.symbol)
                                        .foregroundStyle(provider.tint)
                                        .frame(width: 30, height: 30)
                                        .background(provider.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                                    Text(provider.name)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer(minLength: 0)
                                }
                                .padding(12)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                            }
                        }
                    }
                    .tag(1)

                    onboardingPage(
                        tag: 2,
                        symbol: "hand.raised.fill",
                        title: "You stay in control",
                        detail: "PocketKernel asks before sending, posting, deleting, or scheduling anything important.",
                        tint: .green
                    ) {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Ready to run", systemImage: "checkmark.shield.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                            Text("Send the weekly project update to the team channel")
                                .font(.title3.weight(.semibold))
                            Text("Nothing happens until you approve this action.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            HStack {
                                Button("Not now") { }
                                    .buttonStyle(.bordered)
                                Spacer()
                                Button("Run action") { }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                    }
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 7) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.22))
                            .frame(width: index == page ? 24 : 7, height: 7)
                            .animation(.snappy, value: page)
                    }
                }
                .padding(.bottom, 18)

                Button {
                    if page < 2 {
                        withAnimation { page += 1 }
                    } else {
                        completion()
                    }
                } label: {
                    Text(page == 2 ? "Start automating" : "Continue")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private func onboardingPage<Preview: View>(
        tag: Int,
        symbol: String,
        title: String,
        detail: String,
        tint: Color,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                PocketLogoMark(size: 74)
                    .padding(.top, 10)

                VStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.title2)
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text(detail)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                preview()
                    .padding(.top, 8)

                Label("Planning happens privately on your iPhone", systemImage: "lock.shield.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
}

// MARK: - Home and chat

struct HomeView: View {
    @EnvironmentObject private var chat: ChatController
    @EnvironmentObject private var executor: ActionExecutor
    @EnvironmentObject private var oauth: OAuthCoordinator
    @State private var input = ""
    @State private var showConnections = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if !chat.hasConversation {
                            HomeLanding(
                                readiness: chat.readiness,
                                connectedCount: oauth.connections.count,
                                onTemplate: { template in Task { await chat.send(template) } },
                                onConnect: { showConnections = true }
                            )
                        } else {
                            conversationHeader
                            ForEach(chat.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
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
                            ThinkingRow()
                        }

                        if let error = chat.errorText, chat.hasConversation {
                            StatusBanner(text: error, symbol: "exclamationmark.triangle.fill", tint: .orange)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: chat.messages.count + chat.pending.count) {
                    let target = chat.pending.last?.id ?? chat.messages.last?.id
                    if let target {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(target, anchor: .bottom)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                ChatComposer(input: $input, focused: $focused, isBusy: chat.isThinking) {
                    send()
                } onTemplate: { template in
                    input = template.prompt
                    focused = true
                }
            }
            .navigationTitle("PocketKernel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    PocketLogoMark(size: 30)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showConnections = true
                    } label: {
                        Image(systemName: oauth.connections.isEmpty ? "link.badge.plus" : "link.circle.fill")
                    }
                    .accessibilityLabel("Connections")

                    Button {
                        chat.reset()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New chat")
                }
            }
            .sheet(isPresented: $showConnections) {
                NavigationStack { ConnectionsView() }
                    .presentationDetents([.large])
            }
        }
    }

    private var conversationHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.green)
            Text("Private planning on this iPhone")
                .font(.caption.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 2)
    }

    private func send() {
        let message = input
        input = ""
        focused = false
        Task { await chat.send(message) }
    }
}

struct HomeLanding: View {
    let readiness: ModelReadiness
    let connectedCount: Int
    let onTemplate: (StarterTemplate) -> Void
    let onConnect: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 12) {
                PocketLogoMark(size: 64)
                Text("What can I take off your plate?")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Describe a task, connect the apps involved, and approve the final action.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            .padding(.top, 8)

            if readiness != .ready {
                StatusBanner(text: readiness.detail, symbol: readiness.symbol, tint: .orange)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: readiness.symbol)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(readiness.title)
                            .font(.subheadline.weight(.semibold))
                        Text(readiness.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Popular starts")
                        .font(.title2.bold())
                    Spacer()
                    Text("Tap to try")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(StarterTemplate.featured.prefix(6)) { template in
                        StarterTemplateCard(template: template) {
                            onTemplate(template)
                        }
                    }
                }
            }
            .padding(.horizontal)

            ConnectionSummaryCard(connectedCount: connectedCount, action: onConnect)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 12) {
                Text("How it works")
                    .font(.headline)
                HowItWorksRow(number: "1", title: "Ask naturally", detail: "No builder or code required")
                HowItWorksRow(number: "2", title: "Review the plan", detail: "See the exact action before it runs")
                HowItWorksRow(number: "3", title: "Approve and relax", detail: "Save repeatable tasks as automations")
            }
            .padding(18)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
    }
}

struct StarterTemplateCard: View {
    let template: StarterTemplate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: template.symbol)
                    .font(.title2)
                    .foregroundStyle(template.tint)
                    .frame(width: 40, height: 40)
                    .background(template.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                Text(template.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(template.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 145, alignment: .topLeading)
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Starts this automation in chat")
    }
}

struct ConnectionSummaryCard: View {
    let connectedCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: connectedCount == 0 ? "link.badge.plus" : "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(connectedCount == 0 ? Color.blue : Color.green)
                    .frame(width: 44, height: 44)
                    .background((connectedCount == 0 ? Color.blue : Color.green).opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text(connectedCount == 0 ? "Connect your everyday apps" : "\(connectedCount) app\(connectedCount == 1 ? "" : "s") connected")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(connectedCount == 0 ? "Gmail, Calendar, Slack, Notion, and more" : "Manage connections and permissions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }
}

struct HowItWorksRow: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 25, height: 25)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct ChatComposer: View {
    @Binding var input: String
    var focused: FocusState<Bool>.Binding
    let isBusy: Bool
    let send: () -> Void
    let onTemplate: (StarterTemplate) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Menu {
                ForEach(StarterTemplate.featured) { template in
                    Button {
                        onTemplate(template)
                    } label: {
                        Label(template.title, systemImage: template.symbol)
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(Color.secondary.opacity(0.12), in: Circle())
            }
            .accessibilityLabel("Prompt ideas")

            TextField("Describe what you want done", text: $input, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
                .focused(focused)
                .submitLabel(.send)
                .onSubmit {
                    if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { send() }
                }

            Button(action: send) {
                Image(systemName: isBusy ? "ellipsis" : "arrow.up")
                    .font(.headline.bold())
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        Group {
            if message.role == .system {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                    Text(message.text)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .bottom, spacing: 9) {
                    if message.role == .assistant {
                        PocketLogoMark(size: 28)
                    } else {
                        Spacer(minLength: 48)
                    }

                    VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 5) {
                        Text(message.text)
                            .textSelection(.enabled)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 20))
                            .foregroundStyle(message.role == .user ? .white : .primary)
                        Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if message.role == .assistant {
                        Spacer(minLength: 48)
                    }
                }
                .padding(.horizontal)
            }
        }
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = message.text
            }
        }
    }

    private var bubbleBackground: AnyShapeStyle {
        message.role == .user
            ? AnyShapeStyle(Color.accentColor)
            : AnyShapeStyle(Color.secondary.opacity(0.10))
    }
}

struct ThinkingRow: View {
    var body: some View {
        HStack(spacing: 10) {
            PocketLogoMark(size: 28)
            HStack(spacing: 5) {
                ProgressView().controlSize(.small)
                Text("Working on it…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
            Spacer()
        }
        .padding(.horizontal)
    }
}

struct ApprovalCard: View {
    let proposal: ToolProposal
    let approve: () -> Void
    let reject: () -> Void

    private var provider: ProviderDescriptor? {
        ProviderDescriptor.named(proposal.provider)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: cardSymbol)
                    .font(.title2)
                    .foregroundStyle(cardTint)
                    .frame(width: 44, height: 44)
                    .background(cardTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(proposal.kind == .schedule ? "Save this automation?" : "Ready to run")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(cardTint)
                    Text(proposal.title)
                        .font(.headline)
                }
                Spacer()
            }

            Text(proposal.summary)
                .font(.body)
                .foregroundStyle(.secondary)

            if let provider {
                Label(provider.name, systemImage: provider.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(provider.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(provider.tint.opacity(0.10), in: Capsule())
            }

            if !proposal.input.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(proposal.input.keys.sorted().enumerated()), id: \.element) { index, key in
                        HStack(alignment: .top) {
                            Text(key.pocketHumanizedKey)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 92, alignment: .leading)
                            Text(proposal.input[key] ?? "")
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(4)
                        }
                        .padding(.vertical, 8)
                        if index < proposal.input.count - 1 { Divider() }
                    }
                }
                .padding(.horizontal, 12)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            }

            Label("Nothing happens until you approve", systemImage: "hand.raised.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Not now", role: .cancel, action: reject)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                Button(proposal.kind == .schedule ? "Save automation" : "Run action", action: approve)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(cardTint.opacity(0.28)))
        .padding(.horizontal)
    }

    private var cardSymbol: String {
        switch proposal.kind {
        case .native: "iphone.gen3"
        case .service: provider?.symbol ?? "link"
        case .schedule: "calendar.badge.clock"
        }
    }

    private var cardTint: Color {
        switch proposal.kind {
        case .native: .blue
        case .service: provider?.tint ?? .indigo
        case .schedule: .purple
        }
    }
}

struct StatusBanner: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(text)
                .font(.callout)
            Spacer()
        }
        .padding(14)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// MARK: - Connections

struct ConnectionsView: View {
    @EnvironmentObject private var oauth: OAuthCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect your apps")
                        .font(.largeTitle.bold())
                    Text("PocketKernel opens each app’s official sign-in page. Your password never enters PocketKernel.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                if let error = oauth.errorText {
                    StatusBanner(text: error, symbol: "exclamationmark.triangle.fill", tint: .orange)
                        .padding(.horizontal, -16)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(ProviderDescriptor.all) { provider in
                        ProviderCard(
                            provider: provider,
                            connection: oauth.connections.first { $0.provider == provider.id },
                            configured: oauth.configured[provider.id] == true,
                            connect: { Task { await oauth.connect(provider.id) } },
                            disconnect: { Task { await oauth.disconnect(provider.id) } }
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Designed for privacy", systemImage: "lock.shield.fill")
                        .font(.headline)
                    Text("Planning stays on your iPhone. Connected services receive only the details needed for an action you approve or an automation you deliberately save.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(Color.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 20))
            }
            .padding()
        }
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await oauth.refresh() }
        .overlay { if oauth.isLoading { ProgressView() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }
}

struct ProviderCard: View {
    let provider: ProviderDescriptor
    let connection: ServiceConnection?
    let configured: Bool
    let connect: () -> Void
    let disconnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: provider.symbol)
                    .font(.title2)
                    .foregroundStyle(provider.tint)
                    .frame(width: 42, height: 42)
                    .background(provider.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                Spacer()
                if connection != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(provider.name)
                    .font(.headline)
                Text(provider.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(provider.benefit)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)

            if connection != nil {
                Menu {
                    Button("Disconnect", role: .destructive, action: disconnect)
                } label: {
                    Text("Connected")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.green)
            } else if configured {
                Button("Connect", action: connect)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            } else {
                Text("Coming soon")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .padding(15)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.secondary.opacity(0.12)))
    }
}

// MARK: - Automations

@MainActor
final class AutomationListModel: ObservableObject {
    @Published var items: [SavedAutomation] = []
    @Published var isLoading = false
    @Published var busyIDs: Set<String> = []
    @Published var errorText: String?

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await BackendClient.shared.automations()
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    func toggle(_ item: SavedAutomation) async {
        busyIDs.insert(item.id)
        defer { busyIDs.remove(item.id) }
        do {
            replace(try await BackendClient.shared.setAutomation(item.id, enabled: !item.enabled))
            errorText = nil
        } catch { errorText = error.localizedDescription }
    }

    func run(_ item: SavedAutomation) async {
        busyIDs.insert(item.id)
        defer { busyIDs.remove(item.id) }
        do {
            replace(try await BackendClient.shared.runAutomation(item.id))
            errorText = nil
        } catch { errorText = error.localizedDescription }
    }

    func delete(_ item: SavedAutomation) async {
        busyIDs.insert(item.id)
        defer { busyIDs.remove(item.id) }
        do {
            try await BackendClient.shared.deleteAutomation(item.id)
            items.removeAll { $0.id == item.id }
            errorText = nil
        } catch { errorText = error.localizedDescription }
    }

    private func replace(_ item: SavedAutomation) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.insert(item, at: 0)
        }
    }
}

enum AutomationFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case paused = "Paused"
    var id: String { rawValue }
}

struct AutomationsView: View {
    @StateObject private var model = AutomationListModel()
    @State private var filter: AutomationFilter = .all
    @State private var itemToDelete: SavedAutomation?
    let onCreate: () -> Void

    private var visibleItems: [SavedAutomation] {
        switch filter {
        case .all: model.items
        case .active: model.items.filter(\.enabled)
        case .paused: model.items.filter { !$0.enabled }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !model.items.isEmpty {
                        Picker("Filter", selection: $filter) {
                            ForEach(AutomationFilter.allCases) { item in
                                Text(item.rawValue).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                    }

                    if model.items.isEmpty && !model.isLoading {
                        EmptyAutomationsView(onCreate: onCreate)
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(visibleItems) { item in
                                AutomationCard(
                                    item: item,
                                    isBusy: model.busyIDs.contains(item.id),
                                    toggle: { Task { await model.toggle(item) } },
                                    run: { Task { await model.run(item) } },
                                    delete: { itemToDelete = item }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }

                    if let error = model.errorText {
                        StatusBanner(text: error, symbol: "exclamationmark.triangle.fill", tint: .orange)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Automations")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New", systemImage: "plus", action: onCreate)
                }
            }
            .task { await model.refresh() }
            .refreshable { await model.refresh() }
            .overlay { if model.isLoading { ProgressView() } }
            .confirmationDialog(
                "Delete this automation?",
                isPresented: Binding(
                    get: { itemToDelete != nil },
                    set: { if !$0 { itemToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let item = itemToDelete {
                        Task { await model.delete(item) }
                    }
                    itemToDelete = nil
                }
                Button("Cancel", role: .cancel) { itemToDelete = nil }
            }
        }
    }
}

struct EmptyAutomationsView: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.system(size: 52))
                .foregroundStyle(.purple)
                .padding(22)
                .background(Color.purple.opacity(0.11), in: Circle())
            VStack(spacing: 7) {
                Text("Put repeat work on autopilot")
                    .font(.title2.bold())
                Text("Ask PocketKernel to repeat a connected-app action on a schedule. You’ll review every detail before it is saved.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Create an automation", systemImage: "sparkles", action: onCreate)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(StarterTemplate.featured.filter { $0.category == .inbox || $0.category == .planning }.prefix(3)) { template in
                    Label(template.title, systemImage: template.symbol)
                        .font(.subheadline)
                }
            }
            .padding(16)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
        }
        .padding(28)
    }
}

struct AutomationCard: View {
    let item: SavedAutomation
    let isBusy: Bool
    let toggle: () -> Void
    let run: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.enabled ? "bolt.fill" : "pause.fill")
                    .foregroundStyle(item.enabled ? Color.purple : Color.secondary)
                    .frame(width: 42, height: 42)
                    .background((item.enabled ? Color.purple : Color.secondary).opacity(0.11), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                    Text(item.prompt)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer()
                Menu {
                    Button(item.enabled ? "Pause" : "Resume", systemImage: item.enabled ? "pause" : "play", action: toggle)
                    Button("Run now", systemImage: "play.fill", action: run)
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive, action: delete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .disabled(isBusy)
            }

            Divider()

            HStack {
                Label(item.enabled ? "Active" : "Paused", systemImage: item.enabled ? "checkmark.circle.fill" : "pause.circle.fill")
                    .foregroundStyle(item.enabled ? .green : .secondary)
                Spacer()
                if let next = PocketDateFormatter.friendly(item.nextRunAt), item.enabled {
                    Label(next, systemImage: "clock")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption.weight(.semibold))

            if let last = PocketDateFormatter.full(item.lastRunAt) {
                HStack(spacing: 7) {
                    Image(systemName: item.lastRunOK == false ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(item.lastRunOK == false ? .red : .green)
                    Text(item.lastRunOK == false ? "Last run failed · \(last)" : "Last ran \(last)")
                    Spacer()
                    if isBusy { ProgressView().controlSize(.small) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.secondary.opacity(0.12)))
    }
}

// MARK: - Activity

struct ActivityView: View {
    @EnvironmentObject private var chat: ChatController

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if chat.activity.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 54))
                                .foregroundStyle(.green)
                            Text("Your completed actions will appear here")
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)
                            Text("PocketKernel keeps a local history so you can see what ran and whether it succeeded.")
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(36)
                    } else {
                        ActivitySummary(items: chat.activity)
                            .padding(.horizontal)

                        LazyVStack(spacing: 12) {
                            ForEach(chat.activity) { item in
                                HStack(alignment: .top, spacing: 13) {
                                    Image(systemName: item.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(item.succeeded ? .green : .red)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.title).font(.headline)
                                        Text(item.detail)
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(8)
                                        Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                }
                                .padding(16)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Activity")
            .toolbar {
                if !chat.activity.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear", role: .destructive) { chat.clearActivity() }
                    }
                }
            }
        }
    }
}

struct ActivitySummary: View {
    let items: [ActivityItem]

    var body: some View {
        HStack(spacing: 12) {
            summaryTile(title: "Completed", value: String(items.filter(\.succeeded).count), tint: .green)
            summaryTile(title: "Needs attention", value: String(items.filter { !$0.succeeded }.count), tint: .orange)
        }
    }

    private func summaryTile(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title.bold())
                .foregroundStyle(tint)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Profile, privacy, and support

struct ProfileView: View {
    @EnvironmentObject private var chat: ChatController
    @EnvironmentObject private var oauth: OAuthCoordinator
    @AppStorage("didCompleteOnboarding.v2") private var didCompleteOnboarding = true
    @State private var serviceStatus = "Checking…"
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var errorText: String?
    let showOnboarding: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        PocketLogoMark(size: 52)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("PocketKernel")
                                .font(.title3.bold())
                            Text("Private automation on your iPhone")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Your apps") {
                    NavigationLink {
                        ConnectionsView()
                    } label: {
                        Label {
                            HStack {
                                Text("Connections")
                                Spacer()
                                Text("\(oauth.connections.count)")
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "link.circle.fill").foregroundStyle(.blue)
                        }
                    }
                }


                Section("Account") {
                    if let profile = account.profile {
                        LabeledContent("Signed in as", value: profile.displayName)
                        if let email = profile.email, !email.isEmpty {
                            LabeledContent("Email", value: email)
                        }
                        LabeledContent("Method", value: profile.provider.capitalized)
                    }
                    Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right") {
                        account.signOut()
                    }
                }

                Section("Privacy and control") {
                    Label("Planning stays on this iPhone", systemImage: "iphone.gen3.radiowaves.left.and.right")
                    Label("Approval before important actions", systemImage: "hand.raised.fill")
                    Link(destination: URL(string: "https://pocketkernel.vercel.app/privacy.html")!) {
                        Label("Privacy policy", systemImage: "lock.doc.fill")
                    }
                    Link(destination: URL(string: "https://pocketkernel.vercel.app/terms.html")!) {
                        Label("Terms of use", systemImage: "doc.text.fill")
                    }
                }

                Section("Help") {
                    Button {
                        didCompleteOnboarding = false
                        showOnboarding()
                    } label: {
                        Label("Replay introduction", systemImage: "play.rectangle.fill")
                    }
                    Link(destination: URL(string: "https://pocketkernel.vercel.app/support.html")!) {
                        Label("Help and support", systemImage: "questionmark.circle.fill")
                    }
                    LabeledContent("Automation service", value: serviceStatus)
                }

                Section("On this iPhone") {
                    Button("Start a new chat", systemImage: "square.and.pencil") { chat.reset() }
                    Button("Clear activity history", systemImage: "clock.arrow.circlepath") { chat.clearActivity() }
                }

                Section {
                    Button("Delete my PocketKernel data", systemImage: "trash", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .disabled(isDeleting)
                    if isDeleting {
                        HStack { ProgressView(); Text("Deleting your data…") }
                    }
                    if let errorText {
                        Text(errorText).foregroundStyle(.red).font(.caption)
                    }
                } footer: {
                    Text("This removes connected apps, saved automations, and local history. It cannot be undone.")
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Intelligence", value: "On-device")
                    LabeledContent("Tracking", value: "None")
                }
            }
            .navigationTitle("You")
            .task { await checkService() }
            .alert("Delete your PocketKernel data?", isPresented: $showDeleteConfirmation) {
                Button("Delete data", role: .destructive) {
                    Task { await deleteData() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Your connected apps, cloud automations, and local history will be removed.")
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.1"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func checkService() async {
        do { serviceStatus = try await BackendClient.shared.health() }
        catch { serviceStatus = "Unavailable" }
    }

    private func deleteData() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await BackendClient.shared.deleteAccount()
            account.finishDeletion()
            chat.clearAllLocalData()
            oauth.connections.removeAll()
            oauth.configured.removeAll()
            didCompleteOnboarding = false
            showOnboarding()
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Brand

struct PocketLogoMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.indigo, Color.blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: size * 0.62, height: size * 0.62)
            Image(systemName: "bolt.fill")
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.indigo.opacity(0.18), radius: size * 0.12, y: size * 0.05)
        .accessibilityHidden(true)
    }
}
