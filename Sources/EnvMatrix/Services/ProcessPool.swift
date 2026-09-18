import Foundation

public enum ProcessPoolError: Error {
    case queueFull
    case cancelled
}

public protocol ProcessPool: AnyObject {
    func run(command: String, arguments: [String], environment: [String: String]?, dedupeKey: String?) async throws -> ProcessResult
    func cancelAll()
    var inflightCount: Int { get }
    var queuedCount: Int { get }
    var maxConcurrent: Int { get }
}

public actor AsyncSemaphore {
    var permits: Int
    var waiters: [CheckedContinuation<Void, Never>] = []

    public init(permits: Int) {
        self.permits = permits
    }

    public func wait() async {
        if permits > 0 {
            permits -= 1
            return
        }
        await withCheckedContinuation { c in
            waiters.append(c)
        }
    }

    public func signal() {
        if !waiters.isEmpty {
            let c = waiters.removeFirst()
            c.resume()
        } else {
            permits += 1
        }
    }
}

public protocol ShellRunner: Sendable {
    func run(command: String, arguments: [String], environment: [String: String]?) async throws -> ProcessResult
}

public struct DefaultShellRunner: ShellRunner {
    public init() {}

    public func run(command: String, arguments: [String], environment: [String: String]?) async throws -> ProcessResult {
        let result = try await Shell.run(command, arguments, env: environment)
        return ProcessResult(stdout: result.stdout, stderr: result.stderr, exitCode: result.exitCode)
    }
}

public final class DefaultProcessPool: ProcessPool, @unchecked Sendable {
    let semaphore: AsyncSemaphore
    let runner: ShellRunner
    let queueLimit: Int
    public let maxConcurrent: Int

    let lock = NSLock()
    var inflight: [String: Task<ProcessResult, Error>] = [:]
    var pendingLimitCounter: Int = 0
    var waitingCount: Int = 0
    var runningCount: Int = 0
    var allTasks: [Task<ProcessResult, Error>] = []

    public var inflightCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return runningCount
    }

    public var queuedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return waitingCount
    }

    public init(maxConcurrent: Int = 4, queueLimit: Int = 200, runner: ShellRunner = DefaultShellRunner()) {
        self.maxConcurrent = maxConcurrent <= 0 ? 0 : maxConcurrent
        let permits = maxConcurrent <= 0 ? Int.max : maxConcurrent
        self.semaphore = AsyncSemaphore(permits: permits)
        self.runner = runner
        self.queueLimit = queueLimit
    }

    public func run(command: String, arguments: [String], environment: [String: String]?, dedupeKey: String?) async throws -> ProcessResult {
        // Looking up the key and registering the new task must happen in ONE
        // critical section. Releasing the lock in between let two callers with
        // the same key both miss the lookup and both spawn a process, which is
        // exactly what dedupe exists to prevent. The task is created while the
        // lock is held; that only schedules the closure, and its first act is
        // an `await`, so it cannot contend for this lock before we release it.
        lock.lock()
        if let key = dedupeKey, let existing = inflight[key] {
            lock.unlock()
            return try await existing.value
        }

        if pendingLimitCounter >= queueLimit {
            lock.unlock()
            throw ProcessPoolError.queueFull
        }
        pendingLimitCounter += 1
        waitingCount += 1

        let semaphore = self.semaphore
        let runner = self.runner
        let poolRef = self
        let task = Task<ProcessResult, Error> {
            await semaphore.wait()
            poolRef.lock.lock()
            poolRef.waitingCount -= 1
            poolRef.runningCount += 1
            poolRef.lock.unlock()
            do {
                try Task.checkCancellation()
                let r = try await runner.run(command: command, arguments: arguments, environment: environment)
                poolRef.lock.lock()
                poolRef.runningCount -= 1
                poolRef.lock.unlock()
                await semaphore.signal()
                return r
            } catch {
                poolRef.lock.lock()
                poolRef.runningCount -= 1
                poolRef.lock.unlock()
                await semaphore.signal()
                throw error
            }
        }

        if let key = dedupeKey {
            inflight[key] = task
        }
        allTasks.append(task)
        lock.unlock()

        let cleanup: () -> Void = { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            // Only retract our own registration: a later call with the same key
            // may already have installed a fresh task, and clearing that would
            // let the next caller start a duplicate process.
            if let key = dedupeKey, self.inflight[key] == task {
                self.inflight[key] = nil
            }
            self.pendingLimitCounter -= 1
            if let idx = self.allTasks.firstIndex(where: { $0 == task }) {
                self.allTasks.remove(at: idx)
            }
            self.lock.unlock()
        }

        do {
            let r = try await task.value
            cleanup()
            return r
        } catch {
            cleanup()
            throw error
        }
    }

    public func cancelAll() {
        lock.lock()
        let snapshot = allTasks
        lock.unlock()
        for task in snapshot {
            task.cancel()
        }
    }
}
