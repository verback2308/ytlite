import Foundation

// MARK: - Media URL query helpers

extension MWebSource {
    static func nValue(of url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first { $0.name == "n" }?.value
    }

    static func hasQuery(_ url: URL, _ name: String) -> Bool {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.contains { $0.name == name } ?? false
    }

    static func replacingN(in url: URL, solved: String) -> URL {
        guard var components = URLComponents(
            url: url, resolvingAgainstBaseURL: false
        ) else {
            return url
        }
        var items = components.queryItems ?? []
        if let index = items.firstIndex(where: { $0.name == "n" }) {
            items[index] = URLQueryItem(name: "n", value: solved)
        }
        components.queryItems = items
        return components.url ?? url
    }
}
