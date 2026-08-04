# Getting started

## 1. Add the package

In Xcode, choose **File > Add Package Dependencies…** and enter:

```text
https://github.com/haduong825/NetInspect.git
```

For a manifest-based project:

```swift
dependencies: [
    .package(
        url: "https://github.com/haduong825/NetInspect.git",
        from: "0.1.0"
    )
]
```

Add `NetInspectCore` and `NetInspectURLSession` to capture traffic. Add `NetInspectUI` for the iOS monitor and `NetInspectTransport` only when sending telemetry.

## 2. Start NetInspect

Start it once during app launch, before creating captured requests:

```swift
import NetInspectCore

NetInspect.start(configuration: NetInspectConfiguration(
    storage: StorageConfiguration(maxEvents: 500, maxBytes: 10 * 1_024 * 1_024),
    redaction: .commonSecrets
))
```

Calling `start` again replaces the recorder and clears its previous in-memory state.

## 3. Capture requests

```swift
import Foundation
import NetInspectURLSession

let session = NetInspectURLSession.makeSession()
let request = URLRequest(url: URL(string: "https://example.com/api/profile")!)
let (data, response) = try await session.data(for: request)
```

If the application already has a custom configuration, preserve it and add the protocol:

```swift
let base = URLSessionConfiguration.default
base.timeoutIntervalForRequest = 30
base.waitsForConnectivity = true

let session = URLSession(
    configuration: NetInspectURLSession.configuration(basedOn: base)
)
```

NetInspect captures requests only from enabled sessions. It does not modify `URLSession.shared`, existing sessions, or unrelated networking libraries.

## Alamofire

Add the `NetInspectAlamofire` product to the application target, then create the Alamofire session once and inject it into networking services:

```swift
import Alamofire
import NetInspectAlamofire

let session = NetInspectAlamofire.makeSession(
    configuration: .default,
    interceptor: authenticationInterceptor
)

session.request("https://example.com/profile").response { response in
    // Handle the response normally.
}
```

The factory accepts Alamofire's interceptor, trust manager, redirect handler, cache handler, queues, and event monitors. Requests made through the global `AF` shortcut are not captured.

## 4. Open the monitor

```swift
import NetInspectUI
import SwiftUI

Button("Monitor") {
    NetInspectUI.present()
}
```

Or install shake-to-present on the root view:

```swift
ContentView()
    .background(NetInspectShakeInstaller())
```

Continue with [configuration](configuration.md) and review [privacy and security](privacy-and-security.md) before enabling capture outside a local development build.
