import SwiftUI
import AppKit

@main
struct EnvMatrixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("EnvMatrix") {
            RootView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1100, height: 720)
        // NOTE: We intentionally do NOT declare a `Settings { ... }` scene.
        // All settings live inside the main window's sidebar section, and
        // adding a Settings scene caused SwiftUI to restore a ghost floating
        // window on subsequent launches.
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = image
        }

        // macOS persists the last window frame in the user's defaults.
        // If a previous launch left the window narrower than our layout
        // needs, the sidebar column silently collapses. Force the main
        // window to at least the design minimum on every launch.
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first else { return }
            let currentFrame = window.frame
            let minWidth: CGFloat = 1120
            let minHeight: CGFloat = 720
            if currentFrame.width < minWidth || currentFrame.height < minHeight {
                let newFrame = NSRect(
                    x: currentFrame.origin.x,
                    y: currentFrame.origin.y,
                    width: max(currentFrame.width, minWidth),
                    height: max(currentFrame.height, minHeight)
                )
                window.setFrame(newFrame, display: true, animate: false)
            }
            window.center()
        }
    }
}
