import Foundation

public struct CaptureConfiguration: Sendable, Equatable {
    public var captureBodies: Bool
    public var maxBodyBytes: Int
    public var captureRequestHeaders: Bool
    public var captureResponseHeaders: Bool

    public init(
        captureBodies: Bool = true,
        maxBodyBytes: Int = 1_048_576,
        captureRequestHeaders: Bool = true,
        captureResponseHeaders: Bool = true
    ) {
        self.captureBodies = captureBodies
        self.maxBodyBytes = max(0, maxBodyBytes)
        self.captureRequestHeaders = captureRequestHeaders
        self.captureResponseHeaders = captureResponseHeaders
    }
}

public struct StorageConfiguration: Sendable, Equatable {
    public var maxEvents: Int
    public var maxBytes: Int

    public init(maxEvents: Int = 500, maxBytes: Int = 10 * 1_024 * 1_024) {
        self.maxEvents = max(1, maxEvents)
        self.maxBytes = max(1, maxBytes)
    }
}

public struct RedactionConfiguration: Sendable, Equatable {
    public var headerNames: Set<String>
    public var jsonKeys: Set<String>
    public var urlQueryNames: Set<String>
    public var replacement: String

    public init(
        headerNames: Set<String> = [],
        jsonKeys: Set<String> = [],
        urlQueryNames: Set<String> = [],
        replacement: String = "[REDACTED]"
    ) {
        self.headerNames = Set(headerNames.map { $0.lowercased() })
        self.jsonKeys = Set(jsonKeys.map { $0.lowercased() })
        self.urlQueryNames = Set(urlQueryNames.map { $0.lowercased() })
        self.replacement = replacement
    }

    public static let commonSecrets = RedactionConfiguration(
        headerNames: ["authorization", "cookie", "set-cookie", "x-api-key"],
        jsonKeys: ["password", "passwd", "token", "access_token", "refresh_token", "secret", "api_key"]
    )
}

public struct NetInspectConfiguration: @unchecked Sendable {
    public var capture: CaptureConfiguration
    public var storage: StorageConfiguration
    public var redaction: RedactionConfiguration
    public var batchSize: Int
    public var batchInterval: TimeInterval
    public var transport: (any NetInspectTransport)?
    public var logger: (any NetInspectLogger)?
    public var loggerCategory: String
    public var enablePrintBridge: Bool

    public init(
        capture: CaptureConfiguration = .init(),
        storage: StorageConfiguration = .init(),
        redaction: RedactionConfiguration = .init(),
        batchSize: Int = 25,
        batchInterval: TimeInterval = 10,
        transport: (any NetInspectTransport)? = nil,
        logger: (any NetInspectLogger)? = nil,
        loggerCategory: String = "NetInspect",
        enablePrintBridge: Bool = false
    ) {
        self.capture = capture
        self.storage = storage
        self.redaction = redaction
        self.batchSize = max(1, batchSize)
        self.batchInterval = max(0.1, batchInterval)
        self.transport = transport
        self.logger = logger
        self.loggerCategory = loggerCategory
        self.enablePrintBridge = enablePrintBridge
    }
}

public protocol NetInspectTransport: Sendable {
    func send(_ events: [NetInspectEvent]) async throws
}

public protocol NetInspectLogger: Sendable {
    func log(level: LogLevel, category: String, message: String, metadata: [String: String])
}
