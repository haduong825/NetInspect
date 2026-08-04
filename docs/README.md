# NetInspect documentation

This documentation covers integration, configuration, operations, and the design constraints of NetInspect.

## Start here

1. [Getting started](getting-started.md) — install the package, start capture, make a request, and open the monitor.
2. [Configuration reference](configuration.md) — choose capture, storage, redaction, logging, and batching behavior.
3. [Privacy and security](privacy-and-security.md) — understand sensitive-data handling before shipping.

## Guides

- [Monitoring UI](monitoring-ui.md)
- [Logging and export](logging-and-export.md)
- [Telemetry](telemetry.md)
- [Troubleshooting](troubleshooting.md)

## Architecture

The [architecture decision records](architecture/README.md) explain why NetInspect uses explicit `URLSession` configuration, sanitizes before storage, and provides an injectable logger.

## Module map

```text
NetInspectCore
├── NetInspectURLSession
├── NetInspectTransport
└── NetInspectUI
```

All optional modules depend on `NetInspectCore`; they do not depend on one another. Consumers should link only the products they need.

