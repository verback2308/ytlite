import Foundation

// MARK: - Token Refresh

extension OAuthClient {
    func tryRefreshIfNeeded() {
        guard let tokens else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .authorizationRequired,
                    object: nil
                )
            }
            return
        }
        doRefresh(tokens: tokens) { [weak self] result in
            switch result {
            case .success:
                AppLog.auth(
                    "Token auto-refreshed on 401"
                )
            case .failure:
                AppLog.auth(
                    "Refresh failed on 401"
                        + " → require auth"
                )
                self?.tokens = nil
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .authorizationRequired,
                        object: nil
                    )
                }
            }
        }
    }

    func refreshIfStale() {
        let lastRefresh = UserDefaults.standard.double(
            forKey: "OAuthClient.lastRefresh"
        )
        let interval: TimeInterval = 12 * 60 * 60
        guard Date().timeIntervalSince1970 - lastRefresh
            > interval
        else {
            return
        }
        guard let tokens else {
            return
        }
        doRefresh(tokens: tokens) { result in
            if case .success = result {
                UserDefaults.standard.set(
                    Date().timeIntervalSince1970,
                    forKey: "OAuthClient.lastRefresh"
                )
                AppLog.auth(
                    "Periodic token refresh succeeded"
                )
            }
        }
    }
}
