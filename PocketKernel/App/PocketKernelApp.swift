import SwiftUI
import Foundation
import FoundationModels
import AuthenticationServices
import Security
import UserNotifications
import EventKit
import UIKit

// MARK: - Application entry

@main
struct PocketKernelApp: App {
    @StateObject private var chat = ChatController()
    @StateObject private var executor = ActionExecutor()
    @StateObject private var oauth = OAuthCoordinator()
    @StateObject private var auth = AuthController()

    var body: some Scene {
        WindowGroup {
            AppGateway()
                .environmentObject(chat)
                .environmentObject(executor)
                .environmentObject(oauth)
                .environmentObject(auth)
                .onOpenURL { url in
                    Task {
                        await auth.handleIncomingURL(url)
                        await oauth.refresh()
                    }
                }
        }
    }
}

// MARK: - Root routing

struct AppGateway: View {
    @EnvironmentObject private var auth: AuthController
    @EnvironmentObject private var chat: ChatController
    @EnvironmentObject private var oauth: OAuthCoordinator
    @State private var bootComplete = false
    @State private var accountSheet = false

    var body: some View {
        ZStack {
            if !bootComplete {
                CinematicBootView()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            } else if auth.isAuthenticated {
                ZStack(alignment: .topTrailing) {
                    RootView()
                    accountControl
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                AuthGatewayView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.smooth(duration: 0.62), value: bootComplete)
        .animation(.smooth(duration: 0.55), value: auth.isAuthenticated)
        .task {
            guard !bootComplete else { return }
            let restore = Task { await auth.restore() }
            try? await Task.sleep(nanoseconds: 2_450_000_000)
            _ = await restore.value
            withAnimation(.smooth(duration: 0.7)) { bootComplete = true }
        }
        .sheet(isPresented: $accountSheet) {
            AccountSheet()
                .environmentObject(auth)
                .environmentObject(chat)
                .environmentObject(oauth)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var accountControl: some View {
        Button {
            accountSheet = true
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.9), .indigo.opacity(0.55), .blue.opacity(0.35)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                Text(auth.profile.initials)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
            }
            .frame(width: 34, height: 34)
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        }
        .buttonStyle(PressScaleButtonStyle())
        .padding(.top, 9)
        .padding(.trailing, 52)
        .accessibilityLabel("Account")
    }
}

// MARK: - Authentication state

struct AuthProfile: Codable, Sendable, Equatable {
    var id: String
    var email: String?
    var displayName: String?
    var provider: String

    static let empty = AuthProfile(id: "", email: nil, displayName: nil, provider: "")

    var friendlyName: String {
        if let displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return displayName
        }
        if let email, let first = email.split(separator: "@").first, !first.isEmpty {
            return String(first)
        }
        return "You"
    }

    var initials: String {
        let words = friendlyName.split(separator: " ").prefix(2)
        let value = words.compactMap(\.first).map(String.init).joined().uppercased()
        return value.isEmpty ? "PK" : value
    }
}

@MainActor
final class AuthController: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var profile: AuthProfile = .empty
    @Published var isWorking = false
    @Published var errorText: String?

    private var webSession: ASWebAuthenticationSession?

    struct AuthResponse: Decodable {
        let userID: String
        let token: String
        let expiresIn: Int
        let profile: AuthProfile
    }

    struct GoogleStartResponse: Decodable {
        let authorizationURL: String
    }

    struct ExchangeBody: Encodable { let code: String }
    struct EmailBody: Encodable {
        let email: String
        let password: String
        let displayName: String?
    }
    struct AppleBody: Encodable {
        let identityToken: String
        let authorizationCode: String?
        let email: String?
        let displayName: String?
    }

    func restore() async {
        guard let token = KeychainStore.string(for: "apiToken"), !token.isEmpty,
              let userID = KeychainStore.string(for: "userID"), !userID.isEmpty else {
            isAuthenticated = false
            return
        }

        let profile = AuthProfile(
            id: userID,
            email: KeychainStore.string(for: "accountEmail").flatMap { $0.isEmpty ? nil : $0 },
            displayName: KeychainStore.string(for: "accountName").flatMap { $0.isEmpty ? nil : $0 },
            provider: KeychainStore.string(for: "accountProvider") ?? "account"
        )
        self.profile = profile
        isAuthenticated = true
    }

    func emailSignIn(email: String, password: String) async {
        await emailRequest(path: "/api/auth/email/signin", email: email, password: password, displayName: nil)
    }

    func emailSignUp(name: String, email: String, password: String) async {
        await emailRequest(path: "/api/auth/email/signup", email: email, password: password, displayName: name)
    }

    private func emailRequest(path: String, email: String, password: String, displayName: String?) async {
        await perform {
            let response: AuthResponse = try await self.post(
                path: path,
                body: EmailBody(email: email, password: password, displayName: displayName)
            )
            await self.accept(response)
        }
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        Task {
            switch result {
            case .failure(let error):
                errorText = error.localizedDescription
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let identityData = credential.identityToken,
                      let identityToken = String(data: identityData, encoding: .utf8) else {
                    errorText = "Apple did not return a valid identity token."
                    return
                }
                let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
                let name = PersonNameComponentsFormatter().string(from: credential.fullName ?? PersonNameComponents())
                await perform {
                    let response: AuthResponse = try await self.post(
                        path: "/api/auth/apple",
                        body: AppleBody(
                            identityToken: identityToken,
                            authorizationCode: code,
                            email: credential.email,
                            displayName: name.isEmpty ? nil : name
                        )
                    )
                    await self.accept(response)
                }
            }
        }
    }

    func signInWithGoogle() async {
        await perform {
            let start: GoogleStartResponse = try await self.get(path: "/api/auth/google/start")
            guard let url = URL(string: start.authorizationURL) else { throw AuthError.invalidResponse }
            let callbackURL = try await self.openWebAuthentication(url: url)
            guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
                  !code.isEmpty else {
                throw AuthError.providerDidNotFinish
            }
            let response: AuthResponse = try await self.post(path: "/api/auth/exchange", body: ExchangeBody(code: code))
            await self.accept(response)
        }
    }

    func handleIncomingURL(_ url: URL) async {
        guard url.scheme == "pocketkernel", url.host == "auth" else { return }
        guard let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else { return }
        await perform {
            let response: AuthResponse = try await self.post(path: "/api/auth/exchange", body: ExchangeBody(code: code))
            await self.accept(response)
        }
    }

    func signOut() async {
        await BackendClient.shared.clearIdentity()
        KeychainStore.set("", for: "accountEmail")
        KeychainStore.set("", for: "accountName")
        KeychainStore.set("", for: "accountProvider")
        profile = .empty
        isAuthenticated = false
        errorText = nil
    }

    private func accept(_ response: AuthResponse) async {
        await BackendClient.shared.clearIdentity()
        KeychainStore.set(response.token, for: "apiToken")
        KeychainStore.set(response.userID, for: "userID")
        KeychainStore.set(response.profile.email ?? "", for: "accountEmail")
        KeychainStore.set(response.profile.displayName ?? "", for: "accountName")
        KeychainStore.set(response.profile.provider, for: "accountProvider")
        profile = response.profile
        errorText = nil
        isAuthenticated = true
    }

    private func perform(_ operation: @escaping () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        do { try await operation() }
        catch { errorText = friendly(error) }
    }

    private func openWebAuthentication(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "pocketkernel") { [weak self] callbackURL, error in
                self?.webSession = nil
                if let error { continuation.resume(throwing: error); return }
                guard let callbackURL else { continuation.resume(throwing: AuthError.providerDidNotFinish); return }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webSession = session
            guard session.start() else {
                self.webSession = nil
                continuation.resume(throwing: AuthError.couldNotStart)
                return
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return window }
        if let scene = scenes.first { return UIWindow(windowScene: scene) }
        return UIWindow(frame: .zero)
    }

    private var baseURL: URL {
        let stored = UserDefaults.standard.string(forKey: "backendURL") ?? "https://pocketkernel.vercel.app"
        return URL(string: stored.trimmingCharacters(in: CharacterSet(charactersIn: "/")))!
    }

    private func get<Response: Decodable>(path: String) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.setValue("application/json", forHTTPHeaderField: "accept")
        return try await decode(request)
    }

    private func post<Response: Decodable, Body: Encodable>(path: String, body: Body) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await decode(request)
    }

    private func decode<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ServerError.self, from: data).error) ?? "HTTP \(http.statusCode)"
            throw AuthError.server(message)
        }
        do { return try JSONDecoder().decode(Response.self, from: data) }
        catch { throw AuthError.server("The account service returned unreadable data.") }
    }

    private func friendly(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription { return description }
        return error.localizedDescription
    }

    struct ServerError: Decodable { let error: String }

    enum AuthError: LocalizedError {
        case invalidResponse
        case providerDidNotFinish
        case couldNotStart
        case server(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "The account service returned an invalid response."
            case .providerDidNotFinish: "The sign-in window closed before the account was connected."
            case .couldNotStart: "PocketKernel could not open the secure sign-in window."
            case .server(let value): value.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }
    }
}

// MARK: - Cinematic launch

struct CinematicBootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var progress: CGFloat = 0.06
    @State private var status = "Waking your private workspace"

    var body: some View {
        ZStack {
            MotionBackdrop(intensity: 1.0)

            VStack(spacing: 32) {
                Spacer()

                KineticLogo(size: 126, energetic: !reduceMotion)
                    .scaleEffect(appeared ? 1 : 0.78)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: 9) {
                    Text("PocketKernel")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .tracking(-1.2)
                    Text("Your world, quietly automated")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.68))
                }
                .foregroundStyle(.white)
                .offset(y: appeared ? 0 : 16)
                .opacity(appeared ? 1 : 0)

                Spacer()

                VStack(spacing: 12) {
                    HStack {
                        Text(status)
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.caption.monospacedDigit().weight(.bold))
                    }
                    .foregroundStyle(.white.opacity(0.68))

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.10))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.cyan, .blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: proxy.size.width * progress)
                                .shadow(color: .cyan.opacity(0.45), radius: 12)
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 42)
            }
        }
        .ignoresSafeArea()
        .task {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.72)) { appeared = true }
            withAnimation(.easeInOut(duration: 0.75)) { progress = 0.38 }
            try? await Task.sleep(nanoseconds: 750_000_000)
            status = "Securing your account"
            withAnimation(.easeInOut(duration: 0.7)) { progress = 0.72 }
            try? await Task.sleep(nanoseconds: 680_000_000)
            status = "Preparing your command center"
            withAnimation(.easeOut(duration: 0.7)) { progress = 1.0 }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("PocketKernel is starting")
    }
}

// MARK: - Account gateway

struct AuthGatewayView: View {
    @EnvironmentObject private var auth: AuthController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showEmail = false
    @State private var reveal = false
    @State private var selectedBenefit = 0

    private let benefits = [
        ("bolt.shield.fill", "Private intelligence", "Planning stays on your iPhone."),
        ("arrow.triangle.2.circlepath", "Always in motion", "Automations keep working when you are busy."),
        ("hand.raised.fill", "You approve the important stuff", "Nothing sensitive runs behind your back.")
    ]

    var body: some View {
        ZStack {
            MotionBackdrop(intensity: 0.86)

            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 34)

                    KineticLogo(size: 94, energetic: !reduceMotion)
                        .scaleEffect(reveal ? 1 : 0.72)
                        .opacity(reveal ? 1 : 0)

                    VStack(spacing: 10) {
                        Text("Make your phone work for you")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .tracking(-1.0)
                        Text("Sign in once. Then ask PocketKernel to handle the repetitive parts of your day.")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.67))
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .offset(y: reveal ? 0 : 20)
                    .opacity(reveal ? 1 : 0)

                    benefitCarousel

                    VStack(spacing: 12) {
                        SignInWithAppleButton(.continue) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            auth.completeAppleSignIn(result)
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .disabled(auth.isWorking)

                        Button {
                            Task { await auth.signInWithGoogle() }
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(.white)
                                    Text("G")
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                        .foregroundStyle(.blue)
                                }
                                .frame(width: 27, height: 27)
                                Text("Continue with Google")
                                    .font(.headline)
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.subheadline.bold())
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(.white.opacity(0.18)))
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        .disabled(auth.isWorking)

                        Button {
                            showEmail = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "envelope.fill")
                                    .frame(width: 27, height: 27)
                                Text("Continue with email")
                                    .font(.headline)
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.subheadline.bold())
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(.white.opacity(0.14)))
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        .disabled(auth.isWorking)

                        if auth.isWorking {
                            HStack(spacing: 10) {
                                ProgressView().tint(.white)
                                Text("Signing you in securely…")
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.top, 4)
                        }

                        if let error = auth.errorText {
                            AuthErrorBanner(text: error)
                        }
                    }
                    .padding(18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.34), .white.opacity(0.08), .indigo.opacity(0.35)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.30), radius: 36, y: 22)
                    .padding(.horizontal, 18)
                    .offset(y: reveal ? 0 : 30)
                    .opacity(reveal ? 1 : 0)

                    HStack(spacing: 5) {
                        Text("By continuing, you agree to the")
                        Link("Terms", destination: URL(string: "https://pocketkernel.vercel.app/terms.html")!)
                        Text("and")
                        Link("Privacy Policy", destination: URL(string: "https://pocketkernel.vercel.app/privacy.html")!)
                    }
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.56))
                    .tint(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 28)
                }
            }
            .scrollIndicators(.hidden)
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showEmail) {
            EmailAuthSheet()
                .environmentObject(auth)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            withAnimation(.spring(response: 0.82, dampingFraction: 0.78).delay(0.08)) { reveal = true }
            guard !reduceMotion else { return }
            Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_200_000_000)
                    withAnimation(.snappy(duration: 0.65)) { selectedBenefit = (selectedBenefit + 1) % benefits.count }
                }
            }
        }
    }

    private var benefitCarousel: some View {
        let benefit = benefits[selectedBenefit]
        return HStack(spacing: 14) {
            Image(systemName: benefit.0)
                .font(.title2)
                .foregroundStyle(.cyan)
                .frame(width: 48, height: 48)
                .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 3) {
                Text(benefit.1)
                    .font(.headline)
                Text(benefit.2)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .id(selectedBenefit)
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
        .padding(.horizontal, 26)
        .frame(maxWidth: 560)
    }
}

struct EmailAuthSheet: View {
    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign in"
        case create = "Create account"
        var id: String { rawValue }
    }

    @EnvironmentObject private var auth: AuthController
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var revealPassword = false
    @FocusState private var focusedField: Field?

    enum Field { case name, email, password, confirm }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        KineticLogo(size: 72, energetic: false)
                            .padding(.top, 12)

                        VStack(spacing: 8) {
                            Text(mode == .signIn ? "Welcome back" : "Build your command center")
                                .font(.largeTitle.bold())
                                .multilineTextAlignment(.center)
                            Text(mode == .signIn ? "Use the email linked to your PocketKernel account." : "Create one secure account for your automations and connected apps.")
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        Picker("Account action", selection: $mode) {
                            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        VStack(spacing: 14) {
                            if mode == .create {
                                AuthTextField(
                                    title: "Your name",
                                    symbol: "person.fill",
                                    text: $name,
                                    contentType: .name,
                                    secure: false,
                                    revealSecure: .constant(false)
                                )
                                .focused($focusedField, equals: .name)
                            }

                            AuthTextField(
                                title: "Email address",
                                symbol: "envelope.fill",
                                text: $email,
                                contentType: .emailAddress,
                                secure: false,
                                revealSecure: .constant(false)
                            )
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .focused($focusedField, equals: .email)

                            AuthTextField(
                                title: "Password",
                                symbol: "lock.fill",
                                text: $password,
                                contentType: mode == .create ? .newPassword : .password,
                                secure: true,
                                revealSecure: $revealPassword
                            )
                            .focused($focusedField, equals: .password)

                            if mode == .create {
                                AuthTextField(
                                    title: "Confirm password",
                                    symbol: "checkmark.shield.fill",
                                    text: $confirmPassword,
                                    contentType: .newPassword,
                                    secure: true,
                                    revealSecure: $revealPassword
                                )
                                .focused($focusedField, equals: .confirm)
                            }
                        }

                        if mode == .create {
                            PasswordStrengthView(password: password)
                        }

                        if let localError {
                            AuthErrorBanner(text: localError, darkText: true)
                        } else if let error = auth.errorText {
                            AuthErrorBanner(text: error, darkText: true)
                        }

                        Button {
                            focusedField = nil
                            Task {
                                if mode == .signIn {
                                    await auth.emailSignIn(email: normalizedEmail, password: password)
                                } else {
                                    await auth.emailSignUp(name: name.trimmingCharacters(in: .whitespacesAndNewlines), email: normalizedEmail, password: password)
                                }
                                if auth.isAuthenticated { dismiss() }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                if auth.isWorking { ProgressView().tint(.white) }
                                Text(mode == .signIn ? "Sign in" : "Create account")
                                    .font(.headline)
                                Image(systemName: "arrow.right")
                            }
                            .frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: 17))
                        .disabled(localError != nil || auth.isWorking)

                        Text(mode == .create ? "Use at least 8 characters. PocketKernel never sells your personal data." : "Your account secures saved automations across devices.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onChange(of: mode) {
                auth.errorText = nil
                confirmPassword = ""
            }
        }
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var localError: String? {
        if mode == .create && name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 { return "Enter your name." }
        if !normalizedEmail.contains("@") || !normalizedEmail.contains(".") { return "Enter a valid email address." }
        if password.count < 8 { return "Password must contain at least 8 characters." }
        if mode == .create && password != confirmPassword { return "The passwords do not match." }
        return nil
    }
}

struct AuthTextField: View {
    let title: String
    let symbol: String
    @Binding var text: String
    let contentType: UITextContentType?
    let secure: Bool
    @Binding var revealSecure: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.indigo)
                .frame(width: 24)
            Group {
                if secure && !revealSecure {
                    SecureField(title, text: $text)
                } else {
                    TextField(title, text: $text)
                }
            }
            .textContentType(contentType)
            .font(.body.weight(.medium))
            if secure {
                Button { revealSecure.toggle() } label: {
                    Image(systemName: revealSecure ? "eye.slash.fill" : "eye.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 56)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.secondary.opacity(0.18)))
    }
}

struct PasswordStrengthView: View {
    let password: String

    private var score: Int {
        var score = 0
        if password.count >= 8 { score += 1 }
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil { score += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { score += 1 }
        if password.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil { score += 1 }
        return score
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index < score ? strengthColor : Color.secondary.opacity(0.16))
                        .frame(height: 5)
                }
            }
            Text(score <= 1 ? "Use a stronger password" : score == 2 ? "Good password" : "Strong password")
                .font(.caption.weight(.semibold))
                .foregroundStyle(score <= 1 ? .orange : .green)
        }
    }

    private var strengthColor: Color { score <= 1 ? .orange : score == 2 ? .yellow : .green }
}

struct AccountSheet: View {
    @EnvironmentObject private var auth: AuthController
    @EnvironmentObject private var chat: ChatController
    @EnvironmentObject private var oauth: OAuthCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle().fill(LinearGradient(colors: [.indigo, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                            Text(auth.profile.initials)
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                        }
                        .frame(width: 58, height: 58)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(auth.profile.friendlyName).font(.title3.bold())
                            if let email = auth.profile.email { Text(email).font(.caption).foregroundStyle(.secondary) }
                            Text(auth.profile.provider.capitalized)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.indigo)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Workspace") {
                    LabeledContent("Connected apps", value: String(oauth.connections.count))
                    LabeledContent("Recent actions", value: String(chat.activity.count))
                    Label("Private planning on this iPhone", systemImage: "lock.shield.fill")
                }

                Section {
                    Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        confirmSignOut = true
                    }
                }
            }
            .navigationTitle("Account")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Sign out of PocketKernel?", isPresented: $confirmSignOut) {
                Button("Sign out", role: .destructive) {
                    Task {
                        await auth.signOut()
                        chat.clearAllLocalData()
                        oauth.connections.removeAll()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Your saved cloud automations remain in your account. Local chat and activity history will be cleared from this iPhone.")
            }
        }
    }
}

// MARK: - Motion system

struct MotionBackdrop: View {
    let intensity: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.025, green: 0.035, blue: 0.10), Color(red: 0.055, green: 0.02, blue: 0.16), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.indigo.opacity(0.55 * intensity))
                .frame(width: 420, height: 420)
                .blur(radius: 80)
                .offset(x: drift ? 150 : -140, y: drift ? -260 : -170)

            Circle()
                .fill(Color.cyan.opacity(0.34 * intensity))
                .frame(width: 330, height: 330)
                .blur(radius: 85)
                .offset(x: drift ? -170 : 170, y: drift ? 210 : 310)

            Circle()
                .fill(Color.purple.opacity(0.34 * intensity))
                .frame(width: 300, height: 300)
                .blur(radius: 70)
                .offset(x: drift ? 150 : -180, y: drift ? 90 : 20)

            ParticleField(active: !reduceMotion)
                .opacity(0.62 * intensity)

            LinearGradient(colors: [.white.opacity(0.05), .clear, .black.opacity(0.20)], startPoint: .top, endPoint: .bottom)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 8.5).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

struct ParticleField: View {
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: active ? 1.0 / 30.0 : 1.0, paused: !active)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<34 {
                    let seed = Double(index * 37 + 11)
                    let baseX = (sin(seed * 1.71) + 1) * 0.5
                    let baseY = (cos(seed * 2.13) + 1) * 0.5
                    let x = baseX * size.width + sin(time * (0.11 + Double(index % 5) * 0.018) + seed) * 34
                    let y = baseY * size.height + cos(time * (0.08 + Double(index % 7) * 0.014) + seed) * 46
                    let radius = 0.8 + Double(index % 4) * 0.65
                    let alpha = 0.15 + Double(index % 5) * 0.06
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                        with: .color(.white.opacity(alpha))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct KineticLogo: View {
    let size: CGFloat
    let energetic: Bool
    @State private var spin = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(AngularGradient(colors: [.cyan, .blue, .purple, .cyan], center: .center), lineWidth: size * 0.025)
                .frame(width: size, height: size)
                .rotationEffect(.degrees(spin ? 360 : 0))

            Circle()
                .trim(from: 0.12, to: 0.74)
                .stroke(.white.opacity(0.38), style: StrokeStyle(lineWidth: size * 0.018, lineCap: .round))
                .frame(width: size * 0.79, height: size * 0.79)
                .rotationEffect(.degrees(spin ? -320 : 0))

            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.indigo, Color.blue, Color.cyan.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.57, height: size * 0.57)
                .shadow(color: .cyan.opacity(0.36), radius: size * 0.17)
                .overlay {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: size * 0.25, weight: .black))
                        .foregroundStyle(.white)
                }
                .scaleEffect(pulse ? 1.055 : 0.96)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard energetic else { return }
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

struct AuthErrorBanner: View {
    let text: String
    var darkText = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(darkText ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.white.opacity(0.88)))
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(darkText ? 0.12 : 0.18), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
