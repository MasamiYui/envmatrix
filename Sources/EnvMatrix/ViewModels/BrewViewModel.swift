import Foundation
import SwiftUI

@MainActor
public final class BrewViewModel: ObservableObject {
    // MARK: - Data
    @Published public private(set) var formulae: [BrewPackage] = []
    @Published public private(set) var casks: [BrewPackage] = []
    @Published public private(set) var outdatedCount: Int = 0
    @Published public private(set) var brewVersion: String = ""
    @Published public private(set) var brewPath: String = ""

    // MARK: - UI state
    @Published public var selectedKind: BrewPackageKind = .formula
    @Published public var searchText: String = ""
    @Published public var showOnlyOutdated: Bool = false
    @Published public var showOnlyRequested: Bool = false
    @Published public var selectedPackageID: String?

    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var runningOperation: BrewOperation?
    @Published public private(set) var lastOperationOutput: String = ""
    @Published public var errorMessage: String?
    @Published public private(set) var isAvailable: Bool = true

    private let service: HomebrewService
    private var hasLoadedOnce = false

    public init(service: HomebrewService = DefaultHomebrewService()) {
        self.service = service
        self.isAvailable = service.isAvailable
        self.brewPath = service.brewPath
    }

    // MARK: - Derived

    /// Packages of the currently selected kind, filtered by search + toggles.
    public var visiblePackages: [BrewPackage] {
        let base = selectedKind == .formula ? formulae : casks
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return base.filter { pkg in
            if showOnlyOutdated && !pkg.isOutdated { return false }
            if showOnlyRequested && !pkg.installedOnRequest { return false }
            if q.isEmpty { return true }
            if pkg.name.lowercased().contains(q) { return true }
            if pkg.fullName.lowercased().contains(q) { return true }
            if let d = pkg.description?.lowercased(), d.contains(q) { return true }
            return false
        }
    }

    public var selectedPackage: BrewPackage? {
        guard let id = selectedPackageID else { return nil }
        return (formulae + casks).first { $0.id == id }
    }

    public var formulaeCount: Int { formulae.count }
    public var casksCount: Int { casks.count }
    public var totalCount: Int { formulaeCount + casksCount }
    public var requestedCount: Int {
        formulae.filter(\.installedOnRequest).count + casks.count
    }

    // MARK: - Actions

    public func refreshIfNeeded() async {
        if hasLoadedOnce { return }
        await refresh(force: false)
    }

    public func refresh(force: Bool = true) async {
        guard service.isAvailable else {
            isAvailable = false
            errorMessage = BrewError.notInstalled.errorDescription
            return
        }
        isAvailable = true
        isLoading = true
        defer { isLoading = false }
        do {
            let inv = try await service.inventory(forceRefresh: force)
            self.formulae = inv.formulae
            self.casks = inv.casks
            self.outdatedCount = inv.outdatedCount
            self.brewVersion = inv.brewVersion
            self.brewPath = inv.brewPath
            self.hasLoadedOnce = true
            self.errorMessage = nil
        } catch {
            self.errorMessage = (error as? BrewError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func run(_ operation: BrewOperation) async {
        guard runningOperation == nil else { return }
        runningOperation = operation
        defer { runningOperation = nil }
        do {
            let output = try await service.run(operation)
            self.lastOperationOutput = output
            await refresh(force: true)
            SystemNotifier.shared.notify(
                title: L("notify.brew.success.title"),
                body: String(format: L("notify.brew.success.body"), operation.displayLabel)
            )
        } catch {
            let message = (error as? BrewError)?.errorDescription ?? error.localizedDescription
            self.errorMessage = message
            SystemNotifier.shared.notify(
                title: L("notify.brew.failure.title"),
                body: String(format: L("notify.brew.failure.body"), operation.displayLabel)
            )
        }
    }

    public func upgrade(_ pkg: BrewPackage) async {
        await run(.upgrade(pkg.name))
    }

    public func uninstall(_ pkg: BrewPackage) async {
        await run(.uninstall(pkg.name, pkg.kind))
    }

    public func togglePin(_ pkg: BrewPackage) async {
        await run(pkg.isPinned ? .unpin(pkg.name) : .pin(pkg.name))
    }
}
