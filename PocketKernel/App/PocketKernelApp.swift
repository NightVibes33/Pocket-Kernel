import SwiftUI

@main
struct PocketKernelApp: App {
    @State private var environment = AppEnvironment()
    var body: some Scene {
        WindowGroup { RootTabView().environment(environment).task { await environment.load() } }
    }
}

