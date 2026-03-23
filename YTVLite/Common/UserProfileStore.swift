import UIKit

/// Shared cache for the authenticated user's profile data (avatar + display name).
/// Loaded once after sign-in and cleared on sign-out.
final class UserProfileStore {

    static let shared = UserProfileStore()
    static let didUpdateNotification = Notification.Name("UserProfileStoreDidUpdate")

    private(set) var avatarImage: UIImage?
    private(set) var displayName: String?
    private var isLoading = false

    private init() {}

    func load() {
        guard OAuthClient.shared.isSignedIn, !isLoading else { return }
        isLoading = true

        OAuthClient.shared.validToken { [weak self] result in
            guard let self = self, case .success(let token) = result else {
                self?.isLoading = false
                return
            }
            guard let url = URL(string:
                "https://www.googleapis.com/youtube/v3/channels?part=snippet&mine=true") else {
                self.isLoading = false; return
            }
            let headers = ["Authorization": "Bearer \(token)"]
            APIClient().get(url: url, headers: headers) { [weak self] result in
                guard let self = self else { return }
                self.isLoading = false
                guard case .success(let data) = result,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let item = (json["items"] as? [[String: Any]])?.first,
                      let snippet = item["snippet"] as? [String: Any] else { return }

                let name = snippet["title"] as? String ?? ""
                let thumbs = snippet["thumbnails"] as? [String: Any] ?? [:]
                let thumb = (thumbs["high"] ?? thumbs["medium"] ?? thumbs["default"]) as? [String: Any]
                let thumbURLString = thumb?["url"] as? String ?? ""

                self.displayName = name

                if let avatarURL = URL(string: thumbURLString) {
                    URLSession.shared.dataTask(with: avatarURL) { [weak self] data, _, _ in
                        guard let self = self, let data = data, let img = UIImage(data: data) else { return }
                        DispatchQueue.main.async {
                            self.avatarImage = img
                            NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
                        }
                    }.resume()
                } else {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
                    }
                }
            }
        }
    }

    func clear() {
        avatarImage = nil
        displayName = nil
        isLoading = false
        NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
    }
}
