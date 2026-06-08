import Foundation

// MARK: - Keypath traversal for Innertube JSON responses
//
// Replaces deeply-nested optional chains like:
//   (json["ownerText"] as? [String: Any])
//     .flatMap { ($0["runs"] as? [[String: Any]])?
//       .first?["text"] as? String }
// with:
//   json.dig("ownerText", "runs", 0, "text") as? String

extension Dictionary where Key == String, Value == Any {
    /// Traverses a mixed keypath (string keys + integer array indices).
    /// Returns `nil` if any step is missing or has the wrong type.
    func dig(_ keys: Any...) -> Any? {
        dig(keys: keys[...])
    }

    private func dig(keys: ArraySlice<Any>) -> Any? {
        guard let first = keys.first else {
            return self as Any
        }
        let rest = keys.dropFirst()

        guard let key = first as? String, let value = self[key] else {
            return nil
        }
        if rest.isEmpty {
            return value
        }

        if let dict = value as? [String: Any] {
            return dict.dig(keys: rest)
        }
        if let arr = value as? [[String: Any]],
           let idx = rest.first as? Int,
           arr.indices.contains(idx) {
            let remaining = rest.dropFirst()
            return remaining.isEmpty ? arr[idx] : arr[idx].dig(keys: remaining)
        }
        return nil
    }

    // MARK: - Typed convenience

    func digString(_ keys: Any...) -> String? {
        dig(keys: keys[...]) as? String
    }

    func digInt(_ keys: Any...) -> Int? {
        dig(keys: keys[...]) as? Int
    }

    func digDict(_ keys: Any...) -> [String: Any]? {
        dig(keys: keys[...]) as? [String: Any]
    }

    func digArray(_ keys: Any...) -> [[String: Any]]? {
        dig(keys: keys[...]) as? [[String: Any]]
    }

    /// Extracts `runs[0].text` — the most common Innertube text pattern.
    func runsText(_ key: String) -> String? {
        (self[key] as? [String: Any]).flatMap {
            ($0["runs"] as? [[String: Any]])?.first?["text"] as? String
        } ?? (self[key] as? [String: Any])?["simpleText"] as? String
    }

    /// Extracts `simpleText` or first `runs[].text`, whichever is present.
    func innertubeText(_ key: String) -> String? {
        guard let node = self[key] as? [String: Any] else {
            return nil
        }
        return node["simpleText"] as? String
            ?? (node["runs"] as? [[String: Any]])?
                .compactMap { $0["text"] as? String }
                .joined()
    }

    /// Returns the last thumbnail URL from a `thumbnails` array keyed by `key`.
    func thumbnailURL(_ key: String = "thumbnail") -> String? {
        ((self[key] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.last?["url"] as? String
    }
}
