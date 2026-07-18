import Foundation
import SwiftUI

@MainActor
public final class RuntimeViewModel: ObservableObject {
    public let kind: RuntimeKind

    @Published public var installed: [RuntimeVersion] = []
    @Published public var available: [RuntimeVersion] = []
    @Published public var activeVersion: String? = nil
    @Published public var isManagedActive: Bool = false
    @Published public var isLoadingAvailable: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var installProgress: [String: Double] = [:]
    @Published public var installingVersionIDs: Set<String> = []

    private let service: RuntimeService

    public init(kind: RuntimeKind, service: RuntimeService = DefaultRuntimeService()) {
        self.kind = kind
        self.service = service
    }

    public func refreshInstalled() async {
        let svc = service
        let k = kind
        // Move the subprocess-heavy scan off the MainActor so the UI stays
        // responsive while we enumerate managed versions and probe active
        // binaries (each involves fork + waitUntilExit inside the detector).
        let result: (list: [RuntimeVersion], active: String?)? = await Task
            .detached(priority: .userInitiated) { () -> (list: [RuntimeVersion], active: String?)? in
                do {
                    let list = try svc.listInstalled(kind: k)
                    let active = svc.currentActive(kind: k)
                    return (list, active)
                } catch {
                    return nil
                }
            }.value
        guard let result = result else {
            self.errorMessage = "Failed to list installed versions"
            return
        }
        self.installed = result.list
        self.activeVersion = result.active
        if let active = result.active {
            self.isManagedActive = result.list.contains { !$0.isSystem && $0.version == active }
        } else {
            self.isManagedActive = false
        }
    }

    public func loadAvailable() async {
        isLoadingAvailable = true
        defer { isLoadingAvailable = false }
        do {
            let list = try await service.listAvailable(kind: kind)
            self.available = list
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func install(_ version: RuntimeVersion) async {
        installingVersionIDs.insert(version.id)
        installProgress[version.id] = 0
        defer {
            installingVersionIDs.remove(version.id)
        }
        do {
            try await service.install(version: version) { [weak self] fraction in
                Task { @MainActor in
                    self?.installProgress[version.id] = fraction
                }
            }
            installProgress[version.id] = 1.0
            await refreshInstalled()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func activate(_ version: RuntimeVersion) async {
        do {
            try service.activate(version: version)
            await refreshInstalled()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func uninstall(_ version: RuntimeVersion) async {
        do {
            try service.uninstall(version: version)
            await refreshInstalled()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
