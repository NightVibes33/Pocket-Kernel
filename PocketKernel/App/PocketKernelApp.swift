import SwiftUI

@main struct PocketKernelApp: App {
    @State private var environment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(environment)
                .transaction { transaction in
                    if ProcessInfo.processInfo.arguments.contains("-PKDisableAnimations") { transaction.animation = nil }
                }
                .task { await environment.load() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { environment.lifecycle.markRuntimeClosed() }
                }
        }
    }
}
