import Foundation
import CommonCrypto

// MARK: - AES-CTR + HMAC

enum OnesieCrypto {
    static func encryptAesCtrHmac(
        data: Data,
        clientKeyData: Data
    ) -> OnesieEncryptedData? {
        guard clientKeyData.count == 32 else {
            AppLog.onesie(
                "clientKeyData wrong length: "
                    + "\(clientKeyData.count)"
            )
            return nil
        }
        let aesKey = clientKeyData.prefix(16)
        let hmacKey = clientKeyData.suffix(16)
        guard let iv = generateIV() else {
            return nil
        }
        guard let ciphertext = aesCTR(
            data: data, key: aesKey, iv: iv
        ) else {
            return nil
        }
        var toSign = ciphertext
        toSign.append(iv)
        guard let hmac = hmacSHA256(
            data: toSign, key: hmacKey
        ) else {
            return nil
        }
        return OnesieEncryptedData(
            ciphertext: ciphertext,
            hmac: hmac,
            iv: iv
        )
    }

    static func generateIV() -> Data? {
        var iv = Data(count: 16)
        let result = iv.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let addr = buffer.baseAddress else {
                return errSecParam
            }
            return SecRandomCopyBytes(
                kSecRandomDefault, 16, addr
            )
        }
        guard result == errSecSuccess else {
            return nil
        }
        return iv
    }
}

// MARK: - AES-CTR Implementation

extension OnesieCrypto {
    static func aesCTR(
        data: Data,
        key: Data,
        iv: Data
    ) -> Data? {
        guard let ref = createCTRCryptor(
            key: key, iv: iv
        ) else {
            return nil
        }
        defer { CCCryptorRelease(ref) }
        return performCTRUpdate(
            ref: ref, data: data
        )
    }

    static func createCTRCryptor(
        key: Data,
        iv: Data
    ) -> CCCryptorRef? {
        var ref: CCCryptorRef?
        let status = key.withUnsafeBytes { keyPtr in
            iv.withUnsafeBytes { ivPtr in
                CCCryptorCreateWithMode(
                    CCOperation(kCCEncrypt),
                    CCMode(kCCModeCTR),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(0),
                    ivPtr.baseAddress,
                    keyPtr.baseAddress,
                    key.count,
                    nil,
                    0,
                    0,
                    CCModeOptions(
                        kCCModeOptionCTR_BE
                    ),
                    &ref
                )
            }
        }
        guard status == kCCSuccess else {
            AppLog.onesie(
                "CCCryptorCreateWithMode failed:"
                    + " \(status)"
            )
            return nil
        }
        return ref
    }

    static func performCTRUpdate(
        ref: CCCryptorRef,
        data: Data
    ) -> Data? {
        let capacity = data.count
            + kCCBlockSizeAES128
        var output = Data(count: capacity)
        var moved = 0
        let status = data.withUnsafeBytes { dp in
            output.withUnsafeMutableBytes { op in
                CCCryptorUpdate(
                    ref,
                    dp.baseAddress,
                    data.count,
                    op.baseAddress,
                    capacity,
                    &moved
                )
            }
        }
        guard status == kCCSuccess else {
            AppLog.onesie(
                "CCCryptorUpdate failed: \(status)"
            )
            return nil
        }
        return output.prefix(moved)
    }
}

// MARK: - HMAC-SHA256

extension OnesieCrypto {
    static func hmacSHA256(
        data: Data,
        key: Data
    ) -> Data? {
        var result = Data(
            count: Int(CC_SHA256_DIGEST_LENGTH)
        )
        result.withUnsafeMutableBytes { rp in
            data.withUnsafeBytes { dp in
                key.withUnsafeBytes { kp in
                    CCHmac(
                        CCHmacAlgorithm(
                            kCCHmacAlgSHA256
                        ),
                        kp.baseAddress,
                        key.count,
                        dp.baseAddress,
                        data.count,
                        rp.baseAddress
                    )
                }
            }
        }
        return result
    }
}

// MARK: - Encoding Helpers

extension OnesieCrypto {
    static func encodeVideoId(
        _ videoId: String
    ) -> String {
        var normalized = videoId
            .replacingOccurrences(
                of: "-", with: "+"
            )
            .replacingOccurrences(
                of: "_", with: "/"
            )
        padBase64(&normalized)
        if let decoded = Data(
            base64Encoded: normalized
        ) {
            return hexEncode(decoded)
        }
        guard let utf8 = videoId.data(
            using: .utf8
        ) else {
            return videoId
        }
        return hexEncode(utf8)
    }

    static func decodeWebSafeBase64(
        _ string: String
    ) -> Data? {
        var normalized = string
            .replacingOccurrences(
                of: "-", with: "+"
            )
            .replacingOccurrences(
                of: "_", with: "/"
            )
        padBase64(&normalized)
        return Data(base64Encoded: normalized)
    }

    static func padBase64(
        _ string: inout String
    ) {
        let remainder = string.count % 4
        if remainder != 0 {
            string.append(
                String(
                    repeating: "=",
                    count: 4 - remainder
                )
            )
        }
    }

    static func hexEncode(_ data: Data) -> String {
        let parts = data.map {
            String(format: "%02x", $0)
        }
        return parts.joined()
    }
}
