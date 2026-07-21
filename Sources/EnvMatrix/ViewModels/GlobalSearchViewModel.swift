import Foundation
import Combine
import SwiftUI

/// Drives the global search palette (⌘F).
@MainActor
public final class GlobalSearchViewModel: ObservableObject {
    @Published public var query: String = ""
    @Published public private(set) var results: [SearchHit] = []
    @Published public private(set) var isSearching: Bool = false

    private let aggregator: SearchAggregator
    private var currentTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    public init(aggregator: SearchAggregator? = nil) {
        // Default to the shared, TTL-cached aggregator so successive ⌘F
        // opens reuse the previously-scanned corpora.
        self.aggregator = aggregator ?? SearchAggregator.shared
    }

    /// Trigger a debounced search whenever `query` changes.
    public func queryDidChange(_ newValue: String) {
        query = newValue
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            await self?.performSearch()
        }
    }

    public func reset() {
        query = ""
        results = []
        currentTask?.cancel()
        debounceTask?.cancel()
    }

    private func performSearch() async {
        currentTask?.cancel()
        let q = query
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        currentTask = Task { [weak self] in
            guard let self else { return }
            let hits = await self.aggregator.search(q)
            if Task.isCancelled { return }
            await MainActor.run {
                self.results = hits
                self.isSearching = false
            }
        }
    }
}
