import SwiftUI
import Foundation
import FoundationModels
import AuthenticationServices
import Security
import UserNotifications
import EventKit
import UIKit

// MARK: - OAuth UI coordinator

@MainActor
final class OAuthCoordinator: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var connections: [ServiceConnection] = []
    @Published var configured: [String: Bool] = [:]
    @Published var isLoading = false
    @Published var errorText: String?
    private var session: ASWebAuthenticationSession?

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await BackendClient.shared.connections()
            connections = response.connections
            configured = response.configured
            errorText = nil
        } catch { errorText = error.localizedDescription }
    }

    func connect(_ provider: String) async {
        do {
            let url = try await BackendClient.shared.startOAuth(provider: provider)
            try await withCheckedThrowingContinuation { continuation in
                let webSession = ASWebAuthenticationSession(url: url, callbackURLScheme: "pocketkernel") { [weak self] callbackURL, error in
                    self?.session = nil
                    if let error { continuation.resume(throwing: error); return }
                    guard let callbackURL,
                          URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "status" })?.value == "connected" else {
                        continuation.resume(throwing: OAuthError.failed)
                        return
                    }
                    continuation.resume(returning: ())
                }
                webSession.presentationContextProvider = self
                webSession.prefersEphemeralWebBrowserSession = false
                self.session = webSession
                guard webSession.start() else {
                    self.session = nil
                    continuation.resume(throwing: OAuthError.couldNotStart)
                    return
                }
            }
            await refresh()
        } catch { errorText = error.localizedDescription }
    }

    func disconnect(_ provider: String) async {
        do {
            try await BackendClient.shared.disconnect(provider: provider)
            await refresh()
        } catch { errorText = error.localizedDescription }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    enum OAuthError: LocalizedError {
        case failed, couldNotStart
        var errorDescription: String? {
            switch self {
            case .failed: "The service did not complete sign-in."
            case .couldNotStart: "Could not open the secure sign-in window."
            }
        }
    }
}
