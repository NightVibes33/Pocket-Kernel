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
    @Published var messages: [ChatMessage] = [
        ChatMessage(role: .assistant, text: "Tell me what you want done. I use the iOS 27 model on this iPhone, call registered tools, and ask before anything sensitive happens.")
    ]
    @Published var pending: [ToolProposal] = []
    @Published var activity: [ActivityItem] = []
    @Published var isThinking = false
    @Published var errorText: String?

    private let broker = ProposalBroker()
    private var session: Any?

    var modelStatus: String {
        guard #available(iOS 27.0, *) else { return "Requires iOS 27" }
        return SystemLanguageModel.default.isAvailable ? "On-device model ready" : "Apple Intelligence unavailable"
    }

    func send(_ text: String) async {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        messages.append(ChatMessage(role: .user, text: prompt))
        errorText = nil
        isThinking = true
        defer { isThinking = false }

        guard #available(iOS 27.0, *) else {
            errorText = "PocketKernel requires iOS 27 for its on-device chat agent."
            return
        }
        guard SystemLanguageModel.default.isAvailable else {
            errorText = "Turn on Apple Intelligence and allow the model to finish downloading."
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
                    You are PocketKernel, a private chat automation agent running with Apple's on-device iOS 27 foundation model.

                    Your job is to understand requests, explain briefly, and call registered tools when an action is needed.
                    Never claim an action happened unless a tool result confirms it.
                    Never ask for OAuth passwords or tokens. The app handles official service sign-in.
                    Never invent unsupported tools or services.
                    For Gmail, Slack, Discord, Reddit, Notion, and Google Calendar, use serviceAction.
                    For repeated unattended service work, first propose the concrete service action, then use scheduleAutomation with deterministic steps.
                    For iPhone actions, use nativeAction.
                    Sensitive writes must be proposed for approval. Read-only Gmail listing may run without approval.
                    Keep responses direct and useful.
                    """
                }
                session = activeSession
            }
            let response = try await activeSession.respond(to: prompt)
            messages.append(ChatMessage(role: .assistant, text: response.content))
            let newProposals = await broker.drain()
            pending.append(contentsOf: newProposals)
        } catch {
            errorText = error.localizedDescription
            messages.append(ChatMessage(role: .system, text: "The on-device agent stopped: \(error.localizedDescription)"))
        }
    }

    func approve(_ proposal: ToolProposal, executor: ActionExecutor) async {
        pending.removeAll { $0.id == proposal.id }
        do {
            let result = try await executor.execute(proposal)
            activity.insert(ActivityItem(title: proposal.title, detail: result, succeeded: true), at: 0)
            messages.append(ChatMessage(role: .assistant, text: result))
            if #available(iOS 27.0, *), let activeSession = session as? LanguageModelSession {
                _ = try? await activeSession.respond(to: "The person approved proposal \(proposal.id.uuidString). Execution result: \(result). Acknowledge the result without calling another tool unless necessary.")
            }
        } catch {
            activity.insert(ActivityItem(title: proposal.title, detail: error.localizedDescription, succeeded: false), at: 0)
            messages.append(ChatMessage(role: .system, text: "Couldn’t complete “\(proposal.title)”: \(error.localizedDescription)"))
        }
    }

    func reject(_ proposal: ToolProposal) {
        pending.removeAll { $0.id == proposal.id }
        messages.append(ChatMessage(role: .system, text: "Canceled “\(proposal.title)”."))
    }

    func reset() {
        session = nil
        messages = [ChatMessage(role: .assistant, text: "New private chat started. What should I automate?")]
        pending.removeAll()
        errorText = nil
    }
}
