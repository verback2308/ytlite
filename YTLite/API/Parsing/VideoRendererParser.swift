import Foundation

// MARK: - VideoRendererParser

/// A single link in the renderer chain. Each parser handles one renderer type
/// (e.g. "tileRenderer", "videoRenderer") from an item dictionary.
///
/// Item dictionaries look like: {"tileRenderer": {...}} or {"videoRenderer": {...}}.
protocol VideoRendererParser {
    /// Returns a `Video` if this parser can handle the item, nil otherwise.
    func video(from item: [String: Any]) -> Video?
}

// MARK: - VideoRendererParserChain

/// Tries each registered VideoRendererParser in priority order and returns the
/// first non-nil result. Replaces repeated if/else chains in browse parsing:
///
///   Before:
///     if let tile = item["tileRenderer"]     { parseTileRenderer(tile) }
///     if let vr   = item["videoRenderer"]    { parseWebVideoRenderer(vr) }
///     if let vr   = item["compactVideoRenderer"] { parseWebVideoRenderer(vr) }
///     if let ri   = item["richItemRenderer"] { ... vr = ri["content"]["videoRenderer"] ... }
///
///   After:
///     VideoRendererParserChain.shared.video(from: item)
///
enum VideoRendererParserChain {
    private static let parsers: [VideoRendererParser] = [
        TileVideoRendererParser(),
        DirectVideoRendererParser(),
        CompactVideoRendererParser(),
        GridVideoRendererParser(),
        RichItemVideoRendererParser(),
        LockupViewModelVideoParser(),
        RadioRendererParser(),
        PlaylistRendererParser()
    ]

    static func video(from item: [String: Any]) -> Video? {
        parsers.lazy.compactMap { $0.video(from: item) }.first
    }

    /// Extracts a continuation token from a `continuationItemRenderer` item, if present.
    static func continuation(from item: [String: Any]) -> String? {
        guard let renderer = item["continuationItemRenderer"] as? [String: Any],
              let ct = renderer["continuationEndpoint"] as? [String: Any],
              let cmd = ct["continuationCommand"] as? [String: Any],
              let token = cmd["token"] as? String
        else {
            return nil
        }
        return token
    }

    /// Convenience: maps a list of items to videos, skipping unrecognised items.
    static func videos(from items: [[String: Any]]) -> [Video] {
        items.compactMap { video(from: $0) }
    }

    /// Convenience: maps items to videos AND extracts the first continuation token found.
    static func parse(items: [[String: Any]]) -> (videos: [Video], continuation: String?) {
        var videos: [Video] = []
        var continuation: String?
        for item in items {
            if let video = video(from: item) {
                videos.append(video)
            } else if continuation == nil, let token = Self.continuation(from: item) {
                continuation = token
            }
        }
        return (videos, continuation)
    }
}
