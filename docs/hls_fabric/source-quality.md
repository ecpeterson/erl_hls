# Source quality checks

Use OTP 28.0.2 and rebar3 3.24.0:

```sh
python3 tools/test_source_contracts.py
python3 tools/check_source_contracts.py
rebar3 dialyzer
python3 tools/hls_fabric/check_application_boundaries.py
```

The contract check requires formal docs for exported functions, callbacks and types; specs for functions; explanations for private declarations; and comments for dispatcher clauses. It parses owned `.erl`/`.hrl` files without expanding macros, so both conditional branches are checked. Generated exports and declarations inside macro expansions still require review.

Unchanged omissions are reported, but do not block migration. New or changed declarations must meet every requirement. CI compares against the PR base (or the preceding commit on a branch push); locally the default is the merge base with `origin/main`. Use `--base REVISION` to choose another comparison, or `--strict PATH...` to require complete coverage of selected modules. `_build/source-contracts.json` records all remaining gaps locally; CI diagnostics have [size and retention limits](ci.md). There is no editable exception inventory.

Erlang source moves retain inherited gaps only when one literal `-module` identity occurs exactly once in each revision's complete owned inventory. The declaration id, requirement and fingerprint must still match; body, spec and visibility changes remain subject to the audit. Clean files participate in duplicate detection, and duplicate or multiple module declarations always fail, including under a path-restricted check. Headers, DSLX and Erlang files without a resolved literal module identity remain path-bound; matching basenames grant no exemption. Parse failures always reject. Strict mode still requires zero gaps.

CI cannot assess whether prose is useful or a spec is truthful. Review changed contracts against [STYLE.md](../../apps/hls_fabric/STYLE.md); favor short behavioral descriptions over implementation narratives. Keep working notes in `yap/`.

Handwritten DSLX under `apps/hls_lowering/priv/xls/` uses the same declaration-comment audit as the compiler. Input fragments use `.x.in`; generated complete modules are checked by XLS in the backend regressions. Existing omissions are migration work; new and changed declarations must pass.

## Formatting

`rebar3 fmt` formats owned production Erlang under `src/`, `apps/*/src/` and `include/` using the pinned developer-only erlfmt plugin. `rebar3 fmt --check` checks the same scope without writing. The formatter preserves Erlang syntax and comments; module responsibility, export groups and behavioral documentation still need review. Source-location test fixtures and historical experiments are outside this formatting scope.

Six map-type field-fragment macros are formatted manually, with a per-form `erlfmt:ignore` comment: the formatter cannot parse their partial type syntax. Their surrounding modules remain formatted, and compilation, Dialyzer and the contract audit still check the definitions.

The optional [spacetime observation application](../../apps/hls_spacetime_observer/README.md) is selected by the root `spacetime` profile: run `rebar3 as spacetime compile`, `rebar3 as spacetime eunit --dir=apps/hls_spacetime_observer/test` and `rebar3 as spacetime dialyzer`. Ordinary builds exclude it and its private offline-tool dependency. The repository-wide formatter and source-contract audit include its owned Erlang declarations without selecting the profile.

## Package boundaries

`python3 tools/hls_fabric/check_application_boundaries.py` additionally rejects direct calls, remote types and declared dependencies from the compiler, lowering and runtime libraries into `hls_phi` or `hls_snowflake`. Example packages may depend on the libraries; the reverse direction is an ownership error. The report is `_build/application-boundaries.json`.

After compilation, run `python3 tools/hls_fabric/check_package_boundaries.py --runtime hls_core --runtime hls_runtime --runtime hls_fabric --release _build/default/rel/hls_fabric`. The shared auditor rejects direct BEAM imports, remote type references and declared application dependencies from runtime applications into compiler/build applications; `hls_core` additionally rejects every other inspected application and therefore remains an OTP-only library. For a supplied runtime release it also checks application and individual BEAM ownership, so moving a compiler module into a runtime package cannot hide it. These static checks do not infer targets of arbitrary dynamic calls; runtime-only behavior tests exercise supported retained-codec and session paths.
