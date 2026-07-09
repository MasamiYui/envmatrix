import SwiftUI

@main
struct EnvMatrixApp: App {
    var body: some Scene {
        WindowGroup("EnvMatrix") {
            RootView()
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsPlaceholder()
        }
    }
}
