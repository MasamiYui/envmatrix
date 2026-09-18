import Foundation
import CoreServices

public struct FileSystemChange {
    public let path: String
    public let flags: UInt32

    public init(path: String, flags: UInt32) {
        self.path = path
        self.flags = flags
    }
}

public final class WatchHandle {
    private var onInvalidate: (() -> Void)?
    private var invalidated: Bool = false

    public init(onInvalidate: @escaping () -> Void) {
        self.onInvalidate = onInvalidate
    }

    public func invalidate() {
        guard !invalidated else { return }
        invalidated = true
        onInvalidate?()
        onInvalidate = nil
    }
}

public protocol FileSystemWatcher: AnyObject {
    func watch(
        paths: [String],
        latency: TimeInterval,
        debounceInterval: TimeInterval,
        onChange: @escaping ([FileSystemChange]) -> Void
    ) -> WatchHandle
}

public final class NoopFileSystemWatcher: FileSystemWatcher {
    public init() {}

    public func watch(
        paths: [String],
        latency: TimeInterval,
        debounceInterval: TimeInterval,
        onChange: @escaping ([FileSystemChange]) -> Void
    ) -> WatchHandle {
        return WatchHandle(onInvalidate: {})
    }
}

public final class FSEventsFileSystemWatcher: FileSystemWatcher {
    final class Session {
        var stream: FSEventStreamRef?
        let onChange: ([FileSystemChange]) -> Void
        let debounceInterval: TimeInterval
        var pendingChanges: [FileSystemChange] = []
        var debounceTask: Task<Void, Never>?
        let queue: DispatchQueue

        init(onChange: @escaping ([FileSystemChange]) -> Void, debounceInterval: TimeInterval) {
            self.onChange = onChange
            self.debounceInterval = debounceInterval
            self.queue = DispatchQueue(label: "envmatrix.fsevents")
        }

        func append(_ changes: [FileSystemChange]) {
            queue.async {
                self.pendingChanges.append(contentsOf: changes)
                self.debounceTask?.cancel()
                let interval = self.debounceInterval
                self.debounceTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    guard let self = self else { return }
                    let toEmit = self.drain()
                    if !toEmit.isEmpty {
                        self.onChange(toEmit)
                    }
                }
            }
        }

        func drain() -> [FileSystemChange] {
            return queue.sync {
                let current = self.pendingChanges
                self.pendingChanges.removeAll()
                return current
            }
        }

        func stop() {
            debounceTask?.cancel()
            debounceTask = nil
            if let s = stream {
                FSEventStreamStop(s)
                FSEventStreamSetDispatchQueue(s, nil)
                FSEventStreamInvalidate(s)
                FSEventStreamRelease(s)
                stream = nil
            }
        }
    }

    public init() {}

    public func watch(
        paths: [String],
        latency: TimeInterval,
        debounceInterval: TimeInterval,
        onChange: @escaping ([FileSystemChange]) -> Void
    ) -> WatchHandle {
        let existingPaths = paths.filter { FileManager.default.fileExists(atPath: $0) }
        if existingPaths.isEmpty {
            print("FSEventsFileSystemWatcher: no valid paths to watch (input=\(paths))")
            return WatchHandle(onInvalidate: {})
        }

        let session = Session(onChange: onChange, debounceInterval: debounceInterval)
        let opaque = Unmanaged.passRetained(session).toOpaque()

        var context = FSEventStreamContext(
            version: 0,
            info: opaque,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, _ in
            guard let info = info else { return }
            let session = Unmanaged<Session>.fromOpaque(info).takeUnretainedValue()
            let pathList = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            var changes: [FileSystemChange] = []
            changes.reserveCapacity(numEvents)
            for i in 0..<numEvents {
                let path = i < pathList.count ? pathList[i] : ""
                let flags = eventFlags[i]
                changes.append(FileSystemChange(path: path, flags: UInt32(flags)))
            }
            session.append(changes)
        }

        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagUseCFTypes
        )
        let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            existingPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        )

        guard let stream = stream else {
            print("FSEventsFileSystemWatcher: FSEventStreamCreate returned nil")
            Unmanaged<Session>.fromOpaque(opaque).release()
            return WatchHandle(onInvalidate: {})
        }

        session.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)

        return WatchHandle(onInvalidate: {
            session.stop()
            Unmanaged<Session>.fromOpaque(opaque).release()
        })
    }
}
