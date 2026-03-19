//
//  SZAVPlayerContentInfo.swift
//  SZAVPlayer
//
//  Created by CaiSanze on 2019/12/6.
//

import UIKit

public struct SZAVPlayerContentInfo: SZBaseModel {

    static let tableName: String = "SZAVPlayerContentInfo"

    var uniqueID: String
    var mimeType: String
    var contentLength: Int64
    var updated: Int64 = 0
    var isByteRangeAccessSupported: Bool = false

    static func isNotExpired(updated: Int64) -> Bool {
        let expiredTimeInterval = 3600
        return Int64(Date().timeIntervalSince1970) - updated <= expiredTimeInterval
    }

}

extension SZAVPlayerContentInfo: Decodable {

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        uniqueID = try values.decode(String.self, forKey: .uniqueID)
        mimeType = try values.decode(String.self, forKey: .mimeType)
        contentLength = try values.decode(Int64.self, forKey: .contentLength)
        updated = try values.decode(Int64.self, forKey: .updated)

        let rangeAccessSupportedValue = try values.decode(Int.self, forKey: .isByteRangeAccessSupported)
        isByteRangeAccessSupported = rangeAccessSupportedValue == 1 ? true : false
    }

}
