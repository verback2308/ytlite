import UIKit

// MARK: - Token Refresh

extension HomeViewController {
    func observeTokenRefresh() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTokenRefresh),
            name: .tokenDidRefresh,
            object: nil
        )
    }

    @objc
    func handleTokenRefresh() {
        AppLog.home("token refreshed → reloading feed")
        feedGeneration += 1
        selectedCategoryIndex = 0
        chipBar.setSelected(0)
        reloadFeedFromScratch()
    }
}
