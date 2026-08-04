import Foundation

public enum LogLevel: String, Codable, Sendable, CaseIterable {
    case trace
    case debug
    case info
    case warning
    case error
    case fault
}

public enum BodyEncoding: String, Codable, Sendable {
    case utf8
    case base64
}

public struct CapturedBody: Codable, Sendable, Equatable {
    public let value: String
    public let encoding: BodyEncoding
    public let isTruncated: Bool

    public init(value: String, encoding: BodyEncoding = .utf8, isTruncated: Bool = false) {
        self.value = value
        self.encoding = encoding
        self.isTruncated = isTruncated
    }

    public static func from(data: Data?, maxBytes: Int) -> CapturedBody? {
        guard let data, !data.isEmpty else { return nil }
        let limit = max(0, maxBytes)
        let truncated = data.count > limit
        let prefix = truncated ? data.prefix(limit) : data
        if let string = String(data: prefix, encoding: .utf8) {
            return CapturedBody(value: string, encoding: .utf8, isTruncated: truncated)
        }
        return CapturedBody(value: Data(prefix).base64EncodedString(), encoding: .base64, isTruncated: truncated)
    }
}

public struct NetworkEvent: Codable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let url: String
    public let method: String
    public let requestHeaders: [String: String]
    public let requestBody: CapturedBody?
    public let responseStatusCode: Int?
    public let responseHeaders: [String: String]
    public let responseBody: CapturedBody?
    public let durationMilliseconds: Double?
    public let errorDescription: String?
    public let requestBytes: Int?
    public let responseBytes: Int?
    public let isTelemetryRequest: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        url: String,
        method: String,
        requestHeaders: [String: String] = [:],
        requestBody: CapturedBody? = nil,
        responseStatusCode: Int? = nil,
        responseHeaders: [String: String] = [:],
        responseBody: CapturedBody? = nil,
        durationMilliseconds: Double? = nil,
        errorDescription: String? = nil,
        requestBytes: Int? = nil,
        responseBytes: Int? = nil,
        isTelemetryRequest: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.url = url
        self.method = method
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.responseStatusCode = responseStatusCode
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.durationMilliseconds = durationMilliseconds
        self.errorDescription = errorDescription
        self.requestBytes = requestBytes
        self.responseBytes = responseBytes
        self.isTelemetryRequest = isTelemetryRequest
    }
}

/// A group of network calls that share the same HTTP method and normalized URL.
public struct DuplicateNetworkCall: Sendable, Equatable, Identifiable {
    public let key: String
    public let method: String
    public let url: String
    public let calls: [NetworkEvent]

    public var id: String { key }

    public init(key: String, method: String, url: String, calls: [NetworkEvent]) {
        self.key = key
        self.method = method
        self.url = url
        self.calls = calls
    }
}

public extension NetworkEvent {
    /// Stable comparison key used to detect repeated calls. Query items are sorted,
    /// while their names and values remain part of the comparison.
    var duplicateComparisonKey: String {
        "\(method.uppercased()) \(normalizedURLForComparison)"
    }

    static func duplicateGroups(in events: [NetworkEvent]) -> [DuplicateNetworkCall] {
        Dictionary(grouping: events, by: \.duplicateComparisonKey)
            .compactMap { key, calls -> DuplicateNetworkCall? in
                guard calls.count > 1, let first = calls.first else { return nil }
                return DuplicateNetworkCall(
                    key: key,
                    method: first.method.uppercased(),
                    url: first.normalizedURLForComparison,
                    calls: calls.sorted { $0.timestamp < $1.timestamp }
                )
            }
            .sorted { lhs, rhs in
                let lhsLatest = lhs.calls.last?.timestamp ?? .distantPast
                let rhsLatest = rhs.calls.last?.timestamp ?? .distantPast
                return lhsLatest > rhsLatest
            }
    }

    private var normalizedURLForComparison: String {
        guard var components = URLComponents(string: url) else { return url }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        if let queryItems = components.queryItems {
            components.queryItems = queryItems.sorted {
                if $0.name == $1.name { return ($0.value ?? "") < ($1.value ?? "") }
                return $0.name < $1.name
            }
        }
        return components.string ?? url
    }
}

public struct ConsoleLogEvent: Codable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let category: String
    public let message: String
    public let metadata: [String: String]
    public let thread: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel,
        category: String = "default",
        message: String,
        metadata: [String: String] = [:],
        thread: String = "unknown"
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.metadata = metadata
        self.thread = thread
    }
}

public enum NetInspectEvent: Codable, Sendable, Equatable {
    case network(NetworkEvent)
    case console(ConsoleLogEvent)

    private enum CodingKeys: String, CodingKey { case type, network, console }
    private enum EventType: String, Codable { case network, console }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .network(let event):
            try container.encode(EventType.network, forKey: .type)
            try container.encode(event, forKey: .network)
        case .console(let event):
            try container.encode(EventType.console, forKey: .type)
            try container.encode(event, forKey: .console)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(EventType.self, forKey: .type) {
        case .network: self = .network(try container.decode(NetworkEvent.self, forKey: .network))
        case .console: self = .console(try container.decode(ConsoleLogEvent.self, forKey: .console))
        }
    }

    public var timestamp: Date {
        switch self {
        case .network(let event): return event.timestamp
        case .console(let event): return event.timestamp
        }
    }
}

public struct ExportEnvelope: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let device: [String: String]
    public let session: [String: String]
    public let events: [NetInspectEvent]

    public init(
        schemaVersion: Int = 1,
        device: [String: String] = [:],
        session: [String: String] = [:],
        events: [NetInspectEvent]
    ) {
        self.schemaVersion = schemaVersion
        self.device = device
        self.session = session
        self.events = events
    }
}
