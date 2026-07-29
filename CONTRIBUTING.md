# CONTRIBUTING

1. Read [AGENTS.md](AGENTS.md) and [docs/architecture/README.md](docs/architecture/README.md).
2. Do not add antivirus/cleaner/optimizer features.
3. Observation only — no injection, hooks, or OS mutation beyond Pulse’s own install/data.
4. Open PRs against `main` with a clear description and test notes.
5. Run `pulse_wire_tests` and Flutter analyze before requesting review.
6. New architectural changes require an ADR under `docs/architecture/decisions/`.
