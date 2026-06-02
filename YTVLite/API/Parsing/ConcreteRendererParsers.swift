// swiftlint:disable:this file_name
import Foundation

// MARK: - TileVideoRendererParser

/// Handles {"tileRenderer": {...}} — used by TV/TVHTML5 client responses.
struct TileVideoRendererParser: VideoRendererParser {
    func video(from item: [String: Any]) -> Video? {
        guard let tile = item[RendererKey.tile] as? [String: Any]
        else { return nil }
        return InnertubeClient.parseTileRenderer(tile)
    }
}

// MARK: - DirectVideoRendererParser

/// Handles {"videoRenderer": {...}} — used by WEB client browse/search responses.
struct DirectVideoRendererParser: VideoRendererParser {
    func video(from item: [String: Any]) -> Video? {
        guard let vr = item[RendererKey.video] as? [String: Any]
        else { return nil }
        return InnertubeClient.parseWebVideoRenderer(vr)
    }
}

// MARK: - CompactVideoRendererParser

/// Handles {"compactVideoRenderer": {...}} — used in continuation and related responses.
struct CompactVideoRendererParser: VideoRendererParser {
    func video(from item: [String: Any]) -> Video? {
        guard let vr = item[RendererKey.compactVideo] as? [String: Any]
        else { return nil }
        return InnertubeClient.parseWebVideoRenderer(vr)
    }
}

// MARK: - GridVideoRendererParser

/// Handles {"gridVideoRenderer": {...}} — used by WEB channel tab grids.
struct GridVideoRendererParser: VideoRendererParser {
    func video(from item: [String: Any]) -> Video? {
        guard let vr = item["gridVideoRenderer"] as? [String: Any]
        else { return nil }
        return InnertubeClient.parseGridVideoRenderer(vr)
    }
}

// MARK: - RichItemVideoRendererParser

/// WEB home/subscription feed richItemRenderer parser.
struct RichItemVideoRendererParser: VideoRendererParser {
    func video(from item: [String: Any]) -> Video? {
        guard let vr = item.digDict(
            RendererKey.richItem, JSONKey.content, RendererKey.video
        )
        else { return nil }
        return InnertubeClient.parseWebVideoRenderer(vr)
    }
}

// MARK: - LockupViewModelVideoParser

/// Handles {"lockupViewModel": {...}} — new YouTube channel grid format.
struct LockupViewModelVideoParser: VideoRendererParser {
    func video(from item: [String: Any]) -> Video? {
        guard let lockup = item["lockupViewModel"] as? [String: Any]
        else { return nil }
        return InnertubeClient.parseLockupVideo(lockup)
    }
}

// MARK: - RadioRendererParser

/// Handles {"radioRenderer": {...}} — radio mix / playlist items.
struct RadioRendererParser: VideoRendererParser {
    func video(from item: [String: Any]) -> Video? {
        guard let rr = item["radioRenderer"] as? [String: Any]
        else { return nil }
        return InnertubeClient.parseRadioRenderer(rr)
    }
}

// MARK: - PlaylistRendererParser

/// Handles {"playlistRenderer": {...}} — inline playlist items.
struct PlaylistRendererParser: VideoRendererParser {
    func video(from item: [String: Any]) -> Video? {
        guard let pr = item["playlistRenderer"] as? [String: Any]
        else { return nil }
        return InnertubeClient.parsePlaylistRenderer(pr)
    }
}
