import Foundation
import FoundationModels
import UIKit
import UserNotifications
import Vision

enum HostServiceError: LocalizedError {
    case invalidURL, insecureURL, domainDenied, responseTooLarge, invalidResponse, permissionDenied, unsupported, invalidInput

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The URL is invalid."
        case .insecureURL: "Only HTTPS requests are allowed."
        case .domainDenied: "The destination domain is not allowed."
        case .responseTooLarge: "The response exceeded 1 MB."
        case .invalidResponse: "The service returned an invalid response."
        case .permissionDenied: "Permission was denied."
        case .unsupported: "This operation is not supported."
        case .invalidInput: "The requested operation has invalid input."
        }
    }
}

final class RedirectValidator: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let allowedHosts: Set<String>
    init(allowedHosts: Set<String>) { self.allowedHosts = allowedHosts }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard request.url?.scheme == "https", let host = request.url?.host?.lowercased(), allowedHosts.contains(host) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

struct NetworkService: Sendable {
    func request(urlString: String, method: String, body: PocketValue?, allowedDomains: [String]) async throws -> PocketValue {
        guard let url = URL(string: urlString) else { throw HostServiceError.invalidURL }
        guard url.scheme?.lowercased() == "https" else { throw HostServiceError.insecureURL }
        let hosts = Set(allowedDomains.map { $0.lowercased() })
        guard let host = url.host?.lowercased(), hosts.contains(host) else { throw HostServiceError.domainDenied }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: RedirectValidator(allowedHosts: hosts), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)
        guard data.count <= 1_048_576 else { throw HostServiceError.responseTooLarge }
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              http.url?.scheme?.lowercased() == "https",
              let finalHost = http.url?.host?.lowercased(), hosts.contains(finalHost)
        else { throw HostServiceError.invalidResponse }

        if let value = try? JSONDecoder().decode(PocketValue.self, from: data) { return value }
        if let json = try? JSONSerialization.jsonObject(with: data) { return Self.pocketValue(json) }
        return .string(String(decoding: data, as: UTF8.self))
    }

    private static func pocketValue(_ value: Any) -> PocketValue {
        switch value {
        case is NSNull: .null
        case let value as Bool: .bool(value)
        case let value as NSNumber: .number(value.doubleValue)
        case let value as String: .string(value)
        case let value as [Any]: .array(value.map(pocketValue))
        case let value as [String: Any]: .object(value.mapValues(pocketValue))
        default: .string(String(describing: value))
        }
    }
}

@MainActor struct ClipboardService {
    func write(_ string: String) { UIPasteboard.general.string = string }
    func read() -> String? { UIPasteboard.general.string }
}

struct NotificationService: Sendable {
    func schedule(title: String, body: String, after seconds: TimeInterval) async throws {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        guard granted else { throw HostServiceError.permissionDenied }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 1), repeats: false)
        try await UNUserNotificationCenter.current().add(.init(identifier: UUID().uuidString, content: content, trigger: trigger))
    }
}

struct VisionTextService: Sendable {
    func recognizeText(in data: Data) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let text = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            do { try VNImageRequestHandler(data: data).perform([request]) }
            catch { continuation.resume(throwing: error) }
        }
    }
}

enum IntelligenceOperation: String, Sendable { case generate, summarize, extract, classify, rewrite }

protocol IntelligenceServicing: Sendable {
    func process(_ operation: IntelligenceOperation, text: String, instruction: String?) async throws -> PocketValue
}

struct MockIntelligenceService: IntelligenceServicing {
    func process(_ operation: IntelligenceOperation, text: String, instruction: String?) async throws -> PocketValue {
        switch operation {
        case .generate: .string("Generated response for: \(text)")
        case .summarize: .string(String(text.prefix(80)))
        case .extract: .object(["text": .string(text), "length": .number(Double(text.count))])
        case .classify: .string(text.isEmpty ? "empty" : "general")
        case .rewrite: .string(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

@Generable(description: "Structured fields extracted from user text")
private struct ExtractedTextFields {
    @Guide(description: "A short title") var title: String
    @Guide(description: "A concise summary") var summary: String
    @Guide(description: "Useful comma-separated tags") var tags: String
}

struct FoundationModelsService: IntelligenceServicing {
    func process(_ operation: IntelligenceOperation, text: String, instruction: String?) async throws -> PocketValue {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { throw FoundationModelError.unavailable(String(describing: model.availability)) }
        let session = LanguageModelSession(model: model, instructions: "Operate only on the supplied local text. Be concise, accurate, and never invent private data.")
        switch operation {
        case .extract:
            let response = try await session.respond(to: text, generating: ExtractedTextFields.self)
            return .object(["title": .string(response.content.title), "summary": .string(response.content.summary), "tags": .string(response.content.tags)])
        case .generate:
            let response = try await session.respond(to: instruction.map { "\($0)\n\n\(text)" } ?? text)
            return .string(response.content)
        case .summarize:
            let response = try await session.respond(to: "Summarize this text without adding facts:\n\(text)")
            return .string(response.content)
        case .classify:
            let response = try await session.respond(to: "Classify this text using one short category label:\n\(text)")
            return .string(response.content)
        case .rewrite:
            let response = try await session.respond(to: "Rewrite the following text according to this instruction: \(instruction ?? "Improve clarity")\n\n\(text)")
            return .string(response.content)
        }
    }
}
