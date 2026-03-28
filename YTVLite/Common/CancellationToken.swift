import Foundation

/// A lightweight cancellation token for coordinating cancellation of
/// async operations that use completion handlers (pre-Swift-Concurrency).
///
/// Usage:
///   let token = CancellationToken()
///   apiClient.fetch(..., cancellationToken: token) { result in ... }
///   token.cancel()  // all registered tasks are cancelled, callbacks are silenced
final class CancellationToken {
    private let lock = NSLock()
    private var tasks: [URLSessionDataTask] = []
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let pending = tasks
        tasks = []
        lock.unlock()
        pending.forEach { $0.cancel() }
    }

    func register(_ task: URLSessionDataTask) {
        lock.lock()
        if cancelled {
            lock.unlock()
            task.cancel()
        } else {
            tasks.append(task)
            lock.unlock()
        }
    }
}
