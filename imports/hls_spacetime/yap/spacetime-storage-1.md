# S6 — Storage-picture validation

2026-11-06. The cross-cycle storage portion is complete. Public-completion, publication and numerical contributor attribution remain open; S5/S6 as a whole are not complete. This change consumes the saved S3/S4 projections without simulation, native work, catalogue import or evidence recollection.

## Rendering boundary

The old viewer showed only selected versions and omitted the write-at-C to Q-at-C+1 interval. Single-sample words therefore collapsed to points. The new model emits separate load and retention intervals for all matching visible words, preserving equal-write identities and stopping before replacement, reset or an unobserved sample. A resource picker and selectable version histories expose roots as well as writes. Root provenance never gains an invented producer.

The default view groups storage by logical word. An explicitly selected word can expand to supported cell locations; folded cell identities draw once, while unknown bits/candidates/unplaced cells retain an unknown-rail representation. These are simulated logical transitions at finite-witness value locations, not native FF CE observations, electrical switching or exclusive task occupancy. The stack reports any omission at its 20,000-stroke bound. It keeps the complete graph and uses interval groups rather than one allocation per cell per clock.

The selected C1775–C1873 step shows 463 load bridges and 271 residence spans across 51 register words. The C1852–C1866 example exposes 409 qualified cells and 128 unresolved bits for `register/____state_154`. The separate RAM example retains read-first response identity after replacement and breaks storage at reset incarnations, even when contents survive.

## Independent check and local qualification

`node scripts/check-storage-view.mjs PROJECTION.json` advances a separate word-state table clock by clock using the recorded accesses, then compares each adjacent-clock connection against the viewer's compressed intervals. It rejects stale write identities, incorrect read selection, mismatched or overdue responses, reset reuse, missing/duplicate bridges and exceeded comparison budgets. Complete declared coverage qualifies the logical edge check; unknown initial contents and ancestry stay unknown. It does not reread raw samples or reestablish producer/native correspondence.

- Saved live projection SHA-256 `61cd76ff5d73d9be83836c45a4cb38f35548e10c0378736f69ebf1bbb3906319`: all 120,768 edge comparisons agree (7,633 loads and 113,135 holds). All 7,637 committed writes remain in the graph; four terminal writes lack a following sample and correctly produce no load bridge. The check covers 1,807 read requests/results and 51 unknown storage roots.
- Saved memory projection SHA-256 `c673efd6d134bfc52da6060c3d90b541e1df7f5f1d6f2413ab9d744467c654bd`: all 30 edges agree (six loads, 24 holds), including two masked writes, three responses after replacement and two reset-retired requests.
- Thirty browser-model tests and nine independent-replay tests pass. The first replay-test run exposed an inconsistent fixture claiming both complete coverage and loss; the fixture now separately checks unqualified incomplete coverage and rejection of contradictory completeness. Its failure and focused correction are retained.
- The unchanged library passes 138 EUnit tests, formatting, Dialyzer and strict source contracts over 13 Erlang files, with zero gaps. Browser syntax/format checks pass. No Actions run was requested.
- Browser inspection covers grouped storage with no selected event, the 99-clock selection, actor filtering, 409-cell expansion, resource/version selection, the read-first response and reset/carry-in root. No browser errors were reported.

Compact reports, guard outcomes and the implementation patch are retained under the external `spacetime-2026-11-06/view-storage-1` archive. All checked local groups exited and are gone, without a guard trigger. Existing projection/source identities remain unchanged. Retention review is due 2026-11-13.

## Next executable target

The current recording includes public outputs but lacks the gateway input handshakes. Add passive top-level `event0_data/valid/ready` and `event1_data/valid/ready` taps, bound to the exact application RTL closure. Assign accepted transfers identities by endpoint and ordinal, then join decoded public frames by declared route and per-endpoint FIFO order; payload comparison only validates that join. Reset must retire partial queues, and missing, reordered or unmatched frames must reject. Preregister one bounded new capture/replay; reuse the completed native implementation.

Next connect each endpoint transfer to an acknowledged actor publication through source-derived route bindings, including simultaneous offers, independent stalls, equal-payload new occurrences and reset with pending work. Emit missing source-to-link metadata from the lowering plan; do not parse identifiers to infer it. Selected numerical D contributors remain a separate checked-runtime-expression task. Static cones, value equality and same-clock chronology must never be inserted as dynamic ancestry.
