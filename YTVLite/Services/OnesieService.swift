import Foundation

// MARK: - Service

final class OnesieService {
    static let shared = OnesieService()

    var cachedConfig: OnesieHotConfig?
    var cachedRedirectorHost: String?
    let queue = DispatchQueue(
        label: "com.ytvlite.onesie"
    )

    private init() {}

    // MARK: - Public

    func fetchPlayerResponse(
        videoId: String,
        visitorData: String,
        poToken: String? = nil,
        cpn: String? = nil,
        completion: @escaping (
            Result<[String: Any], Error>
        ) -> Void
    ) {
        fetchPlaybackBootstrap(
            videoId: videoId,
            visitorData: visitorData,
            poToken: poToken,
            cpn: cpn
        ) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let bootstrap):
                completion(
                    .success(bootstrap.playerJSON)
                )
            }
        }
    }

    func fetchPlaybackBootstrap(
        videoId: String,
        visitorData: String,
        poToken: String? = nil,
        cpn: String? = nil,
        completion: @escaping (
            Result<OnesiePlaybackBootstrap, Error>
        ) -> Void
    ) {
        resolveAuthAndConfig { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let ctx):
                let params = OnesieRequestParams(
                    videoId: videoId,
                    visitorData: visitorData,
                    poToken: poToken,
                    authToken: ctx.authToken,
                    config: ctx.config,
                    redirectorHost: ctx.host,
                    contentPlaybackNonce: cpn
                )
                self?.executeOnesie(
                    params: params,
                    completion: completion
                )
            }
        }
    }

    func fetchAbrRoute(
        videoId: String,
        audioItag: Int,
        videoItag: Int,
        completion: @escaping (
            Result<OnesieAbrRoute, Error>
        ) -> Void
    ) {
        resolveConfigAndHost { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let pair):
                let route = Self.buildAbrResult(
                    videoId: videoId,
                    pair: pair,
                    itags: (videoItag, audioItag)
                )
                completion(route)
            }
        }
    }
}

// MARK: - ABR Route Building

extension OnesieService {
    static func buildAbrResult(
        videoId: String,
        pair: (OnesieHotConfig, String),
        itags: (Int, Int)
    ) -> Result<OnesieAbrRoute, Error> {
        let config = pair.0
        let host = pair.1
        let idHex = OnesieCrypto.encodeVideoId(
            videoId
        )
        let routeStr = host + config.baseUrl
            + "&id=\(idHex)"
            + "&cmo:sensitive_content=yes"
            + "&opr=1&osts=0&por=1&owc=yes"
            + "&alr=yes&rn=0"
            + "&pvi=\(itags.0)"
            + "&pai=\(itags.1)"
        guard let url = URL(string: routeStr) else {
            return .failure(OnesieError.invalidURL)
        }
        return .success(
            OnesieAbrRoute(
                url: url,
                ustreamerConfig:
                    config.onesieUstreamerConfig
            )
        )
    }

    func resolveAuthAndConfig(
        completion: @escaping (
            Result<OnesieAuthContext, Error>
        ) -> Void
    ) {
        OAuthClient.shared.validToken { [weak self] tokenResult in
            let authToken: String?
            if case .success(let token) = tokenResult {
                authToken = token
            } else {
                authToken = nil
            }
            self?.resolveConfigAndHost { result in
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let pair):
                    let ctx = OnesieAuthContext(
                        authToken: authToken,
                        config: pair.0,
                        host: pair.1
                    )
                    completion(.success(ctx))
                }
            }
        }
    }

    func resolveConfigAndHost(
        completion: @escaping (
            Result<(OnesieHotConfig, String), Error>
        ) -> Void
    ) {
        fetchHotConfig { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let config):
                self?.fetchRedirectorHost { hostResult in
                    switch hostResult {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success(let host):
                        completion(
                            .success((config, host))
                        )
                    }
                }
            }
        }
    }
}
