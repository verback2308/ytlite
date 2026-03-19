//
//  SZAVPlayerDataLoader.swift
//  SZAVPlayer
//
//  Created by CaiSanze on 2019/12/6.
//

import UIKit

public typealias SZAVPlayerRange = Range<Int64>

protocol SZAVPlayerDataLoaderDelegate: AnyObject {

    func dataLoader(_ loader: SZAVPlayerDataLoader, willBeginRequest dataRequest: SZAVPlayerDataRequest)
    func dataLoader(_ loader: SZAVPlayerDataLoader, didFinishRequest dataRequest: SZAVPlayerDataRequest, error: Error?)
    func dataLoader(_ loader: SZAVPlayerDataLoader, didReceive data: Data, dataRequest: SZAVPlayerDataRequest)

}

class SZAVPlayerDataLoader: NSObject {

    public weak var delegate: SZAVPlayerDataLoaderDelegate?

    private let callbackQueue: DispatchQueue
    private lazy var dataLoaderOperationQueue = createOperationQueue(name: "dataLoaderOperationQueue")
    private let uniqueID: String
    private let url: URL
    private let config: SZAVPlayerConfig
    private var mediaData: Data?

    init(uniqueID: String, url: URL, config: SZAVPlayerConfig, callbackQueue: DispatchQueue) {
        self.uniqueID = uniqueID
        self.url = url
        self.config = config
        self.callbackQueue = callbackQueue
        super.init()
    }

    deinit {
        SZLogInfo("deinit")
    }

    public func append(requestedRange: SZAVPlayerRange, dataRequest: SZAVPlayerDataRequest) {
        let dataLoaderOperation = SZAVPlayerDataLoaderOperation(uniqueID: uniqueID,
                                                                url: url,
                                                                config: config,
                                                                requestedRange: requestedRange,
                                                                dataRequest: dataRequest)
        dataLoaderOperation.delegate = self
        dataLoaderOperationQueue.addOperation(dataLoaderOperation)
    }

    public func cancel() {
        dataLoaderOperationQueue.cancelAllOperations()
    }

    public static func isOutOfRange(startOffset: Int64, endOffset: Int64, fileInfo: SZAVPlayerLocalFileInfo) -> Bool {
        let localFileStartOffset = fileInfo.startOffset
        let localFileEndOffset = fileInfo.startOffset + fileInfo.loadedByteLength
        let remainRange = startOffset..<endOffset

        let isIntersectionWithRange = remainRange.contains(localFileStartOffset) || remainRange.contains(localFileEndOffset - 1)
        let isContainsRange = localFileStartOffset <= startOffset && localFileEndOffset >= endOffset

        return !(isIntersectionWithRange || isContainsRange)
    }

}

// MARK: - SZAVPlayerDataLoaderOperationDelegate

extension SZAVPlayerDataLoader: SZAVPlayerDataLoaderOperationDelegate {

    func dataLoaderOperation(_ operation: SZAVPlayerDataLoaderOperation, willBeginRequest dataRequest: SZAVPlayerDataRequest) {
        delegate?.dataLoader(self, willBeginRequest: dataRequest)
    }

    func dataLoaderOperation(_ operation: SZAVPlayerDataLoaderOperation, didReceive data: Data, dataRequest: SZAVPlayerDataRequest) {
        callbackQueue.sync { [weak self] in
            guard let self = self else { return }

            self.delegate?.dataLoader(self, didReceive: data, dataRequest: dataRequest)
        }
    }

    func dataLoaderOperation(_ operation: SZAVPlayerDataLoaderOperation, didFinishRequest dataRequest: SZAVPlayerDataRequest, error: Error?) {
        callbackQueue.sync { [weak self] in
            guard let self = self else { return }

            self.delegate?.dataLoader(self, didFinishRequest: dataRequest, error: error)
        }
    }

}

// MARK: - Getter

extension SZAVPlayerDataLoader {

    private func createOperationQueue(name: String) -> OperationQueue {
        let queue = OperationQueue()
        queue.name = name

        return queue
    }

}
