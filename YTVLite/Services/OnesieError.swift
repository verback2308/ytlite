import Foundation

// MARK: - Errors

enum OnesieError: Error, CustomStringConvertible {
    case invalidURL
    case invalidResponse
    case parseError(String)
    case encryptError
    case invalidRedirector
    case encodeError

    var description: String {
        switch self {
        case .invalidURL:
            return "invalid URL"
        case .invalidResponse:
            return "invalid response"
        case .parseError(let msg):
            return "parse error: \(msg)"
        case .encryptError:
            return "encryption error"
        case .invalidRedirector:
            return "invalid redirector response"
        case .encodeError:
            return "encode error"
        }
    }
}

// MARK: - Configuration

struct OnesieHotConfig {
    let clientKeyData: Data
    let encryptedClientKey: Data
    let onesieUstreamerConfig: Data
    let baseUrl: String
    let keyExpiresInSeconds: Int
    let fetchedAt: Date

    var isValid: Bool {
        Date().timeIntervalSince(fetchedAt)
            < Double(keyExpiresInSeconds)
    }
}

// MARK: - Response Types

struct OnesieResponsePart {
    let type: Int
    let compressionType: Int
    let payload: Data
}

struct OnesiePlaybackBootstrap {
    let playerJSON: [String: Any]
    let responseParts: [OnesieResponsePart]
    let proxyStatus: Int
    let httpStatus: Int
}

struct OnesieAbrRoute {
    let url: URL
    let ustreamerConfig: Data
}

// MARK: - Request Parameters

struct OnesieRequestParams {
    let videoId: String
    let visitorData: String
    let poToken: String?
    let authToken: String?
    let config: OnesieHotConfig
    let redirectorHost: String
    let contentPlaybackNonce: String?
}

// MARK: - Auth Resolution

struct OnesieAuthContext {
    let authToken: String?
    let config: OnesieHotConfig
    let host: String
}

// MARK: - Internal Parsing Types

struct OnesieHeaderInfo {
    let type: Int
    let compressionType: Int
}

struct OnesieEncryptedData {
    let ciphertext: Data
    let hmac: Data
    let iv: Data
}
