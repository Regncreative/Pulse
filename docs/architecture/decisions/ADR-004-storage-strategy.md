# ADR-004: Hot Cache + Async SQLite Storage

**Status:** Accepted (revised 2026-07-27)

**Date:** 2026-07-27

---

## Context

Pulse needs low-latency live updates and durable history. The original “shared ring + sync SQLite on ingest” design failed architecture review (P0-1, P0-3).

## Decision

1. **Hot:** recent summary cache (single-writer) + **per-connection live queues** for UI  
2. **Cold:** dedicated **async SQLite writer** thread (WAL)  
3. **Raw Level 3:** not in the primary events table by default; lazy fetch / optional side store  

## Alternatives Considered

| Alternative | Pros | Cons |
|-------------|------|------|
| Shared multi-reader ring | Simple mental model | Unsafe concurrent head; rejected |
| Sync SQLite on ingest | Strong durability before notify | Blocks live path; rejected |
| In-memory only | Fast | No history |
| SQLite only on hot path | One store | Fights responsiveness |

## Consequences

- Live clients can drop events under backpressure without stalling collection  
- History may lag live by writer queue delay (acceptable for v1)  
- Detail raw XML may require lazy load  

## References

- [10 — Storage](../10-storage.md)
- [ADR-008](ADR-008-hot-cold-live-queues.md)
- [23 — Architecture Review](../23-architecture-review.md)
