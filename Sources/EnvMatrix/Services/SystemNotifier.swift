import Foundation
import UserNotifications
import AppKit

/// Thin wrapper around `UNUserNotificationCenter` for one-shot completion
/// banners after long-running operations (Homebrew installs, npm cache
/// clean, Maven / Go bulk deletes).
///
/// The service is a no-op if:
/// - the app is not running as a proper bundle (e.g. `swift run` in a CLI
///   context), OR
/// - the user denied notification permission, OR
/// - the user disabled notifications in `SettingsView`.
///
/// Callers never need to await permission; the first `notify(...)` call
/// requests it silently.
@MainActor
public final class SystemNotifier {
    public static let shared = SystemNotifier()

    private var permissionGranted: Bool?
    private let userDefaultsKey = "notificationsEnabled"

    private init() {}

    public var isUserEnabled: Bool {
        // Default ON: users can opt out in Settings.
        UserDefaults.standard.object(forKey: userDefaultsKey) as? Bool ?? true
    }

    public func setUserEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: userDefaultsKey)
    }

    /// Fire a completion banner. Silently returns on any failure.
    ///
    /// - Parameter onlyWhenInactive: for quick operations whose result is
    ///   already visible in-app (mirror switch, uninstall), only notify when
    ///   EnvMatrix is not the frontmost app so the user isn't told twice.
    public func notify(title: String, body: String, onlyWhenInactive: Bool = false) {
        guard isUserEnabled, Self.hasNotificationCapableBundle else { return }
        if onlyWhenInactive && NSApplication.shared.isActive { return }
        Task {
            guard await ensurePermission() else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let req = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(req)
        }
    }

    /// Convenience for the ten registry pages and the preset applier.
    public func notifyRegistrySwitched(ecosystem: String, value: String) {
        notify(
            title: String(format: L("notify.registry.title"), ecosystem),
            body: value,
            onlyWhenInactive: true
        )
    }

    /// `UNUserNotificationCenter.current()` raises an Objective-C exception
    /// (not a catchable Swift error) when the process has no bundle
    /// identifier — `swift run`, unit tests, or a mis-packaged .app. The
    /// class doc promised this was a no-op; this check makes it true.
    static var hasNotificationCapableBundle: Bool {
        guard let id = Bundle.main.bundleIdentifier, !id.isEmpty else { return false }
        return Bundle.main.bundleURL.pathExtension == "app"
    }

    private func ensurePermission() async -> Bool {
        if let cached = permissionGranted { return cached }
        guard Self.hasNotificationCapableBundle else {
            permissionGranted = false
            return false
        }
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            permissionGranted = granted
            return granted
        } catch {
            permissionGranted = false
            return false
        }
    }
}
