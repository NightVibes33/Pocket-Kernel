import SwiftUI
import Foundation
import FoundationModels
import AuthenticationServices
import Security
import UserNotifications
import EventKit
import UIKit

// MARK: - App

@main
struct PocketKernelApp: App {
    @StateObject private var chat = ChatController()
    @StateObject private var executor = ActionExecutor()
    @StateObject private var oauth = OAuthCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(chat)
                .environmentObject(executor)
                .environmentObject(oauth)
                .onOpenURL { _ in Task { await oauth.refresh() } }
        }
    }
}
