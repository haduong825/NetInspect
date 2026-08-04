# Telemetry

Telemetry is opt-in. Without a transport, events remain in the bounded in-memory buffer.

## Built-in HTTP transport

```swift
import Foundation
import NetInspectCore
import NetInspectTransport

let transport = HTTPTransport(configuration: HTTPTransportConfiguration(
    endpoint: URL(string: "https://collector.example/events")!,
    headers: ["Authorization": "Bearer <token>"],
    timeout: 15
))

NetInspect.start(configuration: NetInspectConfiguration(
    redaction: .commonSecrets,
    transport: transport,
    batchSize: 25,
    batchInterval: 10
))
```

`HTTPTransport` posts an encoded `ExportEnvelope` as JSON. It retries network failures, HTTP 408, HTTP 429, and HTTP 5xx responses up to three times with exponential backoff. Its own session is excluded from capture to avoid recursive telemetry events.

## Custom transport

```swift
struct AppTransport: NetInspectTransport {
    func send(_ events: [NetInspectEvent]) async throws {
        // Store or forward the already-sanitized batch.
    }
}
```

Force delivery of the pending batch with:

```swift
await NetInspect.flush()
```

Failed batches are re-queued for a later flush. The receiving service remains responsible for authentication, authorization, validation, rate limiting, retention, and deletion.

