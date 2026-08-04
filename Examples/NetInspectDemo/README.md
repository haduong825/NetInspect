# NetInspectDemo

Open `NetInspectDemo.xcodeproj` in Xcode and select an iOS 15+ Simulator or device. The project references the local NetInspect package and depends on Alamofire directly for its demo-only integration.

At app startup, configure:

```swift
NetInspect.start(configuration: NetInspectConfiguration(redaction: .commonSecrets))
```

`DemoApp` starts monitoring with common secret redaction. `ContentView` includes `NetInspectShakeInstaller`, so shaking a physical device presents the monitor. Use the `Monitor` button to open the same UI in Simulator.

The Service Playground calls three public internet services through both supported clients:

- JSONPlaceholder: `GET /posts/1` through `NetInspectURLSession.makeSession()`
- REST Countries: `GET /v3.1/name/vietnam` through `NetInspectURLSession.makeSession()`
- httpbin: `POST /anything/netinspect-demo` with a JSON body through `NetInspectAlamofire.makeSession()`

Each card identifies its network client, shows a small parsed result, and adds the captured request/response to the same event list. `Run all` triggers all three services at once.

If Xcode shows undefined symbols for `NetInspectShakeInstaller`, choose the `NetInspectDemo` scheme and clean the build folder. Do not run the package-only `NetInspectUI` scheme.

On Apple Silicon, use an arm64 Simulator. The project excludes x86_64 Simulator builds to keep the app and local package modules on the same architecture.
