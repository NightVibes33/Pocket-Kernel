import Foundation
import Observation

private struct RuntimeSessionMarker: Codable, Sendable {
    var appID: UUID
    var openedAt: Date
    var lastEvent: String
}

@MainActor @Observable final class AppLifecycleController {
    private let markerURL: URL
    private(set) var recoveryRequired = false
    private(set) var affectedAppID: UUID?
    private(set) var lastRuntimeEvent = "The previous runtime session did not close normally."

    init(layout: PocketStorageLayout, arguments: [String] = ProcessInfo.processInfo.arguments) {
        markerURL = layout.recovery.appending(path: "runtime-session-open.json")
        if arguments.contains("-PKRecoveryFixture") {
            recoveryRequired = true
            affectedAppID = nil
            lastRuntimeEvent = "Recovery fixture requested by UI tests."
        } else if let data = try? Data(contentsOf: markerURL), let marker = try? JSONDecoder().decode(RuntimeSessionMarker.self, from: data) {
            recoveryRequired = true
            affectedAppID = marker.appID
            lastRuntimeEvent = marker.lastEvent
        }
    }

    func markRuntimeOpen(appID: UUID, event: String = "Opened a Pocket App runtime.") {
        affectedAppID = appID
        let marker = RuntimeSessionMarker(appID: appID, openedAt: Date(), lastEvent: event)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(marker) { try? data.write(to: markerURL, options: [.atomic]) }
    }

    func updateRuntimeEvent(_ event: String) {
        guard let affectedAppID else { return }
        markRuntimeOpen(appID: affectedAppID, event: event)
    }

    func markRuntimeClosed() {
        try? FileManager.default.removeItem(at: markerURL)
        affectedAppID = nil
    }

    func dismissRecovery() {
        recoveryRequired = false
        markRuntimeClosed()
    }

    func resumeSession() {
        recoveryRequired = false
        try? FileManager.default.removeItem(at: markerURL)
    }
}
