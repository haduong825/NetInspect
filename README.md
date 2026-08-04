# NetInspect

NetInspect is a native Swift Package Manager SDK for inspecting HTTP/HTTPS traffic and application logs in iOS apps. It is designed for development builds, QA environments, and controlled telemetry sessions.

The SDK provides:

- URL loading instrumentation through a dedicated URLProtocol.
- An in-memory event buffer with event-count and byte-size limits.
- Header, query-string, and JSON-body redaction.
- JSON export for debugging or telemetry.
- A SwiftUI/UIKit monitoring screen with search, filters, copy actions, JSON formatting, cURL export, and collapsible event sections.
- Optional batched telemetry through a transport protocol or the built-in HTTPTransport.
- A logger bridge for structured logs and legacy print output.

## Requirements

- iOS 15 or newer.
- macOS 12 or newer for package-side development and tests.
- Xcode with Swift Package Manager support.
- Network requests made through NetInspectURLSession when they need to be captured.

## Modules

| Module | Purpose |
| --- | --- |
| NetInspectCore | Events, configuration, redaction, storage, logging, JSON export, and lifecycle. |
| NetInspectURLSession | Captures HTTP/HTTPS requests and responses through URLProtocol. |
| NetInspectTransport | Built-in HTTP batch transport and transport configuration. |
| NetInspectUI | Ready-made monitoring screen and shake-to-present integration. |

## Installation

### Add the package in Xcode

1. Open the app project in Xcode.
2. Select **File > Add Package Dependencies…**.
3. Add the package URL, or choose the local NetInspect package directory.
4. Add the products required by the app target:
   - NetInspectCore
   - NetInspectURLSession
   - NetInspectUI if the monitoring screen is needed.
   - NetInspectTransport if telemetry is needed.

### Add as a local Swift package dependency

For a package-based app or test target:

```
dependencies: [
    .package(path: "../NetInspect")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            "NetInspectCore",
            "NetInspectURLSession",
            "NetInspectUI",
            "NetInspectTransport"
        ]
    )
]
```

## Quick start

Start NetInspect once during application startup. A SwiftUI app can initialize it in its App type:

```
import SwiftUI
import NetInspectCore

@main
struct MyApp: App {
    init() {
        NetInspect.start(configuration: NetInspectConfiguration(
            storage: StorageConfiguration(
                maxEvents: 500,
                maxBytes: 10 * 1_024 * 1_024
            ),
            redaction: .commonSecrets,
            enablePrintBridge: true
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

NetInspect.start replaces any existing recorder. Starting it again is safe, but it resets the previous recorder and its buffer.

### Make a captured request

```
import Foundation
import NetInspectURLSession

let session = NetInspectURLSession.makeSession()
let url = URL(string: "https://example.com")!

session.dataTask(with: url) { data, response, error in
    // The request and response are recorded when the task completes.
}.resume()
```

For an async/await request:

```
import Foundation
import NetInspectURLSession

let session = NetInspectURLSession.makeSession()
let request = URLRequest(url: URL(string: "https://example.com")!)
let (data, response) = try await session.data(for: request)
```

URLSession.shared and sessions created with a normal URLSessionConfiguration are not automatically intercepted. Use NetInspectURLSession.makeSession for application traffic that should appear in NetInspect.

## Capturing URLSession traffic

### Custom URLSession configuration

Use configuration(basedOn:) when the app already has a custom configuration:

```
import Foundation
import NetInspectURLSession

let configuration = URLSessionConfiguration.default
configuration.timeoutIntervalForRequest = 30
configuration.waitsForConnectivity = true

let session = URLSession(
    configuration: NetInspectURLSession.configuration(basedOn: configuration)
)
```

Or let the SDK create the session:

```
let session = NetInspectURLSession.makeSession(
    configuration: configuration
)
```

### What is captured

For each HTTP/HTTPS request, NetInspect records:

- Timestamp, URL, HTTP method, and duration.
- Request and response headers, when enabled.
- Request and response bodies, when enabled and available.
- HTTP response status code.
- Error description, if the request fails.
- Request and response byte counts.

The protocol captures request data from URLRequest.httpBody. Streaming upload bodies are not available through that property and may not be captured.

## Configuration

NetInspectConfiguration combines capture, storage, redaction, logging, and telemetry settings:

```
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

### Capture settings

```
CaptureConfiguration(
    captureBodies: true,
    maxBodyBytes: 1_048_576,
    captureRequestHeaders: true,
    captureResponseHeaders: true
)
```

- captureBodies: enables request and response body capture.
- maxBodyBytes: maximum number of bytes stored per captured body. Larger bodies are truncated.
- captureRequestHeaders: enables request header capture.
- captureResponseHeaders: enables response header capture.

### Storage settings

```
StorageConfiguration(
    maxEvents: 500,
    maxBytes: 10 * 1_024 * 1_024
)
```

The buffer evicts older events when either limit is reached. The minimum effective value for both limits is 1.

## Redaction and privacy

Redaction happens before events enter the in-memory buffer or telemetry queue.

The built-in .commonSecrets configuration redacts:

- Headers: Authorization, Cookie, Set-Cookie, and X-Api-Key.
- JSON keys: password, passwd, token, access_token, refresh_token, secret, and api_key.

It also supports query-string redaction:

```
let redaction = RedactionConfiguration(
    headerNames: [
        "Authorization",
        "Cookie",
        "X-Client-Secret"
    ],
    jsonKeys: [
        "password",
        "access_token",
        "credit_card"
    ],
    urlQueryNames: [
        "token",
        "api_key",
        "signature"
    ],
    replacement: "[REDACTED]"
)

NetInspect.start(configuration: NetInspectConfiguration(
    redaction: redaction
))
```

Header names, JSON keys, and query names are matched case-insensitively. JSON redaction applies to valid UTF-8 JSON bodies and recursively handles nested dictionaries and arrays.

For production builds, consider disabling payload capture unless it is explicitly required:

```
let productionCapture = CaptureConfiguration(
    captureBodies: false,
    captureRequestHeaders: false,
    captureResponseHeaders: false
)
```

Redaction is a safety layer, not a replacement for access control. Do not log secrets intentionally, and review the fields your app sends before enabling telemetry.

## Monitoring UI

### SwiftUI integration

Add the installer to the root view:

```
import SwiftUI
import NetInspectUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(NetInspectShakeInstaller())
        }
    }
}
```

On a physical device, shake the device to present the monitor. In Simulator or during debugging, expose a button:

```
import NetInspectUI

Button("Monitor") {
    NetInspectUI.present()
}
```

### UIKit integration

Install the shake observer after the root view controller has been attached to the window:

```
import NetInspectUI

NetInspectUI.installShakeToPresent(in: window)
```

You can customize the title and modal presentation style:

```
let configuration = NetInspectUIConfiguration(
    title: "Network Inspector",
    presentationStyle: .pageSheet
)

NetInspectUI.installShakeToPresent(
    in: window,
    configuration: configuration
)
```

To create the monitor view controller yourself:

```
let controller = NetInspectUI.makeViewController(
    configuration: configuration
)
present(controller, animated: true)
```

### Monitor features

The built-in monitor provides:

- Search across URLs, methods, messages, headers, bodies, and metadata.
- All/Network/Console event tabs.
- Status filters for success, 4xx, 5xx, and failed requests.
- Console log-level filters.
- Newest-first and oldest-first sorting.
- Live event, request, and issue totals.
- Clear-buffer action with confirmation.
- Independently collapsible error, header, body, metadata, and raw JSON sections.
- JSON pretty-printing for valid request and response bodies.
- Icon-only copy buttons with VoiceOver labels.
- Copy of the full redacted event buffer.
- Copy of individual URLs, headers, bodies, messages, metadata, and raw event JSON.
- cURL export for network events based on the captured method, URL, headers, and request body.

The copied content comes from the sanitized event stored by NetInspect. If capture is disabled or a body was truncated, the copied result reflects those settings.

## Logging

### Structured logs

```
import NetInspectCore

NetInspect.log(
    level: .warning,
    category: "checkout",
    message: "Payment retrying",
    metadata: [
        "orderID": "123",
        "attempt": "2"
    ]
)
```

Available log levels are:

```
.trace
.debug
.info
.warning
.error
.fault
```

Log metadata is subject to the configured JSON-key redaction rules.

### Capture legacy print output

Enable the bridge at startup:

```
NetInspect.start(configuration: NetInspectConfiguration(
    enablePrintBridge: true
))
```

Or route selected output through the SDK explicitly:

```
import NetInspectCore

var stream = NetInspectPrintStream(
    level: .info,
    category: "legacy"
)

print("Captured through NetInspect", to: &stream)
```

The SDK sends logs to Logger/os_log and the process console. It cannot safely read every os_log message emitted by unrelated libraries; those libraries need to use the logger bridge if their messages must appear as captured console events.

### Custom logger

Provide a logger that conforms to NetInspectLogger:

```
import NetInspectCore

struct AppLogger: NetInspectLogger {
    func log(
        level: LogLevel,
        category: String,
        message: String,
        metadata: [String: String]
    ) {
        // Forward to the app's logging system.
    }
}

NetInspect.start(configuration: NetInspectConfiguration(
    logger: AppLogger(),
    loggerCategory: "MyApp"
))
```

## Export and lifecycle

### Export the current buffer

exportJSON() returns a pretty-printed, ISO-8601 encoded JSON document:

```
let data = try NetInspect.exportJSON()
let json = String(decoding: data, as: UTF8.self)
print(json)
```

The exported envelope contains the schema version, device/session metadata, and captured events.

### Clear, stop, and inspect state

```
NetInspect.clear()

let running = NetInspect.isRunning()
let capture = NetInspect.currentCaptureConfiguration()
let redaction = NetInspect.currentRedactionConfiguration()

NetInspect.stop()
```

clear removes the current in-memory buffer and pending telemetry batch. stop stops the recorder and cancels the periodic telemetry task.

### Flush telemetry

When the app needs to force a pending telemetry batch to be sent:

```
await NetInspect.flush()
```

If the transport fails, the batch is re-queued and can be retried by a later flush.

## Telemetry

Telemetry is optional. Configure a NetInspectTransport implementation if events need to leave the device.

### Built-in HTTP transport

```
import Foundation
import NetInspectCore
import NetInspectTransport

let transport = HTTPTransport(
    configuration: HTTPTransportConfiguration(
        endpoint: URL(string: "https://collector.example/events")!,
        headers: [
            "Authorization": "Bearer <token>",
            "X-App-Version": "1.0"
        ],
        timeout: 15
    )
)

NetInspect.start(configuration: NetInspectConfiguration(
    redaction: .commonSecrets,
    transport: transport,
    batchSize: 25,
    batchInterval: 10
))
```

HTTPTransport:

- Sends batches as POST requests with Content-Type: application/json.
- Encodes an ExportEnvelope using ISO-8601 dates.
- Retries network failures, HTTP 408, HTTP 429, and HTTP 5xx responses up to three times with exponential backoff.
- Uses its own URLSession, so telemetry requests are not captured again by NetInspectURLProtocol.

The transport endpoint should authenticate and validate incoming data. Do not use a debug collector as a production data store without access control and retention policies.

### Custom transport

Implement NetInspectTransport for another destination:

```
import NetInspectCore

struct FileTransport: NetInspectTransport {
    func send(_ events: [NetInspectEvent]) async throws {
        // Persist or forward the sanitized events.
    }
}

NetInspect.start(configuration: NetInspectConfiguration(
    transport: FileTransport()
))
```

Events passed to the transport have already gone through the configured redaction and capture rules.

## Demo app

The repository includes Examples/NetInspectDemo.

1. Open Examples/NetInspectDemo/NetInspectDemo.xcodeproj in Xcode.
2. Select the NetInspectDemo scheme.
3. Choose an iOS 15+ Simulator or physical device.
4. Build and run.
5. Tap **Monitor** in Simulator, or shake a physical device.

The demo contains a Service Playground that sends captured requests to public endpoints:

- JSONPlaceholder: GET https://jsonplaceholder.typicode.com/posts/1
- REST Countries: GET https://restcountries.com/v3.1/name/vietnam?fields=name,capital,population
- httpbin: POST https://httpbin.org/anything/netinspect-demo

The playground displays a parsed result and appends each request to the NetInspect event stream. **Run all** sends all three requests.

For more demo-specific notes, see Examples/NetInspectDemo/README.md.

## Validation

Run the package tests from the repository root:

```
swift test
```

Build the iOS demo without code signing:

```
xcodebuild \
  -project Examples/NetInspectDemo/NetInspectDemo.xcodeproj \
  -scheme NetInspectDemo \
  -sdk iphonesimulator \
  -configuration Debug \
  -derivedDataPath /tmp/NetInspectDemoDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The demo target should finish with:

```
** BUILD SUCCEEDED **
```

## Troubleshooting

### No request appears in the monitor

Confirm that the request uses NetInspectURLSession.makeSession() or a configuration returned by NetInspectURLSession.configuration(basedOn:). Existing URLSession.shared requests are not retroactively intercepted.

### Bodies or headers are missing

Check CaptureConfiguration:

```
CaptureConfiguration(
    captureBodies: true,
    captureRequestHeaders: true,
    captureResponseHeaders: true
)
```

Also check maxBodyBytes; large bodies are intentionally truncated.

### Data is redacted

This is expected when a header, query parameter, or JSON key matches RedactionConfiguration. Inspect the redaction configuration before disabling it. Redaction is applied before storage and export.

### NetInspectShakeInstaller or SwiftUI symbols are undefined

Make sure the app target links NetInspectUI and that Xcode is building the NetInspectDemo app scheme, not a package-only scheme. Then try:

1. **Product > Clean Build Folder**.
2. **File > Packages > Reset Package Caches**.
3. Resolve the package again.

### The monitor opens with the keyboard

The monitor explicitly resigns first responder when presented. If the host app presents another keyboard-driven control at the same time, dismiss that control before calling NetInspectUI.present().

## Production checklist

Before shipping an integration:

- Use a deliberate CaptureConfiguration; do not capture bodies by default unless required.
- Configure redaction for every credential, token, personal identifier, and sensitive query parameter used by the app.
- Keep telemetry disabled in builds that do not need it.
- Protect the telemetry endpoint with authentication and server-side authorization.
- Apply retention and deletion policies to captured data.
- Confirm that copied/exported data is appropriate for the user and environment.
- Call NetInspect.stop() when the integration is no longer needed.


