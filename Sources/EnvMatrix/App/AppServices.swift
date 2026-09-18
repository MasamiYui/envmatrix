import Foundation

public final class AppServices {
    public static let shared = AppServices()

    public let fileSystemWatcher: FileSystemWatcher
    public let processPool: ProcessPool

    public let fsEventsEnabled: Bool
    public let processPoolMaxConcurrent: Int

    private var activeHandles: [WatchHandle] = []
    private let handlesLock = NSLock()

    private init(defaults: UserDefaults = .standard) {
        if defaults.object(forKey: "perf.fsevents.enabled") == nil {
            defaults.set(true, forKey: "perf.fsevents.enabled")
        }
        let fsEnabled = defaults.bool(forKey: "perf.fsevents.enabled")
        self.fsEventsEnabled = fsEnabled

        let rawMax = defaults.object(forKey: "perf.processPool.maxConcurrent") as? Int
        let maxConcurrent = rawMax ?? 4
        self.processPoolMaxConcurrent = maxConcurrent

        if fsEnabled {
            self.fileSystemWatcher = FSEventsFileSystemWatcher()
        } else {
            self.fileSystemWatcher = NoopFileSystemWatcher()
        }

        self.processPool = DefaultProcessPool(maxConcurrent: maxConcurrent)
    }

    public func registerHandle(_ handle: WatchHandle) {
        handlesLock.lock()
        activeHandles.append(handle)
        handlesLock.unlock()
    }

    public var activeHandleCount: Int {
        handlesLock.lock()
        defer { handlesLock.unlock() }
        return activeHandles.count
    }

    public func shutdown() {
        handlesLock.lock()
        let snapshot = activeHandles
        activeHandles.removeAll()
        handlesLock.unlock()
        for h in snapshot {
            h.invalidate()
        }
        processPool.cancelAll()
    }
}
