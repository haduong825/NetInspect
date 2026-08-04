# Configuration reference

`NetInspectConfiguration` combines capture, storage, sanitization, logging, and optional transport settings.

```swift
let configuration = NetInspectConfiguration(
    capture: CaptureConfiguration(
        captureBodies: true,
        maxBodyBytes: 512 * 1_024,
        captureRequestHeaders: true,
        captureResponseHeaders: true
    ),
    storage: StorageConfiguration(
        maxEvents: 300,
        maxBytes: 5 * 1_024 * 1_024
    ),
    redaction: .commonSecrets,
    batchSize: 25,
    batchInterval: 10,
    enablePrintBridge: false
)

NetInspect.start(configuration: configuration)
```

## CaptureConfiguration

| Setting | Meaning |
| --- | --- |
| `captureBodies` | Captures request and response bodies when available |
| `maxBodyBytes` | Maximum bytes retained for each body; larger bodies are truncated |
| `captureRequestHeaders` | Includes request headers |
| `captureResponseHeaders` | Includes response headers |

Streaming upload bodies may not be available through `URLRequest.httpBody` and therefore may not be captured. Binary bodies are stored as Base64.

## StorageConfiguration

The in-memory ring buffer evicts the oldest events when `maxEvents` or `maxBytes` is reached. Both values have a minimum effective limit of 1. The package does not persist the buffer to disk by itself.

## RedactionConfiguration

The built-in `.commonSecrets` preset redacts common credential headers and JSON keys. Add application-specific fields explicitly:

```swift
let redaction = RedactionConfiguration(
    headerNames: ["Authorization", "Cookie", "X-Client-Secret"],
    jsonKeys: ["password", "access_token", "credit_card"],
    urlQueryNames: ["token", "api_key", "signature"],
    replacement: "[REDACTED]"
)
```

Names are matched case-insensitively. JSON redaction handles nested dictionaries and arrays when the body is valid UTF-8 JSON. See [privacy and security](privacy-and-security.md) for limitations.

## Lifecycle

```swift
let running = NetInspect.isRunning()
let capture = NetInspect.currentCaptureConfiguration()
let redaction = NetInspect.currentRedactionConfiguration()

NetInspect.clear() // Clears buffered events and the pending telemetry batch.
NetInspect.stop()  // Stops recording and cancels periodic telemetry work.
```

