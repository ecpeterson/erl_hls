# Source quality checks

Use OTP 28.0.2 and rebar3 3.24.0:

```sh
python3 tools/test_source_contracts.py
python3 tools/check_source_contracts.py
rebar3 dialyzer
```

The contract check requires formal docs for exported Erlang functions, callbacks and types; specs for functions; explanations for private declarations; and comments for dispatcher clauses. It parses owned `.erl`/`.hrl` files without expanding macros, so both conditional branches are checked. Generated exports and declarations inside macro expansions still require review.

Handwritten DSLX under `priv/xls/` requires adjacent comments on functions, types and procs, including each proc's `config`, `init` and `next`. Comments describe bounds, validity flags, ordering and blocking where relevant. A module banner does not document every declaration. DSLX signatures already carry types; XLS checks them in the semantic regressions. This audit only locates declarations, ignoring expression bodies and literals; unsupported declaration forms fail the check. Constants, proc fields and generated DSLX are outside this comment audit.

Unchanged omissions are reported, but do not block migration. New or changed declarations must meet every requirement. CI compares against the PR base (or the preceding commit on a branch push); locally the default is the merge base with `origin/main`. Use `--base REVISION` to choose another comparison, or `--strict PATH...` to require complete coverage of selected modules. `_build/source-contracts.json` records all remaining gaps and is retained by CI. There is no editable exception inventory.

CI cannot assess whether prose is useful or a spec is truthful. Review changed contracts against [STYLE.md](../STYLE.md); favor short behavioral descriptions over implementation narratives. Keep working notes in `yap/`.

Native `-doc`/`-moduledoc` attributes are available through `code:get_doc/1` and Erlang shell help. For HTML generation, use [ExDoc](https://www.erlang.org/doc/system/documentation.html#using-exdoc-to-generate-html-epub-documentation): EDoc in the pinned OTP release reads comment tags instead. `-moduledoc false` hides the entire module from ExDoc, while its function docs remain in the BEAM chunk for source/shell use. Internal exports still require contracts; hiding a module does not waive the audit. There is not yet a generated HTML documentation build.
