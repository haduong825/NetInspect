# Logging and export

## Structured logging

```swift
import NetInspectCore

NetInspect.log(
    level: .warning,
    category: "checkout",
    message: "Payment retrying",
    metadata: ["orderID": "123", "attempt": "2"]
)
```

Supported levels are `.trace`, `.debug`, `.info`, `.warning`, `.error`, and `.fault`. Metadata is processed by configured JSON-key redaction rules.

## Explicit print bridge

Set `enablePrintBridge` when starting NetInspect, or route selected output through a stream:

```swift
var stream = NetInspectPrintStream(level: .info, category: "legacy")
print("Captured by NetInspect", to: &stream)
```

NetInspect cannot read every `os_log` message emitted by the process. Code that must appear in the event stream should use `NetInspect.log`, `NetInspectLogger`, or `NetInspectPrintStream`.

## Custom logger

```swift
struct AppLogger: NetInspectLogger {
    func log(
        level: LogLevel,
        category: String,
        message: String,
        metadata: [String: String]
    ) {
        // Forward to the application's logging backend.
    }
}

NetInspect.start(configuration: .init(logger: AppLogger()))
```

## Export

```swift
let data = try NetInspect.exportJSON()
let json = String(decoding: data, as: UTF8.self)
```

The exported `ExportEnvelope` includes a schema version, device/session metadata, and the currently buffered sanitized events. Dates use ISO 8601 encoding.

