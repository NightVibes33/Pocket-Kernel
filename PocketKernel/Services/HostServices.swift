import Foundation
import UIKit
import UserNotifications
import Vision

enum HostServiceError: LocalizedError {
    case invalidURL, insecureURL, domainDenied, responseTooLarge, invalidResponse, permissionDenied, unsupported
    var errorDescription: String? {
        switch self { case .invalidURL: "The URL is invalid."; case .insecureURL: "Only HTTPS requests are allowed."; case .domainDenied: "The destination domain is not allowed."; case .responseTooLarge: "The response exceeded 1 MB."; case .invalidResponse: "The service returned an invalid response."; case .permissionDenied: "Permission was denied."; case .unsupported: "This operation is not supported." }
    }
}

final class RedirectValidator: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let allowedHosts: Set<String>
    init(allowedHosts: Set<String>) { self.allowedHosts = allowedHosts }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection newRequest: URLRequest, newResponse: HTTPURLResponse, completionHandler: @escaping (URLRequest?) -> Void) {
        guard newRequest.url?.scheme == "https", let host = newRequest.url?.host?.lowercased(), allowedHosts.contains(host) else { completionHandler(nil); return }
        completionHandler(newRequest)
    }
}

struct NetworkService: Sendable {
    func request(urlString: String, method: String, body: PocketValue?, allowedDomains: [String]) async throws -> PocketValue {
        guard let url = URL(string: urlString) else { throw HostServiceError.invalidURL }
        guard url.scheme == "https" else { throw HostServiceError.insecureURL }
        let hosts = Set(allowedDomains.map { $0.lowercased() }); guard let host = url.host?.lowercased(), hosts.contains(host) else { throw HostServiceError.domainDenied }
        var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = 15
        if let body { request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let configuration = URLSessionConfiguration.ephemeral; configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil; configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: RedirectValidator(allowedHosts: hosts), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard data.count <= 1_048_576 else { throw HostServiceError.responseTooLarge }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), http.url?.scheme == "https", let finalHost = http.url?.host?.lowercased(), hosts.contains(finalHost) else { throw HostServiceError.invalidResponse }
        if let value = try? JSONDecoder().decode(PocketValue.self, from: data) { return value }
        return .string(String(decoding: data, as: UTF8.self))
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
        let content = UNMutableNotificationContent(); content.title = title; content.body = body
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 1), repeats: false)
        try await UNUserNotificationCenter.current().add(.init(identifier: UUID().uuidString, content: content, trigger: trigger))
    }
}

struct VisionTextService: Sendable {
    func recognizeText(in data: Data) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let text = (request.results as? [VNRecognizedTextObservation])?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            do { try VNImageRequestHandler(data: data).perform([request]) } catch { continuation.resume(throwing: error) }
        }
    }
}
