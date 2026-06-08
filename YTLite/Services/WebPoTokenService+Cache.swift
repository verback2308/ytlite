import Foundation

// MARK: - Token Cache

extension WebPoTokenService {
    func validCachedToken(
        for identifier: String
    ) -> CachedToken? {
        guard let cached = tokenCache[identifier]
        else {
            return nil
        }
        let age = Date()
            .timeIntervalSince(cached.createdAt)
        return age <= tokenCacheLifetime
            ? cached : nil
    }

    func staleFallbackToken(
        for identifier: String
    ) -> CachedToken? {
        guard let cached = tokenCache[identifier]
        else {
            return nil
        }
        let age = Date()
            .timeIntervalSince(cached.createdAt)
        return age <= staleFallbackLifetime
            ? cached : nil
    }

    func storeCachedToken(
        _ token: String,
        for identifier: String
    ) {
        tokenCache[identifier] = CachedToken(
            token: token, createdAt: Date()
        )
        persistCache()
    }

    func loadPersistedCache() {
        guard let raw = UserDefaults.standard
            .dictionary(
                forKey: tokenCacheDefaultsKey
            ) as? [String: [String: Any]]
        else {
            return
        }
        var loaded: [String: CachedToken] = [:]
        for (identifier, entry) in raw {
            guard let token = entry["token"]
                as? String,
                  let ts = entry["createdAt"]
                      as? TimeInterval
            else {
                continue
            }
            loaded[identifier] = CachedToken(
                token: token,
                createdAt: Date(
                    timeIntervalSince1970: ts
                )
            )
        }
        tokenCache = loaded
    }

    func persistCache() {
        let serialized = tokenCache
            .mapValues { cached in
                [
                    "token": cached.token,
                    "createdAt": cached.createdAt
                        .timeIntervalSince1970
                ] as [String: Any]
            }
        UserDefaults.standard.set(
            serialized,
            forKey: tokenCacheDefaultsKey
        )
    }
}
