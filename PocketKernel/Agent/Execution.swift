import SwiftUI
import Foundation
import FoundationModels
import AuthenticationServices
import Security
import UserNotifications
import EventKit
import UIKit

// MARK: - Native and remote execution

@MainActor
final class ActionExecutor: ObservableObject {
    private let eventStore = EKEventStore()

    func execute(_ proposal: ToolProposal) async throws -> String {
        switch proposal.kind {
        case .service:
            guard let provider = proposal.provider else { throw ExecutionError.missingProvider }
            return try await BackendClient.shared.execute(provider: provider, action: proposal.action, input: proposal.input)
        case .schedule:
            return try await saveSchedule(proposal)
        case .native:
            return try await executeNative(proposal)
        }
    }

    private func executeNative(_ proposal: ToolProposal) async throws -> String {
        switch proposal.action {
        case "notify":
            let center = UNUserNotificationCenter.current()
            guard try await center.requestAuthorization(options: [.alert, .sound, .badge]) else { throw ExecutionError.permissionDenied }
            let content = UNMutableNotificationContent()
            content.title = proposal.title
            content.body = proposal.input["text"] ?? proposal.summary
            content.sound = .default
            try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            return "Notification delivered."
        case "reminder":
            guard try await eventStore.requestFullAccessToReminders() else { throw ExecutionError.permissionDenied }
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = proposal.input["title"] ?? proposal.title
            reminder.notes = proposal.input["notes"]
            reminder.calendar = eventStore.defaultCalendarForNewReminders()
            if let raw = proposal.input["due"], let date = ISO8601DateFormatter().date(from: raw) {
                reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            }
            try eventStore.save(reminder, commit: true)
            return "Reminder created."
        case "calendar":
            guard try await eventStore.requestFullAccessToEvents() else { throw ExecutionError.permissionDenied }
            let event = EKEvent(eventStore: eventStore)
            event.title = proposal.input["title"] ?? proposal.title
            event.notes = proposal.input["notes"]
            let formatter = ISO8601DateFormatter()
            event.startDate = proposal.input["start"].flatMap { formatter.date(from: $0) } ?? Date().addingTimeInterval(300)
            event.endDate = proposal.input["end"].flatMap { formatter.date(from: $0) } ?? event.startDate.addingTimeInterval(1800)
            event.calendar = eventStore.defaultCalendarForNewEvents
            try eventStore.save(event, span: .thisEvent, commit: true)
            return "Calendar event created."
        case "openURL":
            guard let raw = proposal.input["url"], let url = URL(string: raw), url.scheme == "https" else { throw ExecutionError.invalidURL }
            guard await UIApplication.shared.open(url) else { throw ExecutionError.invalidURL }
            return "Opened \(url.host ?? "the URL")."
        case "copyText":
            UIPasteboard.general.string = proposal.input["text"] ?? proposal.summary
            return "Copied to the clipboard."
        case "appendNote":
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let file = directory.appendingPathComponent("PocketKernel Notes.txt")
            let text = "[\(Date().formatted())] \(proposal.input["text"] ?? proposal.summary)\n"
            if FileManager.default.fileExists(atPath: file.path) {
                let handle = try FileHandle(forWritingTo: file)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(text.utf8))
                try handle.close()
            } else {
                try Data(text.utf8).write(to: file, options: .atomic)
            }
            return "Appended to PocketKernel Notes.txt."
        default:
            throw ExecutionError.unsupportedAction
        }
    }

    private func saveSchedule(_ proposal: ToolProposal) async throws -> String {
        guard let raw = proposal.input["stepsJSON"], let data = raw.data(using: .utf8),
              let value = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw ExecutionError.invalidSteps }
        let steps: [[String: JSONValue]] = value.map { object in
            object.mapValues(Self.jsonValue)
        }
        let next = proposal.input["nextRunAt"].flatMap { $0.isEmpty ? nil : $0 }
        let repeatSeconds = Int(proposal.input["repeatSeconds"] ?? "0") ?? 0
        let saved = try await BackendClient.shared.saveAutomation(title: proposal.title, prompt: proposal.summary, steps: steps, nextRunAt: next, repeatSeconds: repeatSeconds)
        return "Saved automation “\(saved.title)”."
    }

    private static func jsonValue(_ value: Any) -> JSONValue {
        switch value {
        case let v as String: .string(v)
        case let v as NSNumber: CFGetTypeID(v) == CFBooleanGetTypeID() ? .bool(v.boolValue) : .number(v.doubleValue)
        case let v as [String: Any]: .object(v.mapValues(jsonValue))
        case let v as [Any]: .array(v.map(jsonValue))
        default: .null
        }
    }

    enum ExecutionError: LocalizedError {
        case missingProvider, permissionDenied, invalidURL, unsupportedAction, invalidSteps
        var errorDescription: String? {
            switch self {
            case .missingProvider: "The service provider is missing."
            case .permissionDenied: "The required iOS permission was denied."
            case .invalidURL: "Only valid HTTPS URLs can be opened."
            case .unsupportedAction: "That native action is not supported."
            case .invalidSteps: "The automation steps are invalid."
            }
        }
    }
}
