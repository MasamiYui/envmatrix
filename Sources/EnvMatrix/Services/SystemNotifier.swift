import Foundation
import UserNotifications

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
    public func notify(title: String, body: String) {
        guard isUserEnabled else { return }
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

    private func ensurePermission() async -> Bool {
        if let cached = permissionGranted { return cached }
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
