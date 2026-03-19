//
//  SZLog.swift
//
//  Created by CaiSanze on 2019/11/27.
//

import UIKit

#if DEBUG
private let shouldLog: Bool = true
#else
private let shouldLog: Bool = false
#endif

@inlinable
public func SZLogError(_ message: @autoclosure () -> String,
                       file: StaticString = #file,
                       function: StaticString = #function,
                       line: UInt = #line)
{
    SZLog.log(message(), type: .error, file: file, function: function, line: line)
}

@inlinable
public func SZLogWarn(_ message: @autoclosure () -> String,
                      file: StaticString = #file,
                      function: StaticString = #function,
                      line: UInt = #line)
{
    SZLog.log(message(), type: .warning, file: file, function: function, line: line)
}

@inlinable
public func SZLogInfo(_ message: @autoclosure () -> String,
                      file: StaticString = #file,
                      function: StaticString = #function,
                      line: UInt = #line)
{
    SZLog.log(message(), type: .info, file: file, function: function, line: line)
}

@inlinable
public func SZLogDebug(_ message: @autoclosure () -> String,
                       file: StaticString = #file,
                       function: StaticString = #function,
                       line: UInt = #line)
{
    SZLog.log(message(), type: .debug, file: file, function: function, line: line)
}

@inlinable
public func SZLogVerbose(_ message: @autoclosure () -> String,
                         file: StaticString = #file,
                         function: StaticString = #function,
                         line: UInt = #line)
{
    SZLog.log(message(), type: .verbose, file: file, function: function, line: line)
}

public class SZLog {
    public enum logType {
        case error
        case warning
        case info
        case debug
        case verbose
    }
    
    public static func log(_ message: @autoclosure () -> String,
                           type: logType,
                           file: StaticString,
                           function: StaticString,
                           line: UInt)
    {
        guard shouldLog else { return }

        let fileName = String(describing: file).lastPathComponent
        let formattedMsg = String(format: "file:%@ func:%@ line:%d msg:---%@", fileName, String(describing: function), line, message())
        SZLogFormatter.shared.log(message: formattedMsg, type: type)
    }
    
}

private extension String {

    var fileURL: URL {
        return URL(fileURLWithPath: self)
    }

    var pathExtension: String {
        return fileURL.pathExtension
    }

    var lastPathComponent: String {
        return fileURL.lastPathComponent
    }

}

class SZLogFormatter: NSObject {

    static let shared = SZLogFormatter()
    let dateFormatter: DateFormatter
    
    override init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss:SSS"
        super.init()
    }
    
    func log(message logMessage: String, type: SZLog.logType) {
        var logLevelStr: String
        switch type {
        case .error:
            logLevelStr = "‼️ Error"
        case .warning:
            logLevelStr = "⚠️ Warning"
        case .info:
            logLevelStr = "ℹ️ Info"
        case .debug:
            logLevelStr = "✅ Debug"
        case .verbose:
            logLevelStr = "⚪ Verbose"
        }
        
        let dateStr = dateFormatter.string(from: Date())
        let finalMessage = String(format: "%@ | %@ %@", logLevelStr, dateStr, logMessage)
        print(finalMessage)
    }
}
