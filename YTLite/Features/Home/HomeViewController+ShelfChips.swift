import UIKit

/// A contiguous titled run of the accumulated "All" feed.
struct FeedRun {
    let title: String?
    var videos: [Video]
    /// The originating shelf's own token (rails restore their
    /// horizontal paging with it).
    var continuation: String?
}

// MARK: - Dynamic shelf chips
//
// Shelf titles found in feed pages become chips between "All" and the
// static destination tail. Tapping one filters the accumulated feed
// to that title and pages on with the shelf's own continuation
// tokens. On load/refresh a few extra pages are prefetched in the
// background to collect enough titles; the bar shows pulsing
// placeholders meanwhile.

extension HomeViewController {
    static let maxShelfChips = 10
    /// Stop prefetching once this many titles are collected.
    static let chipPrefetchTarget = 8

    // MARK: - Chip bar contents

    func rebuildChips() {
        var cats: [HomeCategory] = [.feed]
        cats += shelfTitles.map {
            HomeCategory(label: $0, kind: .shelf)
        }
        let placeholders = chipDiscoveryActive
            ? max(1, min(3, Self.chipPrefetchTarget - shelfTitles.count))
            : 0
        cats += Array(repeating: .placeholder, count: placeholders)
        // The static tail joins only once discovery settles — a bar
        // that is half skeleton, half finished chips looks odd.
        if !chipDiscoveryActive {
            cats += HomeCategory.destinations
        }
        let selected = categories.indices.contains(selectedCategoryIndex)
            ? categories[selectedCategoryIndex]
            : .feed
        categories = cats
        selectedCategoryIndex = cats.firstIndex(of: selected) ?? 0
        let start = shelfTitles.count + 1
        chipBar.setLabels(
            cats.map { $0.label },
            selected: selectedCategoryIndex,
            placeholders: IndexSet(integersIn: start..<start + placeholders)
        )
    }

    /// Adds the page's new shelf titles as chips. Titles clashing
    /// with the static chips are skipped to avoid duplicates.
    func updateChips(from page: FeedPage) {
        guard let shelves = page.shelves else {
            return
        }
        let reserved = Set(
            ([HomeCategory.feed] + HomeCategory.destinations)
                .map { $0.label.lowercased() }
        )
        var added = false
        for shelf in shelves {
            guard shelfTitles.count < Self.maxShelfChips else {
                break
            }
            guard let title = shelf.title,
                  !title.isEmpty,
                  title.count <= 30,
                  !reserved.contains(title.lowercased()),
                  !shelfTitles.contains(title)
            else {
                continue
            }
            shelfTitles.append(title)
            added = true
        }
        if added {
            rebuildChips()
        }
    }

    func resetChipState() {
        shelfTitles = []
        feedRuns = []
        chipTokens = []
        selectedShelfTitle = nil
        allContinuation = nil
        pendingChipReselect = nil
        chipDiscoveryActive = false
        chipPrefetchBudget = 0
        rebuildChips()
    }

    // MARK: - Feed accumulation

    /// Records the page's titled runs so chips can filter and "All"
    /// re-entry can restore without a refetch.
    func recordRuns(from page: FeedPage) {
        let shelves = page.shelves
            ?? [FeedShelf(title: nil, count: page.videos.count)]
        var index = 0
        for shelf in shelves {
            let end = min(index + shelf.count, page.videos.count)
            appendRun(
                title: shelf.title,
                videos: Array(page.videos[index..<end]),
                continuation: shelf.continuation
            )
            index = end
        }
        appendRun(
            title: nil,
            videos: Array(page.videos.dropFirst(index)),
            continuation: nil
        )
    }

    private func appendRun(
        title: String?,
        videos: [Video],
        continuation: String?
    ) {
        guard !videos.isEmpty else {
            return
        }
        if let last = feedRuns.indices.last, feedRuns[last].title == title {
            feedRuns[last].videos += videos
        } else {
            feedRuns.append(
                FeedRun(
                    title: title,
                    videos: videos,
                    continuation: continuation
                )
            )
        }
    }

    // MARK: - Chip selection

    /// Filters the accumulated feed to the title and queues the
    /// title's shelf tokens for pagination.
    func enterShelfChip(_ title: String) {
        selectedShelfTitle = title
        let videos = feedRuns
            .filter { $0.title == title }
            .flatMap { $0.videos }
        chipTokens = shelfQueue
            .filter { $0.title == title }
            .map { $0.token }
        let first = chipTokens.isEmpty ? nil : chipTokens.removeFirst()
        var page = FeedPage(videos: videos, continuation: nil)
        if useRails {
            // One rail paging horizontally through the shelf; no
            // page continuation, or the vertical trigger would loop.
            page.shelves = [
                FeedShelf(title: title, count: videos.count, continuation: first)
            ]
        } else {
            page.continuation = first
        }
        setPage(page)
    }

    /// Rebuilds "All" from the accumulated runs — no refetch, and the
    /// shelf-drain state carries on where it left off.
    func restoreAllFeed() {
        var page = FeedPage(
            videos: feedRuns.flatMap { $0.videos },
            continuation: allContinuation
        )
        page.shelves = feedRuns.map {
            FeedShelf(
                title: $0.title,
                count: $0.videos.count,
                continuation: $0.continuation
            )
        }
        setPage(page)
    }

    func loadMoreForChip() {
        guard let token = currentContinuation else {
            finishLoadingMore()
            return
        }
        let generation = feedGeneration
        service.fetchNextPage(continuation: token) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.feedGeneration == generation else {
                    return
                }
                switch result {
                case .success(var page):
                    if page.continuation == nil, !self.chipTokens.isEmpty {
                        page.continuation = self.chipTokens.removeFirst()
                    }
                    self.appendPage(page)
                case .failure where !self.chipTokens.isEmpty:
                    self.appendPage(FeedPage(
                        videos: [],
                        continuation: self.chipTokens.removeFirst()
                    ))
                case .failure:
                    self.finishLoadingMore()
                }
            }
        }
    }

    // MARK: - Background chip discovery

    func beginChipDiscovery() {
        chipDiscoveryActive = true
        chipPrefetchBudget = 3
        rebuildChips()
    }

    func endChipDiscovery() {
        guard chipDiscoveryActive else {
            return
        }
        chipDiscoveryActive = false
        chipPrefetchBudget = 0
        rebuildChips()
    }

    /// Fetches the next feed page in the background while more chips
    /// are wanted; piggybacks on the regular load-more pipeline, so
    /// the videos also extend the scrollable feed.
    func continueChipPrefetchIfNeeded() {
        guard chipDiscoveryActive else {
            return
        }
        let wantMore = selectedShelfTitle == nil
            && categories[selectedCategoryIndex].kind == .feed
            && shelfTitles.count < Self.chipPrefetchTarget
            && chipPrefetchBudget > 0
            && currentContinuation != nil
        guard wantMore else {
            endChipDiscovery()
            return
        }
        guard !isLoadingMore else {
            return
        }
        chipPrefetchBudget -= 1
        isLoadingMore = true
        handleLoadMore()
    }

    /// After a refresh, jumps back to the shelf chip that was
    /// selected — if the fresh feed still has it.
    func applyPendingChipReselect() {
        guard let title = pendingChipReselect else {
            return
        }
        pendingChipReselect = nil
        guard let idx = categories.firstIndex(
            of: HomeCategory(label: title, kind: .shelf)
        ) else {
            return
        }
        chipBar.setSelected(idx)
        selectCategory(at: idx)
    }

    func refreshAllFeed() {
        cache.clearHomeFeed()
        reloadFeedFromScratch()
    }

    /// Drops the accumulated session (runs, chips, chip filter) and
    /// refetches the feed.
    func reloadFeedFromScratch() {
        startFreshSession()
        loadFeed()
    }

    /// Clears the accumulated session so the next applied page
    /// starts a new one.
    func startFreshSession() {
        selectedShelfTitle = nil
        chipTokens = []
        feedRuns = []
        shelfTitles = []
    }
}
