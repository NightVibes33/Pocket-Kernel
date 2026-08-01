import SwiftUI

@main
struct PocketKernelApp: App {
    @State private var environment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup { RootTabView().environment(environment).task { await environment.load() } }
            .onChange(of: scenePhase) { _, phase in if phase == .background { environment.lifecycle.cleanBackgroundTransition() } else if phase == .active { Task { await environment.load() } } }
    }
}
