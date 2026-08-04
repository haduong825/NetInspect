import Foundation
import XCTest
@testable import NetInspectCore
@testable import NetInspectURLSession
@testable import NetInspectTransport

final class CoreTests: XCTestCase {
    override func tearDown() {
        NetInspect.stop()
        super.tearDown()
    }

    func testExportContainsRedactedNetworkEvent() throws {
        NetInspect.start(configuration: NetInspectConfiguration(
            redaction: RedactionConfiguration(
                headerNames: ["Authorization"],
                jsonKeys: ["password"],
                urlQueryNames: ["token"]
            ),
            logger: NoopLogger()
        ))

        let event = NetworkEvent(
            url: "https://example.com/login?token=secret",
            method: "POST",
            requestHeaders: ["Authorization": "Bearer secret", "Content-Type": "application/json"],
            requestBody: CapturedBody(value: "{\"password\":\"secret\",\"name\":\"Ada\"}"),
            responseStatusCode: 200
        )
        NetInspect.record(.network(event))

        let data = try NetInspect.exportJSON()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(ExportEnvelope.self, from: data)
        guard case .network(let network) = envelope.events.first else {
            return XCTFail("Expected a network event")
        }
        XCTAssertEqual(network.requestHeaders["Authorization"], "[REDACTED]")
        XCTAssertEqual(network.url, "https://example.com/login?token=%5BREDACTED%5D")
        XCTAssertTrue(network.requestBody?.value.contains("[REDACTED]") == true)
    }

    func testRingBufferEvictsOldestEvents() throws {
        NetInspect.start(configuration: NetInspectConfiguration(
            storage: StorageConfiguration(maxEvents: 2, maxBytes: 100_000),
            logger: NoopLogger()
        ))

        for index in 0..<3 {
            NetInspect.record(.console(ConsoleLogEvent(level: .info, message: "event-\(index)")))
        }

        let data = try NetInspect.exportJSON()
        let envelope = try decodeEnvelope(data)
        XCTAssertEqual(envelope.events.count, 2)
        XCTAssertFalse(envelope.events.contains { event in
            if case .console(let log) = event { return log.message == "event-0" }
            return false
        })
    }

    func testLoggerCreatesConsoleEvent() throws {
        NetInspect.start(configuration: NetInspectConfiguration(logger: NoopLogger()))
        NetInspect.log(level: .warning, category: "test", message: "warning", metadata: ["code": "42"])

        let envelope = try decodeEnvelope(try NetInspect.exportJSON())
        guard case .console(let log) = envelope.events.first else {
            return XCTFail("Expected a console event")
        }
        XCTAssertEqual(log.level, .warning)
        XCTAssertEqual(log.metadata["code"], "42")
    }

    func testClearRemovesStoredAndPendingEvents() throws {
        NetInspect.start(configuration: NetInspectConfiguration(logger: NoopLogger()))
        NetInspect.record(.console(ConsoleLogEvent(level: .info, message: "to clear")))
        NetInspect.clear()

        let envelope = try decodeEnvelope(try NetInspect.exportJSON())
        XCTAssertTrue(envelope.events.isEmpty)
    }

    func testURLSessionConfigurationInstallsProtocol() {
        let configuration = NetInspectURLSession.configuration(basedOn: .ephemeral)
        XCTAssertTrue(configuration.protocolClasses?.contains { $0 == NetInspectURLProtocol.self } == true)
        XCTAssertTrue(NetInspectURLProtocol.canInit(with: URLRequest(url: URL(string: "https://example.com")!)))
    }

    func testHTTPTransportSendsJSON() async throws {
        StubURLProtocol.statusCode = 204
        StubURLProtocol.receivedBody = nil
        URLProtocol.registerClass(StubURLProtocol.self)
        defer { URLProtocol.unregisterClass(StubURLProtocol.self) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let transport = HTTPTransport(
            configuration: HTTPTransportConfiguration(endpoint: URL(string: "https://collector.invalid/events")!),
            session: session
        )

        try await transport.send([.console(ConsoleLogEvent(level: .info, message: "hello"))])
        XCTAssertNotNil(StubURLProtocol.receivedBody)
        XCTAssertTrue(String(data: StubURLProtocol.receivedBody ?? Data(), encoding: .utf8)?.contains("hello") == true)
    }

    private func decodeEnvelope(_ data: Data) throws -> ExportEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ExportEnvelope.self, from: data)
    }
}

private struct NoopLogger: NetInspectLogger {
    func log(level: LogLevel, category: String, message: String, metadata: [String: String]) {}
}

private final class StubURLProtocol: URLProtocol {
    static var statusCode = 200
    static var receivedBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let body = request.httpBody {
            Self.receivedBody = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            var output = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4_096)
            defer { buffer.deallocate(); stream.close() }
            while stream.hasBytesAvailable {
                let count = stream.read(buffer, maxLength: 4_096)
                if count <= 0 { break }
                output.append(buffer, count: count)
            }
            Self.receivedBody = output
        } else {
            Self.receivedBody = Data()
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
