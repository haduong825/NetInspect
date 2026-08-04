# Privacy and security

Network inspection can expose credentials, personal data, payment details, and proprietary content. Treat captured events as sensitive data.

## Data flow

NetInspect applies capture limits and configured redaction before events enter the in-memory buffer or telemetry queue. The monitor, JSON export, and transports consume that sanitized representation.

Redaction is a safety layer, not an access-control boundary. It only protects fields that match the configured rules and formats the redactor understands.

## Important limitations

- Unknown or application-specific secret names are not automatically detected.
- JSON-key redaction requires a valid UTF-8 JSON body.
- Secrets embedded in unstructured text, binary payloads, path components, or unexpected encodings may remain visible.
- Headers and query parameters not listed in the configuration remain captured.
- Anyone who can use the monitor, clipboard, export, or telemetry endpoint may access sanitized event data.

## Recommended production policy

```swift
#if DEBUG
NetInspect.start(configuration: .init(redaction: .commonSecrets))
#endif
```

If NetInspect is required outside debug builds:

1. Disable bodies and headers unless they are necessary.
2. List every credential, identifier, and sensitive application field in `RedactionConfiguration`.
3. Keep the event and byte limits small and appropriate for the device.
4. Restrict access to monitor and export features.
5. Authenticate and authorize telemetry ingestion.
6. Define server-side retention and deletion policies.
7. Test sanitized output with representative requests before release.
8. Call `NetInspect.stop()` when the inspection session ends.

Example restrictive capture configuration:

```swift
CaptureConfiguration(
    captureBodies: false,
    maxBodyBytes: 1,
    captureRequestHeaders: false,
    captureResponseHeaders: false
)
```

Never intentionally log secrets and do not rely on client-side sanitization as the only protection for regulated or highly sensitive data.

