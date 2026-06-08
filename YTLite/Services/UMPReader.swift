import Foundation

// MARK: - UMP Part

struct UMPPart {
    let type: Int
    let size: Int
    let payload: Data
}

// MARK: - UMP Reader

final class UMPReader {
    private var buffer = Data()

    static func varintByteLength(
        _ firstByte: Int
    ) -> Int {
        let thresholds = [128, 192, 224, 240]
        let idx = thresholds.firstIndex {
            firstByte < $0
        }
        return (idx ?? thresholds.count) + 1
    }

    static func decodeVarint(
        data: Data,
        offset: Int,
        firstByte: Int,
        byteLength: Int
    ) -> (Int, Int) {
        switch byteLength {
        case 1:
            return (firstByte, offset + 1)
        case 2:
            let b2 = Int(data[offset + 1])
            return (
                (firstByte & 0x3f) + 64 * b2,
                offset + 2
            )
        case 3:
            let b2 = Int(data[offset + 1])
            let b3 = Int(data[offset + 2])
            let val = (firstByte & 0x1f)
                + 32 * (b2 + 256 * b3)
            return (val, offset + 3)
        case 4:
            return decode4ByteVarint(
                data: data,
                offset: offset,
                firstByte: firstByte
            )
        default:
            return decode5ByteVarint(
                data: data,
                offset: offset
            )
        }
    }

    static func decode4ByteVarint(
        data: Data,
        offset: Int,
        firstByte: Int
    ) -> (Int, Int) {
        let b2 = Int(data[offset + 1])
        let b3 = Int(data[offset + 2])
        let b4 = Int(data[offset + 3])
        let val = (firstByte & 0x0f)
            + 16 * (b2 + 256 * (b3 + 256 * b4))
        return (val, offset + 4)
    }

    static func decode5ByteVarint(
        data: Data,
        offset: Int
    ) -> (Int, Int) {
        let b2 = Int(data[offset + 1])
        let b3 = Int(data[offset + 2])
        let b4 = Int(data[offset + 3])
        let b5 = Int(data[offset + 4])
        let val = b2
            + 256 * (b3 + 256 * (b4 + 256 * b5))
        return (val, offset + 5)
    }

    static func readVarint(
        from data: Data,
        offset: Int
    ) -> (Int, Int)? {
        guard offset < data.count else {
            return nil
        }
        let firstByte = Int(data[offset])
        let byteLen = varintByteLength(firstByte)
        guard offset + byteLen <= data.count else {
            return nil
        }
        return decodeVarint(
            data: data,
            offset: offset,
            firstByte: firstByte,
            byteLength: byteLen
        )
    }

    func append(_ chunk: Data) {
        buffer.append(chunk)
    }

    func readAvailableParts(
        limit: Int = .max
    ) -> [UMPPart] {
        var parts: [UMPPart] = []
        var offset = 0
        while parts.count < limit {
            guard let result = readNextPart(
                offset: offset
            ) else {
                break
            }
            parts.append(result.0)
            offset = result.1
        }
        if offset > 0 {
            buffer.removeSubrange(0..<offset)
        }
        return parts
    }

    func readNextPart(
        offset: Int
    ) -> (UMPPart, Int)? {
        guard
            let (partType, typeOff) = Self.readVarint(
                from: buffer, offset: offset
            ),
            let (partSize, sizeOff) = Self.readVarint(
                from: buffer, offset: typeOff
            ),
            partType >= 0,
            partSize >= 0,
            sizeOff + partSize <= buffer.count
        else {
            return nil
        }
        let payload = buffer.subdata(
            in: sizeOff..<(sizeOff + partSize)
        )
        let part = UMPPart(
            type: partType,
            size: partSize,
            payload: payload
        )
        return (part, sizeOff + partSize)
    }
}
