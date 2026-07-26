import SwiftUI
import AppKit

extension Notification.Name {
    static let envMatrixOpenGlobalSearch = Notification.Name("envmatrix.openGlobalSearch")
}

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
        .commands {
            CommandGroup(after: .textEditing) {
                Button("Find in Packages…") {
                    NotificationCenter.default.post(name: .envMatrixOpenGlobalSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])
            }
        }
        // NOTE: We intentionally do NOT declare a `Settings { ... }` scene.
        // All settings live inside the main window's sidebar section, and
        // adding a Settings scene caused SwiftUI to restore a ghost floating
        // window on subsequent launches.
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let image = Self.loadAppIconImage() {
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

    /// Loads the bundled AppIcon in a way that never fatals at launch.
    ///
    /// `Bundle.module` triggers an unconditional `fatalError` when the SwiftPM
    /// resource bundle cannot be located next to the executable (e.g. when a
    /// packaging script forgot to copy `EnvMatrix_EnvMatrix.bundle` into the
    /// `.app`). We walk the candidate locations manually so a missing icon
    /// degrades gracefully instead of crashing the whole process.
    private static func loadAppIconImage() -> NSImage? {
        let candidateBundles: [Bundle] = {
            var bundles: [Bundle] = [.main]
            let exeDir = Bundle.main.bundleURL
                .appendingPathComponent("Contents/MacOS", isDirectory: true)
            let bundleName = "EnvMatrix_EnvMatrix.bundle"
            let candidatePaths = [
                exeDir.appendingPathComponent(bundleName),
                Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(bundleName)"),
                Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(bundleName)
            ]
            for url in candidatePaths {
                if FileManager.default.fileExists(atPath: url.path),
                   let bundle = Bundle(url: url) {
                    bundles.append(bundle)
                }
            }
            return bundles
        }()

        for bundle in candidateBundles {
            if let url = bundle.url(forResource: "AppIcon", withExtension: "icns"),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }
}
