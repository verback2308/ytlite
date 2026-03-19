//
//  SZAVPlayerFileSystem.swift
//
//  Created by CaiSanze on 2019/11/27.
//

import UIKit
import AVKit
import CommonCrypto

struct SZAVPlayerFileSystem {

    static let documentsDirectory: URL = {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return urls[urls.endIndex - 1]
    }()

    static let cacheDirectory: URL = {
        return SZAVPlayerFileSystem.documentsDirectory.appendingPathComponent("SZCache")
    }()

    static func createCacheDirectory() {
        let directory = SZAVPlayerFileSystem.cacheDirectory
        if !FileManager.default.fileExists(atPath: directory.absoluteString){
            do {
                try FileManager.default.createDirectory(atPath: directory.path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                SZLogError(String(describing: error))
            }
        }
    }

}

// MARK: - Actions

extension SZAVPlayerFileSystem {

    @discardableResult
    static func write(data: Data, url: URL) -> Bool {
        do {
            try data.write(to: url, options: .atomic)

            return true
        } catch {
            SZLogError(String(describing: error))

            return false
        }
    }

    @discardableResult
    static func read(url: URL, range: SZAVPlayerRange) -> Data? {
        guard isExist(url: url) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url, options: [])
            if data.count >= range.upperBound {
                return data.subdata(in: Int(range.lowerBound)..<Int(range.upperBound))
            }

            return nil
        } catch {
            SZLogError(String(describing: error))

            return nil
        }
    }

    @discardableResult
    static func isExist(url: URL) -> Bool {
        return FileManager.default.fileExists(atPath: url.path)
    }

    @discardableResult
    static func delete(url: URL) -> Bool {
        do {
            try FileManager.default.removeItem(at: url)

            return true
        } catch {
            SZLogError(String(describing: error))

            return false
        }
    }

    static func localFilePath(fileName: String) -> URL {
        return cacheDirectory.appendingPathComponent(fileName)
    }

    static func cleanCachedFiles() {
        let allCachedFiles = allFiles(path: SZAVPlayerFileSystem.cacheDirectory)
        for file in allCachedFiles {
            delete(url: file)
        }
    }

}

// MARK: - Getter

extension SZAVPlayerFileSystem {

    static func uniqueID(url: URL) -> String {
        return url.absoluteString.md5
    }

    static func allFiles(path: URL) -> [URL] {
        do {
            let resourceKeys : [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
            let enumerator = FileManager.default.enumerator(at: path, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles], errorHandler: { (url, error) -> Bool in
                SZLogError("Directory enumerator error at \(url): \(error)")
                return true
            })!

            var tmpFiles: [(URL, TimeInterval)] = []
            for case let fileURL as URL in enumerator {
                let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                if let isDirectory = resourceValues.isDirectory, isDirectory {
                    // 跳过目录
                } else if let lastModified = resourceValues.contentModificationDate {
                    tmpFiles.append((fileURL, lastModified.timeIntervalSince1970))
                }
            }
            let sortedFiles = tmpFiles.sorted { $0.1 < $1.1 }
                .map{ $0.0 }

            return sortedFiles
        } catch {
            SZLogError("\(error)")
            return []
        }
    }

    static func attributes(url: String) -> [FileAttributeKey : Any]? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url)

            return attributes
        } catch {
            SZLogError(String(describing: error))

            return nil
        }
    }

    static func sizeStr(with size: Int64) -> String {
        var convertedValue: Double = Double(size)
        var multiplyFactor = 0
        let tokens = ["bytes", "KB", "MB", "GB", "TB", "PB",  "EB",  "ZB", "YB"]
        while convertedValue > 1024 {
            convertedValue /= 1024
            multiplyFactor += 1
        }

        return String(format: "%4.2f %@", convertedValue, tokens[multiplyFactor])
    }

    static func snapshot(url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        let timestamp = CMTime(seconds: 2, preferredTimescale: 60)

        do {
            let imageRef = try generator.copyCGImage(at: timestamp, actualTime: nil)

            return UIImage(cgImage: imageRef)
        } catch let error as NSError {
            SZLogError("Image generation failed with error \(error)")

            return nil
        }
    }

    static func resolution(url: URL) -> CGSize? {
        guard let track = AVURLAsset(url: url).tracks(withMediaType: AVMediaType.video).first else {
            return nil
        }

        let size = track.naturalSize.applying(track.preferredTransform)
        let resolution = CGSize(width: abs(size.width), height: abs(size.height))

        return resolution
    }

    static func duration(url: URL) -> Int64 {
        let asset = AVURLAsset(url: url)
        let durationTime = CMTimeGetSeconds(asset.duration)

        return Int64.convert(from: durationTime)
    }

}

private extension String {

    var md5: String {
        guard let data = self.data(using: .utf8) else {
            return self
        }
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        _ = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            return CC_MD5(bytes.baseAddress, CC_LONG(data.count), &digest)
        }

        return digest.map { String(format: "%02x", $0) }.joined()
    }

}

private extension Int64 {

    static func convert(from: Float64) -> Int64 {
        if from.isNaN || from.isInfinite {
            return 0
        }

        return Int64(from)
    }

}
