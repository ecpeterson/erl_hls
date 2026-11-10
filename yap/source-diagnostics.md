# Source diagnostics qualification

Source scopes carry include-aware Erlang annotations through structured DSLX formatting. Finalization appends readable source comments to the main module and generated imports; the external XLS executor reads those comments and appends an Erlang source note without rewriting tool stderr. Compile-time JSON sidecars and their separate range-map API are gone. Runtime failure codes and their codebook remain unchanged.

The ordinary case is a right-column `// @erl "actor.erl":23`. A line with distinct origins adds explicit half-open byte-column ranges and aligned `// @erl+` continuation comments. These annotations apply only to their code line. Generated support without an origin stays unannotated. Existing comments and quoted literals are preserved; comments inside a multiline literal cannot supply metadata. Composing already-rendered text must preserve the comments’ association with their code, including ranged columns.

The 2026-11-09 local witness moved four ordinary actor bundles before invoking the real pinned XLS converter (`xls-optimized-2026-09-30`, converter SHA-256 `c5529f50118aea3d34d76f580d08090d58394d56ad4b11a2e2cf2fe058debd59`). Three deliberate type errors mapped to `actor.erl:23`, `include/callbacks.hrl:37` and `remote_math.erl:49`; the fourth actor converted successfully. Bundle manifests hash the annotated DSLX itself, and the reported Erlang files are absent from the relocated bundles. This is a finite conversion/diagnostic witness, not an RTL equivalence claim.

The register-service example contains 150 annotations across 416 lines, with no continuation lines; 132 annotations align at column 84, and longer existing code lines retain a two-space gap. A separate real-converter probe exercises mixed-origin continuation comments before a later type error, checking that physical row changes do not shift attribution to the wrong Erlang source.

Local checks covered all 1,124 EUnit tests: 1,114 passed in the main run and ten source-context tests passed separately. The initial full run hit the existing relocation test’s peer-startup timeout; its scratch was preserved, and that isolated test passed in 1.6 seconds with absolute BEAM paths and a 30-second test limit. The first narrow retry encountered the leftover scratch; a subsequent isolated invocation needed absolute search paths because the fixture changes directory. These failures remain recorded.

Twelve diagnostic consumer tests, 33 executor tests (one optional real-codegen case skipped), eight source-bundle tests, 26 source-auditor tests, four package-auditor tests, formatting and Dialyzer passed. The source audit reports zero new gaps and 3,334 inherited gaps; 37 runtime modules have zero package violations. The register-service golden changed only in comments; noncomment code lines remain byte-identical. The continuation probe passed after correcting its standalone diagnostics-directory setup. Remote CI was not requested.

To reproduce the converter witnesses in a fresh directory:

```sh
rebar3 as test compile
erl -noshell -pa _build/test/lib/erl_hls/ebin -pa _build/test/lib/hls_runtime/ebin -pa _build/test/lib/erl_hls/test \
  -eval 'ok = xls_source_map_dslx:write("_build/source-maps"), halt().'
python3 tools/test_source_maps.py --xls /path/to/xls --stage _build/source-maps
```

The consumer rejects malformed or ambiguous annotations. Diagnostics without positions, unannotated generated code, and transformed IR locations without a retained DSLX position remain unmapped. Locations identify source association, not the cause of placement or timing behavior. Exact qualification outputs and initial failures are retained in the external `compiler-usability-2026-11-09` artifact record; the earlier sidecar implementation’s evidence remains historical.
