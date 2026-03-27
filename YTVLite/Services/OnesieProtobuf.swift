import Foundation

// MARK: - Protobuf Encoding

enum OnesieProtobuf {
    static func appendTag(
        _ fieldNumber: Int,
        wireType: Int,
        to data: inout Data
    ) {
        appendRawVarint(
            UInt64((fieldNumber << 3) | wireType),
            to: &data
        )
    }

    static func appendRawVarint(
        _ value: UInt64,
        to data: inout Data
    ) {
        var val = value
        while val >= 0x80 {
            data.append(UInt8(val & 0x7f | 0x80))
            val >>= 7
        }
        data.append(UInt8(val))
    }

    static func appendBytes(
        _ fieldNumber: Int,
        payload: Data,
        to data: inout Data
    ) {
        appendTag(
            fieldNumber, wireType: 2, to: &data
        )
        appendRawVarint(
            UInt64(payload.count), to: &data
        )
        data.append(payload)
    }

    static func appendString(
        _ fieldNumber: Int,
        value: String,
        to data: inout Data
    ) {
        guard let encoded = value.data(
            using: .utf8
        ) else {
            return
        }
        appendBytes(
            fieldNumber,
            payload: encoded,
            to: &data
        )
    }

    static func appendBool(
        _ fieldNumber: Int,
        value: Bool,
        to data: inout Data
    ) {
        appendTag(
            fieldNumber, wireType: 0, to: &data
        )
        data.append(value ? 1 : 0)
    }

    static func appendInt32(
        _ fieldNumber: Int,
        value: Int,
        to data: inout Data
    ) {
        appendTag(
            fieldNumber, wireType: 0, to: &data
        )
        appendRawVarint(
            UInt64(bitPattern: Int64(value)),
            to: &data
        )
    }
}

// MARK: - Protobuf Decoding

extension OnesieProtobuf {
    static func extractVarintField(
        fieldNumber: Int,
        from data: Data
    ) -> Int? {
        var offset = 0
        while offset < data.count {
            guard let (tag, nextOff) =
                readProtoVarint(
                    data, offset: offset
                ) else {
                return nil
            }
            let wireType = tag & 0x7
            let fieldNum = tag >> 3
            offset = nextOff
            if fieldNum == fieldNumber,
               wireType == 0 {
                return readProtoVarint(
                    data, offset: offset
                )?.0
            }
            guard let skip = skipProtoField(
                wireType: wireType,
                in: data,
                offset: offset
            ) else {
                return nil
            }
            offset = skip
        }
        return nil
    }

    static func extractBytesField(
        fieldNumber: Int,
        from data: Data
    ) -> Data? {
        var offset = 0
        while offset < data.count {
            guard let (tag, nextOff) =
                readProtoVarint(
                    data, offset: offset
                ) else {
                return nil
            }
            let wireType = tag & 0x7
            let fieldNum = tag >> 3
            offset = nextOff
            if fieldNum == fieldNumber,
               wireType == 2 {
                return readLengthDelimited(
                    data, offset: offset
                )
            }
            guard let skip = skipProtoField(
                wireType: wireType,
                in: data,
                offset: offset
            ) else {
                return nil
            }
            offset = skip
        }
        return nil
    }
}

// MARK: - Low-Level Protobuf Helpers

extension OnesieProtobuf {
    static func readLengthDelimited(
        _ data: Data,
        offset: Int
    ) -> Data? {
        guard
            let (length, valOff) = readProtoVarint(
                data, offset: offset
            ),
            valOff + length <= data.count
        else {
            return nil
        }
        return data.subdata(
            in: valOff..<(valOff + length)
        )
    }

    static func readProtoVarint(
        _ data: Data,
        offset: Int
    ) -> (Int, Int)? {
        var result = 0
        var shift = 0
        var off = offset
        while off < data.count {
            let byte = Int(data[off])
            off += 1
            result |= (byte & 0x7f) << shift
            if byte & 0x80 == 0 {
                return (result, off)
            }
            shift += 7
            if shift >= 64 {
                return nil
            }
        }
        return nil
    }

    static func skipProtoField(
        wireType: Int,
        in data: Data,
        offset: Int
    ) -> Int? {
        switch wireType {
        case 0:
            return readProtoVarint(
                data, offset: offset
            )?.1
        case 2:
            return skipLengthDelimited(
                data, offset: offset
            )
        case 5:
            return skipFixed(
                4, in: data, offset: offset
            )
        case 1:
            return skipFixed(
                8, in: data, offset: offset
            )
        default:
            return nil
        }
    }

    static func skipLengthDelimited(
        _ data: Data,
        offset: Int
    ) -> Int? {
        guard
            let (len, off) = readProtoVarint(
                data, offset: offset
            ),
            off + len <= data.count
        else {
            return nil
        }
        return off + len
    }

    static func skipFixed(
        _ width: Int,
        in data: Data,
        offset: Int
    ) -> Int? {
        guard offset + width <= data.count else {
            return nil
        }
        return offset + width
    }
}
