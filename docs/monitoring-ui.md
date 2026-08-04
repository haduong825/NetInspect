# Monitoring UI

`NetInspectUI` supplies an iOS monitor for SwiftUI and UIKit applications.

## SwiftUI

Install shake-to-present at the root of the view tree:

```swift
import NetInspectUI

ContentView()
    .background(NetInspectShakeInstaller())
```

For a visible development control:

```swift
Button("Monitor") {
    NetInspectUI.present()
}
```

## UIKit

Install the observer after the root view controller is attached to its window:

```swift
import NetInspectUI

let configuration = NetInspectUIConfiguration(
    title: "Network Inspector",
    presentationStyle: .pageSheet
)

NetInspectUI.installShakeToPresent(in: window, configuration: configuration)
```

To control presentation yourself:

```swift
let controller = NetInspectUI.makeViewController(configuration: configuration)
present(controller, animated: true)
```

## Included tools

- Network and console event tabs
- Full-text search and status/log-level filters
- Newest-first and oldest-first sorting
- Expandable headers, bodies, metadata, error, and raw JSON sections
- Pretty-printed JSON, copy actions, and cURL export
- Clear-buffer confirmation and live totals
- VoiceOver labels for icon-only controls

The monitor displays and copies the sanitized event stored by NetInspect. Disabled or truncated fields cannot be recovered by the UI.

