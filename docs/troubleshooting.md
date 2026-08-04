# Troubleshooting

## Requests do not appear

Confirm the request uses a session created by `NetInspectURLSession.makeSession()` or a configuration returned by `NetInspectURLSession.configuration(basedOn:)`. `URLSession.shared` and sessions created before configuration are not intercepted.

Also verify that `NetInspect.start()` runs before the request begins.

## Bodies or headers are missing

Check the corresponding `CaptureConfiguration` flags and `maxBodyBytes`. Streaming upload bodies may not be visible through `URLRequest.httpBody`; oversized bodies are truncated deliberately.

## Values appear as `[REDACTED]`

The field matched `RedactionConfiguration`. This happens before storage, so the original value cannot be restored in the monitor or export. Change redaction only after evaluating the privacy impact.

## UI symbols are unavailable

Ensure the application target links the `NetInspectUI` product and is building for iOS 15+. In Xcode, clean the build folder and resolve package dependencies again if product membership recently changed.

## Shake-to-present does not work

On UIKit, install the observer after the root controller is attached to a window. On Simulator, use an explicit button that calls `NetInspectUI.present()`.

## Telemetry is not delivered

Verify the endpoint, authentication headers, and server response. Retryable failures are attempted up to three times; a failed batch is re-queued. Call `await NetInspect.flush()` when you need an immediate delivery attempt.

## Package resolution fails

Confirm the deployment targets meet iOS 15/macOS 12 and the toolchain supports Swift tools version 5.9. NetInspect uses semantic versions; make sure the requested version (for example `0.1.1`) has a matching Git tag and that Xcode can access the repository.
