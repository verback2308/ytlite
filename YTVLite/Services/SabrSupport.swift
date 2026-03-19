import Foundation

struct SabrRequestMetadata {
    let format: SabrFormatInfo?
    let isSABR: Bool
    let isUMP: Bool
    let isInitSegment: Bool
    let byteRange: ClosedRange<Int>?
    let timestamp: Date
}

final class SabrRequestMetadataStore {
    static let shared = SabrRequestMetadataStore()

    private let cleanupInterval: TimeInterval = 30
    private let expirationInterval: TimeInterval = 60 * 3
    private var lastCleanup = Date()
    private var entries: [String: SabrRequestMetadata] = [:]
    private let queue = DispatchQueue(label: "com.ytvlite.sabr-request-metadata")

    private init() {}

    func metadata(for requestNumber: String, remove: Bool = false) -> SabrRequestMetadata? {
        queue.sync {
            defer { conditionalCleanup() }

            guard let metadata = entries[requestNumber] else {
                return nil
            }

            if Date().timeIntervalSince(metadata.timestamp) > expirationInterval {
                entries[requestNumber] = nil
                return nil
            }

            if remove {
                entries[requestNumber] = nil
            }

            return metadata
        }
    }

    func setMetadata(_ metadata: SabrRequestMetadata, for requestNumber: String) {
        queue.sync {
            entries[requestNumber] = metadata
            conditionalCleanup()
        }
    }

    func removeAll() {
        queue.sync {
            entries.removeAll()
            lastCleanup = Date()
        }
    }

    private func conditionalCleanup() {
        let now = Date()
        guard now.timeIntervalSince(lastCleanup) > cleanupInterval else { return }
        entries = entries.filter { now.timeIntervalSince($0.value.timestamp) <= expirationInterval }
        lastCleanup = now
    }
}

struct SabrUMPPart {
    let type: Int
    let size: Int
    let payload: Data
}

struct SabrContextState {
    let type: Int
    let value: Data
    let sendByDefault: Bool
}

struct SabrNextRequestPolicyState {
    let rawPayload: Data
}

final class SabrUMPReader {
    private var buffer = Data()

    func append(_ chunk: Data) {
        buffer.append(chunk)
    }

    func readAvailableParts(limit: Int = .max) -> [SabrUMPPart] {
        var parts: [SabrUMPPart] = []
        var offset = 0

        while parts.count < limit {
            guard let (partType, typeOffset) = Self.readVarint(from: buffer, offset: offset),
                  let (partSize, sizeOffset) = Self.readVarint(from: buffer, offset: typeOffset)
            else {
                break
            }

            guard partType >= 0, partSize >= 0, sizeOffset + partSize <= buffer.count else {
                break
            }

            let payload = buffer.subdata(in: sizeOffset..<(sizeOffset + partSize))
            parts.append(SabrUMPPart(type: partType, size: partSize, payload: payload))
            offset = sizeOffset + partSize
        }

        if offset > 0 {
            buffer.removeSubrange(0..<offset)
        }

        return parts
    }

    static func readVarint(from data: Data, offset: Int) -> (Int, Int)? {
        guard offset < data.count else { return nil }

        let firstByte = Int(data[offset])
        let byteLength: Int
        switch firstByte {
        case ..<128:
            byteLength = 1
        case ..<192:
            byteLength = 2
        case ..<224:
            byteLength = 3
        case ..<240:
            byteLength = 4
        default:
            byteLength = 5
        }

        guard offset + byteLength <= data.count else { return nil }

        switch byteLength {
        case 1:
            return (firstByte, offset + 1)
        case 2:
            let byte2 = Int(data[offset + 1])
            return ((firstByte & 0x3f) + 64 * byte2, offset + 2)
        case 3:
            let byte2 = Int(data[offset + 1])
            let byte3 = Int(data[offset + 2])
            return ((firstByte & 0x1f) + 32 * (byte2 + 256 * byte3), offset + 3)
        case 4:
            let byte2 = Int(data[offset + 1])
            let byte3 = Int(data[offset + 2])
            let byte4 = Int(data[offset + 3])
            return ((firstByte & 0x0f) + 16 * (byte2 + 256 * (byte3 + 256 * byte4)), offset + 4)
        default:
            let byte2 = Int(data[offset + 1])
            let byte3 = Int(data[offset + 2])
            let byte4 = Int(data[offset + 3])
            let byte5 = Int(data[offset + 4])
            return (byte2 + 256 * (byte3 + 256 * (byte4 + 256 * byte5)), offset + 5)
        }
    }
}
