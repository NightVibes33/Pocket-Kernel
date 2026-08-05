import SwiftUI
import Foundation
import FoundationModels
import AuthenticationServices
import GoogleSignInSwift
import Security
import UserNotifications
import EventKit
import UIKit

@main
struct PocketKernelApp: App {
    @StateObject private var chat = ChatController()
    @StateObject private var executor = ActionExecutor()
    @StateObject private var oauth = OAuthCoordinator()
    @StateObject private var account = AccountController()

    init() {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithTransparentBackground()
        navigation.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        navigation.titleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation

        let tab = UITabBarAppearance()
        tab.configureWithTransparentBackground()
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }

    var body: some Scene {
        WindowGroup {
            NovaEntryView()
                .environmentObject(chat)
                .environmentObject(executor)
                .environmentObject(oauth)
                .environmentObject(account)
                .preferredColorScheme(.dark)
                .tint(NovaPalette.electric)
                .onOpenURL { _ in Task { await oauth.refresh() } }
        }
    }
}

// MARK: - Brand system

enum NovaPalette {
    static let ink = Color(red: 0.018, green: 0.024, blue: 0.067)
    static let raised = Color(red: 0.045, green: 0.055, blue: 0.125)
    static let violet = Color(red: 0.46, green: 0.26, blue: 1.0)
    static let electric = Color(red: 0.15, green: 0.82, blue: 1.0)
    static let orchid = Color(red: 0.78, green: 0.38, blue: 1.0)
    static let mint = Color(red: 0.34, green: 1.0, blue: 0.77)
    static let warning = Color(red: 1.0, green: 0.59, blue: 0.38)

    static let hero = LinearGradient(
        colors: [electric, Color(red: 0.45, green: 0.36, blue: 1), orchid],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct NovaBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(NovaPalette.ink))

                let sources: [(Color, CGFloat, CGFloat, CGFloat, Double)] = [
                    (NovaPalette.violet.opacity(0.34), 0.22, 0.22, 0.42, 0.11),
                    (NovaPalette.electric.opacity(0.22), 0.82, 0.28, 0.34, -0.09),
                    (NovaPalette.orchid.opacity(0.20), 0.56, 0.82, 0.38, 0.075)
                ]

                context.addFilter(.blur(radius: min(size.width, size.height) * 0.12))
                for (index, source) in sources.enumerated() {
                    let (color, x, y, radiusFactor, speed) = source
                    let radius = min(size.width, size.height) * radiusFactor
                    let phase = t * speed + Double(index) * 2.1
                    let point = CGPoint(
                        x: size.width * x + cos(phase) * size.width * 0.08,
                        y: size.height * y + sin(phase * 0.8) * size.height * 0.07
                    )
                    let rect = CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct NovaGrain: View {
    var body: some View {
        Canvas { context, size in
            var generator = SeededGenerator(seed: 0x5EED)
            for _ in 0..<480 {
                let x = CGFloat.random(in: 0...size.width, using: &generator)
                let y = CGFloat.random(in: 0...size.height, using: &generator)
                let alpha = Double.random(in: 0.015...0.045, using: &generator)
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)),
                    with: .color(.white.opacity(alpha))
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .blendMode(.softLight)
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}

struct NovaKernelMark: View {
    var size: CGFloat
    var animate = true
    @State private var rotation = 0.0
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            NovaPalette.raised.opacity(0.9),
                            NovaPalette.ink.opacity(0.92)
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size * 0.66
                    )
                )
                .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
                .shadow(color: NovaPalette.violet.opacity(0.55), radius: size * 0.28, y: size * 0.1)

            ForEach(0..<3, id: \.self) { index in
                Ellipse()
                    .stroke(
                        index == 1 ? NovaPalette.electric.opacity(0.92) : NovaPalette.orchid.opacity(0.65),
                        style: StrokeStyle(lineWidth: max(1.5, size * 0.025), lineCap: .round)
                    )
                    .frame(
                        width: size * (0.58 - CGFloat(index) * 0.07),
                        height: size * (0.27 + CGFloat(index) * 0.08)
                    )
                    .rotationEffect(.degrees(rotation * (index.isMultiple(of: 2) ? 1 : -0.72) + Double(index * 57)))
                    .shadow(color: index == 1 ? NovaPalette.electric : NovaPalette.violet, radius: size * 0.08)
            }

            Circle()
                .fill(NovaPalette.hero)
                .frame(width: size * 0.23, height: size * 0.23)
                .overlay(Circle().stroke(.white.opacity(0.75), lineWidth: 1))
                .scaleEffect(pulse ? 1.08 : 0.94)
                .shadow(color: NovaPalette.electric.opacity(0.9), radius: size * 0.18)

            Circle()
                .fill(.white)
                .frame(width: size * 0.055, height: size * 0.055)
                .offset(x: size * 0.23, y: -size * 0.12)
                .shadow(color: NovaPalette.electric, radius: size * 0.08)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard animate, !reduceMotion else { return }
            withAnimation(.linear(duration: 16).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityHidden(true)
    }
}

struct NovaGlassCard<Content: View>: View {
    var padding: CGFloat = 18
    private let content: Content

    init(padding: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.10), .clear, NovaPalette.violet.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.26), .white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 24, y: 14)
    }
}

struct NovaPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(NovaPalette.hero, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(configuration.isPressed ? 0.10 : 0.30), lineWidth: 1)
            )
            .shadow(color: NovaPalette.violet.opacity(configuration.isPressed ? 0.22 : 0.48), radius: 18, y: 10)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.snappy(duration: 0.22), value: configuration.isPressed)
    }
}

// MARK: - Entry experience

struct NovaEntryView: View {
    var body: some View {
        RealityRootView()
    }
}

struct NovaBootView: View {
    @State private var reveal = false
    @State private var sweep = false
    @State private var statusIndex = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let status = [
        "Waking your private kernel",
        "Restoring your workspace",
        "Ready"
    ]

    var body: some View {
        ZStack {
            NovaBackdrop()
            NovaGrain()

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.07), lineWidth: 1)
                        .frame(width: 220, height: 220)
                        .scaleEffect(sweep ? 1.22 : 0.82)
                        .opacity(sweep ? 0 : 0.8)

                    Circle()
                        .trim(from: 0.08, to: 0.84)
                        .stroke(
                            NovaPalette.hero,
                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                        )
                        .frame(width: 176, height: 176)
                        .rotationEffect(.degrees(sweep ? 310 : -40))
                        .opacity(reveal ? 1 : 0)

                    NovaKernelMark(size: 118)
                        .scaleEffect(reveal ? 1 : 0.68)
                        .opacity(reveal ? 1 : 0)
                }
                .frame(height: 236)

                VStack(spacing: 10) {
                    Text("POCKETKERNEL")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .tracking(5.2)
                    Text("AUTOMATION, REIMAGINED")
                        .font(.caption2.weight(.bold))
                        .tracking(2.4)
                        .foregroundStyle(.white.opacity(0.48))
                }
                .foregroundStyle(.white)
                .offset(y: reveal ? 0 : 18)
                .opacity(reveal ? 1 : 0)

                Spacer()

                VStack(spacing: 13) {
                    Text(status[statusIndex])
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.68))
                        .contentTransition(.numericText())

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.09))
                            Capsule()
                                .fill(NovaPalette.hero)
                                .frame(width: proxy.size.width * (statusIndex == 0 ? 0.34 : statusIndex == 1 ? 0.72 : 1))
                        }
                    }
                    .frame(width: 154, height: 4)
                }
                .padding(.bottom, 52)
                .opacity(reveal ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(duration: 0.8, bounce: 0.18)) {
                reveal = true
            }
            guard !reduceMotion else {
                statusIndex = 2
                return
            }
            withAnimation(.easeOut(duration: 1.05)) { sweep = true }
            Task {
                try? await Task.sleep(for: .milliseconds(290))
                withAnimation(.snappy) { statusIndex = 1 }
                try? await Task.sleep(for: .milliseconds(360))
                withAnimation(.snappy) { statusIndex = 2 }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("PocketKernel is starting")
    }
}

// MARK: - Authentication

private struct NovaHealthResponse: Decodable {
    let configuration: NovaHealthConfiguration
}

private struct NovaHealthConfiguration: Decodable {
    let redis: Bool
    let sessionSecret: Bool
    let providers: [String: Bool]
}

@MainActor
final class NovaAuthReadiness: ObservableObject {
    @Published private(set) var coreReady = true
    @Published private(set) var googleReady = true
    @Published private(set) var emailReady = true
    @Published private(set) var checked = false

    func refresh() async {
        guard let url = URL(string: "https://pocketkernel.vercel.app/api/health") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            let value = try JSONDecoder().decode(NovaHealthResponse.self, from: data)
            coreReady = value.configuration.redis && value.configuration.sessionSecret
            googleReady = coreReady && (value.configuration.providers["google"] ?? false)
            emailReady = coreReady
            checked = true
        } catch {
            checked = true
        }
    }
}

struct NovaAccountGatewayView: View {
    @EnvironmentObject private var account: AccountController
    @StateObject private var readiness = NovaAuthReadiness()
    @State private var showEmail = false
    @State private var reveal = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                NovaBackdrop()
                NovaGrain()

                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: max(28, proxy.safeAreaInsets.top + 14))

                        HStack {
                            HStack(spacing: 10) {
                                NovaKernelMark(size: 34)
                                Text("PocketKernel")
                                    .font(.headline.weight(.black))
                            }
                            Spacer()
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(readiness.coreReady ? NovaPalette.mint : NovaPalette.warning)
                                    .frame(width: 7, height: 7)
                                Text(readiness.coreReady ? "Secure cloud ready" : "Setup required")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(.horizontal, 22)
                        .opacity(reveal ? 1 : 0)

                        Spacer(minLength: 34)

                        VStack(spacing: 18) {
                            ZStack {
                                Circle()
                                    .fill(NovaPalette.violet.opacity(0.20))
                                    .frame(width: 168, height: 168)
                                    .blur(radius: 28)
                                NovaKernelMark(size: 112)
                            }

                            VStack(spacing: 12) {
                                Text("Put the repeat work\non autopilot.")
                                    .font(.system(size: 43, weight: .black, design: .rounded))
                                    .tracking(-1.8)
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(-3)

                                Text("Describe what you want. PocketKernel plans it privately, connects your services, and keeps you in control.")
                                    .font(.title3.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.64))
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(4)
                                    .padding(.horizontal, 18)
                            }
                        }
                        .foregroundStyle(.white)
                        .offset(y: reveal ? 0 : 28)
                        .opacity(reveal ? 1 : 0)

                        Spacer(minLength: 34)

                        NovaGlassCard(padding: 16) {
                            VStack(spacing: 13) {
                                SignInWithAppleButton(.continue) { request in
                                    account.configureAppleRequest(request)
                                } onCompletion: { result in
                                    account.completeAppleSignIn(result)
                                }
                                .signInWithAppleButtonStyle(.white)
                                .frame(height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                                .disabled(account.isBusy || !readiness.coreReady)

                                GoogleSignInButton {
                                    Task { await account.signInWithGoogle() }
                                }
                                .frame(height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                                .disabled(account.isBusy || !readiness.googleReady)

                                Button {
                                    showEmail = true
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "envelope.fill")
                                            .font(.body.weight(.bold))
                                        Text("Continue with email")
                                            .font(.headline.weight(.bold))
                                        Spacer()
                                        Image(systemName: "arrow.right")
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(.white.opacity(0.48))
                                    }
                                    .padding(.horizontal, 18)
                                    .frame(height: 56)
                                    .foregroundStyle(.white)
                                    .background(.white.opacity(0.085), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                                            .stroke(.white.opacity(0.15), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(account.isBusy || !readiness.emailReady)

                                if account.isBusy {
                                    HStack(spacing: 10) {
                                        ProgressView().tint(.white)
                                        Text("Securing your session…")
                                    }
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.68))
                                    .padding(.top, 2)
                                }

                                if readiness.checked && !readiness.coreReady {
                                    NovaInlineNotice(
                                        symbol: "wrench.and.screwdriver.fill",
                                        title: "Account service needs configuration",
                                        detail: "The app is ready, but the live server is missing its secure session and database settings."
                                    )
                                } else if let error = account.errorMessage {
                                    NovaInlineNotice(
                                        symbol: "exclamationmark.triangle.fill",
                                        title: "Couldn’t sign you in",
                                        detail: error
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .offset(y: reveal ? 0 : 36)
                        .opacity(reveal ? 1 : 0)

                        VStack(spacing: 11) {
                            Label("Private planning stays on your iPhone", systemImage: "lock.shield.fill")
                                .font(.footnote.weight(.semibold))
                            Text("By continuing, you agree to the Terms and acknowledge the Privacy Policy.")
                                .font(.caption)
                                .multilineTextAlignment(.center)
                            HStack(spacing: 20) {
                                Link("Privacy", destination: URL(string: "https://pocketkernel.vercel.app/privacy.html")!)
                                Link("Terms", destination: URL(string: "https://pocketkernel.vercel.app/terms.html")!)
                                Link("Support", destination: URL(string: "https://pocketkernel.vercel.app/support.html")!)
                            }
                            .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(.white.opacity(0.48))
                        .padding(.horizontal, 34)
                        .padding(.top, 22)
                        .padding(.bottom, max(26, proxy.safeAreaInsets.bottom + 14))
                        .opacity(reveal ? 1 : 0)
                    }
                    .frame(minHeight: proxy.size.height)
                }
                .scrollIndicators(.hidden)
            }
        }
        .sheet(isPresented: $showEmail) {
            NovaEmailSignInSheet()
                .environmentObject(account)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(34)
        }
        .task { await readiness.refresh() }
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.15) : .spring(duration: 0.95, bounce: 0.13)) {
                reveal = true
            }
        }
    }
}

struct NovaInlineNotice: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(NovaPalette.warning)
                .frame(width: 28, height: 28)
                .background(NovaPalette.warning.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.footnote.weight(.bold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.61))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(13)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

struct NovaEmailSignInSheet: View {
    @EnvironmentObject private var account: AccountController
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""
    @State private var cooldown = 0
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case code
    }

    private var waitingForCode: Bool {
        account.emailAwaitingCode != nil
    }

    var body: some View {
        ZStack {
            NovaBackdrop()
            NovaGrain()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack {
                        NovaKernelMark(size: 42)
                        Spacer()
                        Button {
                            account.cancelEmail()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.bold))
                                .frame(width: 38, height: 38)
                                .background(.white.opacity(0.09), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(waitingForCode ? "Check your inbox" : "Continue with email")
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .tracking(-1.1)
                        Text(
                            waitingForCode
                            ? "Enter the six-digit code sent to \(account.emailAwaitingCode ?? email)."
                            : "No password. We’ll email a one-time code that expires in ten minutes."
                        )
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineSpacing(4)
                    }

                    if waitingForCode {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("VERIFICATION CODE")
                                .font(.caption2.weight(.black))
                                .tracking(1.6)
                                .foregroundStyle(.white.opacity(0.45))

                            TextField("000000", text: $code)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                .focused($focusedField, equals: .code)
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .tracking(10)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                                .frame(height: 72)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(code.count == 6 ? NovaPalette.electric.opacity(0.7) : .white.opacity(0.13), lineWidth: 1)
                                )
                                .onChange(of: code) { _, value in
                                    code = String(value.filter(\.isNumber).prefix(6))
                                    if code.count == 6 {
                                        Task { await account.verifyEmailCode(code) }
                                    }
                                }
                        }

                        Button {
                            Task { await account.verifyEmailCode(code) }
                        } label: {
                            HStack {
                                if account.isBusy { ProgressView().tint(.white) }
                                Text(account.isBusy ? "Verifying…" : "Verify and continue")
                            }
                        }
                        .buttonStyle(NovaPrimaryButtonStyle())
                        .disabled(account.isBusy || code.count != 6)

                        HStack {
                            Button("Use another email") {
                                code = ""
                                account.cancelEmail()
                                focusedField = .email
                            }
                            Spacer()
                            Button(cooldown > 0 ? "Resend in \(cooldown)s" : "Resend code") {
                                guard cooldown == 0, let target = account.emailAwaitingCode else { return }
                                cooldown = 30
                                Task {
                                    await account.requestEmailCode(target)
                                    await runCooldown()
                                }
                            }
                            .disabled(cooldown > 0 || account.isBusy)
                        }
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(NovaPalette.electric)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("EMAIL ADDRESS")
                                .font(.caption2.weight(.black))
                                .tracking(1.6)
                                .foregroundStyle(.white.opacity(0.45))

                            HStack(spacing: 12) {
                                Image(systemName: "envelope.fill")
                                    .foregroundStyle(NovaPalette.electric)
                                TextField("you@example.com", text: $email)
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .focused($focusedField, equals: .email)
                                    .font(.title3.weight(.semibold))
                                    .onSubmit { Task { await account.requestEmailCode(email) } }
                            }
                            .padding(.horizontal, 17)
                            .frame(height: 62)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 19, style: .continuous)
                                    .stroke(.white.opacity(0.13), lineWidth: 1)
                            )
                        }

                        Button {
                            Task { await account.requestEmailCode(email) }
                        } label: {
                            HStack {
                                if account.isBusy { ProgressView().tint(.white) }
                                Text(account.isBusy ? "Sending code…" : "Email me a code")
                            }
                        }
                        .buttonStyle(NovaPrimaryButtonStyle())
                        .disabled(account.isBusy || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if let error = account.errorMessage {
                        NovaInlineNotice(
                            symbol: "exclamationmark.triangle.fill",
                            title: "Couldn’t continue",
                            detail: error
                        )
                    }

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundStyle(NovaPalette.mint)
                        Text("Codes are single-use, expire automatically, and are never stored in plain text.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .padding(22)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            focusedField = waitingForCode ? .code : .email
        }
        .onChange(of: account.isSignedIn) { _, signedIn in
            if signedIn { dismiss() }
        }
    }

    @MainActor
    private func runCooldown() async {
        while cooldown > 0 {
            try? await Task.sleep(for: .seconds(1))
            cooldown -= 1
        }
    }
}

// MARK: - Onboarding

struct NovaOnboardingView: View {
    let completion: () -> Void
    @State private var page = 0

    private let pages: [(String, String, String, String)] = [
        (
            "bubble.left.and.sparkles.fill",
            "Ask naturally",
            "Tell PocketKernel what you want done in everyday language.",
            "Every weekday, brief me on the emails that actually need a reply."
        ),
        (
            "point.3.connected.trianglepath.dotted",
            "Connect your world",
            "Link the services you already use through their official secure sign-in.",
            "Gmail  •  Calendar  •  Slack  •  Notion"
        ),
        (
            "hand.raised.fill",
            "Approve the important stuff",
            "PocketKernel shows its plan before sending, posting, deleting, or scheduling.",
            "Nothing important happens without your approval."
        )
    ]

    var body: some View {
        ZStack {
            NovaBackdrop()
            NovaGrain()

            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 10) {
                        NovaKernelMark(size: 34)
                        Text("PocketKernel").font(.headline.weight(.black))
                    }
                    Spacer()
                    Button("Skip", action: completion)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)

                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        NovaOnboardingPage(
                            symbol: pages[index].0,
                            title: pages[index].1,
                            detail: pages[index].2,
                            example: pages[index].3,
                            index: index
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 7) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? NovaPalette.electric : .white.opacity(0.16))
                            .frame(width: index == page ? 28 : 8, height: 8)
                    }
                }
                .animation(.snappy, value: page)
                .padding(.bottom, 20)

                Button {
                    if page < pages.count - 1 {
                        withAnimation(.snappy) { page += 1 }
                    } else {
                        completion()
                    }
                } label: {
                    Text(page == pages.count - 1 ? "Enter PocketKernel" : "Continue")
                }
                .buttonStyle(NovaPrimaryButtonStyle())
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
        }
        .foregroundStyle(.white)
    }
}

struct NovaOnboardingPage: View {
    let symbol: String
    let title: String
    let detail: String
    let example: String
    let index: Int

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 24)

                ZStack {
                    Circle()
                        .fill(NovaPalette.violet.opacity(0.20))
                        .frame(width: 220, height: 220)
                        .blur(radius: 28)
                    NovaKernelMark(size: 126)
                    Image(systemName: symbol)
                        .font(.system(size: 27, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(NovaPalette.hero, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .offset(x: 72, y: 70)
                        .shadow(color: NovaPalette.violet.opacity(0.6), radius: 18, y: 8)
                }

                VStack(spacing: 12) {
                    Text(title)
                        .font(.system(size: 39, weight: .black, design: .rounded))
                        .tracking(-1.4)
                        .multilineTextAlignment(.center)
                    Text(detail)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                NovaGlassCard {
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: index == 0 ? "quote.opening" : index == 1 ? "link" : "checkmark.shield.fill")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(index == 2 ? NovaPalette.mint : NovaPalette.electric)
                        Text(example)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Main application

enum NovaMainTab: String, CaseIterable, Identifiable {
    case home
    case automations
    case activity
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .automations: "Automations"
        case .activity: "Activity"
        case .profile: "You"
        }
    }

    var symbol: String {
        switch self {
        case .home: "sparkles"
        case .automations: "bolt.horizontal.circle.fill"
        case .activity: "waveform.path.ecg"
        case .profile: "person.crop.circle.fill"
        }
    }
}

struct NovaRootView: View {
    @EnvironmentObject private var oauth: OAuthCoordinator
    @AppStorage("didCompleteOnboarding.v3") private var didCompleteOnboarding = false
    @State private var selected: NovaMainTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            NovaBackdrop()
            NovaGrain()

            Group {
                switch selected {
                case .home:
                    NovaHomeView()
                case .automations:
                    NovaAutomationsView { selected = .home }
                case .activity:
                    NovaActivityView()
                case .profile:
                    NovaProfileView { didCompleteOnboarding = false }
                }
            }
            .safeAreaPadding(.bottom, 94)
            .transition(.opacity.combined(with: .scale(scale: 0.992)))

            NovaTabBar(selected: $selected)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
        .animation(.snappy(duration: 0.32), value: selected)
        .task { await oauth.refresh() }
    }
}

struct NovaTabBar: View {
    @Binding var selected: NovaMainTab
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 5) {
            ForEach(NovaMainTab.allCases) { tab in
                Button {
                    selected = tab
                } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            if selected == tab {
                                Capsule()
                                    .fill(NovaPalette.hero.opacity(0.9))
                                    .matchedGeometryEffect(id: "selection", in: selection)
                                    .frame(width: 48, height: 31)
                                    .shadow(color: NovaPalette.violet.opacity(0.55), radius: 12, y: 5)
                            }
                            Image(systemName: tab.symbol)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(selected == tab ? .white : .white.opacity(0.48))
                        }
                        Text(tab.title)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(selected == tab ? .white : .white.opacity(0.42))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 27, style: .continuous)
                        .fill(NovaPalette.raised.opacity(0.42))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.42), radius: 26, y: 14)
    }
}

struct NovaHomeView: View {
    @EnvironmentObject private var chat: ChatController
    @EnvironmentObject private var executor: ActionExecutor
    @EnvironmentObject private var oauth: OAuthCoordinator
    @EnvironmentObject private var account: AccountController
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    private var firstName: String {
        let name = account.profile?.displayName ?? "there"
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 18) {
                        NovaHomeHeader(
                            name: firstName,
                            readiness: chat.readiness,
                            connectedCount: oauth.connections.count
                        )

                        NovaCommandComposer(
                            input: $input,
                            focused: $inputFocused,
                            isThinking: chat.isThinking,
                            send: send
                        )

                        if !chat.hasConversation {
                            NovaStarterGrid { template in
                                input = template.prompt
                                Task { await send() }
                            }
                        } else {
                            NovaConversationSection()
                                .environmentObject(chat)
                                .environmentObject(executor)
                        }

                        if !chat.activity.isEmpty {
                            NovaActivityPreview(items: Array(chat.activity.prefix(3)))
                        }

                        Color.clear.frame(height: 12).id("bottom")
                    }
                    .padding(.horizontal, 17)
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                }
                .scrollIndicators(.hidden)
                .onChange(of: chat.messages.count) { _, _ in
                    withAnimation(.snappy) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(Color.clear)
        }
    }

    private func send() async {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        input = ""
        inputFocused = false
        await chat.send(prompt)
    }
}

struct NovaHomeHeader: View {
    let name: String
    let readiness: ModelReadiness
    let connectedCount: Int

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            NovaKernelMark(size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text("Good \(dayPart), \(name)")
                    .font(.system(size: 27, weight: .black, design: .rounded))
                    .tracking(-0.7)
                HStack(spacing: 7) {
                    Circle()
                        .fill(readiness == .ready ? NovaPalette.mint : NovaPalette.warning)
                        .frame(width: 7, height: 7)
                    Text(readiness == .ready ? "Private intelligence ready" : readiness.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            Spacer()
            VStack(spacing: 2) {
                Text("\(connectedCount)")
                    .font(.title3.weight(.black))
                Text("linked")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(width: 54, height: 54)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(.white.opacity(0.11)))
        }
        .foregroundStyle(.white)
    }

    private var dayPart: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "morning" }
        if hour < 18 { return "afternoon" }
        return "evening"
    }
}

struct NovaCommandComposer: View {
    @Binding var input: String
    var focused: FocusState<Bool>.Binding
    let isThinking: Bool
    let send: () async -> Void

    var body: some View {
        NovaGlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(NovaPalette.electric)
                        Text("CREATE WITH POCKETKERNEL")
                            .font(.caption2.weight(.black))
                            .tracking(1.2)
                    }
                    Spacer()
                    Text("ON DEVICE")
                        .font(.caption2.weight(.black))
                        .tracking(1)
                        .foregroundStyle(NovaPalette.mint)
                }
                .padding(.horizontal, 18)
                .padding(.top, 17)

                TextEditor(text: $input)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .frame(minHeight: 104, maxHeight: 160)
                    .padding(.horizontal, 14)
                    .padding(.top, 9)
                    .focused(focused)
                    .overlay(alignment: .topLeading) {
                        if input.isEmpty {
                            Text("What should happen automatically?")
                                .font(.system(size: 21, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.29))
                                .padding(.horizontal, 19)
                                .padding(.top, 18)
                                .allowsHitTesting(false)
                        }
                    }

                HStack(spacing: 10) {
                    Label("No code required", systemImage: "wand.and.stars")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Button {
                        Task { await send() }
                    } label: {
                        HStack(spacing: 8) {
                            if isThinking {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.headline.weight(.black))
                            }
                            Text(isThinking ? "Planning" : "Build it")
                                .font(.subheadline.weight(.black))
                        }
                        .padding(.horizontal, 17)
                        .frame(height: 44)
                        .background(NovaPalette.hero, in: Capsule())
                        .shadow(color: NovaPalette.violet.opacity(0.48), radius: 14, y: 7)
                    }
                    .buttonStyle(.plain)
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
                }
                .padding(14)
                .background(.white.opacity(0.035))
            }
        }
    }
}

struct NovaStarterGrid: View {
    let select: (StarterTemplate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Start with an idea")
                    .font(.title3.weight(.black))
                Spacer()
                Text("TAP TO TRY")
                    .font(.caption2.weight(.black))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.42))
            }
            .foregroundStyle(.white)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 11) {
                ForEach(StarterTemplate.featured.prefix(6)) { template in
                    Button {
                        select(template)
                    } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: template.symbol)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 38, height: 38)
                                    .background(
                                        LinearGradient(
                                            colors: [template.tint, template.tint.opacity(0.48)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    )
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.34))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.leading)
                                Text(template.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.48))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
                        .padding(14)
                        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(.white.opacity(0.09), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct NovaConversationSection: View {
    @EnvironmentObject private var chat: ChatController
    @EnvironmentObject private var executor: ActionExecutor

    var body: some View {
        VStack(spacing: 13) {
            HStack {
                Text("Conversation")
                    .font(.title3.weight(.black))
                Spacer()
                Button("Clear") { chat.reset() }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NovaPalette.electric)
            }
            .foregroundStyle(.white)

            ForEach(chat.messages.suffix(16)) { message in
                NovaMessageBubble(message: message)
            }

            ForEach(chat.pending) { proposal in
                NovaProposalCard(proposal: proposal)
                    .environmentObject(chat)
                    .environmentObject(executor)
            }

            if let error = chat.errorText {
                NovaInlineNotice(
                    symbol: "exclamationmark.triangle.fill",
                    title: "PocketKernel paused",
                    detail: error
                )
            }
        }
    }
}

struct NovaMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if message.role == .user { Spacer(minLength: 44) }
            if message.role != .user {
                NovaKernelMark(size: 28, animate: false)
            }
            Text(message.text)
                .font(.body.weight(message.role == .user ? .semibold : .regular))
                .foregroundStyle(.white.opacity(message.role == .system ? 0.68 : 0.92))
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .background(
                    message.role == .user ? AnyShapeStyle(NovaPalette.hero) : AnyShapeStyle(.white.opacity(0.07)),
                    in: RoundedRectangle(cornerRadius: 19, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .stroke(.white.opacity(message.role == .user ? 0.20 : 0.08))
                )
            if message.role != .user { Spacer(minLength: 34) }
        }
    }
}

struct NovaProposalCard: View {
    let proposal: ToolProposal
    @EnvironmentObject private var chat: ChatController
    @EnvironmentObject private var executor: ActionExecutor

    var body: some View {
        NovaGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 11) {
                    Image(systemName: proposal.kind == .schedule ? "clock.badge.checkmark" : "bolt.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(NovaPalette.hero, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("READY FOR APPROVAL")
                            .font(.caption2.weight(.black))
                            .tracking(1.1)
                            .foregroundStyle(NovaPalette.mint)
                        Text(proposal.title)
                            .font(.headline.weight(.bold))
                    }
                }

                Text(proposal.summary)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.60))

                HStack(spacing: 10) {
                    Button("Not now") { chat.reject(proposal) }
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    Button {
                        Task { await chat.approve(proposal, executor: executor) }
                    } label: {
                        Text("Approve")
                            .font(.subheadline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(NovaPalette.hero, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
        }
    }
}

struct NovaActivityPreview: View {
    let items: [ActivityItem]

    var body: some View {
        NovaGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Latest activity")
                        .font(.headline.weight(.black))
                    Spacer()
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(NovaPalette.electric)
                }

                ForEach(items) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.succeeded ? "checkmark" : "xmark")
                            .font(.caption.weight(.black))
                            .foregroundStyle(item.succeeded ? NovaPalette.mint : NovaPalette.warning)
                            .frame(width: 30, height: 30)
                            .background(
                                (item.succeeded ? NovaPalette.mint : NovaPalette.warning).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.bold))
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.48))
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(item.date, style: .relative)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.34))
                    }
                }
            }
            .foregroundStyle(.white)
        }
    }
}
