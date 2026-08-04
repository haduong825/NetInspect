# NetInspect

Native HTTP inspection and structured logging for Swift applications.

NetInspect is a Swift Package for capturing requests made by explicitly configured `URLSession` instances, viewing sanitized events in an in-app monitor, and optionally exporting them to a telemetry backend. It uses public Apple APIs only—there is no method swizzling or global interception.

> NetInspect can capture sensitive application data. Review the [privacy and security guide](docs/privacy-and-security.md) before enabling it outside development builds.

## Features

- HTTP/HTTPS request and response inspection through `URLProtocol`
- Bounded in-memory storage by event count and byte size
- Header, URL query, and recursive JSON redaction
- SwiftUI/UIKit monitor with search, filters, copy, JSON formatting, and cURL export
- Structured application logs and an explicit `print` bridge
- JSON export and optional batched telemetry
- Core products have no third-party runtime dependencies; Alamofire support is isolated in an optional product

## Requirements

- Swift 5.9+
- Xcode 15+
- iOS 15+
- macOS 12+ for the core, URLSession, and transport modules

`NetInspectUI` uses UIKit and SwiftUI and is intended for iOS applications.

## Installation

In Xcode, select **File > Add Package Dependencies…** and enter:

```text
https://github.com/haduong825/NetInspect.git
```

Or add the repository to `Package.swift`:

```swift
dependencies: [
    .package(
        url: "https://github.com/haduong825/NetInspect.git",
        from: "0.1.1"
    )
]
```

Then add only the products your target uses:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "NetInspectCore", package: "NetInspect"),
        .product(name: "NetInspectURLSession", package: "NetInspect"),
        .product(name: "NetInspectAlamofire", package: "NetInspect"),
        .product(name: "NetInspectUI", package: "NetInspect")
    ]
)
```

This uses Swift Package Manager's semantic-version requirement, so package updates can be resolved from release tags instead of commit IDs.

## Quick start

Start the recorder once during application launch:

```swift
import NetInspectCore
import SwiftUI

@main
struct MyApp: App {
    init() {
        #if DEBUG
        NetInspect.start(configuration: .init(redaction: .commonSecrets))
        #endif
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

Create requests with a NetInspect-enabled session:

```swift
import Foundation
import NetInspectURLSession

let session = NetInspectURLSession.makeSession()
let url = URL(string: "https://example.com")!
let (data, response) = try await session.data(from: url)
```

Present the monitor from SwiftUI:

```swift
import NetInspectUI

Button("Open Network Inspector") {
    NetInspectUI.present()
}
```

`URLSession.shared` is not intercepted. Requests must use `NetInspectURLSession.makeSession()` or a configuration returned by `NetInspectURLSession.configuration(basedOn:)`.

### Alamofire

Add the `NetInspectAlamofire` product and create the app's Alamofire session through the factory:

```swift
import Alamofire
import NetInspectAlamofire

let session = NetInspectAlamofire.makeSession()

session.request("https://example.com")
    .validate()
    .responseDecodable(of: ExampleResponse.self) { response in
        // Handle the response as usual.
    }
```

Pass existing Alamofire customization directly to the factory:

```swift
let session = NetInspectAlamofire.makeSession(
    configuration: appURLSessionConfiguration,
    interceptor: authenticationInterceptor,
    serverTrustManager: trustManager,
    eventMonitors: eventMonitors
)
```

Use this session instead of the global `AF` APIs. `AF` uses Alamofire's already-created shared session, so NetInspect cannot instrument it retroactively.

The optional adapter currently supports Alamofire 5.10.x, matching NetInspect's Swift 5.9 toolchain requirement.

## Products

| Product | Use it for |
| --- | --- |
| `NetInspectCore` | Configuration, events, storage, redaction, logs, and JSON export |
| `NetInspectURLSession` | Capturing HTTP traffic from configured sessions |
| `NetInspectAlamofire` | Creating Alamofire sessions with capture enabled |
| `NetInspectUI` | The iOS SwiftUI/UIKit monitor and shake-to-present integration |
| `NetInspectTransport` | Sending sanitized event batches to an HTTP endpoint |

## Documentation

- [Documentation index](docs/README.md)
- [Getting started](docs/getting-started.md)
- [Configuration reference](docs/configuration.md)
- [Monitoring UI](docs/monitoring-ui.md)
- [Logging and export](docs/logging-and-export.md)
- [Telemetry](docs/telemetry.md)
- [Privacy and security](docs/privacy-and-security.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Architecture decisions](docs/architecture/README.md)

## Development

Run package tests from the repository root:

```bash
swift test
```

## Project status

NetInspect is currently pre-release. Public APIs may change before the first stable version. Issues and focused pull requests are welcome through GitHub.
