import Foundation
import SwiftUI

/// Backs the menu-bar panel: which runtimes have versions to switch
/// between, and the currently active one for each.
///
/// Kept deliberately small — the panel only needs installed versions, and
/// it reloads on open rather than polling.
@MainActor
public final class MenuBarViewModel: ObservableObject {
    public struct Item: Identifiable {
        public let kind: RuntimeKind
        public let active: String?
        public let versions: [RuntimeVersion]
        public var id: String { kind.rawValue }

        /// Only runtimes with more than one version are worth switching.
        public var isSwitchable: Bool { versions.count > 1 }
    }

    @Published public private(set) var items: [Item] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var loadedAt: Date?
    @Published public var switchingKind: RuntimeKind?
    @Published public var errorMessage: String?

    public nonisolated static let ttl: TimeInterval = 30

    private let service: RuntimeService

    public init(service: RuntimeService = DefaultRuntimeService()) {
        self.service = service
    }

    public func refreshIfStale(force: Bool = false) async {
        if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < Self.ttl { return }
        await refresh()
    }

    public func refresh() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        let svc = service
        let loaded = await Task.detached(priority: .userInitiated) { () -> [Item] in
            var result: [Item] = []
            for kind in RuntimeKind.allCases {
                let versions = (try? svc.listInstalled(kind: kind)) ?? []
                guard !versions.isEmpty else { continue }
                result.append(Item(kind: kind, active: svc.currentActive(kind: kind), versions: versions))
            }
            return result
        }.value
        items = loaded
        loadedAt = Date()
        InstalledRuntimesStore.shared.update(
            activeKinds: Set(loaded.filter { $0.active != nil }.map { $0.kind })
        )
    }

    public func activate(_ version: RuntimeVersion) async {
        switchingKind = version.kind
        defer { switchingKind = nil }
        do {
            try service.activate(version: version)
            OperationLog.shared.record(
                .runtime,
                title: String(format: L("history.op.runtime.activate"), version.kind.displayName, version.version),
                detail: L("menubar.source")
            )
            SystemNotifier.shared.notify(
                title: String(format: L("notify.runtime.activated.title"), version.kind.displayName, version.version),
                body: L("notify.runtime.activated.body"),
                onlyWhenInactive: true
            )
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
