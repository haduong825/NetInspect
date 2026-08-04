import Foundation
import NetInspectCore

public struct HTTPTransportConfiguration: Sendable {
    public let endpoint: URL
    public var headers: [String: String]
    public var timeout: TimeInterval

    public init(endpoint: URL, headers: [String: String] = [:], timeout: TimeInterval = 15) {
        self.endpoint = endpoint
        self.headers = headers
        self.timeout = timeout
    }
}

public enum HTTPTransportError: Error, Equatable, LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Telemetry response was not an HTTP response."
        case .httpStatus(let status): return "Telemetry endpoint returned HTTP \(status)."
        }
    }
}

public final class HTTPTransport: NetInspectTransport, @unchecked Sendable {
    private let configuration: HTTPTransportConfiguration
    private let session: URLSession
    private let encoder: JSONEncoder
    private let maxRetries = 3

    public init(configuration: HTTPTransportConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    public func send(_ events: [NetInspectEvent]) async throws {
        guard !events.isEmpty else { return }
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        configuration.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = try encoder.encode(ExportEnvelope(events: events))

        var attempt = 0
        while true {
            do {
                let (_, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw HTTPTransportError.invalidResponse }
                guard (200..<300).contains(http.statusCode) else {
                    throw HTTPTransportError.httpStatus(http.statusCode)
                }
                return
            } catch {
                guard attempt < maxRetries, shouldRetry(error: error) else { throw error }
                attempt += 1
                let delay = min(pow(2.0, Double(attempt - 1)), 8.0)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    private func shouldRetry(error: Error) -> Bool {
        if let error = error as? HTTPTransportError {
            switch error {
            case .invalidResponse: return true
            case .httpStatus(let status): return status == 408 || status == 429 || (500..<600).contains(status)
            }
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
    }
}
