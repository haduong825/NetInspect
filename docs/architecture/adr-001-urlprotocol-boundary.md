# ADR-001: URLProtocol as the network interception boundary

## Status

Accepted

## Decision

Use `URLProtocol` in explicitly configured `URLSession` instances. Do not use private APIs or runtime swizzling to intercept `URLSession.shared` globally.

## Rationale

`URLProtocol` is a public Foundation extension point, works for requests routed through a custom session, and keeps the SDK compatible with App Store review requirements. Global interception would require fragile runtime behavior and could alter unrelated networking.

## Consequence

Consumers must create sessions through `NetInspectURLSession` or route their own configuration through the helper. Existing sessions that bypass the helper are outside the guaranteed capture boundary.
