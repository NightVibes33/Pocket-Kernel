import SwiftUI
import Foundation
import FoundationModels
import AuthenticationServices
import Security
import UserNotifications
import EventKit
import UIKit

// MARK: - Backend API

actor BackendClient {
    static let shared = BackendClient()

    struct DeviceSession: Codable, Sendable {
        let userID: String
        let token: String
        let expiresIn: Int
    }

    struct ConnectionResponse: Codable, Sendable {
        let connections: [ServiceConnection]
        let providers: [String]
        let configured: [String: Bool]
    }

    struct OAuthStartResponse: Codable, Sendable {
        let authorizationURL: String
        let state: String
    }

    struct AutomationResponse: Codable, Sendable {
        let automations: [SavedAutomation]
    }

    private var session: DeviceSession?

    var baseURL: URL {
        let stored = UserDefaults.standard.string(forKey: "backendURL") ?? "https://pocketkernel.vercel.app"
        return URL(string: stored.trimmingCharacters(in: CharacterSet(charactersIn: "/")))!
    }

    private func deviceID() -> String {
        if let value = KeychainStore.string(for: "deviceID") { return value }
        let value = "ios_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        KeychainStore.set(value, for: "deviceID")
        return value
    }

    func ensureSession() async throws -> DeviceSession {
        if let session { return session }
        if let token = KeychainStore.string(for: "apiToken"), !token.isEmpty,
           let userID = KeychainStore.string(for: "userID") {
            let cached = DeviceSession(userID: userID, token: token, expiresIn: 0)
            session = cached
            return cached
        }
        let body = ["deviceID": deviceID()]
        let created: DeviceSession = try await request(path: "/api/auth/device", method: "POST", body: body, authenticated: false)
        KeychainStore.set(created.token, for: "apiToken")
        KeychainStore.set(created.userID, for: "userID")
        session = created
        return created
    }

    func health() async throws -> String {
        struct Health: Codable { let status: String; let version: String }
        let value: Health = try await request(path: "/api/health", authenticated: false)
        return "\(value.status) · v\(value.version)"
    }

    func connections() async throws -> ConnectionResponse {
        try await request(path: "/api/connections")
    }

    func startOAuth(provider: String) async throws -> URL {
        let response: OAuthStartResponse = try await request(path: "/api/oauth/start", method: "POST", body: ["provider": provider])
        guard let url = URL(string: response.authorizationURL) else { throw APIError.invalidResponse }
        return url
    }

    func disconnect(provider: String) async throws {
        struct Result: Codable { let disconnected: String }
        let _: Result = try await request(path: "/api/connections/disconnect", method: "POST", body: ["provider": provider])
    }

    func execute(provider: String, action: String, input: [String: String]) async throws -> String {
        struct Result: Codable { let ok: Bool; let result: JSONValue }
        let response: Result = try await request(
            path: "/api/execute",
            method: "POST",
            body: ServiceActionRequest(provider: provider, action: action, input: input)
        )
        return response.result.pretty
    }

    func automations() async throws -> [SavedAutomation] {
        let response: AutomationResponse = try await request(path: "/api/automations")
        return response.automations
    }

    func saveAutomation(title: String, prompt: String, steps: [[String: JSONValue]], nextRunAt: String?, repeatSeconds: Int) async throws -> SavedAutomation {
        struct Body: Codable {
            let title: String
            let prompt: String
            let steps: [[String: JSONValue]]
            let enabled: Bool
            let nextRunAt: String?
            let repeatSeconds: Int
        }
        struct Response: Codable { let automation: SavedAutomation }
        let response: Response = try await request(
            path: "/api/automations",
            method: "POST",
            body: Body(title: title, prompt: prompt, steps: steps, enabled: true, nextRunAt: nextRunAt, repeatSeconds: repeatSeconds)
        )
        return response.automation
    }

    private func request<Response: Decodable>(path: String, method: String = "GET", body: (any Encodable)? = nil, authenticated: Bool = true) async throws -> Response {
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "accept")
        if authenticated {
            let current = try await ensureSession()
            request.setValue("Bearer \(current.token)", forHTTPHeaderField: "authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if !(200..<300).contains(http.statusCode) {
            let backend = try? JSONDecoder().decode(BackendError.self, from: data)
            if http.statusCode == 401 {
                session = nil
                KeychainStore.set("", for: "apiToken")
            }
            throw APIError.server(backend?.error ?? "HTTP \(http.statusCode)")
        }
        do { return try JSONDecoder().decode(Response.self, from: data) }
        catch { throw APIError.decoding(error.localizedDescription) }
    }

    struct ServiceActionRequest: Codable { let provider: String; let action: String; let input: [String: String] }
    struct BackendError: Codable { let error: String }
    enum APIError: LocalizedError {
        case invalidResponse
        case server(String)
        case decoding(String)
        var errorDescription: String? {
            switch self {
            case .invalidResponse: "The server returned an invalid response."
            case .server(let value): value.replacingOccurrences(of: "_", with: " ")
            case .decoding(let value): "Could not read the server response: \(value)"
            }
        }
    }
}

struct AnyEncodable: Encodable {
    private let encodeBlock: (Encoder) throws -> Void
    init(_ value: any Encodable) { encodeBlock = { encoder in try value.encode(to: encoder) } }
    func encode(to encoder: Encoder) throws { try encodeBlock(encoder) }
}

enum JSONValue: Codable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    var pretty: String {
        switch self {
        case .string(let v): v
        case .number(let v): String(v)
        case .bool(let v): String(v)
        case .object(let v): v.map { "\($0): \($1.pretty)" }.sorted().joined(separator: "\n")
        case .array(let v): v.map(\.pretty).joined(separator: "\n")
        case .null: "Done"
        }
    }
}
