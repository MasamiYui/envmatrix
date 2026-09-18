import Foundation
import SwiftUI

/// App-wide update state: runs the GitHub check (on launch when enabled,
/// or on demand from About), remembers skipped versions, and exposes the
/// result for the top-of-window banner and the About tab.
@MainActor
public final class UpdateChecker: ObservableObject {
    public static let shared = UpdateChecker()

    public enum State: Equatable {
        case idle
        case checking
        case upToDate(latest: String)
        case available(AppRelease)
        case failed(String)
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var lastCheckedAt: Date?

    public static let autoCheckKey = "updates.autoCheck"
    private static let skippedKey = "updates.skippedVersion"
    private static let lastCheckedKey = "updates.lastCheckedAt"
    private static let autoCheckInterval: TimeInterval = 24 * 60 * 60

    private let service: UpdateCheckService
    private let defaults: UserDefaults
    private let currentVersionProvider: () -> String

    public init(
        service: UpdateCheckService = GitHubUpdateCheckService(),
        defaults: UserDefaults = .standard,
        currentVersion: @escaping () -> String = { UpdateChecker.bundleVersion() }
    ) {
        self.service = service
        self.defaults = defaults
        self.currentVersionProvider = currentVersion
        if let t = defaults.object(forKey: Self.lastCheckedKey) as? Date {
            lastCheckedAt = t
        }
    }

    public var currentVersion: String { currentVersionProvider() }

    public var isAutoCheckEnabled: Bool {
        defaults.object(forKey: Self.autoCheckKey) as? Bool ?? true
    }

    /// The release the banner should advertise: newer than the running
    /// build and not explicitly skipped by the user.
    public var pendingRelease: AppRelease? {
        guard case .available(let release) = state else { return nil }
        if defaults.string(forKey: Self.skippedKey) == release.version { return nil }
        return release
    }

    /// Launch-time check, throttled to once per day. No-op when the user
    /// turned automatic checks off or the build has no real version.
    public func checkOnLaunchIfNeeded() {
        guard isAutoCheckEnabled else { return }
        guard Self.isRealVersion(currentVersion) else { return }
        if let last = lastCheckedAt, Date().timeIntervalSince(last) < Self.autoCheckInterval {
            return
        }
        Task { await check() }
    }

    public func check() async {
        if case .checking = state { return }
        state = .checking
        do {
            let release = try await service.fetchLatestRelease()
            lastCheckedAt = Date()
            defaults.set(lastCheckedAt, forKey: Self.lastCheckedKey)
            if SemanticVersion.isNewer(release.version, than: currentVersion) {
                state = .available(release)
            } else {
                state = .upToDate(latest: release.version)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func skip(_ release: AppRelease) {
        defaults.set(release.version, forKey: Self.skippedKey)
        objectWillChange.send()
    }

    public func clearSkipped() {
        defaults.removeObject(forKey: Self.skippedKey)
        objectWillChange.send()
    }

    // MARK: - Version helpers

    public nonisolated static func bundleVersion() -> String {
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !v.isEmpty {
            return v
        }
        return "dev"
    }

    /// `swift run` builds carry no Info.plist version; don't nag those.
    nonisolated static func isRealVersion(_ v: String) -> Bool {
        v != "dev" && v.first?.isNumber == true
    }
}
