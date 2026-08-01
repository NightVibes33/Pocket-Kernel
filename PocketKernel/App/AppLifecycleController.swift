import Foundation
import Observation

@MainActor @Observable
final class AppLifecycleController {
    private struct Marker: Codable { var appID: UUID?; var openedAt: Date }
    private let markerURL: URL?
    var recoveryRequired = false
    var affectedAppID: UUID?

    init() {
        let root = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "PocketKernel/Recovery", directoryHint: .isDirectory)
        if let root { try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
        markerURL = root?.appending(path: "runtime-session-open.json")
        let arguments = ProcessInfo.processInfo.arguments
        let shouldReadRecoveryMarker = !arguments.contains("-PKUITesting") || arguments.contains("-PKRecoveryFixture")
        if shouldReadRecoveryMarker, let markerURL, let data = try? Data(contentsOf: markerURL), let marker = try? JSONDecoder().decode(Marker.self, from: data) {
            recoveryRequired = true; affectedAppID = marker.appID
        }
        if arguments.contains("-PKRecoveryFixture") { recoveryRequired = true }
        writeMarker(appID: nil)
    }

    func markRuntimeOpen(appID: UUID) { writeMarker(appID: appID) }
    func cleanBackgroundTransition() { if let markerURL { try? FileManager.default.removeItem(at: markerURL) } }
    func resumeSession() { recoveryRequired = false; writeMarker(appID: affectedAppID) }
    func dismissRecovery() { recoveryRequired = false; affectedAppID = nil; writeMarker(appID: nil) }

    private func writeMarker(appID: UUID?) {
        guard let markerURL, let data = try? JSONEncoder().encode(Marker(appID: appID, openedAt: Date())) else { return }
        try? data.write(to: markerURL, options: .atomic)
    }
}
