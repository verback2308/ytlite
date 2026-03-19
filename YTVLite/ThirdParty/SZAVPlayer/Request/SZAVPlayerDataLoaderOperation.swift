//
//  SZAVPlayerDataLoaderOperation.swift
//  SZAVPlayer
//
//  Created by CaiSanze on 2021/1/23.
//

import UIKit

protocol SZAVPlayerDataLoaderOperationDelegate: AnyObject {

    func dataLoaderOperation(_ operation: SZAVPlayerDataLoaderOperation, willBeginRequest dataRequest: SZAVPlayerDataRequest)
    func dataLoaderOperation(_ operation: SZAVPlayerDataLoaderOperation, didFinishRequest dataRequest: SZAVPlayerDataRequest, error: Error?)
    func dataLoaderOperation(_ operation: SZAVPlayerDataLoaderOperation, didReceive data: Data, dataRequest: SZAVPlayerDataRequest)

}

class SZAVPlayerDataLoaderOperation: Operation {

    public typealias CompletionHandler = () -> Void
    public weak var delegate: SZAVPlayerDataLoaderOperationDelegate?

    private lazy var operationQueue = createOperationQueue(name: "dataLoaderOperationQueue")
    private var operationCompletion: CompletionHandler?
    private let uniqueID: String
    private let url: URL
    private let config: SZAVPlayerConfig
    private let requestedRange: SZAVPlayerRange
    private let dataRequest: SZAVPlayerDataRequest
    private var mediaData: Data?
    private var finalOperation: Operation?

    private var _finished: Bool = false
    private var _executing: Bool = false

    deinit {
        SZLogInfo("deinit")
    }

    init(uniqueID: String,
         url: URL,
         config: SZAVPlayerConfig,
         requestedRange: SZAVPlayerRange,
         dataRequest: SZAVPlayerDataRequest)
    {
        self.uniqueID = uniqueID
        self.url = url
        self.config = config
        self.requestedRange = requestedRange
        self.dataRequest = dataRequest
        super.init()

        operationCompletion = defaultCompletion()
    }

    // MARK: Operation Requirements

    override public func start() {
        guard !isCancelled else {return}
        markAsRunning()
        DispatchQueue.global(qos: .background).async {
            self.work { [weak self] in
                guard let self = self else { return }

                DispatchQueue.main.async {
                    guard !self.isCancelled else {return}
                    self.markAsFinished()
                }
            }
        }
    }

    override public func cancel() {
        super.cancel()
        
        if isExecuting {
            markAsFinished()
        }
    }

    override open var isFinished: Bool {
        get { return _finished }
        set { _finished = newValue }
    }

    override open var isExecuting: Bool {
        get { return _executing }
        set { _executing = newValue }
    }

    override open var isAsynchronous: Bool {
        return true
    }

}

// MARK: - Actions

extension SZAVPlayerDataLoaderOperation {

    private func work(completion: @escaping CompletionHandler) {
        operationCompletion = completion
        finalOperation = nil
        guard let delegate = delegate else {
            completion()
            return
        }

        delegate.dataLoaderOperation(self, willBeginRequest: dataRequest)

        let localFileInfos = SZAVPlayerDatabase.shared.localFileInfos(uniqueID: uniqueID)
        guard !config.disableDiskCache, localFileInfos.count > 0 else {
            finalOperation = addRemoteRequest(range: requestedRange)
            return
        }

        var startOffset = requestedRange.lowerBound
        let endOffset = requestedRange.upperBound
        for fileInfo in localFileInfos {
            if SZAVPlayerDataLoader.isOutOfRange(startOffset: startOffset, endOffset: endOffset, fileInfo: fileInfo) {
                continue
            }

            var tmpOperation: Operation?
            let localFileStartOffset = fileInfo.startOffset
            if startOffset >= localFileStartOffset {
                tmpOperation = addLocalFileRequest(startOffset: &startOffset, endOffset: endOffset, fileInfo: fileInfo)
            } else {
                tmpOperation = addRemoteRequest(startOffset: startOffset, endOffset: localFileStartOffset + 1)
                tmpOperation = addLocalFileRequest(startOffset: &startOffset, endOffset: endOffset, fileInfo: fileInfo)
            }

            finalOperation = tmpOperation
        }

        let notEnded = startOffset < endOffset
        if notEnded {
            finalOperation = addRemoteRequest(startOffset: startOffset, endOffset: endOffset)
        }
    }
    
}

// MARK: - Requests

extension SZAVPlayerDataLoaderOperation {

    private func addLocalFileRequest(startOffset: inout Int64,
                                     endOffset: Int64,
                                     fileInfo: SZAVPlayerLocalFileInfo) -> Operation?
    {
        let requestedLength = endOffset - startOffset
        guard requestedLength > 0 else { return nil }

        let localFileStartOffset = max(0, startOffset - fileInfo.startOffset)
        let localFileUsefulLength = min(fileInfo.loadedByteLength - localFileStartOffset, requestedLength)
        let localFileRequestRange = localFileStartOffset..<localFileStartOffset + localFileUsefulLength
        let operation = localFileOperation(range: localFileRequestRange, fileInfo: fileInfo)
        operationQueue.addOperation(operation)

        startOffset = startOffset + localFileUsefulLength
        return operation
    }

    private func addRemoteRequest(startOffset: Int64, endOffset: Int64) -> Operation? {
        guard startOffset < endOffset else { return nil }

        let range = startOffset..<endOffset
        return addRemoteRequest(range: range)
    }

    private func addRemoteRequest(range: SZAVPlayerRange) -> Operation {
        let operation = remoteRequestOperation(range: range)
        operationQueue.addOperation(operation)

        return operation
    }

    private func localFileOperation(range: SZAVPlayerRange, fileInfo: SZAVPlayerLocalFileInfo) -> Operation {
        let uniqueName = "\(fileInfo.localFileName)_\(Date().timeIntervalSince1970 * 1000)"
        let operation = BlockOperation { [weak self] in
            guard let self = self, !self.isCancelled else { return }

            let fileURL = SZAVPlayerFileSystem.localFilePath(fileName: fileInfo.localFileName)
            if let data = SZAVPlayerFileSystem.read(url: fileURL, range: range) {
                self.delegate?.dataLoaderOperation(self, didReceive: data, dataRequest: self.dataRequest)

                if let finalOperation = self.finalOperation,
                   finalOperation.name == uniqueName
                {
                    self.delegate?.dataLoaderOperation(self, didFinishRequest: self.dataRequest, error: nil)
                }
            } else {
                self.delegate?.dataLoaderOperation(self, didFinishRequest: self.dataRequest, error: SZAVPlayerError.localFileNotExist)
            }
        }

        operation.name = uniqueName
        return operation
    }

    private func remoteRequestOperation(range: SZAVPlayerRange) -> SZAVPlayerRequestOperation {
        let operation = SZAVPlayerRequestOperation(url: url,
                                                   range: range,
                                                   config: config)
        operation.delegate = self

        return operation
    }

}

// MARK: - SZAVPlayerRequestOperationDelegate

extension SZAVPlayerDataLoaderOperation: SZAVPlayerRequestOperationDelegate {

    func requestOperationWillStart(_ operation: SZAVPlayerRequestOperation) {
        mediaData = Data()
    }

    func requestOperation(_ operation: SZAVPlayerRequestOperation, didReceive data: Data) {
        mediaData?.append(data)
        delegate?.dataLoaderOperation(self, didReceive: data, dataRequest: dataRequest)
    }

    func requestOperation(_ operation: SZAVPlayerRequestOperation, didCompleteWithError error: Error?) {
        let shouldSaveData = error == nil
        if shouldSaveData, !config.disableDiskCache, let mediaData = mediaData, mediaData.count > 0 {
            SZAVPlayerCache.shared.save(uniqueID: uniqueID, mediaData: mediaData, startOffset: operation.startOffset)
            self.mediaData = nil
        }

        if let error = error {
            print("[SZAVPlayer] data request failed \(uniqueID): \(error.localizedDescription)")
            delegate?.dataLoaderOperation(self, didFinishRequest: dataRequest, error: error)
        } else {
            print("[SZAVPlayer] data request completed \(uniqueID): start=\(operation.startOffset)")
            if let finalOperation = finalOperation,
               finalOperation == operation
            {
                delegate?.dataLoaderOperation(self, didFinishRequest: dataRequest, error: nil)
            }
        }
    }

}

// MARK: - Private

extension SZAVPlayerDataLoaderOperation {

    private func markAsRunning() {
        willChangeValue(for: .isExecuting)
        _executing = true
        didChangeValue(for: .isExecuting)
    }

    private func markAsFinished() {
        willChangeValue(for: .isExecuting)
        willChangeValue(for: .isFinished)
        _executing = false
        _finished = true
        didChangeValue(for: .isExecuting)
        didChangeValue(for: .isFinished)
    }

    private func willChangeValue(for key: OperationChangeKey) {
        self.willChangeValue(forKey: key.rawValue)
    }

    private func didChangeValue(for key: OperationChangeKey) {
        self.didChangeValue(forKey: key.rawValue)
    }

    private enum OperationChangeKey: String {
        case isFinished
        case isExecuting
    }

}

// MARK: - Getter

extension SZAVPlayerDataLoaderOperation {

    private func defaultCompletion() -> CompletionHandler {
        return { [weak self] in
            self?.markAsFinished()
        }
    }

    private func createOperationQueue(name: String) -> OperationQueue {
        let queue = OperationQueue()
        queue.name = name
        queue.maxConcurrentOperationCount = 1

        return queue
    }

}
