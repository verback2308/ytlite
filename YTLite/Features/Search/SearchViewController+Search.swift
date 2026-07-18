import UIKit

// MARK: - Search flow

extension SearchViewController {
    func search(query: String) {
        let normalizedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedQuery.isEmpty else {
            clearSearchResults()
            return
        }

        searchHistory.add(normalizedQuery)
        setPanel(.hidden)
        let cancellationToken = beginSearch(for: normalizedQuery)
        service.search(
            query: normalizedQuery,
            filters: filters,
            continuation: nil,
            cancellationToken: cancellationToken
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                guard self.shouldApplyResult(
                    for: normalizedQuery,
                    cancellationToken: cancellationToken
                ) else {
                    return
                }
                self.applySearchResult(result, append: false)
            }
        }
    }

    func loadNextPage() {
        guard let token = continuationToken,
              !isLoadingNextPage,
              !lastQuery.isEmpty else {
            return
        }
        isLoadingNextPage = true
        let query = lastQuery
        let cancellationToken = searchCancellationToken
        service.search(
            query: query,
            filters: nil,
            continuation: token,
            cancellationToken: cancellationToken
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.isLoadingNextPage = false
                guard self.shouldApplyResult(
                    for: query,
                    cancellationToken: cancellationToken
                ) else {
                    return
                }
                self.applySearchResult(result, append: true)
            }
        }
    }

    private func beginSearch(for query: String) -> CancellationToken {
        searchCancellationToken.cancel()
        let cancellationToken = CancellationToken()
        searchCancellationToken = cancellationToken
        lastQuery = query
        activeSearchQuery = query
        return cancellationToken
    }

    private func applySearchResult(
        _ result: Result<SearchPage, Error>,
        append: Bool
    ) {
        refreshControl.endRefreshing()
        switch result {
        case .success(let page):
            results = append ? results + page.videos : page.videos
            continuationToken = page.continuation
            tableView.reloadData()
        case .failure(let error):
            // Silently keep the current page when a next-page load fails.
            if !append {
                presentSearchError(error)
            }
        }
    }

    private func presentSearchError(_ error: Error) {
        let alert = UIAlertController(
            title: "错误",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(
            UIAlertAction(title: "好", style: .default)
        )
        present(alert, animated: true)
    }

    private func shouldApplyResult(
        for query: String,
        cancellationToken: CancellationToken
    ) -> Bool {
        searchCancellationToken === cancellationToken
            && activeSearchQuery == query
            && !cancellationToken.isCancelled
    }

    func clearSearchResults() {
        searchCancellationToken.cancel()
        searchCancellationToken = CancellationToken()
        activeSearchQuery = nil
        lastQuery = ""
        results = []
        continuationToken = nil
        isLoadingNextPage = false
        refreshControl.endRefreshing()
        tableView.reloadData()
    }
}
