import SwiftUI
import NetInspectCore

@main
struct NetInspectDemoApp: App {
    init() {
        NetInspect.start(configuration: NetInspectConfiguration(
            storage: StorageConfiguration(maxEvents: 500, maxBytes: 10 * 1_024 * 1_024),
            redaction: .commonSecrets,
            enablePrintBridge: true
        ))
        NetInspect.log(level: .info, category: "demo", message: "NetInspect demo started")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
