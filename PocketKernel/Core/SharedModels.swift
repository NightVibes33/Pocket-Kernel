import SwiftUI
import Foundation
import FoundationModels
import AuthenticationServices
import Security
import UserNotifications
import EventKit
import UIKit

// MARK: - Shared models

enum ChatRole: String, Codable, Sendable { case user, assistant, system }

struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var role: ChatRole
    var text: String
    var createdAt = Date()
}

enum ProposalKind: String, Codable, Hashable, Sendable {
    case native
    case service
    case schedule
}

struct ToolProposal: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var kind: ProposalKind
    var title: String
    var summary: String
    var provider: String?
    var action: String
    var input: [String: String]
    var requiresApproval: Bool
    var createdAt = Date()
}

struct ServiceConnection: Identifiable, Codable, Hashable, Sendable {
    var provider: String
    var connectedAt: String?
    var expiresAt: String?
    var id: String { provider }
}

struct SavedAutomation: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var title: String
    var prompt: String
    var enabled: Bool
    var nextRunAt: String?
    var repeatSeconds: Int
    var createdAt: String
    var lastRunAt: String?
    var lastRunOK: Bool?
    var lastError: String?
}

struct ActivityItem: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var detail: String
    var succeeded: Bool
    var date = Date()
}

struct ProviderDescriptor: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let tint: Color
    let description: String

    static let all: [ProviderDescriptor] = [
        .init(id: "google", name: "Google", symbol: "envelope.badge", tint: .blue, description: "Gmail, Calendar, and Drive"),
        .init(id: "slack", name: "Slack", symbol: "number", tint: .purple, description: "Channels and messages"),
        .init(id: "discord", name: "Discord", symbol: "bubble.left.and.bubble.right.fill", tint: .indigo, description: "Servers and webhooks"),
        .init(id: "reddit", name: "Reddit", symbol: "text.bubble.fill", tint: .orange, description: "Read and publish posts"),
        .init(id: "notion", name: "Notion", symbol: "doc.text.fill", tint: .primary, description: "Pages and databases")
    ]
}
