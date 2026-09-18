import Foundation
import SwiftUI

/// App-wide observable state for "is ~/.envmatrix/shims on PATH?".
///
/// Shared as a singleton because the check forks the user's login shell
/// (~1s) and its answer is the same for every screen that cares.
@MainActor
public final class ShimsPathStatus: ObservableObject {
    public static let shared = ShimsPathStatus()

    /// `nil` until the first check has finished.
    @Published public private(set) var isConfigured: Bool?
    @Published public private(set) var isChecking: Bool = false
    @Published public private(set) var isWriting: Bool = false
    @Published public var lastError: String?
    /// Set after a successful write so the banner can tell the user which
    /// file changed and that a new terminal is needed.
    @Published public private(set) var writtenRcFile: ShellRcFile?

    private let service: ShimsPathService
    private var checkTask: Task<Void, Never>?

    public init(service: ShimsPathService = DefaultShimsPathService()) {
        self.service = service
    }

    public var exportLine: String { service.exportLine }
    public var targetRcDisplayName: String { service.targetRcFile().kind.displayName }

    /// Runs the PATH check once; subsequent calls are no-ops unless `force`.
    public func check(force: Bool = false) {
        if isChecking { return }
        if !force, isConfigured != nil { return }
        isChecking = true
        let svc = service
        checkTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { svc.isShimsOnPath() }.value
            guard let self, !Task.isCancelled else { return }
            self.isConfigured = result
            self.isChecking = false
        }
    }

    public func addToShellRc() {
        guard !isWriting else { return }
        isWriting = true
        lastError = nil
        do {
            let file = try service.addShimsToShellRc()
            writtenRcFile = file
            // The rc file is now correct even though the running shell
            // hasn't sourced it; treat as configured so banners go away.
            isConfigured = true
        } catch {
            lastError = error.localizedDescription
        }
        isWriting = false
    }
}
