# Source style

Prefer the clearest current design over compatibility scaffolding for obsolete internal formats. Keep library validation, producer interpretation, vendor extraction and browser rendering at explicit boundaries. This library does not depend on a compiler or run an OTP process.

## Erlang

- Destructure related maps and tuples once. Use guards for scalar bounds and pattern matching for shapes; trust typed internal contracts rather than repeating boundary validation.
- Give normalized data one authority. Recompute inexpensive derived summaries when checking them.
- Express fixed-width bounds as `0 .. ((1 bsl 32) - 1)`, not expanded decimal limits.
- Give every exported function and type a nonempty `-doc`, every function a `-spec`, and private declarations an adjacent explanation. Describe inputs, failures, ordering and bounds, without restating implementation.
- Format production Erlang with the pinned erlfmt configuration. Use concise error reasons carrying the values needed to diagnose rejected input.

## Evidence and documentation

- Simulation is a finite witness. Proof claims identify the property, quantified domain, assumptions, horizon and trust boundary.
- Keep cycle time, static timing, placement, dependencies and electrical activity distinct. Unknown evidence remains unknown; names and equality do not establish causality.
- Human documentation belongs in `docs/`; campaign/design notes belong in `yap/`. Keep one authoritative campaign plan. Do not manually wrap Markdown paragraphs.
- Keep generated measurements outside the repository. Retain small fixtures and generators; saved hashes do not exempt bulk artifacts from retention limits.
- Run the checks in [source quality](docs/source-quality.md) and focused regressions. Do not rerun a complete native or application witness to qualify a parser change.
