import SwiftUI
import Foundation
import FoundationModels
import AuthenticationServices
import Security
import UserNotifications
import EventKit
import UIKit

// MARK: - Chat agent

@MainActor
final class ChatController: ObservableObject {
    @Published var messages: [ChatMessage] {
        didSet { persist() }
    }
    @Published var pending: [ToolProposal] = []
    @Published var activity: [ActivityItem] {
        didSet { persist() }
    }
    @Published var isThinking = false
    @Published var errorText: String?

    private let broker = ProposalBroker()
    private var session: Any?
    private static let messagesKey = "pocketkernel.chat.messages.v2"
    private static let activityKey = "pocketkernel.activity.v2"

    init() {
        messages = Self.load([ChatMessage].self, key: Self.messagesKey) ?? [Self.welcomeMessage]
        activity = Self.load([ActivityItem].self, key: Self.activityKey) ?? []
        if messages.isEmpty { messages = [Self.welcomeMessage] }
    }

    static var welcomeMessage: ChatMessage {
        ChatMessage(role: .assistant, text: "What would you like to take off your plate?")
    }

    var hasConversation: Bool {
        messages.contains { $0.role == .user }
    }

    var readiness: ModelReadiness {
        guard #available(iOS 27.0, *) else { return .unsupported }
        return SystemLanguageModel.default.isAvailable ? .ready : .unavailable
    }

    func send(_ text: String) async {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isThinking else { return }
        messages.append(ChatMessage(role: .user, text: prompt))
        errorText = nil
        isThinking = true
        defer { isThinking = false }

        guard #available(iOS 27.0, *) else {
            let message = "Update this iPhone to iOS 27 to use private automation."
            errorText = message
            messages.append(ChatMessage(role: .system, text: message))
            return
        }
        guard SystemLanguageModel.default.isAvailable else {
            let message = "Apple Intelligence is not ready yet. Turn it on in Settings and let the model finish downloading."
            errorText = message
            messages.append(ChatMessage(role: .system, text: message))
            return
        }

        do {
            let activeSession: LanguageModelSession
            if let existing = session as? LanguageModelSession {
                activeSession = existing
            } else {
                activeSession = LanguageModelSession(
                    model: .default,
                    tools: [
                        NativeActionTool(broker: broker),
                        ServiceActionTool(broker: broker),
                        ScheduleAutomationTool(broker: broker)
                    ]
                ) {
                    """
                    You are PocketKernel, a friendly private automation assistant for everyday iPhone users.

                    Understand what the person wants, ask one short clarifying question only when a required detail is missing, and call a registered tool when an action is ready.
                    Use plain language. Do not mention APIs, JSON, OAuth, tokens, providers, backends, language models, or implementation details unless the person explicitly asks.
                    Never claim something happened until a tool result confirms it.
                    Never ask for passwords, access tokens, API keys, or secret credentials. Official sign-in is handled by the app.
                    Never invent unsupported actions or connected apps.
                    For Gmail, Slack, Discord, Reddit, Notion, and Google Calendar, use serviceAction.
                    For repeated unattended work, first identify the exact service action, then use scheduleAutomation with deterministic steps.
                    For reminders, calendar events, links, clipboard, notifications, and local notes, use nativeAction.
                    Significant writes must be shown for approval before execution. Read-only Gmail listing may run without approval.
                    Keep answers warm, concise, and focused on the outcome.
                    """
                }
                session = activeSession
            }
            let response = try await activeSession.respond(to: prompt)
            let reply = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !reply.isEmpty {
                messages.append(ChatMessage(role: .assistant, text: reply))
            }
            let newProposals = await broker.drain()
            pending.append(contentsOf: newProposals)
        } catch {
            let message = friendly(error)
            errorText = message
            messages.append(ChatMessage(role: .system, text: message))
        }
    }

    func send(_ template: StarterTemplate) async {
        await send(template.prompt)
    }

    func approve(_ proposal: ToolProposal, executor: ActionExecutor) async {
        pending.removeAll { $0.id == proposal.id }
        do {
            let result = try await executor.execute(proposal)
            activity.insert(ActivityItem(title: proposal.title, detail: result, succeeded: true), at: 0)
            messages.append(ChatMessage(role: .assistant, text: result.isEmpty ? "Done." : result))
            if #available(iOS 27.0, *), let activeSession = session as? LanguageModelSession {
                _ = try? await activeSession.respond(to: "The person approved the proposed action. It completed with this result: \(result). Keep that result in context. Do not call another tool unless the person asks.")
            }
        } catch {
            let message = friendly(error)
            activity.insert(ActivityItem(title: proposal.title, detail: message, succeeded: false), at: 0)
            messages.append(ChatMessage(role: .system, text: "I couldn’t complete “\(proposal.title)”. \(message)"))
        }
    }

    func reject(_ proposal: ToolProposal) {
        pending.removeAll { $0.id == proposal.id }
        messages.append(ChatMessage(role: .system, text: "No problem — I didn’t run “\(proposal.title)”."))
    }

    func reset() {
        session = nil
        messages = [Self.welcomeMessage]
        pending.removeAll()
        errorText = nil
    }

    func clearActivity() {
        activity.removeAll()
    }

    func clearAllLocalData() {
        session = nil
        messages = [Self.welcomeMessage]
        pending.removeAll()
        activity.removeAll()
        errorText = nil
        UserDefaults.standard.removeObject(forKey: Self.messagesKey)
        UserDefaults.standard.removeObject(forKey: Self.activityKey)
    }

    private func friendly(_ error: Error) -> String {
        let raw = error.localizedDescription
        if raw.localizedCaseInsensitiveContains("network") || raw.localizedCaseInsensitiveContains("offline") {
            return "I couldn’t reach the service. Check your connection and try again."
        }
        if raw.localizedCaseInsensitiveContains("not connected") || raw.localizedCaseInsensitiveContains("connection_required") {
            return "Connect the required app first, then try again."
        }
        if raw.localizedCaseInsensitiveContains("cancel") {
            return "The action was canceled."
        }
        return raw
    }

    private func persist() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(messages) {
            UserDefaults.standard.set(data, forKey: Self.messagesKey)
        }
        if let data = try? encoder.encode(Array(activity.prefix(250))) {
            UserDefaults.standard.set(data, forKey: Self.activityKey)
        }
    }

    private static func load<Value: Decodable>(_ type: Value.Type, key: String) -> Value? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
