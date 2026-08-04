import SwiftUI
import Foundation
import FoundationModels
import AuthenticationServices
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

    var body: some Scene {
        WindowGroup {
            AppEntryView()
                .environmentObject(chat)
                .environmentObject(executor)
                .environmentObject(oauth)
                .environmentObject(account)
                .onOpenURL { _ in Task { await oauth.refresh() } }
        }
    }
}
