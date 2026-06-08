// swiftlint:disable:this file_name
import Foundation

// MARK: - Innertube JSON key constants
//
// Centralises all magic strings used when traversing Innertube JSON responses.
// Usage: json[RendererKey.video] instead of json["videoRenderer"]

// MARK: - Renderer keys

enum RendererKey {
    // Video renderers
    static let video            = "videoRenderer"
    static let tile             = "tileRenderer"
    static let compactVideo     = "compactVideoRenderer"
    static let richItem         = "richItemRenderer"
    static let childVideo       = "childVideoRenderer"

    // Layout / container renderers
    static let richGrid             = "richGridRenderer"
    static let sectionList          = "sectionListRenderer"
    static let itemSection          = "itemSectionRenderer"
    static let grid                 = "gridRenderer"
    static let shelf                = "shelfRenderer"
    static let horizontalList       = "horizontalListRenderer"
    static let verticalList         = "verticalListRenderer"
    static let twoColumnBrowse      = "twoColumnBrowseResultsRenderer"
    static let twoColumnSearch      = "twoColumnSearchResultsRenderer"
    static let twoColumn            = "twoColumnRenderer"

    // TV-specific renderers
    static let tvBrowse             = "tvBrowseRenderer"
    static let tvSecondaryNav       = "tvSecondaryNavRenderer"
    static let tvSecondaryNavSection = "tvSecondaryNavSectionRenderer"
    static let tvSurfaceContent     = "tvSurfaceContentRenderer"

    // Channel renderers
    static let channelHeader        = "channelHeaderRenderer"
    static let channelMetadata      = "channelMetadataRenderer"
    static let pageHeader           = "pageHeaderRenderer"
    static let channelThumbnailLink = "channelThumbnailWithLinkRenderer"

    // Player/watch renderers
    static let playerOverlay        = "playerOverlayRenderer"
    static let playerOverlayAutoplay = "playerOverlayAutoplayRenderer"
    static let slimVideoMetadata    = "slimVideoMetadataRenderer"
    static let slimVideoActions     = "slimVideoActionsRenderer"
    static let slimMetadataToggle   = "slimMetadataToggleButtonRenderer"
    static let videoMetadata        = "videoMetadataRenderer"

    // Playlist / library
    static let playlistVideoList = "playlistVideoListRenderer"

    // Engagement / UI
    static let likeButton           = "likeButtonRenderer"
    static let toggleButton         = "toggleButtonRenderer"
    static let subscribeButton      = "subscribeButtonRenderer"
    static let tab                  = "tabRenderer"
    static let continuationItem     = "continuationItemRenderer"
    static let metadataBadge        = "metadataBadgeRenderer"
    static let thumbnailOverlayTimeStatus = "thumbnailOverlayTimeStatusRenderer"
    static let expandableVideoDesc  = "expandableVideoDescriptionBodyRenderer"
    static let commentsHeader       = "commentsHeaderRenderer"
    static let commentsEntryPointHeader = "commentsEntryPointHeaderRenderer"
    static let commentThread        = "commentThreadRenderer"
    static let lineItem             = "lineItemRenderer"
    static let line                 = "lineRenderer"
    static let avatarLockup         = "avatarLockupRenderer"
    static let activeAccountHeader  = "activeAccountHeaderRenderer"
    static let tileHeader           = "tileHeaderRenderer"
    static let tileMetadata         = "tileMetadataRenderer"
}

// MARK: - Browse IDs

enum BrowseID {
    static let home          = "FEwhat_to_watch"
    static let subscriptions = "FEsubscriptions"
    static let history       = "FEhistory"
    static let library       = "FEmy_youtube"
    static let trending      = "FEtrending"
}

// MARK: - Innertube API endpoint paths

enum InnertubeEndpoint {
    static let browse     = "/browse"
    static let search     = "/search"
    static let player     = "/player"
    static let next       = "/next"
    static let accountList = "/account/accounts_list"
    static let subscribe  = "/subscription/subscribe"
    static let unsubscribe = "/subscription/unsubscribe"
    static let like       = "/like/like"
    static let dislike    = "/like/dislike"
    static let removeLike = "/like/removelike"
    static let commentCreate = "/comment/create_comment"
    static let getComments   = "/comment/get_comments"
}

// MARK: - Common JSON field names

enum JSONKey {
    static let contents     = "contents"
    static let items        = "items"
    static let tabs         = "tabs"
    static let sections     = "sections"
    static let continuations = "continuations"
    static let continuation = "continuation"
    static let token        = "token"
    static let videoId      = "videoId"
    static let title        = "title"
    static let runs         = "runs"
    static let simpleText   = "simpleText"
    static let text         = "text"
    static let thumbnails   = "thumbnails"
    static let url          = "url"
    static let browseId     = "browseId"
    static let params       = "params"
    static let content      = "content"
    static let header       = "header"
}
