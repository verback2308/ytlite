import Foundation

// MARK: - Request Resolution

extension WebPoTokenService {
    func resolve(
        identifier: String,
        result: Result<String, Error>
    ) {
        queue.async {
            let completions = self.pending
                .removeValue(forKey: identifier)
                ?? []
            let item = self.timeoutWorkItems
                .removeValue(forKey: identifier)
            item?.cancel()
            self.activeAttemptIDs
                .removeValue(forKey: identifier)
            guard !completions.isEmpty else {
                return
            }
            if self.shouldRetry(
                result: result,
                completions: completions
            ) {
                self.scheduleRetry(
                    identifier: identifier,
                    completions: completions
                )
                return
            }
            self.deliverResult(
                result,
                for: identifier,
                to: completions
            )
        }
    }

    private func shouldRetry(
        result: Result<String, Error>,
        completions: [PendingRequest]
    ) -> Bool {
        guard case .failure(let error) = result,
              shouldRetryAfterFailure(error),
              let maxRetry = completions
                  .map(\.retryCount).max(),
              maxRetry < maxRetryCount
        else {
            return false
        }
        return true
    }

    private func shouldRetryAfterFailure(
        _ error: Error
    ) -> Bool {
        if case ServiceError.timedOut = error {
            return true
        }
        return false
    }
}

// MARK: - Retry Scheduling

extension WebPoTokenService {
    private func scheduleRetry(
        identifier: String,
        completions: [PendingRequest]
    ) {
        AppLog.poToken(
            "retrying mint after timeout"
        )
        resetWebViewState()
        let retried = completions.map {
            PendingRequest(
                identifier: $0.identifier,
                retryCount: $0.retryCount + 1,
                completion: $0.completion
            )
        }
        pending[identifier] = retried
        scheduleTimeout(for: identifier)
        let maxVal = completions
            .map(\.retryCount).max() ?? 0
        let attempt = maxVal + 1
        DispatchQueue.main.async {
            AppLog.poToken(
                "scheduling mint "
                + "attempt=\(attempt)"
            )
            self.ensureReady {
                self.runMint(
                    identifier: identifier
                )
            }
        }
    }
}

// MARK: - Result Delivery

extension WebPoTokenService {
    private func deliverResult(
        _ result: Result<String, Error>,
        for identifier: String,
        to completions: [PendingRequest]
    ) {
        if case .success(let token) = result {
            AppLog.poToken("mint success")
            storeCachedToken(
                token, for: identifier
            )
        } else if case .failure(let error) = result {
            if deliverStaleFallback(
                identifier: identifier,
                completions: completions
            ) {
                return
            }
            AppLog.poToken(
                "mint failed: \(error)"
            )
        }
        DispatchQueue.main.async {
            completions.forEach {
                $0.completion(result)
            }
        }
    }

    private func deliverStaleFallback(
        identifier: String,
        completions: [PendingRequest]
    ) -> Bool {
        guard let cached = staleFallbackToken(
            for: identifier
        ) else {
            return false
        }
        AppLog.poToken(
            "using stale cached content "
            + "token after failure"
        )
        DispatchQueue.main.async {
            completions.forEach {
                $0.completion(
                    .success(cached.token)
                )
            }
        }
        return true
    }
}
