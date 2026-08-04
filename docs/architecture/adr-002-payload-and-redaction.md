# ADR-002: Full payload capture with configurable redaction

## Status

Accepted

## Decision

Capture request and response bodies by default, apply configured header/JSON/query redaction before persistence and transport, and enforce a maximum body size.

## Rationale

Full payloads are valuable for debugging. Size limits prevent unbounded memory/disk growth, while the redaction pipeline provides an explicit privacy control for tokens and credentials.

## Consequence

Consumers must configure redaction and payload limits for production use. Binary payloads are represented as base64 and oversized payloads are marked truncated.
