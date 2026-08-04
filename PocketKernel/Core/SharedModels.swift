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

enum TemplateCategory: String, CaseIterable, Identifiable {
    case inbox = "Inbox"
    case planning = "Planning"
    case sharing = "Sharing"
    case personal = "Personal"

    var id: String { rawValue }
}

struct StarterTemplate: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let prompt: String
    let symbol: String
    let tint: Color
    let category: TemplateCategory

    static let featured: [StarterTemplate] = [
        .init(
            id: "morning-inbox",
            title: "Morning inbox brief",
            subtitle: "Summarize what needs attention",
            prompt: "Every weekday morning, summarize the important unread emails in my Gmail and tell me what needs a reply.",
            symbol: "sunrise.fill",
            tint: .orange,
            category: .inbox
        ),
        .init(
            id: "follow-up",
            title: "Follow-up reminder",
            subtitle: "Never lose track of a reply",
            prompt: "Remind me in three days if I have not received a reply to the latest important email I sent.",
            symbol: "arrowshape.turn.up.left.fill",
            tint: .blue,
            category: .inbox
        ),
        .init(
            id: "meeting-prep",
            title: "Meeting prep",
            subtitle: "Get ready before the call",
            prompt: "Before my next calendar event, give me a short preparation checklist and the important details from the event.",
            symbol: "person.2.fill",
            tint: .indigo,
            category: .planning
        ),
        .init(
            id: "slack-update",
            title: "Send a team update",
            subtitle: "Turn a thought into a clear post",
            prompt: "Help me write a concise project update and send it to my Slack channel after I approve it.",
            symbol: "text.bubble.fill",
            tint: .purple,
            category: .sharing
        ),
        .init(
            id: "quick-reminder",
            title: "Create a reminder",
            subtitle: "Capture it before you forget",
            prompt: "Create a reminder for tomorrow at 9 AM to review my weekly priorities.",
            symbol: "checkmark.circle.fill",
            tint: .green,
            category: .personal
        ),
        .init(
            id: "calendar-block",
            title: "Protect focus time",
            subtitle: "Add a block to your calendar",
            prompt: "Create a 90-minute focus block on my calendar tomorrow afternoon. Ask me before adding it.",
            symbol: "calendar.badge.plus",
            tint: .teal,
            category: .planning
        )
    ]
}

struct ProviderDescriptor: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let tint: Color
    let description: String
    let benefit: String

    static let all: [ProviderDescriptor] = [
        .init(id: "google", name: "Google", symbol: "envelope.fill", tint: .blue, description: "Gmail and Calendar", benefit: "Summarize mail, send approved messages, and create events"),
        .init(id: "slack", name: "Slack", symbol: "number", tint: .purple, description: "Channels and messages", benefit: "Post updates and keep teams informed"),
        .init(id: "discord", name: "Discord", symbol: "bubble.left.and.bubble.right.fill", tint: .indigo, description: "Servers and webhooks", benefit: "Send approved updates to a community"),
        .init(id: "reddit", name: "Reddit", symbol: "text.bubble.fill", tint: .orange, description: "Posts and communities", benefit: "Draft and publish posts after approval"),
        .init(id: "notion", name: "Notion", symbol: "doc.text.fill", tint: .primary, description: "Pages and workspaces", benefit: "Capture notes and create structured pages")
    ]

    static func named(_ id: String?) -> ProviderDescriptor? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}

enum ModelReadiness: Equatable {
    case ready
    case unavailable
    case unsupported

    var title: String {
        switch self {
        case .ready: "Private intelligence is ready"
        case .unavailable: "Apple Intelligence is still getting ready"
        case .unsupported: "This iPhone needs iOS 27"
        }
    }

    var detail: String {
        switch self {
        case .ready: "Planning happens privately on this iPhone."
        case .unavailable: "Turn on Apple Intelligence and let the model finish downloading."
        case .unsupported: "Update to iOS 27 to use the private automation assistant."
        }
    }

    var symbol: String {
        switch self {
        case .ready: "checkmark.shield.fill"
        case .unavailable: "arrow.down.circle.fill"
        case .unsupported: "exclamationmark.triangle.fill"
        }
    }
}

enum PocketDateFormatter {
    static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    static func friendly(_ value: String?) -> String? {
        guard let date = date(from: value) else { return nil }
        return date.formatted(.relative(presentation: .named))
    }

    static func full(_ value: String?) -> String? {
        guard let date = date(from: value) else { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

extension String {
    var pocketHumanizedKey: String {
        replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "URL", with: "link")
            .split(separator: " ")
            .map(String.init)
            .joined(separator: " ")
            .capitalized
    }
}
