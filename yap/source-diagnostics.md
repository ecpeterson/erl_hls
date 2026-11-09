# Source diagnostics qualification

Source scopes now carry the existing include-aware Erlang annotations through structured DSLX formatting. Finalization emits adjacent hash-bound maps for the main module and generated imports; the external XLS executor appends an Erlang source note without rewriting tool stderr. Byte-only composition invalidates the changed main module’s ranges. Runtime failure codes keep their existing meaning.

The 2026-11-09 local witness moved four ordinary actor bundles before invoking the real pinned XLS converter (`xls-optimized-2026-09-30`, converter SHA-256 `c5529f50118aea3d34d76f580d08090d58394d56ad4b11a2e2cf2fe058debd59`). The three deliberate type errors mapped to `actor.erl:23`, `include/callbacks.hrl:37` and `remote_math.erl:49`. The fourth actor converted successfully. Each bundle manifest retained and hashed its maps, and the reported source files were absent from the relocated bundle. This is a finite conversion/diagnostic witness, not an RTL equivalence claim.

Local validation also exercised the 1,117-test EUnit suite. Three tests needed to account for the transparent annotation/seal, and the isolated bootstrap test exposed missing `xls_entry_comprehensions` and `xls_helper_modules` bootstrap dependencies. The affected tests passed after those fixes. Required Dialyzer, formatting, 33 executor tests, eight source-bundle tests, nine diagnostic consumer tests, 26 source-auditor tests, four package-auditor tests and the unchanged register-service DSLX golden passed. The source audit reports zero new gaps and 3,334 inherited gaps; 37 runtime modules have zero package violations. Remote CI was not requested.

To repeat only the real conversion witness in a fresh directory:

```sh
rebar3 as test compile
erl -noshell -pa _build/test/lib/erl_hls/ebin -pa _build/test/lib/hls_runtime/ebin -pa _build/test/lib/erl_hls/test \
  -eval 'ok = xls_source_map_dslx:write("_build/source-maps"), halt().'
python3 tools/test_source_maps.py --xls /path/to/xls --stage _build/source-maps
```

The consumer rejects stale, malformed or ambiguous maps. Unannotated generated support, diagnostics without positions, and transformed IR locations without a retained DSLX position remain unmapped. Locations identify source association, not the cause of placement or timing behavior. Exact qualification outputs and initial failures are retained in the external `compiler-usability-2026-11-09` artifact record.
