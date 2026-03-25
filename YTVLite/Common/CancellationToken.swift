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
    private(set) var isCancelled = false

    func cancel() {
        lock.lock()
        isCancelled = true
        let pending = tasks
        tasks = []
        lock.unlock()
        pending.forEach { $0.cancel() }
    }

    func register(_ task: URLSessionDataTask) {
        lock.lock()
        if isCancelled {
            lock.unlock()
            task.cancel()
        } else {
            tasks.append(task)
            lock.unlock()
        }
    }
}
