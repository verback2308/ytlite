import Foundation
import zlib

// MARK: - Gzip Decompression

extension OnesieCrypto {
    struct InflateState {
        var status: Int32 = Z_OK
        var result = Data()
    }

    static func gunzip(_ data: Data) -> Data? {
        guard data.count > 2,
              data[0] == 0x1f,
              data[1] == 0x8b else {
            return nil
        }
        return inflateData(data)
    }

    static func inflateData(
        _ data: Data
    ) -> Data? {
        var stream = z_stream()
        let initResult = inflateInit2_(
            &stream,
            15 + 16,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initResult == Z_OK else {
            return nil
        }
        defer { inflateEnd(&stream) }
        return performInflation(
            &stream, data: data
        )
    }

    static func performInflation(
        _ stream: inout z_stream,
        data: Data
    ) -> Data? {
        let chunkSize = 4_096
        var state = InflateState()
        var chunk = [UInt8](
            repeating: 0, count: chunkSize
        )
        data.withUnsafeBytes { rawPtr in
            guard let base = rawPtr.bindMemory(
                to: UInt8.self
            ).baseAddress else {
                return
            }
            stream.next_in = UnsafeMutablePointer(
                mutating: base
            )
            stream.avail_in = uInt(rawPtr.count)
            inflateLoop(
                &stream,
                chunk: &chunk,
                chunkSize: chunkSize,
                state: &state
            )
        }
        return state.result.isEmpty
            ? nil : state.result
    }

    static func inflateLoop(
        _ stream: inout z_stream,
        chunk: inout [UInt8],
        chunkSize: Int,
        state: inout InflateState
    ) {
        while state.status == Z_OK {
            let produced = inflateChunk(
                &stream,
                chunk: &chunk,
                chunkSize: chunkSize,
                status: &state.status
            )
            if state.status < 0 {
                state.result.removeAll()
                return
            }
            state.result.append(
                contentsOf: chunk.prefix(produced)
            )
        }
        if state.status != Z_STREAM_END {
            state.result.removeAll()
        }
    }

    static func inflateChunk(
        _ stream: inout z_stream,
        chunk: inout [UInt8],
        chunkSize: Int,
        status: inout Int32
    ) -> Int {
        chunk.withUnsafeMutableBufferPointer { buf in
            stream.next_out = buf.baseAddress
            stream.avail_out = uInt(chunkSize)
            status = inflate(&stream, Z_NO_FLUSH)
            return chunkSize - Int(stream.avail_out)
        }
    }
}
