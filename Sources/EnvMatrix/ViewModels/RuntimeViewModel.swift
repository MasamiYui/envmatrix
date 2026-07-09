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

    public func refreshInstalled() {
        do {
            let list = try service.listInstalled(kind: kind)
            self.installed = list
            let active = service.currentActive(kind: kind)
            self.activeVersion = active
            // "Managed" means the currently active version exists in installed[] as a non-system entry.
            if let active = active {
                self.isManagedActive = list.contains { !$0.isSystem && $0.version == active }
            } else {
                self.isManagedActive = false
            }
        } catch {
            self.errorMessage = error.localizedDescription
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
            refreshInstalled()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func activate(_ version: RuntimeVersion) {
        do {
            try service.activate(version: version)
            refreshInstalled()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func uninstall(_ version: RuntimeVersion) {
        do {
            try service.uninstall(version: version)
            refreshInstalled()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
