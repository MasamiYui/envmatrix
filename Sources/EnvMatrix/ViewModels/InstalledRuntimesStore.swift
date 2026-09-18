import Foundation
import SwiftUI

/// Which runtimes currently resolve to an active binary. Shared so the
/// sidebar can fold away runtimes the user does not have without forking
/// a detector per navigation; the Dashboard feeds it after its own scan.
@MainActor
public final class InstalledRuntimesStore: ObservableObject {
    public static let shared = InstalledRuntimesStore()

    /// `nil` until the first scan completes; the sidebar shows everything
    /// while unknown so nothing flickers away on launch.
    @Published public private(set) var activeKinds: Set<RuntimeKind>?

    private let service: RuntimeService
    private var isScanning = false

    public init(service: RuntimeService = DefaultRuntimeService()) {
        self.service = service
    }

    public func isInstalled(_ kind: RuntimeKind) -> Bool {
        activeKinds?.contains(kind) ?? true
    }

    /// Called by DashboardViewModel once it has fresh snapshots so the two
    /// never disagree.
    public func update(activeKinds: Set<RuntimeKind>) {
        self.activeKinds = activeKinds
    }

    public func refreshIfNeeded() {
        guard activeKinds == nil, !isScanning else { return }
        isScanning = true
        let svc = service
        Task { [weak self] in
            let kinds = await Task.detached(priority: .utility) { () -> Set<RuntimeKind> in
                var result = Set<RuntimeKind>()
                for kind in RuntimeKind.allCases where svc.currentActive(kind: kind) != nil {
                    result.insert(kind)
                }
                return result
            }.value
            guard let self else { return }
            if self.activeKinds == nil { self.activeKinds = kinds }
            self.isScanning = false
        }
    }
}
