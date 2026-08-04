import Foundation

public final class NetInspect: @unchecked Sendable {
    private static let lock = NSLock()
    private static var recorder: Recorder?

    public static func start(configuration: NetInspectConfiguration = .init()) {
        lock.lock()
        recorder?.stop()
        recorder = Recorder(configuration: configuration)
        recorder?.start()
        lock.unlock()
    }

    public static func stop() {
        lock.lock(); defer { lock.unlock() }
        recorder?.stop()
        recorder = nil
    }

    public static func record(_ event: NetInspectEvent) {
        currentRecorder()?.record(event)
    }

    public static func log(
        level: LogLevel,
        category: String = "default",
        message: String,
        metadata: [String: String] = [:]
    ) {
        currentRecorder()?.log(level: level, category: category, message: message, metadata: metadata)
    }

    public static func exportJSON() throws -> Data {
        let events = currentRecorder()?.events() ?? []
        let envelope = ExportEnvelope(events: events)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    public static func clear() {
        currentRecorder()?.clear()
    }

    public static func flush() async {
        await currentRecorder()?.flush()
    }

    public static func currentCaptureConfiguration() -> CaptureConfiguration {
        currentRecorder()?.captureConfiguration ?? CaptureConfiguration()
    }

    public static func currentRedactionConfiguration() -> RedactionConfiguration {
        currentRecorder()?.redactionConfiguration ?? RedactionConfiguration()
    }

    public static func isRunning() -> Bool {
        currentRecorder() != nil
    }

    private static func currentRecorder() -> Recorder? {
        lock.lock(); defer { lock.unlock() }
        return recorder
    }
}

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private let configuration: NetInspectConfiguration
    private let buffer: RingBuffer
    private var pending: [NetInspectEvent] = []
    private var flushTask: Task<Void, Never>?
    private var stopped = false

    init(configuration: NetInspectConfiguration) {
        self.configuration = configuration
        self.buffer = RingBuffer(configuration: configuration.storage)
    }

    var captureConfiguration: CaptureConfiguration { configuration.capture }
    var redactionConfiguration: RedactionConfiguration { configuration.redaction }

    func start() {
        guard configuration.transport != nil else { return }
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.configuration.batchInterval ?? 10
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self?.flush()
            }
        }
    }

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
        flushTask?.cancel()
        flushTask = nil
    }

    func record(_ event: NetInspectEvent) {
        guard !stopped else { return }
        let sanitized = sanitize(event)
        buffer.append(sanitized)
        lock.lock()
        pending.append(sanitized)
        let shouldFlush = pending.count >= configuration.batchSize
        lock.unlock()
        if shouldFlush {
            Task { await self.flush() }
        }
    }

    func log(level: LogLevel, category: String, message: String, metadata: [String: String]) {
        let logger = configuration.logger ?? DefaultNetInspectLogger()
        logger.log(level: level, category: category, message: message, metadata: metadata)
        record(.console(ConsoleLogEvent(level: level, category: category, message: message, metadata: metadata, thread: Thread.isMainThread ? "main" : "background")))
    }

    func events() -> [NetInspectEvent] { buffer.snapshot() }

    func clear() {
        buffer.removeAll()
        lock.lock()
        pending.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func flush() async {
        guard let transport = configuration.transport else { return }
        guard let batch = takePending(), !batch.isEmpty else { return }
        do {
            try await transport.send(batch)
        } catch {
            requeue(batch)
            configuration.logger?.log(level: .error, category: configuration.loggerCategory, message: "Telemetry flush failed: \(error)", metadata: [:])
        }
    }

    private func takePending() -> [NetInspectEvent]? {
        lock.lock(); defer { lock.unlock() }
        guard !pending.isEmpty else { return nil }
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        return batch
    }

    private func requeue(_ events: [NetInspectEvent]) {
        lock.lock()
        pending.insert(contentsOf: events, at: 0)
        lock.unlock()
    }

    private func sanitize(_ event: NetInspectEvent) -> NetInspectEvent {
        switch event {
        case .console(let log):
            let metadata = log.metadata.reduce(into: [String: String]()) { result, item in
                result[item.key] = configuration.redaction.jsonKeys.contains(item.key.lowercased()) ? configuration.redaction.replacement : item.value
            }
            return .console(ConsoleLogEvent(id: log.id, timestamp: log.timestamp, level: log.level, category: log.category, message: log.message, metadata: metadata, thread: log.thread))
        case .network(let network):
            let requestHeaders = configuration.capture.captureRequestHeaders ? Redactor.headers(network.requestHeaders, configuration: configuration.redaction) : [:]
            let responseHeaders = configuration.capture.captureResponseHeaders ? Redactor.headers(network.responseHeaders, configuration: configuration.redaction) : [:]
            return .network(NetworkEvent(
                id: network.id,
                timestamp: network.timestamp,
                url: Redactor.url(URL(string: network.url), configuration: configuration.redaction) ?? network.url,
                method: network.method,
                requestHeaders: requestHeaders,
                requestBody: configuration.capture.captureBodies ? Redactor.body(network.requestBody, configuration: configuration.redaction) : nil,
                responseStatusCode: network.responseStatusCode,
                responseHeaders: responseHeaders,
                responseBody: configuration.capture.captureBodies ? Redactor.body(network.responseBody, configuration: configuration.redaction) : nil,
                durationMilliseconds: network.durationMilliseconds,
                errorDescription: network.errorDescription,
                requestBytes: network.requestBytes,
                responseBytes: network.responseBytes,
                isTelemetryRequest: network.isTelemetryRequest
            ))
        }
    }
}
