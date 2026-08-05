import SwiftUI

// The consumer shell separates status and quick actions from the full agent conversation.
enum PocketKernelMainTab: String, CaseIterable, Identifiable {
    case work
    case chat
    case routines
    case activity
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .work: "Work"
        case .chat: "Chat"
        case .routines: "Routines"
        case .activity: "Activity"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .work: "rectangle.grid.2x2.fill"
        case .chat: "bubble.left.and.bubble.right.fill"
        case .routines: "clock.arrow.2.circlepath"
        case .activity: "list.bullet.rectangle.portrait"
        case .settings: "gearshape.fill"
        }
    }
}

struct PocketKernelRootView: View {
    @EnvironmentObject private var oauth: OAuthCoordinator
    @State private var selected: PocketKernelMainTab = .work

    var body: some View {
        ZStack(alignment: .bottom) {
            NovaBackdrop()
            NovaGrain()

            Group {
                switch selected {
                case .work:
                    PocketKernelWorkView(
                        openChat: { selected = .chat },
                        openSettings: { selected = .settings }
                    )
                case .chat:
                    PocketKernelChatView(openSettings: { selected = .settings })
                case .routines:
                    AutomationsView(onCreate: { selected = .chat })
                case .activity:
                    RealityActivityView()
                case .settings:
                    RealitySettingsView(openWorkspace: { selected = .chat })
                }
            }
            .safeAreaPadding(.bottom, 82)
            .transition(.opacity)

            PocketKernelTabBar(selected: $selected)
        }
        .animation(.snappy(duration: 0.26), value: selected)
        .task { await oauth.refresh() }
    }
}

struct PocketKernelTabBar: View {
    @Binding var selected: PocketKernelMainTab

    var body: some View {
        HStack(spacing: 1) {
            ForEach(PocketKernelMainTab.allCases) { tab in
                Button {
                    selected = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 16, weight: .bold))
                        Text(tab.title)
                            .font(.system(size: 9, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selected == tab ? .white : .white.opacity(0.39))
                    .frame(maxWidth: .infinity)
                    .frame(height: 55)
                    .background {
                        if selected == tab {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(.white.opacity(0.10))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.11)))
        .shadow(color: .black.opacity(0.35), radius: 22, y: 10)
        .padding(.horizontal, 11)
        .padding(.bottom, 7)
    }
}

struct PocketKernelWorkView: View {
    @EnvironmentObject private var chat: ChatController
    @EnvironmentObject private var oauth: OAuthCoordinator
    @AppStorage("pocketkernel.chatDraft") private var chatDraft = ""

    let openChat: () -> Void
    let openSettings: () -> Void

    private let quickActions: [(symbol: String, title: String, detail: String, prompt: String)] = [
        (
            "checkmark.circle.fill",
            "Reminder",
            "Create it in Apple Reminders",
            "Create a reminder. Ask me for its text, date, and time before preparing it."
        ),
        (
            "calendar.badge.plus",
            "Calendar",
            "Add a real calendar event",
            "Create a calendar event. Ask me for the title, date, start time, and duration before preparing it."
        ),
        (
            "note.text.badge.plus",
            "Local note",
            "Save text on this iPhone",
            "Save a local note. Ask me what the note should say before preparing it."
        ),
        (
            "bell.badge.fill",
            "Notification",
            "Schedule a local alert",
            "Create a local notification. Ask me for its message and delivery time before preparing it."
        ),
        (
            "doc.on.clipboard.fill",
            "Clipboard",
            "Copy approved text",
            "Copy text to my clipboard. Ask me for the exact text before preparing the action."
        ),
        (
            "safari.fill",
            "Open link",
            "Open a secure website",
            "Open a website. Ask me for the HTTPS address before preparing the action."
        )
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    statusCard
                    metrics
                    quickActionsSection
                    recentActivity
                }
                .padding(.horizontal, 16)
                .padding(.top, 9)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            NovaKernelMark(size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("Work")
                    .font(.system(size: 29, weight: .black, design: .rounded))
                Text("Live state and actions that really run")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.46))
            }
            Spacer()
            Button(action: openSettings) {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
    }

    private var statusCard: some View {
        NovaGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: chat.readiness == .ready ? "sparkles" : chat.readiness.symbol)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(chat.readiness == .ready ? NovaPalette.mint : NovaPalette.warning)
                        .frame(width: 45, height: 45)
                        .background(
                            (chat.readiness == .ready ? NovaPalette.mint : NovaPalette.warning).opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 13)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(chat.readiness == .ready ? "PocketKernel is ready" : chat.readiness.title)
                            .font(.headline.weight(.black))
                        Text(chat.readiness == .ready
                             ? "Describe a task in Chat. PocketKernel prepares the exact action and waits for your approval."
                             : chat.readiness.detail)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.53))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                Button(action: openChat) {
                    Label(chat.hasConversation ? "Continue in Chat" : "Open Chat", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(NovaPalette.hero, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
        }
    }

    private var metrics: some View {
        HStack(spacing: 9) {
            workMetric(
                title: "Waiting",
                value: String(chat.pending.count),
                symbol: "hand.raised.fill",
                tint: NovaPalette.orchid
            )
            workMetric(
                title: "Completed",
                value: String(chat.activity.filter(\.succeeded).count),
                symbol: "checkmark.circle.fill",
                tint: NovaPalette.mint
            )
            workMetric(
                title: "Linked",
                value: String(oauth.connections.count),
                symbol: "link.circle.fill",
                tint: NovaPalette.electric
            )
        }
    }

    private func workMetric(title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol)
                .font(.caption.weight(.black))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 25, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.42))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.07)))
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Quick actions")
                    .font(.headline.weight(.black))
                Spacer()
                Text("REAL IPHONE ACTIONS")
                    .font(.system(size: 9, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.32))
            }
            .foregroundStyle(.white)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 9)], spacing: 9) {
                ForEach(Array(quickActions.enumerated()), id: \.offset) { _, action in
                    Button {
                        chatDraft = action.prompt
                        openChat()
                    } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            Image(systemName: action.symbol)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(NovaPalette.electric)
                                .frame(width: 35, height: 35)
                                .background(NovaPalette.electric.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                            Text(action.title)
                                .font(.subheadline.weight(.black))
                            Text(action.detail)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.42))
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 91, alignment: .leading)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.white.opacity(0.043), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var recentActivity: some View {
        if !chat.activity.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent activity")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                ForEach(Array(chat.activity.prefix(3))) { item in
                    NovaActivityRow(item: item)
                }
            }
        }
    }
}

struct PocketKernelChatView: View {
    @EnvironmentObject private var chat: ChatController
    @EnvironmentObject private var executor: ActionExecutor
    @EnvironmentObject private var oauth: OAuthCoordinator
    @AppStorage("pocketkernel.chatDraft") private var input = ""
    @FocusState private var isFocused: Bool

    let openSettings: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                chatHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 11)

                Divider().overlay(.white.opacity(0.08))

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 13) {
                            if !chat.hasConversation {
                                chatEmptyState
                            } else {
                                NovaConversationSection()
                                    .environmentObject(chat)
                                    .environmentObject(executor)
                            }

                            if let error = chat.errorText {
                                RealityNotice(
                                    symbol: "exclamationmark.triangle.fill",
                                    title: "Action paused",
                                    detail: error,
                                    tint: NovaPalette.warning
                                )
                            }

                            Color.clear.frame(height: 2).id("pocket-chat-bottom")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: chat.messages.count + chat.pending.count) { _, _ in
                        withAnimation(.snappy) {
                            proxy.scrollTo("pocket-chat-bottom", anchor: .bottom)
                        }
                    }
                }

                composer
                    .padding(.horizontal, 12)
                    .padding(.top, 7)
                    .padding(.bottom, 8)
                    .background(.black.opacity(0.14))
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var chatHeader: some View {
        HStack(spacing: 11) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(NovaPalette.hero, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text("Chat")
                    .font(.system(size: 25, weight: .black, design: .rounded))
                Text(chat.pending.isEmpty ? "Plan, review, then run" : "\(chat.pending.count) action awaiting approval")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.44))
            }
            Spacer()

            if chat.hasConversation {
                Button {
                    chat.reset()
                    input = ""
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New conversation")
            }

            Button(action: openSettings) {
                Image(systemName: "link")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Connections")
        }
        .foregroundStyle(.white)
    }

    private var chatEmptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Tell PocketKernel what to do.")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .tracking(-0.7)
                Text("It prepares a real action with exact values. Nothing executes until you approve it.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.51))
                    .lineSpacing(2)
            }

            RealityStatusPill(
                symbol: chat.readiness.symbol,
                text: chat.readiness == .ready ? "On-device model ready" : chat.readiness.title,
                tint: chat.readiness == .ready ? NovaPalette.mint : NovaPalette.warning
            )

            if oauth.connections.isEmpty {
                RealityNotice(
                    symbol: "iphone.gen3",
                    title: "Native actions are ready",
                    detail: "Reminders, Calendar, notifications, local notes, clipboard, and secure links work without connecting an external service.",
                    tint: NovaPalette.electric
                )
            } else {
                RealityNotice(
                    symbol: "link.circle.fill",
                    title: "\(oauth.connections.count) service\(oauth.connections.count == 1 ? "" : "s") linked",
                    detail: "Service actions are offered only for providers that the server confirms are configured and connected.",
                    tint: NovaPalette.mint
                )
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(
                chat.readiness == .ready ? "Message PocketKernel…" : "On-device model unavailable",
                text: $input,
                axis: .vertical
            )
            .lineLimit(1...5)
            .font(.body.weight(.medium))
            .foregroundStyle(.white)
            .focused($isFocused)
            .disabled(chat.readiness != .ready || chat.isThinking)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(isFocused ? 0.17 : 0.07)))

            Button {
                Task { await send() }
            } label: {
                Group {
                    if chat.isThinking {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.headline.weight(.black))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(canSend ? AnyShapeStyle(NovaPalette.hero) : AnyShapeStyle(.white.opacity(0.08)), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .onAppear {
            if !input.isEmpty {
                isFocused = true
            }
        }
    }

    private var canSend: Bool {
        chat.readiness == .ready &&
        !chat.isThinking &&
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() async {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        input = ""
        isFocused = false
        await chat.send(prompt)
    }
}
