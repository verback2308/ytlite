import Foundation

// MARK: - UMP Response Parser

enum OnesieUMPParser {
    struct ClassifiedParts {
        let playerEntry: (Int, Data)?
        let responseParts: [OnesieResponsePart]
    }

    static func parse(
        _ data: Data
    ) -> OnesiePlaybackBootstrap? {
        let reader = UMPReader()
        reader.append(data)
        let parts = reader.readAvailableParts(
            limit: 64
        )
        let classified = classifyParts(parts)
        return buildBootstrap(from: classified)
    }

    static func classifyParts(
        _ parts: [UMPPart]
    ) -> ClassifiedParts {
        var headers: [OnesieHeaderInfo] = []
        var playerEntry: (Int, Data)?
        var response: [OnesieResponsePart] = []
        for part in parts {
            processPart(
                part,
                headers: &headers,
                playerEntry: &playerEntry,
                responseParts: &response
            )
        }
        if !headers.isEmpty {
            let types = headers.map(\.type)
            AppLog.onesie(
                "unpaired ONESIE_HEADER: \(types)"
            )
        }
        return ClassifiedParts(
            playerEntry: playerEntry,
            responseParts: response
        )
    }

    static func processPart(
        _ part: UMPPart,
        headers: inout [OnesieHeaderInfo],
        playerEntry: inout (Int, Data)?,
        responseParts: inout [OnesieResponsePart]
    ) {
        switch part.type {
        case 10:
            handleHeaderPart(
                part, headers: &headers
            )
        case 11:
            handleDataPart(
                part,
                headers: &headers,
                playerEntry: &playerEntry,
                responseParts: &responseParts
            )
        case 44:
            AppLog.onesie(
                "SABR_ERROR part in response"
            )
        default:
            AppLog.onesie(
                "UMP part type=\(part.type)"
                    + " size=\(part.size)"
            )
        }
    }
}

// MARK: - Part Handling

extension OnesieUMPParser {
    static func handleHeaderPart(
        _ part: UMPPart,
        headers: inout [OnesieHeaderInfo]
    ) {
        guard let hdr = parseOnesieHeader(
            part.payload
        ) else {
            return
        }
        headers.append(hdr)
        AppLog.onesie(
            "ONESIE_HEADER type=\(hdr.type)"
                + " compression="
                + "\(hdr.compressionType)"
        )
    }

    static func handleDataPart(
        _ part: UMPPart,
        headers: inout [OnesieHeaderInfo],
        playerEntry: inout (Int, Data)?,
        responseParts: inout [OnesieResponsePart]
    ) {
        guard !headers.isEmpty else {
            return
        }
        let header = headers.removeLast()
        responseParts.append(
            OnesieResponsePart(
                type: header.type,
                compressionType:
                    header.compressionType,
                payload: part.payload
            )
        )
        if header.type == 0 {
            playerEntry = (
                header.compressionType,
                part.payload
            )
        }
    }

    static func parseOnesieHeader(
        _ data: Data
    ) -> OnesieHeaderInfo? {
        let type = OnesieProtobuf
            .extractVarintField(
                fieldNumber: 1, from: data
            ) ?? 0
        let cryptoData = OnesieProtobuf
            .extractBytesField(
                fieldNumber: 4, from: data
            )
        let compression = cryptoData.flatMap {
            OnesieProtobuf.extractVarintField(
                fieldNumber: 6, from: $0
            )
        } ?? 0
        return OnesieHeaderInfo(
            type: type,
            compressionType: compression
        )
    }
}

// MARK: - Bootstrap Building

extension OnesieUMPParser {
    struct ParsedResponse {
        let proxyStatus: Int
        let httpStatus: Int
        let rawBody: Data
    }

    static func buildBootstrap(
        from classified: ClassifiedParts
    ) -> OnesiePlaybackBootstrap? {
        guard let (compType, resData) =
            classified.playerEntry else {
            AppLog.onesie(
                "no ONESIE_PLAYER_RESPONSE found"
            )
            return nil
        }
        guard let parsed = parseResponseData(
            resData
        ) else {
            return nil
        }
        return assembleBootstrap(
            parsed: parsed,
            compressionType: compType,
            responseParts: classified.responseParts
        )
    }

    static func parseResponseData(
        _ data: Data
    ) -> ParsedResponse? {
        guard
            let proxyStatus = OnesieProtobuf
                .extractVarintField(
                    fieldNumber: 1, from: data
                ),
            let httpStatus = OnesieProtobuf
                .extractVarintField(
                    fieldNumber: 2, from: data
                ),
            let rawBody = OnesieProtobuf
                .extractBytesField(
                    fieldNumber: 4, from: data
                ),
            proxyStatus == 1,
            httpStatus == 200
        else {
            AppLog.onesie(
                "response parse/status failed"
            )
            return nil
        }
        return ParsedResponse(
            proxyStatus: proxyStatus,
            httpStatus: httpStatus,
            rawBody: rawBody
        )
    }

    static func assembleBootstrap(
        parsed: ParsedResponse,
        compressionType: Int,
        responseParts: [OnesieResponsePart]
    ) -> OnesiePlaybackBootstrap? {
        guard let json = decodePlayerJSON(
            rawBody: parsed.rawBody,
            compressionType: compressionType
        ) else {
            return nil
        }
        logResponseParts(responseParts)
        return OnesiePlaybackBootstrap(
            playerJSON: json,
            responseParts: responseParts,
            proxyStatus: parsed.proxyStatus,
            httpStatus: parsed.httpStatus
        )
    }

    static func decodePlayerJSON(
        rawBody: Data,
        compressionType: Int
    ) -> [String: Any]? {
        let bodyBytes: Data
        if (try? JSONSerialization.jsonObject(
            with: rawBody
        )) != nil {
            bodyBytes = rawBody
        } else if compressionType == 1,
                  let decompressed =
                      OnesieCrypto.gunzip(rawBody) {
            AppLog.onesie(
                "gzip decompressed "
                    + "\(rawBody.count)B → "
                    + "\(decompressed.count)B"
            )
            bodyBytes = decompressed
        } else {
            AppLog.onesie(
                "body is neither JSON nor gzip"
            )
            return nil
        }
        return try? JSONSerialization.jsonObject(
            with: bodyBytes
        ) as? [String: Any]
    }

    static func logResponseParts(
        _ parts: [OnesieResponsePart]
    ) {
        let summary = parts
            .map {
                "\($0.type):\($0.payload.count)B"
                    + "/c\($0.compressionType)"
            }
            .joined(separator: ",")
        AppLog.onesie(
            "captured parts: [\(summary)]"
        )
    }
}
