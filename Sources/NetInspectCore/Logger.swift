import Foundation
import os

public struct DefaultNetInspectLogger: NetInspectLogger {
    private let subsystem: String
    private let osLogger: os.Logger

    public init(subsystem: String = Bundle.main.bundleIdentifier ?? "NetInspect") {
        self.subsystem = subsystem
        self.osLogger = os.Logger(subsystem: subsystem, category: "NetInspect")
    }

    public func log(level: LogLevel, category: String, message: String, metadata: [String: String]) {
        let suffix = metadata.isEmpty ? "" : " \(metadata.map { "\($0.key)=\($0.value)" }.joined(separator: " "))"
        let output = "[\(category)] \(message)\(suffix)"
        switch level {
        case .trace, .debug: osLogger.debug("\(output, privacy: .public)")
        case .info: osLogger.info("\(output, privacy: .public)")
        case .warning: osLogger.warning("\(output, privacy: .public)")
        case .error: osLogger.error("\(output, privacy: .public)")
        case .fault: osLogger.fault("\(output, privacy: .public)")
        }
        if !metadata.isEmpty {
            Swift.print(output)
        } else {
            Swift.print("[\(category)] \(message)")
        }
    }
}

public struct NetInspectPrintStream: TextOutputStream {
    public let level: LogLevel
    public let category: String
    public let metadata: [String: String]

    public init(level: LogLevel = .info, category: String = "print", metadata: [String: String] = [:]) {
        self.level = level
        self.category = category
        self.metadata = metadata
    }

    public mutating func write(_ string: String) {
        NetInspect.log(level: level, category: category, message: string.trimmingCharacters(in: .newlines), metadata: metadata)
    }
}
