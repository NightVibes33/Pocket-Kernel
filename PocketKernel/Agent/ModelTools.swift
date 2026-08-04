import SwiftUI
import Foundation
import FoundationModels
import AuthenticationServices
import Security
import UserNotifications
import EventKit
import UIKit

// MARK: - Proposal broker and model tools

actor ProposalBroker {
    private var proposals: [ToolProposal] = []

    func propose(_ proposal: ToolProposal) -> String {
        proposals.append(proposal)
        return "Queued proposal \(proposal.id.uuidString). The app will ask the person for approval before execution."
    }

    func drain() -> [ToolProposal] {
        defer { proposals.removeAll() }
        return proposals
    }
}

@available(iOS 27.0, *)
struct NativeActionTool: Tool {
    let name = "nativeAction"
    let description = "Proposes a native iPhone action such as a notification, reminder, calendar event, opening an HTTPS URL, copying text, or appending a private local note. The app asks for approval before side effects."
    let broker: ProposalBroker

    @Generable
    struct Arguments {
        @Guide(description: "One of notify, reminder, calendar, openURL, copyText, appendNote.")
        let action: String
        @Guide(description: "Short title shown to the person before approval.")
        let title: String
        @Guide(description: "A JSON object encoded as a string. Examples: {\"text\":\"Hello\"}; {\"title\":\"Meeting\",\"start\":\"2026-08-04T20:00:00Z\",\"end\":\"2026-08-04T20:30:00Z\"}.")
        let inputJSON: String
    }

    func call(arguments: Arguments) async throws -> String {
        let input = Self.decode(arguments.inputJSON)
        return await broker.propose(ToolProposal(
            kind: .native,
            title: arguments.title,
            summary: Self.summary(action: arguments.action, input: input),
            action: arguments.action,
            input: input,
            requiresApproval: true
        ))
    }

    static func decode(_ value: String) -> [String: String] {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ["text": value] }
        return object.mapValues { String(describing: $0) }
    }

    static func summary(action: String, input: [String: String]) -> String {
        input["text"] ?? input["title"] ?? input["url"] ?? action
    }
}

@available(iOS 27.0, *)
struct ServiceActionTool: Tool {
    let name = "serviceAction"
    let description = "Proposes an action through a service the person connected with OAuth. Supported actions: google gmail.list, gmail.send, calendar.create; slack message.send; discord webhook.send; reddit post.create; notion page.create. Write actions always require approval."
    let broker: ProposalBroker

    @Generable
    struct Arguments {
        @Guide(description: "google, slack, discord, reddit, or notion")
        let provider: String
        @Guide(description: "A supported provider action, for example gmail.send or message.send.")
        let action: String
        @Guide(description: "Short title shown in the approval card.")
        let title: String
        @Guide(description: "The action input as a JSON object encoded in a string.")
        let inputJSON: String
    }

    func call(arguments: Arguments) async throws -> String {
        let input = NativeActionTool.decode(arguments.inputJSON)
        let readOnly = arguments.provider.lowercased() == "google" && arguments.action == "gmail.list"
        return await broker.propose(ToolProposal(
            kind: .service,
            title: arguments.title,
            summary: "\(arguments.provider.capitalized) · \(arguments.action)",
            provider: arguments.provider.lowercased(),
            action: arguments.action,
            input: input,
            requiresApproval: !readOnly
        ))
    }
}

@available(iOS 27.0, *)
struct ScheduleAutomationTool: Tool {
    let name = "scheduleAutomation"
    let description = "Proposes saving one or more already-understood service actions as a deterministic server automation. Use only for actions that can run without asking the on-device model again."
    let broker: ProposalBroker

    @Generable
    struct Arguments {
        let title: String
        @Guide(description: "A short summary of the recurring automation.")
        let summary: String
        @Guide(description: "JSON array of deterministic steps. Each service step has kind=service, provider, action, and input object.")
        let stepsJSON: String
        @Guide(description: "ISO-8601 first run time, or an empty string for no scheduled run.")
        let nextRunAt: String
        @Guide(description: "Repeat interval in seconds. Use 0 for one-time. Minimum useful recurring interval is 60.", .range(0...31536000))
        let repeatSeconds: Int
    }

    func call(arguments: Arguments) async throws -> String {
        return await broker.propose(ToolProposal(
            kind: .schedule,
            title: arguments.title,
            summary: arguments.summary,
            action: "saveAutomation",
            input: [
                "stepsJSON": arguments.stepsJSON,
                "nextRunAt": arguments.nextRunAt,
                "repeatSeconds": String(arguments.repeatSeconds)
            ],
            requiresApproval: true
        ))
    }
}
