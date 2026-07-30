## Goal

Plan the **v1.1** minor release after the first public `v0.1.0`.

Focus: broader Event Log coverage and stronger Timeline UX — still **read-only / local-first**.

---

## Candidate themes

### Event Log channels
- [ ] **Application Event Log** channel support (beyond System)
- [ ] **Security Event Log** channel support (with clear privilege / ACL UX)
- [ ] Channel picker / multi-channel Timeline (design ADR if needed)

### Timeline improvements
- [ ] Stronger event grouping / correlation (related process trees, restart chains)
- [ ] Richer Level-1 humanization coverage for common providers
- [ ] Smoother virtualization / very large session performance
- [ ] Optional “stick to live edge” refinements

### Search
- [ ] Faster full-text search across title / summary / provider / event id
- [ ] Saved searches (local only)
- [ ] Search within selected time range

### Filtering
- [ ] Provider filter
- [ ] Process / image-name filter
- [ ] Time-range filter (last 15m / 1h / custom)
- [ ] Combine filters without clearing the snapshot unexpectedly

### Export
- [ ] Export filtered view (not only full buffer)
- [ ] Additional formats beyond JSON (e.g. CSV) if useful for support workflows
- [ ] Optional redaction helpers for shared exports

---

## Out of scope for v1.1

- ETW / WMI engines (see Roadmap v1.2)
- Cloud sync, accounts, telemetry
- Cleaners / optimizers / antivirus features (`AGENTS.md`)

## References

- Architecture: `docs/architecture/README.md`
- Product rules: `AGENTS.md`
