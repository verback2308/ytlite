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

        // Use Innertube /account/accounts_list (TV context + Bearer token)
        // This is how YouTube.js AccountManager.getInfo() works.
        InnertubeClient.shared.fetchAccountInfo { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let err):
                print("[UserProfileStore] fetchAccountInfo failed: \(err)")
                self.isLoading = false
            case .success(let info):
                self.displayName = info.name
                guard let urlStr = info.avatarURL, let avatarURL = URL(string: urlStr) else {
                    self.isLoading = false
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
                    }
                    return
                }
                URLSession.shared.dataTask(with: avatarURL) { [weak self] data, _, _ in
                    guard let self = self else { return }
                    self.isLoading = false
                    if let data = data, let img = UIImage(data: data) {
                        DispatchQueue.main.async {
                            self.avatarImage = img
                            NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
                        }
                    }
                }.resume()
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
