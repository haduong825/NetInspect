# ADR-003: Injectable logger instead of system-wide log scraping

## Status

Accepted

## Decision

Capture events emitted through `NetInspectLogger`, `NetInspect.log`, and the explicit `NetInspectPrintStream` bridge. Do not claim to scrape all process or system `os_log` output.

## Rationale

iOS has no supported public API that reliably lets an application read arbitrary `os_log` output from other libraries. An injectable logger is deterministic, testable, and safe for production.

## Consequence

Applications and libraries that need their logs in the event stream must use the SDK logger or an adapter.
