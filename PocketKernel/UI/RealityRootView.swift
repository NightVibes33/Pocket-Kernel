import SwiftUI

// A compact application shell that surfaces only live state and working actions.
enum RealityTab: String, CaseIterable, Identifiable {
    case workspace
    case routines
    case activity
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace: "Work"
        case .routines: "Routines"
        case .activity: "Activity"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .workspace: "bubble.left.and.sparkles.fill"
        case .routines: "clock.arrow.2.circlepath"
        case .activity: "list.bullet.rectangle.portrait"
        case .settings: "gearshape.fill"
        }
    }
}

struct RealityRootView: View {
    @EnvironmentObject private var oauth: OAuthCoordinator
    @State private var selected: RealityTab = .workspace

    var body: some View {
        ZStack(alignment: .bottom) {
            NovaBackdrop()
            NovaGrain()

            Group {
                switch selected {
                case .workspace:
                    RealityWorkspaceView(openSettings: { selected = .settings })
                case .routines:
                    AutomationsView(onCreate: { selected = .workspace })
                case .activity:
                    RealityActivityView()
                case .settings:
                    RealitySettingsView(openWorkspace: { selected = .workspace })
                }
            }
            .safeAreaPadding(.bottom, 82)
            .transition(.opacity)

            RealityTabBar(selected: $selected)
        }
        .animation(.snappy(duration: 0.26), value: selected)
        .task { await oauth.refresh() }
    }
}

struct RealityTabBar: View {
    @Binding var selected: RealityTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(RealityTab.allCases) { tab in
                Button {
                    selected = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 17, weight: .bold))
                        Text(tab.title)
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(selected == tab ? .white : .white.opacity(0.42))
                    .frame(maxWidth: .infinity)
                    .frame(height: 55)
                    .background {
                        if selected == tab {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.white.opacity(0.09))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.11)))
        .shadow(color: .black.opacity(0.35), radius: 22, y: 10)
        .padding(.horizontal, 13)
        .padding(.bottom, 7)
    }
}

struct RealityWorkspaceView: View {
    @EnvironmentObject private var chat: ChatController
    @EnvironmentObject private var executor: ActionExecutor
    @EnvironmentObject private var oauth: OAuthCoordinator
    @State private var input = ""
    @FocusState private var isFocused: Bool

    let openSettings: () -> Void

    private let nativeStarts: [(String, String, String)] = [
        ("checkmark.circle.fill", "Reminder", "Create a reminder for tomorrow. Ask me for the text and time first."),
        ("calendar.badge.plus", "Calendar", "Create a calendar event. Ask me for its title, date, start time, and duration first."),
        ("bell.badge.fill", "Notification", "Prepare a local notification that says PocketKernel is working."),
        ("note.text.badge.plus", "Local note", "Save a local note. Ask me what the note should say first."),
        ("doc.on.clipboard.fill", "Clipboard", "Copy text to my clipboard. Ask me for the text first."),
        ("safari.fill", "Open link", "Open an HTTPS link. Ask me for the address first.")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                workspaceHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                Divider().overlay(.white.opacity(0.08))

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 13) {
                            if !chat.hasConversation {
                                emptyWorkspace
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

                            Color.clear.frame(height: 2).id("reality-bottom")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: chat.messages.count + chat.pending.count) { _, _ in
                        withAnimation(.snappy) {
                            proxy.scrollTo("reality-bottom", anchor: .bottom)
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

    private var workspaceHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 11) {
                NovaKernelMark(size: 43)
                VStack(alignment: .leading, spacing: 2) {
                    Text("PocketKernel")
                        .font(.system(size: 23, weight: .black, design: .rounded))
                    Text("Review every action before it runs")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.46))
                }
                Spacer()
                Button(action: openSettings) {
                    Label("\(oauth.connections.count)", systemImage: "link")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(.white.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    RealityStatusPill(
                        symbol: chat.readiness.symbol,
                        text: chat.readiness == .ready ? "On-device model ready" : chat.readiness.title,
                        tint: chat.readiness == .ready ? NovaPalette.mint : NovaPalette.warning
                    )
                    RealityStatusPill(
                        symbol: oauth.connections.isEmpty ? "link.badge.plus" : "link.circle.fill",
                        text: oauth.connections.isEmpty ? "No services linked" : "\(oauth.connections.count) linked",
                        tint: oauth.connections.isEmpty ? .white.opacity(0.48) : NovaPalette.electric
                    )
                    if !chat.pending.isEmpty {
                        RealityStatusPill(
                            symbol: "hand.raised.fill",
                            text: "\(chat.pending.count) awaiting approval",
                            tint: NovaPalette.orchid
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(.white)
    }

    private var emptyWorkspace: some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What needs doing?")
                    .font(.system(size: 31, weight: .black, design: .rounded))
                    .tracking(-0.8)
                Text("These starters map to native actions already implemented in the app. Service actions appear only after a provider is actually configured and linked.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.52))
                    .lineSpacing(2)
            }

            if chat.readiness != .ready {
                RealityNotice(
                    symbol: chat.readiness.symbol,
                    title: chat.readiness.title,
                    detail: chat.readiness.detail,
                    tint: NovaPalette.warning
                )
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 9)], spacing: 9) {
                ForEach(Array(nativeStarts.enumerated()), id: \.offset) { _, item in
                    Button {
                        input = item.2
                        isFocused = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.0)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(NovaPalette.electric)
                                .frame(width: 34, height: 34)
                                .background(NovaPalette.electric.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                            Text(item.1)
                                .font(.subheadline.weight(.bold))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.white)
                        .padding(11)
                        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                }
            }

            RealityNotice(
                symbol: "hand.raised.fill",
                title: "Nothing runs silently",
                detail: "PocketKernel first shows the exact action and values. You choose Run action, Save automation, or Cancel.",
                tint: NovaPalette.mint
            )
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(
                chat.readiness == .ready ? "Describe a real action…" : "On-device model unavailable",
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

struct RealityActivityView: View {
    @EnvironmentObject private var chat: ChatController

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RealityScreenHeader(
                    title: "Activity",
                    detail: chat.activity.isEmpty ? "No completed actions" : "\(chat.activity.count) local records",
                    symbol: "list.bullet.rectangle.portrait"
                ) {
                    if !chat.activity.isEmpty {
                        Button(role: .destructive) { chat.clearActivity() } label: {
                            Image(systemName: "trash")
                                .font(.subheadline.weight(.bold))
                                .frame(width: 36, height: 36)
                                .background(.white.opacity(0.06), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                ScrollView {
                    LazyVStack(spacing: 9) {
                        if chat.activity.isEmpty {
                            RealityNotice(
                                symbol: "checkmark.circle",
                                title: "Nothing has run yet",
                                detail: "This list contains only actions that completed or failed. It does not contain example activity.",
                                tint: NovaPalette.mint
                            )
                        } else {
                            ForEach(chat.activity) { item in
                                NovaActivityRow(item: item)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct RealitySettingsView: View {
    @EnvironmentObject private var chat: ChatController
    @EnvironmentObject private var oauth: OAuthCoordinator
    @State private var serviceStatus = "Checking service"

    let openWorkspace: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 13) {
                    RealityScreenHeader(
                        title: "Settings",
                        detail: "Live configuration and local data",
                        symbol: "gearshape.fill"
                    ) { EmptyView() }

                    NavigationLink {
                        ConnectionsView()
                    } label: {
                        settingsRow(
                            symbol: "point.3.connected.trianglepath.dotted",
                            tint: NovaPalette.electric,
                            title: "Connections",
                            detail: oauth.connections.isEmpty ? "No services linked" : "\(oauth.connections.count) linked services",
                            accessory: "chevron.right"
                        )
                    }
                    .buttonStyle(.plain)

                    RealityNotice(
                        symbol: serviceStatus == "Online" ? "checkmark.circle.fill" : "icloud.slash.fill",
                        title: "Cloud service: \(serviceStatus)",
                        detail: configuredProviderText,
                        tint: serviceStatus == "Online" ? NovaPalette.mint : NovaPalette.warning
                    )

                    VStack(spacing: 0) {
                        Button {
                            chat.reset()
                            openWorkspace()
                        } label: {
                            settingsRow(
                                symbol: "square.and.pencil",
                                tint: NovaPalette.electric,
                                title: "New conversation",
                                detail: "Clear the current workspace",
                                accessory: ""
                            )
                        }
                        .buttonStyle(.plain)

                        Divider().overlay(.white.opacity(0.07)).padding(.leading, 58)

                        Button { chat.clearActivity() } label: {
                            settingsRow(
                                symbol: "clock.arrow.circlepath",
                                tint: NovaPalette.orchid,
                                title: "Clear activity",
                                detail: "Remove local action records",
                                accessory: ""
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.07)))

                    RealityNotice(
                        symbol: "lock.shield.fill",
                        title: "No account required",
                        detail: "The app opens directly. Native planning stays on this iPhone. Connected providers receive data only for actions you explicitly approve.",
                        tint: NovaPalette.mint
                    )

                    Text(versionText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.30))
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                do { serviceStatus = try await BackendClient.shared.health() }
                catch { serviceStatus = "Unavailable" }
            }
            .refreshable {
                await oauth.refresh()
                do { serviceStatus = try await BackendClient.shared.health() }
                catch { serviceStatus = "Unavailable" }
            }
        }
    }

    private var configuredProviderText: String {
        let configured = ProviderDescriptor.all.filter { oauth.configured[$0.id] == true }.map(\.name)
        return configured.isEmpty
            ? "No external provider is configured on the server. Native iPhone actions remain available."
            : "Configured providers: \(configured.joined(separator: ", "))."
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "PocketKernel \(version) (\(build))"
    }

    private func settingsRow(
        symbol: String,
        tint: Color,
        title: String,
        detail: String,
        accessory: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.bold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.43))
                    .lineLimit(2)
            }
            Spacer()
            if !accessory.isEmpty {
                Image(systemName: accessory)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.24))
            }
        }
        .foregroundStyle(.white)
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.07)))
    }
}

struct RealityScreenHeader<Trailing: View>: View {
    let title: String
    let detail: String
    let symbol: String
    @ViewBuilder let trailing: Trailing

    init(
        title: String,
        detail: String,
        symbol: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(NovaPalette.hero, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 25, weight: .black, design: .rounded))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.44))
            }
            Spacer()
            trailing
        }
        .foregroundStyle(.white)
    }
}

struct RealityStatusPill: View {
    let symbol: String
    let text: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .frame(height: 27)
            .background(tint.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.13)))
    }
}

struct RealityNotice: View {
    let symbol: String
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.49))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(.white.opacity(0.043), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.07)))
    }
}
