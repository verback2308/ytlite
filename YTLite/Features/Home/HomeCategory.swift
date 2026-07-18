import Foundation

/// A chip on the home screen.
struct HomeCategory: Equatable {
    enum Kind: Equatable {
        /// The personalized home feed ("All").
        case feed
        /// Filters the feed by a shelf title collected at runtime.
        case shelf
        /// Pulsing stand-in while shelf chips are being collected.
        case placeholder
        /// One-shot TV destination page (no pagination — the server
        /// returns the whole page at once).
        case destination(browseId: String)
    }

    static let feed = HomeCategory(label: "All", kind: .feed)
    static let placeholder = HomeCategory(label: "", kind: .placeholder)

    /// Static tail — TV destination pages, kept after the dynamic
    /// shelf chips.
    static let destinations: [HomeCategory] = [
        HomeCategory(
            label: "Live",
            kind: .destination(browseId: BrowseID.liveDestination)
        ),
        HomeCategory(
            label: "News",
            kind: .destination(browseId: BrowseID.newsDestination)
        ),
        HomeCategory(
            label: "Gaming",
            kind: .destination(browseId: BrowseID.gamingDestination)
        ),
        HomeCategory(
            label: "Sports",
            kind: .destination(browseId: BrowseID.sportsDestination)
        ),
        HomeCategory(
            label: "Learning",
            kind: .destination(browseId: BrowseID.learningDestination)
        ),
        HomeCategory(
            label: "Fashion",
            kind: .destination(browseId: BrowseID.fashionDestination)
        )
    ]

    let label: String
    let kind: Kind
}
