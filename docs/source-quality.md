# Source quality checks

Use OTP 28.0.2 and rebar3 3.24.0. Production Erlang under `src/` and `apps/*/src/`, and headers under `include/` use the pinned erlfmt project plugin (v1.8.0) with a 100-column limit. Run `rebar3 fmt` before review and `rebar3 fmt --check` to check the canonical form. Test and semantic fixture layout is outside that formatting scope.

The [shared qualification command](ci.md) runs these checks locally and in CI. For only this group, use `python3 tools/check.py --group quality`. The individual source-contract and type checks remain available:

```sh
python3 tools/test_source_contracts.py
python3 tools/check_source_contracts.py
rebar3 dialyzer
```

The contract check requires formal docs for exported Erlang functions, callbacks and types; specs for functions; explanations for private declarations; and comments for dispatcher clauses. It parses owned `.erl`/`.hrl` files without expanding macros, so both conditional branches are checked. Generated exports and declarations inside macro expansions still require review.

Handwritten DSLX under `priv/xls/` requires adjacent comments on functions, types and procs, including each proc's `config`, `init` and `next`. Comments describe bounds, validity flags, ordering and blocking where relevant. A module banner does not document every declaration. DSLX signatures already carry types; XLS checks them in the semantic regressions. This audit only locates declarations, ignoring expression bodies and literals; unsupported declaration forms fail the check. Constants, proc fields and generated DSLX are outside this comment audit.

Unchanged omissions are reported, but do not block migration. New or changed declarations must meet every requirement. CI compares against the PR base (or the preceding commit on a branch push); locally the default is the merge base with `origin/main`. Use `--base REVISION` to choose another comparison, or `--strict PATH...` to require complete coverage of selected modules. `_build/source-contracts.json` records all remaining gaps locally; CI diagnostics have [size and retention limits](ci.md). There is no editable exception inventory.

Erlang source moves retain inherited gaps only when one literal `-module` identity occurs exactly once in each revision's complete owned inventory. The declaration id, requirement and fingerprint must still match; body, spec and visibility changes remain subject to the audit. Clean files participate in duplicate detection, and duplicate or multiple module declarations always fail, including under a path-restricted check. Headers, DSLX and Erlang files without a resolved literal module identity remain path-bound; matching basenames grant no exemption. Parse failures always reject. Strict mode still requires zero gaps.

CI cannot assess whether prose is useful or a spec is truthful. Review changed contracts against [STYLE.md](../STYLE.md); favor short behavioral descriptions over implementation narratives. Keep working notes in `yap/`.

Native `-doc`/`-moduledoc` attributes are available through `code:get_doc/1` and Erlang shell help. For HTML generation, use [ExDoc](https://www.erlang.org/doc/system/documentation.html#using-exdoc-to-generate-html-epub-documentation): EDoc in the pinned OTP release reads comment tags instead. `-moduledoc false` hides the entire module from ExDoc, while its function docs remain in the BEAM chunk for source/shell use. Internal exports still require contracts; hiding a module does not waive the audit. There is not yet a generated HTML documentation build.

## Package boundaries

After compilation, run `python3 tools/test_package_boundaries.py`, compile the `spacetime` profile, run `python3 tools/hls_fabric/check_application_boundaries.py --profile default --profile spacetime`, then run `python3 tools/check_package_boundaries.py --runtime hls_core --runtime hls_runtime`. The source-quality workflow runs all of these after Dialyzer. The broad application audit and runtime package audit together reject direct BEAM imports, remote type references and declared application dependencies across the one-way architecture: compile cannot call live runtime services, Fabric, target, Spacetime or the facade; Fabric cannot call target, Spacetime or the facade; target cannot call Spacetime or the facade; runtime cannot call any synthesis or optimization application. The compiler's one allowed runtime call is `xls_provider_gs` invoking the process-free retained-handle descriptor `hls_gs:from/0`; every other runtime MFA and every runtime remote type remain forbidden. Loading that provider code does not start a runtime service. `hls_core` rejects every other inspected application and therefore remains an OTP-only library.

For a supplied runtime release the auditor also checks application and individual BEAM ownership, the generated release manifest, the exact project-application closure and the absence of source, target assets and build launchers. Every immediate library root must contain one matching application manifest; the asset scan covers OTP dependencies as well as project applications while permitting native runtime libraries. `bash tools/hls_fabric/test_runtime_release.sh` applies that audit, loads and validates an independently constructed canonical artifact, and separately runs a precompiled virtual-node deployment against code from the assembled release. `hls_protocol_identity_tests` emits a real target application artifact and loads it in a clean child containing only `hls_core` and `hls_runtime`. The finite release witness uses synthetic brokers; it neither starts a stream from the loaded artifact nor qualifies hardware.

`python3 tools/test_external_consumers.py` builds separate runtime-only and compile-time projects against exact installed `hls_runtime` and `erl_hls` release closures from one detached checkout at an immutable umbrella commit. The runtime consumer has no synthesis application on its code path. The compiler consumer uses the supported façade and may load runtime-owned value providers, but it neither starts `hls_runtime` nor starts its supervisor. With no `--revision`, the command requires a clean tracked working tree so the fixture and release revision cannot silently diverge.

`bash tools/test_umbrella_eunit.sh boundaries` builds fresh projections for computation synthesis, communication synthesis, physical target materialization and Spacetime policy. These static checks do not infer targets of arbitrary dynamic calls; the projections and runtime-only behavior tests exercise the supported value and session boundaries.
