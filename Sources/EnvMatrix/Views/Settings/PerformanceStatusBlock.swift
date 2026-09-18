import SwiftUI

struct PerformanceStatusBlock: View {
    @EnvironmentObject private var localization: LocalizationManager
    @State private var running: Int = 0
    @State private var waiting: Int = 0
    @State private var maxConcurrent: Int = 0
    @State private var fsEnabled: Bool = true
    @State private var handles: Int = 0
    @State private var refreshTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("settings.performance.title")).font(.headline)
            Text(L("settings.performance.subtitle"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Text(fsEnabled
                 ? L("settings.performance.fsevents.enabled")
                 : L("settings.performance.fsevents.disabled"))
            Text(String(format: L("settings.performance.fsevents.handles"), handles))
            Text(String(format: L("settings.performance.pool.max"), maxConcurrent))
            Text(String(format: L("settings.performance.pool.running"), running))
            Text(String(format: L("settings.performance.pool.waiting"), waiting))
            Button(L("settings.performance.refresh")) { refreshOnce() }
                .buttonStyle(.borderless)
        }
        .onAppear {
            refreshOnce()
            refreshTask = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    refreshOnce()
                }
            }
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    private func refreshOnce() {
        let services = AppServices.shared
        self.running = services.processPool.inflightCount
        self.waiting = services.processPool.queuedCount
        self.maxConcurrent = services.processPool.maxConcurrent
        self.fsEnabled = services.fsEventsEnabled
        self.handles = services.activeHandleCount
    }
}
