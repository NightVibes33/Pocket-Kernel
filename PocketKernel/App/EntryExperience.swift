import SwiftUI
import AuthenticationServices
import GoogleSignInSwift
import CryptoKit
import Security
import UIKit

struct AccountProfile: Codable, Hashable, Sendable {
    let id: String
    let email: String?
    let name: String?
    let provider: String

    var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return name }
        if let email, let first = email.split(separator: "@").first { return String(first) }
        return "PocketKernel user"
    }
}

private struct AccountEnvelope: Codable, Sendable {
    let userID: String
    let token: String
    let expiresIn: Int
    let profile: AccountProfile
}

private struct AccountSessionResponse: Codable, Sendable {
    let profile: AccountProfile
}

private struct GoogleStartResponse: Codable, Sendable {
    let authorizationURL: String
}

private struct EmailStartResponse: Codable, Sendable {
    let sent: Bool
    let expiresIn: Int
}

actor AccountAPI {
    static let shared = AccountAPI()
    private let baseURL = URL(string: "https://pocketkernel.vercel.app")!

    func restore() async throws -> AccountProfile? {
        guard let token = KeychainStore.string(for: "apiToken"), !token.isEmpty else { return nil }
        let response: AccountSessionResponse = try await request(path: "/api/auth/session", token: token)
        return response.profile
    }

    func signInWithApple(identityToken: String, nonce: String, name: String?, email: String?) async throws -> AccountProfile {
        let envelope: AccountEnvelope = try await request(
            path: "/api/auth/apple",
            method: "POST",
            body: AppleBody(identityToken: identityToken, nonce: nonce, name: name, email: email)
        )
        store(envelope)
        return envelope.profile
    }

    func googleAuthorizationURL() async throws -> URL {
        let response: GoogleStartResponse = try await request(path: "/api/auth/google/start", method: "POST", body: EmptyBody())
        guard let url = URL(string: response.authorizationURL) else { throw AccountError.invalidResponse }
        return url
    }

    func exchangeGoogleTicket(_ ticket: String) async throws -> AccountProfile {
        let envelope: AccountEnvelope = try await request(
            path: "/api/auth/exchange",
            method: "POST",
            body: TicketBody(ticket: ticket)
        )
        store(envelope)
        return envelope.profile
    }

    func startEmail(_ email: String) async throws -> Int {
        let response: EmailStartResponse = try await request(
            path: "/api/auth/email/start",
            method: "POST",
            body: EmailBody(email: email)
        )
        return response.expiresIn
    }

    func verifyEmail(_ email: String, code: String) async throws -> AccountProfile {
        let envelope: AccountEnvelope = try await request(
            path: "/api/auth/email/verify",
            method: "POST",
            body: EmailCodeBody(email: email, code: code)
        )
        store(envelope)
        return envelope.profile
    }

    func clear() {
        KeychainStore.set("", for: "apiToken")
        KeychainStore.set("", for: "userID")
        KeychainStore.set("", for: "accountProvider")
        KeychainStore.set("", for: "accountEmail")
        KeychainStore.set("", for: "accountName")
    }

    private func store(_ envelope: AccountEnvelope) {
        KeychainStore.set(envelope.token, for: "apiToken")
        KeychainStore.set(envelope.userID, for: "userID")
        KeychainStore.set(envelope.profile.provider, for: "accountProvider")
        KeychainStore.set(envelope.profile.email ?? "", for: "accountEmail")
        KeychainStore.set(envelope.profile.name ?? "", for: "accountName")
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String = "GET",
        body: Body,
        token: String? = nil
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(body)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization") }
        return try await perform(request)
    }

    private func request<Response: Decodable>(path: String, token: String? = nil) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization") }
        return try await perform(request)
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AccountError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let backend = try? JSONDecoder().decode(BackendMessage.self, from: data)
            throw AccountError.server(backend?.error ?? "HTTP \(http.statusCode)")
        }
        do { return try JSONDecoder().decode(Response.self, from: data) }
        catch { throw AccountError.invalidResponse }
    }

    private struct EmptyBody: Codable {}
    private struct AppleBody: Codable { let identityToken: String; let nonce: String; let name: String?; let email: String? }
    private struct TicketBody: Codable { let ticket: String }
    private struct EmailBody: Codable { let email: String }
    private struct EmailCodeBody: Codable { let email: String; let code: String }
    private struct BackendMessage: Codable { let error: String }

    enum AccountError: LocalizedError {
        case invalidResponse
        case server(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "The sign-in service returned an unexpected response."
            case .server(let value):
                switch value {
                case "google_not_configured": "Google sign-in is not available yet."
                case "email_not_configured": "Email sign-in is not available yet."
                case "invalid_code": "That code is incorrect or expired."
                case "invalid_apple_token": "Apple could not verify this sign-in. Please try again."
                default: value.replacingOccurrences(of: "_", with: " ").capitalized
                }
            }
        }
    }
}

@MainActor
final class AccountController: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var profile: AccountProfile?
    @Published private(set) var isRestoring = true
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?
    @Published var emailAwaitingCode: String?

    private var webSession: ASWebAuthenticationSession?
    private var appleNonce: String?

    var isSignedIn: Bool { profile != nil }

    func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            profile = try await AccountAPI.shared.restore()
            errorMessage = nil
        } catch {
            await AccountAPI.shared.clear()
            profile = nil
        }
    }

    func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        appleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled { errorMessage = error.localizedDescription }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  let nonce = appleNonce else {
                errorMessage = "Apple did not return a usable sign-in credential."
                return
            }
            let components = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }
            let name = components.isEmpty ? nil : components.joined(separator: " ")
            Task { await self.signInWithApple(token: token, nonce: nonce, name: name, email: credential.email) }
        }
    }

    func signInWithGoogle() async {
        await runBusy {
            let url = try await AccountAPI.shared.googleAuthorizationURL()
            let ticket = try await self.openAuthenticationSession(url: url)
            self.profile = try await AccountAPI.shared.exchangeGoogleTicket(ticket)
        }
    }

    func requestEmailCode(_ email: String) async {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains("@"), normalized.contains(".") else {
            errorMessage = "Enter a valid email address."
            return
        }
        await runBusy {
            _ = try await AccountAPI.shared.startEmail(normalized)
            self.emailAwaitingCode = normalized
        }
    }

    func verifyEmailCode(_ code: String) async {
        guard let email = emailAwaitingCode else { return }
        let normalizedCode = code.filter(\.isNumber)
        guard normalizedCode.count == 6 else {
            errorMessage = "Enter the six-digit code from your email."
            return
        }
        await runBusy {
            self.profile = try await AccountAPI.shared.verifyEmail(email, code: normalizedCode)
            self.emailAwaitingCode = nil
        }
    }

    func cancelEmail() {
        emailAwaitingCode = nil
        errorMessage = nil
    }

    func signOut() {
        Task {
            await AccountAPI.shared.clear()
            await BackendClient.shared.clearIdentity()
        }
        profile = nil
        emailAwaitingCode = nil
        errorMessage = nil
    }

    func finishDeletion() {
        profile = nil
        emailAwaitingCode = nil
        errorMessage = nil
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    private func signInWithApple(token: String, nonce: String, name: String?, email: String?) async {
        await runBusy {
            self.profile = try await AccountAPI.shared.signInWithApple(identityToken: token, nonce: nonce, name: name, email: email)
        }
    }

    private func runBusy(_ operation: @escaping () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do { try await operation() }
        catch { errorMessage = error.localizedDescription }
    }

    private func openAuthenticationSession(url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "pocketkernel-auth") { [weak self] callbackURL, error in
                self?.webSession = nil
                if let error { continuation.resume(throwing: error); return }
                guard let callbackURL,
                      let ticket = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "ticket" })?.value,
                      !ticket.isEmpty else {
                    continuation.resume(throwing: AccountAPI.AccountError.invalidResponse)
                    return
                }
                continuation.resume(returning: ticket)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            webSession = session
            guard session.start() else {
                webSession = nil
                continuation.resume(throwing: AccountAPI.AccountError.invalidResponse)
                return
            }
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var bytes = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return UUID().uuidString }
            for byte in bytes where remaining > 0 {
                if byte < alphabet.count {
                    result.append(alphabet[Int(byte)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct AppEntryView: View {
    @AppStorage("didCompleteOnboarding.v2") private var didCompleteOnboarding = false
    @State private var bootFinished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !bootFinished {
                KernelBootView()
                    .transition(.opacity)
            } else if !didCompleteOnboarding {
                OnboardingView { didCompleteOnboarding = true }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                RootView()
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .linear(duration: 0.16) : .easeInOut(duration: 0.48), value: bootFinished)
        .task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 250 : 1150))
            bootFinished = true
        }
    }
}

struct KernelBootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal = false

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.03, blue: 0.07).ignoresSafeArea()
            KernelMotionField(compact: false)
                .opacity(reveal ? 1 : 0)
            VStack(spacing: 18) {
                KernelGlyph(size: 92)
                    .scaleEffect(reveal ? 1 : 0.72)
                    .opacity(reveal ? 1 : 0)
                VStack(spacing: 7) {
                    Text("PocketKernel")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .tracking(-0.8)
                    Text("Preparing your private workspace")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.58))
                }
                .foregroundStyle(.white)
                .opacity(reveal ? 1 : 0)
                ProgressView()
                    .tint(.white.opacity(0.8))
                    .controlSize(.small)
                    .opacity(reveal ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(duration: 0.9, bounce: 0.22)) { reveal = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("PocketKernel is loading")
    }
}

struct KernelMotionField: View {
    let compact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 45.0, paused: false)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let center = CGPoint(x: size.width * 0.5, y: size.height * (compact ? 0.34 : 0.44))
                let scale = min(size.width, size.height)

                context.addFilter(.blur(radius: compact ? 24 : 36))
                for index in 0..<5 {
                    let phase = t * (0.12 + Double(index) * 0.018)
                    let radius = scale * (0.16 + CGFloat(index) * 0.08)
                    let offset = CGPoint(
                        x: center.x + cos(phase + Double(index)) * radius * 0.32,
                        y: center.y + sin(phase * 0.86 + Double(index)) * radius * 0.22
                    )
                    let rect = CGRect(x: offset.x - radius, y: offset.y - radius, width: radius * 2, height: radius * 2)
                    let color = index.isMultiple(of: 2)
                        ? Color(red: 0.32, green: 0.35, blue: 1.0).opacity(0.28)
                        : Color(red: 0.0, green: 0.82, blue: 0.95).opacity(0.18)
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }

                context.addFilter(.blur(radius: 0))
                for index in 0..<4 {
                    let radius = scale * (0.12 + CGFloat(index) * 0.075)
                    var path = Path()
                    path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius * 0.62, width: radius * 2, height: radius * 1.24))
                    context.stroke(path, with: .color(.white.opacity(0.055 + Double(index) * 0.018)), lineWidth: 0.8)

                    let angle = t * (0.28 + Double(index) * 0.075) + Double(index) * 1.4
                    let node = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius * 0.62)
                    context.fill(Path(ellipseIn: CGRect(x: node.x - 2.7, y: node.y - 2.7, width: 5.4, height: 5.4)), with: .color(.white.opacity(0.82)))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct KernelGlyph: View {
    let size: CGFloat
    @State private var rotation = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(index == 0 ? 0.95 : 0.28))
                    .frame(width: size * (0.54 - CGFloat(index) * 0.11), height: 3)
                    .rotationEffect(.degrees(Double(index) * 60 + rotation * (index.isMultiple(of: 2) ? 1 : -0.7)))
            }
            Circle()
                .fill(.white)
                .frame(width: size * 0.13, height: size * 0.13)
                .shadow(color: .cyan.opacity(0.85), radius: 13)
        }
        .frame(width: size, height: size)
        .shadow(color: .indigo.opacity(0.38), radius: 30, y: 14)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) { rotation = 360 }
        }
        .accessibilityHidden(true)
    }
}

struct AccountGatewayView: View {
    @EnvironmentObject private var account: AccountController
    @State private var showEmail = false
    @State private var entrance = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 0.025, green: 0.03, blue: 0.07).ignoresSafeArea()
                KernelMotionField(compact: true)

                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: max(34, proxy.safeAreaInsets.top + 22))

                        VStack(spacing: 18) {
                            KernelGlyph(size: 72)
                            VStack(spacing: 9) {
                                Text("Your life, on autopilot")
                                    .font(.system(size: 38, weight: .bold, design: .rounded))
                                    .tracking(-1.4)
                                    .multilineTextAlignment(.center)
                                Text("Ask once. PocketKernel handles the repeat work while you stay in control.")
                                    .font(.title3)
                                    .foregroundStyle(.white.opacity(0.64))
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(3)
                            }
                        }
                        .foregroundStyle(.white)
                        .offset(y: entrance ? 0 : 26)
                        .opacity(entrance ? 1 : 0)

                        Spacer(minLength: 36)

                        VStack(spacing: 15) {
                            SignInWithAppleButton(.continue) { request in
                                account.configureAppleRequest(request)
                            } onCompletion: { result in
                                account.completeAppleSignIn(result)
                            }
                            .signInWithAppleButtonStyle(.white)
                            .frame(height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .disabled(account.isBusy)

                            GoogleSignInButton {
                                Task { await account.signInWithGoogle() }
                            }
                            .frame(height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .disabled(account.isBusy)

                            Button {
                                showEmail = true
                            } label: {
                                Label("Continue with email", systemImage: "envelope.fill")
                                    .font(.body.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 54)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white)
                            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.14)))
                            .disabled(account.isBusy)

                            if account.isBusy {
                                HStack(spacing: 10) {
                                    ProgressView().tint(.white)
                                    Text("Signing you in securely…")
                                }
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.white.opacity(0.7))
                                .transition(.opacity)
                            }

                            if let error = account.errorMessage {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(Color(red: 1, green: 0.67, blue: 0.54))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                            }
                        }
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.13)))
                        .shadow(color: .black.opacity(0.28), radius: 32, y: 18)
                        .padding(.horizontal, 20)
                        .offset(y: entrance ? 0 : 38)
                        .opacity(entrance ? 1 : 0)

                        VStack(spacing: 8) {
                            Label("Private planning stays on your iPhone", systemImage: "lock.shield.fill")
                            Text("By continuing, you agree to the Terms and acknowledge the Privacy Policy.")
                                .multilineTextAlignment(.center)
                            HStack(spacing: 18) {
                                Link("Privacy", destination: URL(string: "https://pocketkernel.vercel.app/privacy.html")!)
                                Link("Terms", destination: URL(string: "https://pocketkernel.vercel.app/terms.html")!)
                                Link("Help", destination: URL(string: "https://pocketkernel.vercel.app/support.html")!)
                            }
                            .font(.caption.weight(.semibold))
                        }
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.52))
                        .padding(.horizontal, 34)
                        .padding(.top, 24)
                        .padding(.bottom, max(24, proxy.safeAreaInsets.bottom + 12))
                        .opacity(entrance ? 1 : 0)
                    }
                    .frame(minHeight: proxy.size.height)
                }
                .scrollIndicators(.hidden)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showEmail) {
            EmailSignInSheet()
                .environmentObject(account)
                .presentationDetents([.height(account.emailAwaitingCode == nil ? 360 : 420)])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.18) : .spring(duration: 0.9, bounce: 0.14)) { entrance = true }
        }
    }
}

struct EmailSignInSheet: View {
    @EnvironmentObject private var account: AccountController
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""
    @FocusState private var focusedField: Field?

    private enum Field { case email, code }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(account.emailAwaitingCode == nil ? "Continue with email" : "Check your inbox")
                        .font(.largeTitle.bold())
                    Text(account.emailAwaitingCode == nil
                         ? "We’ll send a one-time code. No password to create or remember."
                         : "Enter the six-digit code sent to \(account.emailAwaitingCode ?? email).")
                        .foregroundStyle(.secondary)
                }

                if account.emailAwaitingCode == nil {
                    TextField("you@example.com", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .font(.title3)
                        .padding(16)
                        .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
                        .onSubmit { Task { await account.requestEmailCode(email) } }

                    Button {
                        Task { await account.requestEmailCode(email) }
                    } label: {
                        Text("Send sign-in code").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(account.isBusy)
                } else {
                    TextField("000000", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($focusedField, equals: .code)
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .tracking(9)
                        .padding(16)
                        .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
                        .onChange(of: code) { _, value in
                            let filtered = String(value.filter(\.isNumber).prefix(6))
                            if filtered != value { code = filtered }
                            if filtered.count == 6 { Task { await account.verifyEmailCode(filtered) } }
                        }

                    Button {
                        Task { await account.verifyEmailCode(code) }
                    } label: {
                        Text("Verify and continue").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(account.isBusy || code.count != 6)

                    Button("Use a different email") {
                        account.cancelEmail()
                        code = ""
                        focusedField = .email
                    }
                    .frame(maxWidth: .infinity)
                }

                if account.isBusy { ProgressView().frame(maxWidth: .infinity) }
                if let error = account.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                Spacer(minLength: 0)
            }
            .padding(22)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { focusedField = account.emailAwaitingCode == nil ? .email : .code }
            .onChange(of: account.isSignedIn) { _, signedIn in if signedIn { dismiss() } }
        }
    }
}
