import SwiftUI

// MARK: - Redesigned automations

struct NovaAutomationsView: View {
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
                VStack(spacing: 18) {
                    NovaSectionHero(
                        eyebrow: "AUTOMATION VAULT",
                        title: "Your routines, alive.",
                        detail: "Every saved workflow stays visible, controllable, and one tap away.",
                        symbol: "bolt.horizontal.circle.fill",
                        value: String(model.items.filter(\.enabled).count),
                        valueLabel: "active"
                    )

                    if !model.items.isEmpty {
                        NovaFilterBar(selection: $filter)
                    }

                    if model.items.isEmpty && !model.isLoading {
                        NovaEmptyAutomationCard(onCreate: onCreate)
                    } else {
                        LazyVStack(spacing: 13) {
                            ForEach(visibleItems) { item in
                                NovaAutomationCard(
                                    item: item,
                                    isBusy: model.busyIDs.contains(item.id),
                                    toggle: { Task { await model.toggle(item) } },
                                    run: { Task { await model.run(item) } },
                                    delete: { itemToDelete = item }
                                )
                            }
                        }
                    }

                    if let error = model.errorText {
                        NovaInlineNotice(
                            symbol: "exclamationmark.triangle.fill",
                            title: "Automations unavailable",
                            detail: error
                        )
                    }
                }
                .padding(.horizontal, 17)
                .padding(.top, 10)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
            .toolbar(.hidden, for: .navigationBar)
            .overlay {
                if model.isLoading && model.items.isEmpty {
                    ProgressView()
                        .tint(.white)
                        .padding(18)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .confirmationDialog(
                "Delete this automation?",
                isPresented: Binding(
                    get: { itemToDelete != nil },
                    set: { if !$0 { itemToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    guard let item = itemToDelete else { return }
                    Task { await model.delete(item) }
                    itemToDelete = nil
                }
                Button("Cancel", role: .cancel) { itemToDelete = nil }
            }
        }
    }
}

struct NovaFilterBar: View {
    @Binding var selection: AutomationFilter
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 5) {
            ForEach(AutomationFilter.allCases) { filter in
                Button {
                    selection = filter
                } label: {
                    Text(filter.rawValue)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(selection == filter ? .white : .white.opacity(0.48))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background {
                            if selection == filter {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(NovaPalette.hero)
                                    .matchedGeometryEffect(id: "filter", in: indicator)
                                    .shadow(color: NovaPalette.violet.opacity(0.42), radius: 12, y: 6)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.09)))
        .animation(.snappy(duration: 0.28), value: selection)
    }
}

struct NovaEmptyAutomationCard: View {
    let onCreate: () -> Void

    var body: some View {
        NovaGlassCard {
            VStack(spacing: 19) {
                ZStack {
                    Circle()
                        .fill(NovaPalette.violet.opacity(0.18))
                        .frame(width: 112, height: 112)
                        .blur(radius: 8)
                    Image(systemName: "clock.arrow.trianglehead.2.counterclockwise.rotate.90")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(NovaPalette.hero)
                }

                VStack(spacing: 7) {
                    Text("Nothing repeating yet")
                        .font(.title2.weight(.black))
                    Text("Turn an everyday request into a routine that runs exactly when you choose.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }

                Button("Create your first automation", action: onCreate)
                    .buttonStyle(NovaPrimaryButtonStyle())

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(StarterTemplate.featured.prefix(3)) { template in
                        HStack(spacing: 11) {
                            Image(systemName: template.symbol)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(template.tint, in: RoundedRectangle(cornerRadius: 9))
                            Text(template.title)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                    }
                }
                .padding(14)
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 17))
            }
            .foregroundStyle(.white)
        }
    }
}

struct NovaAutomationCard: View {
    let item: SavedAutomation
    let isBusy: Bool
    let toggle: () -> Void
    let run: () -> Void
    let delete: () -> Void

    var body: some View {
        NovaGlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top, spacing: 13) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(item.enabled ? NovaPalette.hero : LinearGradient(colors: [.white.opacity(0.13), .white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: item.enabled ? "bolt.fill" : "pause.fill")
                            .font(.headline.weight(.black))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 46, height: 46)
                    .shadow(color: item.enabled ? NovaPalette.violet.opacity(0.42) : .clear, radius: 12, y: 6)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(item.enabled ? NovaPalette.mint : .white.opacity(0.34))
                                .frame(width: 7, height: 7)
                            Text(item.enabled ? "LIVE" : "PAUSED")
                                .font(.caption2.weight(.black))
                                .tracking(1.2)
                                .foregroundStyle(item.enabled ? NovaPalette.mint : .white.opacity(0.42))
                        }
                        Text(item.title)
                            .font(.headline.weight(.black))
                        Text(item.prompt)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.52))
                            .lineLimit(3)
                    }

                    Spacer(minLength: 4)

                    Menu {
                        Button(item.enabled ? "Pause" : "Resume", systemImage: item.enabled ? "pause" : "play", action: toggle)
                        Button("Run now", systemImage: "play.fill", action: run)
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive, action: delete)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white.opacity(0.62))
                            .frame(width: 38, height: 38)
                            .background(.white.opacity(0.07), in: Circle())
                    }
                    .disabled(isBusy)
                }

                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)

                HStack(spacing: 10) {
                    if let next = PocketDateFormatter.friendly(item.nextRunAt), item.enabled {
                        NovaMetadataPill(symbol: "clock.fill", text: next, tint: NovaPalette.electric)
                    } else {
                        NovaMetadataPill(symbol: "pause.fill", text: "Not scheduled", tint: .white.opacity(0.5))
                    }

                    if let last = PocketDateFormatter.full(item.lastRunAt) {
                        NovaMetadataPill(
                            symbol: item.lastRunOK == false ? "xmark" : "checkmark",
                            text: last,
                            tint: item.lastRunOK == false ? NovaPalette.warning : NovaPalette.mint
                        )
                    }

                    Spacer(minLength: 0)
                    if isBusy { ProgressView().tint(.white) }

                    Button(action: run) {
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(NovaPalette.hero, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                }
            }
            .foregroundStyle(.white)
        }
    }
}

struct NovaMetadataPill: View {
    let symbol: String
    let text: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(tint.opacity(0.10), in: Capsule())
            .lineLimit(1)
    }
}

// MARK: - Redesigned activity

struct NovaActivityView: View {
    @EnvironmentObject private var chat: ChatController

    private var succeeded: Int { chat.activity.filter(\.succeeded).count }
    private var failed: Int { chat.activity.count - succeeded }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    NovaSectionHero(
                        eyebrow: "LIVE HISTORY",
                        title: "Everything that happened.",
                        detail: "A clear, local record of what PocketKernel ran and what needs attention.",
                        symbol: "waveform.path.ecg",
                        value: String(chat.activity.count),
                        valueLabel: "events"
                    )

                    HStack(spacing: 11) {
                        NovaMetricCard(title: "Completed", value: String(succeeded), symbol: "checkmark", tint: NovaPalette.mint)
                        NovaMetricCard(title: "Needs attention", value: String(failed), symbol: "exclamationmark", tint: NovaPalette.warning)
                    }

                    if chat.activity.isEmpty {
                        NovaGlassCard {
                            VStack(spacing: 16) {
                                Image(systemName: "waveform.path.ecg.rectangle")
                                    .font(.system(size: 44, weight: .bold))
                                    .foregroundStyle(NovaPalette.hero)
                                Text("Your activity is quiet")
                                    .font(.title2.weight(.black))
                                Text("Completed actions and automation runs will appear here with their exact result.")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.54))
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                            .foregroundStyle(.white)
                        }
                    } else {
                        LazyVStack(spacing: 11) {
                            ForEach(chat.activity) { item in
                                NovaActivityRow(item: item)
                            }
                        }

                        Button(role: .destructive) {
                            chat.clearActivity()
                        } label: {
                            Label("Clear local activity", systemImage: "trash")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(NovaPalette.warning)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(NovaPalette.warning.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 17)
                .padding(.top, 10)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct NovaMetricCard: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol)
                    .font(.caption.weight(.black))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                Spacer()
                Text(value)
                    .font(.system(size: 28, weight: .black, design: .rounded))
            }
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.48))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.09)))
    }
}

struct NovaActivityRow: View {
    let item: ActivityItem

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: item.succeeded ? "checkmark" : "xmark")
                .font(.caption.weight(.black))
                .foregroundStyle(item.succeeded ? NovaPalette.mint : NovaPalette.warning)
                .frame(width: 38, height: 38)
                .background(
                    (item.succeeded ? NovaPalette.mint : NovaPalette.warning).opacity(0.11),
                    in: RoundedRectangle(cornerRadius: 12)
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.subheadline.weight(.black))
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.51))
                    .lineLimit(6)
                Text(item.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.31))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(15)
        .background(.white.opacity(0.052), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(.white.opacity(0.08)))
    }
}

// MARK: - Redesigned profile and connections

struct NovaProfileView: View {
    @EnvironmentObject private var chat: ChatController
    @EnvironmentObject private var oauth: OAuthCoordinator
    @EnvironmentObject private var account: AccountController
    @AppStorage("didCompleteOnboarding.v3") private var didCompleteOnboarding = true
    @State private var serviceStatus = "Checking"
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var errorText: String?
    let showOnboarding: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    NovaProfileHero(profile: account.profile, connectedCount: oauth.connections.count)

                    NovaGlassCard(padding: 0) {
                        VStack(spacing: 0) {
                            NavigationLink {
                                NovaConnectionsView()
                            } label: {
                                NovaSettingsRow(
                                    symbol: "point.3.connected.trianglepath.dotted",
                                    tint: NovaPalette.electric,
                                    title: "Connections",
                                    detail: "\(oauth.connections.count) linked services",
                                    accessory: .chevron
                                )
                            }
                            .buttonStyle(.plain)

                            NovaRowDivider()

                            Button {
                                didCompleteOnboarding = false
                                showOnboarding()
                            } label: {
                                NovaSettingsRow(
                                    symbol: "play.rectangle.fill",
                                    tint: NovaPalette.orchid,
                                    title: "Replay introduction",
                                    detail: "See how PocketKernel works",
                                    accessory: .chevron
                                )
                            }
                            .buttonStyle(.plain)

                            NovaRowDivider()

                            Link(destination: URL(string: "https://pocketkernel.vercel.app/support.html")!) {
                                NovaSettingsRow(
                                    symbol: "questionmark.circle.fill",
                                    tint: NovaPalette.mint,
                                    title: "Help and support",
                                    detail: serviceStatus,
                                    accessory: .external
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    NovaGlassCard(padding: 0) {
                        VStack(spacing: 0) {
                            Link(destination: URL(string: "https://pocketkernel.vercel.app/privacy.html")!) {
                                NovaSettingsRow(
                                    symbol: "lock.shield.fill",
                                    tint: NovaPalette.mint,
                                    title: "Privacy policy",
                                    detail: "Private planning, no tracking",
                                    accessory: .external
                                )
                            }
                            .buttonStyle(.plain)

                            NovaRowDivider()

                            Link(destination: URL(string: "https://pocketkernel.vercel.app/terms.html")!) {
                                NovaSettingsRow(
                                    symbol: "doc.text.fill",
                                    tint: NovaPalette.electric,
                                    title: "Terms of use",
                                    detail: "Your rights and responsibilities",
                                    accessory: .external
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    NovaGlassCard(padding: 0) {
                        VStack(spacing: 0) {
                            Button { chat.reset() } label: {
                                NovaSettingsRow(
                                    symbol: "square.and.pencil",
                                    tint: NovaPalette.electric,
                                    title: "Start a new conversation",
                                    detail: "Clear the current chat",
                                    accessory: .none
                                )
                            }
                            .buttonStyle(.plain)

                            NovaRowDivider()

                            Button { chat.clearActivity() } label: {
                                NovaSettingsRow(
                                    symbol: "clock.arrow.circlepath",
                                    tint: NovaPalette.orchid,
                                    title: "Clear activity history",
                                    detail: "Remove local action records",
                                    accessory: .none
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        account.signOut()
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack(spacing: 9) {
                            if isDeleting { ProgressView().tint(NovaPalette.warning) }
                            Image(systemName: "trash")
                            Text(isDeleting ? "Deleting your data…" : "Delete PocketKernel data")
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(NovaPalette.warning)
                    }
                    .disabled(isDeleting)

                    if let errorText {
                        NovaInlineNotice(
                            symbol: "exclamationmark.triangle.fill",
                            title: "Couldn’t delete data",
                            detail: errorText
                        )
                    }

                    Text("PocketKernel \(appVersion)  •  On-device intelligence  •  No tracking")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.31))
                        .padding(.top, 3)
                }
                .padding(.horizontal, 17)
                .padding(.top, 10)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .task { await checkService() }
            .alert("Delete your PocketKernel data?", isPresented: $showDeleteConfirmation) {
                Button("Delete data", role: .destructive) { Task { await deleteData() } }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Your connected apps, cloud automations, and local history will be removed. This cannot be undone.")
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.2"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "3"
        return "\(version) (\(build))"
    }

    private func checkService() async {
        do { serviceStatus = try await BackendClient.shared.health() }
        catch { serviceStatus = "Service unavailable" }
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

struct NovaProfileHero: View {
    let profile: AccountProfile?
    let connectedCount: Int

    var body: some View {
        NovaGlassCard {
            HStack(spacing: 15) {
                ZStack {
                    NovaKernelMark(size: 70)
                    Text(initials)
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.white)
                        .frame(width: 27, height: 27)
                        .background(NovaPalette.hero, in: Circle())
                        .offset(x: 25, y: 25)
                        .overlay(Circle().stroke(NovaPalette.ink, lineWidth: 3).frame(width: 27, height: 27).offset(x: 25, y: 25))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(profile?.displayName ?? "PocketKernel user")
                        .font(.title2.weight(.black))
                    Text(profile?.email ?? "Private account")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.50))
                    HStack(spacing: 8) {
                        NovaMetadataPill(symbol: "checkmark.shield.fill", text: (profile?.provider ?? "account").capitalized, tint: NovaPalette.mint)
                        NovaMetadataPill(symbol: "link", text: "\(connectedCount) linked", tint: NovaPalette.electric)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
        }
    }

    private var initials: String {
        let name = profile?.displayName ?? "PK"
        let parts = name.split(separator: " ")
        return parts.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

enum NovaSettingsAccessory {
    case none
    case chevron
    case external
}

struct NovaSettingsRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let accessory: NovaSettingsAccessory

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.43))
                    .lineLimit(1)
            }
            Spacer()
            switch accessory {
            case .none:
                EmptyView()
            case .chevron:
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.25))
            case .external:
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 67)
    }
}

struct NovaRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.07))
            .frame(height: 1)
            .padding(.leading, 66)
    }
}

struct NovaConnectionsView: View {
    @EnvironmentObject private var oauth: OAuthCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            NovaBackdrop()
            NovaGrain()

            ScrollView {
                VStack(spacing: 18) {
                    NovaSectionHero(
                        eyebrow: "CONNECTED WORLD",
                        title: "Bring your apps together.",
                        detail: "Official sign-in only. PocketKernel never sees or stores your passwords.",
                        symbol: "point.3.connected.trianglepath.dotted",
                        value: String(oauth.connections.count),
                        valueLabel: "linked"
                    )

                    if let error = oauth.errorText {
                        NovaInlineNotice(
                            symbol: "exclamationmark.triangle.fill",
                            title: "Connection failed",
                            detail: error
                        )
                    }

                    LazyVStack(spacing: 11) {
                        ForEach(ProviderDescriptor.all) { provider in
                            NovaProviderRow(
                                provider: provider,
                                connection: oauth.connections.first { $0.provider == provider.id },
                                configured: oauth.configured[provider.id] == true,
                                connect: { Task { await oauth.connect(provider.id) } },
                                disconnect: { Task { await oauth.disconnect(provider.id) } }
                            )
                        }
                    }

                    NovaGlassCard {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "lock.shield.fill")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(NovaPalette.mint)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Designed for privacy")
                                    .font(.headline.weight(.black))
                                Text("Connected services receive only the details needed for an action you approve or an automation you deliberately save.")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.51))
                            }
                        }
                        .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 17)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .refreshable { await oauth.refresh() }
            .overlay {
                if oauth.isLoading {
                    ProgressView().tint(.white)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Connections").font(.headline.weight(.black)).foregroundStyle(.white)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(NovaPalette.electric)
            }
        }
    }
}

struct NovaProviderRow: View {
    let provider: ProviderDescriptor
    let connection: ServiceConnection?
    let configured: Bool
    let connect: () -> Void
    let disconnect: () -> Void

    var body: some View {
        NovaGlassCard(padding: 15) {
            HStack(spacing: 13) {
                Image(systemName: provider.symbol)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(
                        LinearGradient(
                            colors: [provider.tint, provider.tint.opacity(0.48)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.name)
                        .font(.headline.weight(.black))
                    Text(provider.benefit)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(2)
                }

                Spacer(minLength: 6)

                if connection != nil {
                    Menu {
                        Button("Disconnect", role: .destructive, action: disconnect)
                    } label: {
                        Label("Linked", systemImage: "checkmark")
                            .font(.caption.weight(.black))
                            .foregroundStyle(NovaPalette.mint)
                            .padding(.horizontal, 11)
                            .frame(height: 34)
                            .background(NovaPalette.mint.opacity(0.10), in: Capsule())
                    }
                } else if configured {
                    Button("Connect", action: connect)
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .frame(height: 36)
                        .background(NovaPalette.hero, in: Capsule())
                        .buttonStyle(.plain)
                } else {
                    Text("SETUP")
                        .font(.caption2.weight(.black))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.34))
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(.white.opacity(0.06), in: Capsule())
                }
            }
            .foregroundStyle(.white)
        }
    }
}

// MARK: - Shared secondary-screen hero

struct NovaSectionHero: View {
    let eyebrow: String
    let title: String
    let detail: String
    let symbol: String
    let value: String
    let valueLabel: String

    var body: some View {
        NovaGlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    Image(systemName: symbol)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(NovaPalette.hero, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: NovaPalette.violet.opacity(0.5), radius: 16, y: 8)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(value)
                            .font(.system(size: 30, weight: .black, design: .rounded))
                        Text(valueLabel.uppercased())
                            .font(.caption2.weight(.black))
                            .tracking(1.1)
                            .foregroundStyle(.white.opacity(0.38))
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(eyebrow)
                        .font(.caption2.weight(.black))
                        .tracking(1.5)
                        .foregroundStyle(NovaPalette.electric)
                    Text(title)
                        .font(.system(size: 29, weight: .black, design: .rounded))
                        .tracking(-0.8)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.53))
                        .lineSpacing(3)
                }
            }
            .foregroundStyle(.white)
        }
    }
}
