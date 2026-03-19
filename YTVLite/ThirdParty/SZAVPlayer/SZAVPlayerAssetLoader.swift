//
//  SZAVPlayerAssetLoader.swift
//  SZAVPlayer
//
//  Created by CaiSanze on 2019/12/23.
//

import UIKit
import AVFoundation
import CoreServices

/// AVPlayerItem custom schema
private let SZAVPlayerItemScheme = "SZAVPlayerItemScheme"

public protocol SZAVPlayerAssetLoaderDelegate: AnyObject {
    func assetLoaderDidFinishDownloading(_ assetLoader: SZAVPlayerAssetLoader)
    func assetLoader(_ assetLoader: SZAVPlayerAssetLoader, downloadingFailed error: Error)
}

public class SZAVPlayerAssetLoader: NSObject {

    public weak var delegate: SZAVPlayerAssetLoaderDelegate?
    public var uniqueID: String = "defaultUniqueID"
    public let url: URL
    public var urlAsset: AVURLAsset?

    private let loaderQueue = DispatchQueue(label: "com.SZAVPlayer.loaderQueue")
    private lazy var dataLoader: SZAVPlayerDataLoader = createDataLoader()
    private var currentInfoRequest: SZAVPlayerRequest? {
        didSet {
            oldValue?.cancel()
        }
    }
    private var isCancelled: Bool = false
    private let config: SZAVPlayerConfig

    init(url: URL, config: SZAVPlayerConfig) {
        self.url = url
        self.config = config
        super.init()
    }

    deinit {
        SZLogInfo("deinit")
    }

    public func loadAsset(disableCustomLoading: Bool = false, completion: @escaping (AVURLAsset) -> Void) {
        var asset: AVURLAsset
        if disableCustomLoading {
            asset = AVURLAsset(url: url)
        } else if let urlWithSchema = url.withScheme(SZAVPlayerItemScheme) {
            asset = AVURLAsset(url: urlWithSchema)
            asset.resourceLoader.setDelegate(self, queue: loaderQueue)
        } else {
            assertionFailure("URL schema is empty, please make sure to use the correct initilization func.")
            return
        }

        asset.loadValuesAsynchronously(forKeys: ["playable"]) {
            DispatchQueue.main.async {
                completion(asset)
            }
        }

        urlAsset = asset
    }

}

// MARK: - Actions

extension SZAVPlayerAssetLoader {

    public func cleanup() {
        isCancelled = true
        dataLoader.cancel()
        currentInfoRequest?.cancel()
    }

    private func handleContentInfoRequest(loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let infoRequest = loadingRequest.contentInformationRequest else {
            return false
        }

        // use cached info first
        if !config.disableDiskCache,
            let contentInfo = SZAVPlayerDatabase.shared.contentInfo(uniqueID: self.uniqueID),
            SZAVPlayerContentInfo.isNotExpired(updated: contentInfo.updated)
        {
            print("[SZAVPlayer] content info cache hit for \(uniqueID)")
            self.fillInWithLocalData(infoRequest, contentInfo: contentInfo)
            loadingRequest.finishLoading()

            return true
        }

        let request = contentInfoRequest(loadingRequest: loadingRequest)
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
        let task = session.dataTask(with: request) { (_, response, error) in
            self.handleContentInfoResponse(loadingRequest: loadingRequest,
                                           infoRequest: infoRequest,
                                           response: response,
                                           error: error)
        }
        print("[SZAVPlayer] content info request \(uniqueID): \(request.url?.absoluteString ?? "nil") headers=\(request.allHTTPHeaderFields ?? [:])")

        self.currentInfoRequest = SZAVPlayerContentInfoRequest(
            resourceUrl: url,
            loadingRequest: loadingRequest,
            infoRequest: infoRequest,
            task: task
        )

        task.resume()

        return true
    }

    private func handleContentInfoResponse(loadingRequest: AVAssetResourceLoadingRequest,
                                           infoRequest: AVAssetResourceLoadingContentInformationRequest,
                                           response: URLResponse?,
                                           error: Error?)
    {
        self.loaderQueue.async {
            if self.isCancelled || loadingRequest.isCancelled {
                return
            }

            guard let request = self.currentInfoRequest as? SZAVPlayerContentInfoRequest,
                loadingRequest === request.loadingRequest else
            {
                return
            }

            if let error = error {
                let nsError = error as NSError
                if SZAVPlayerAssetLoader.isNetworkError(code: nsError.code),
                    let contentInfo = SZAVPlayerDatabase.shared.contentInfo(uniqueID: self.uniqueID)
                {
                    self.fillInWithLocalData(infoRequest, contentInfo: contentInfo)
                    loadingRequest.finishLoading()
                } else {
                    SZLogError("Failed with error: \(String(describing: error))")
                    loadingRequest.finishLoading(with: error)
                }

                return
            }

            if let response = response {
                if let httpResponse = response as? HTTPURLResponse {
                    print("[SZAVPlayer] content info status \(self.uniqueID): \(httpResponse.statusCode)")
                }
                if let mimeType = response.mimeType, !self.config.disableDiskCache {
                    let info = SZAVPlayerContentInfo(uniqueID: self.uniqueID,
                                                     mimeType: mimeType,
                                                     contentLength: response.sz_expectedContentLength,
                                                     isByteRangeAccessSupported: response.sz_isByteRangeAccessSupported)
                    SZAVPlayerDatabase.shared.update(contentInfo: info)
                }
                print("[SZAVPlayer] content info response \(self.uniqueID): mime=\(response.mimeType ?? "nil") len=\(response.sz_expectedContentLength) ranges=\(response.sz_isByteRangeAccessSupported)")
                self.fillInWithRemoteResponse(infoRequest, response: response)
                loadingRequest.finishLoading()
            }

            if self.currentInfoRequest === request {
                self.currentInfoRequest = nil
            }
        }
    }

    private func handleDataRequest(loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        if self.isCancelled || loadingRequest.isCancelled {
            return false
        }

        guard let avDataRequest = loadingRequest.dataRequest else {
            return false
        }

        let lowerBound = avDataRequest.requestedOffset
        let length = Int64(avDataRequest.requestedLength)
        let upperBound = lowerBound + length
        let requestedRange = lowerBound..<upperBound
        print("[SZAVPlayer] data request \(uniqueID): \(requestedRange.lowerBound)-\(requestedRange.upperBound)")
        let dataRequest: SZAVPlayerDataRequest = {
            return SZAVPlayerDataRequest(
                resourceUrl: url,
                loadingRequest: loadingRequest,
                dataRequest: avDataRequest,
                range: requestedRange
            )
        }()
        
        dataLoader.append(requestedRange: requestedRange, dataRequest: dataRequest)

        return true
    }

    private func fillInWithLocalData(_ request: AVAssetResourceLoadingContentInformationRequest, contentInfo: SZAVPlayerContentInfo) {
        if let contentType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, contentInfo.mimeType as CFString, nil) {
            let contentTypeStr = contentType.takeRetainedValue() as String
            request.contentType = convertTypeIfNeeded(contentType: contentTypeStr)
        }

        request.contentLength = contentInfo.contentLength
        request.isByteRangeAccessSupported = contentInfo.isByteRangeAccessSupported
    }

    private func fillInWithRemoteResponse(_ request: AVAssetResourceLoadingContentInformationRequest, response: URLResponse) {
        if let mimeType = response.mimeType,
            let contentType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimeType as CFString, nil)
        {
            let contentTypeStr = contentType.takeRetainedValue() as String
            request.contentType = convertTypeIfNeeded(contentType: contentTypeStr)
        }
        request.contentLength = response.sz_expectedContentLength
        request.isByteRangeAccessSupported = response.sz_isByteRangeAccessSupported
    }

    private func convertTypeIfNeeded(contentType: String) -> String {
        if contentType == "public.text" || contentType == "public.plain-text" {
            return config.isVideo ? "public.mpeg-4" : "public.mp3"
        }

        return contentType
    }

}

// MARK: - AVAssetResourceLoaderDelegate

extension SZAVPlayerAssetLoader: AVAssetResourceLoaderDelegate {

    public func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                               shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool
    {
        if let _ = loadingRequest.contentInformationRequest {
            return handleContentInfoRequest(loadingRequest: loadingRequest)
        } else if let _ = loadingRequest.dataRequest {
            return handleDataRequest(loadingRequest: loadingRequest)
        } else {
            return false
        }
    }

    public func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                               didCancel loadingRequest: AVAssetResourceLoadingRequest)
    {
        dataLoader.cancel()
    }

}

// MARK: - SZAVPlayerDataLoaderDelegate

extension SZAVPlayerAssetLoader: SZAVPlayerDataLoaderDelegate {

    func dataLoader(_ loader: SZAVPlayerDataLoader, willBeginRequest dataRequest: SZAVPlayerDataRequest) {

    }

    func dataLoader(_ loader: SZAVPlayerDataLoader, didFinishRequest dataRequest: SZAVPlayerDataRequest, error: Error?) {
        if let error = error {
            dataRequest.loadingRequest.finishLoading(with: error)
            delegate?.assetLoader(self, downloadingFailed: error)
        } else {
            dataRequest.loadingRequest.finishLoading()
            delegate?.assetLoaderDidFinishDownloading(self)
        }
    }


    func dataLoader(_ loader: SZAVPlayerDataLoader, didReceive data: Data, dataRequest: SZAVPlayerDataRequest) {
        if let actualDataRequest = dataRequest.loadingRequest.dataRequest {
            actualDataRequest.respond(with: data)
        }
    }

}

// MARK: - Extensions

fileprivate extension URL {

    func withScheme(_ scheme: String) -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.scheme = scheme
        return components.url
    }

}

fileprivate extension URLResponse {

    var sz_expectedContentLength: Int64 {
        guard let response = self as? HTTPURLResponse else {
            return expectedContentLength
        }

        let contentRangeKeys: [String] = [
            "Content-Range",
            "content-range",
            "Content-range",
            "content-Range",
        ]
        var rangeString: String?
        for key in contentRangeKeys {
            if let value = response.allHeaderFields[key] as? String {
                rangeString = value
                break
            }
        }

        if let rangeString = rangeString,
            let bytesString = rangeString.split(separator: "/").map({String($0)}).last,
            let bytes = Int64(bytesString)
        {
            return bytes
        } else {
            return expectedContentLength
        }
    }

    var sz_isByteRangeAccessSupported: Bool {
        guard let response = self as? HTTPURLResponse else {
            return false
        }

        let rangeAccessKeys: [String] = [
            "Accept-Ranges",
            "accept-ranges",
            "Accept-ranges",
            "accept-Ranges",
        ]

        for key in rangeAccessKeys {
            if let value = response.allHeaderFields[key] as? String,
                value == "bytes"
            {
                return true
            }
        }

        return false
    }

}

// MARK: - Getter

extension SZAVPlayerAssetLoader {

    private static func isNetworkError(code: Int) -> Bool {
        let errorCodes = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut,
        ]

        return errorCodes.contains(code)
    }

    private func contentInfoRequest(loadingRequest: AVAssetResourceLoadingRequest) -> URLRequest {
        var request = URLRequest(url: url)
        if let dataRequest = loadingRequest.dataRequest {
            let lowerBound = Int(dataRequest.requestedOffset)
            let upperBound = lowerBound + Int(dataRequest.requestedLength) - 1
            let rangeHeader = "bytes=\(lowerBound)-\(upperBound)"
            request.setValue(rangeHeader, forHTTPHeaderField: "Range")
        } else {
            request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        }

        if let headers = config.headersForContentInfoRequest {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        return request
    }

    private func createDataLoader() -> SZAVPlayerDataLoader {
        let loader = SZAVPlayerDataLoader(uniqueID: uniqueID,
                                          url: url,
                                          config: config,
                                          callbackQueue: loaderQueue)
        loader.delegate = self

        return loader
    }

}
