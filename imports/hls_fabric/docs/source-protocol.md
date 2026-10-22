# Source-protocol preflight

Inspect the actual repetition/noise application before proposing specialized transport or storage. This command produces a source and topology inventory, including unresolved ownership obligations. It does not remove fields, emit hardware or select a backend.

Prepare the pinned compiler dependency with `python3 tools/prepare_compiler.py`, then run:

```sh
bash tools/inspect_phi_protocol.sh /path/to/fresh-output
```

The shell entry point compiles this checkout's default profile and selects its backend/compiler beams explicitly. The escript compiles the six actor modules and two topology modules from the selected compiler sources, obtains complete ordinary source plans, and normalizes the N2/N3/N6 periodic repetition and D3 noise topologies. It invokes `hls_protocol_topology:elaborate/2` to materialize at most 64 actors and `hls_protocol_inventory:inspect/2` to inventory every route, send alternative and callback family. Application callbacks are analyzed, not run; only the topology constructors execute.

Elaboration retains startup, explicit recipients, spatial coordinates, external streams and lane metadata. Unknown families, duplicate ownership or recipients, out-of-range coordinates and excess population reject. Inventory diagnoses missing source plans, unknown producers/consumers, undeclared ports/boundaries, incomplete or duplicate output routing, retained calls and unexpanded topology shapes. Each actor also retains unresolved generation ownership, per-sender ordering, snapshot lifetime, bounded reservation and boundary obligations. A structurally clean report still has `eligible: false`; it is not permission to replace a mailbox or elide payloads.

`summary.json` records populations, diagnostic/obligation counts and exact source/backend identities. Each topology's `.etf` bundle retains its normalized and expanded topology, freshly compiled source artifacts and complete inventory; `.txt` exposes channels and structural diagnostics for review. ETF files are trusted local build data, never network input. The command requires a fresh output directory, exits nonzero on compilation/elaboration errors or structural diagnostics, and preserves any partial output for diagnosis. Unresolved temporal obligations are expected inspection results, not successful qualification.

The call path is deliberately contained in this PR:

```text
tools/inspect_phi_protocol.sh
  → tools/inspect_phi_protocol.escript
    → ordinary source compilation + hls_topology:normalize/1
    → hls_protocol_topology:elaborate/2
    → hls_protocol_inventory:inspect/2
    → application bundles + diagnostic summary
```

The lower-level inventory API expects artifacts from the same fresh compilation; the command establishes that relationship. It does not validate arbitrary caller-constructed or stale artifacts. Future lowering must discharge its own source, capacity, ordering and progress obligations before using these bundles. Compact capture planning, codecs and incoming-frame domains are deferred until their consuming hardware path can be reviewed with them.

`bash tools/test_source_protocol.sh /path/to/fresh-stage` invokes the production command, then checks all four freshly generated application bundles against independent population/coordinate expectations and their complete compiler artifacts. It exercises malformed topology and missing-binding diagnostics and verifies retained file hashes. These are source-analysis regressions, not RTL witnesses, QEC validation or physical measurements.
