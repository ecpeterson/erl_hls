# Actor source and build context

Use the same preprocessing options for BEAM compilation, source-only interface inference, and DSLX emission:

```erlang
Source = "actors/cell.erl",
Options = [{i, "protocol/include"}, {d, 'CAPACITY', 4}, {d, 'WIDE'}],
{ok, cell} = compile:file(Source, Options),
Interface = xls_parse:actor_interface(Source, Options),
Dslx = xls_parse:to_xls(Source, #{source_options => Options}).
```

Supported source options are `{i, Directory}`, `{d, Name}`, `{d, Name, Value}`, and `{feature, Name, enable | disable}`. Preserve their order when passing them between APIs. Include search follows Erlang's preprocessor: the including file's directory, the build's working directory and main source directory, then the ordered include paths. Source-only calls also retain the `erl_hls` application include directory as a final fallback. `include_lib` resolves through the current Erlang code path; the same application versions must be available to both builds. Undefined macros, missing includes, and syntax errors stop analysis with `{source_errors, [{File, Location, Reporter, Reason}, ...]}` instead of leaving a partially parsed module for later passes.

`shared_service => ordinary | aggregate_only` is independent of `source_options`; it defaults to `ordinary`. These are compiler inputs, not changes to the actor's runtime interface.

`hls_source:options(Source, Options)` anchors a context to its build directory while preserving the original path spellings. Both `actor_interface/2` and the `source_options` field accept that context, so analysis and emission can use it after the working directory changes. Relative include spellings matter: `?FILE` can participate in a preprocessor condition. Reads in the build directory run in-process. Reads elsewhere use a short-lived `peer` BEAM process with the caller's code paths and a stdio control connection, rooted at the build directory; they do not change the caller VM's working directory or require distributed Erlang. This path has process-startup overhead. The context describes preprocessing; it does not contain parsed forms or freeze header contents.

For a compiled `hls_statem`, `hls_pack` records its preprocessing context beside the inferred interface summary. `hls_actor_interface:from_module/1` reparses available source using that captured context and compares the resulting interface with the embedded summary. Changing a transitive header's record layout, macro-selected interface, phase surface, mailbox capacity, or effect layout therefore requires recompiling the BEAM before topology planning. The query also checks the set of source-file spellings recorded by preprocessing: a changed include resolution, or a compiler source-name override that cannot be faithfully replayed, reports `source_origins` with the expected and actual origins. A source-available BEAM without context reports `missing_hls_source_context`; rebuild the actor to provide it. A deployed BEAM whose source is absent uses its validated embedded summary. Deterministic builds omit both build-directory metadata and source verification, preserving their existing embedded-summary behavior.

The comparison covers the summarized interface, not all callback implementation changes, type-provider implementations, or complete artifact identity. The source reader performs preprocessing, not arbitrary parse-transform replay. Build dependencies and code paths must remain stable during a planning pass; there is no atomic snapshot of concurrently edited files or hot-loaded modules.

Topology normalization resolves one interface per distinct actor module across its exact and family sections. Scheduler planning, reduction planning, and DSLX annotation each build their own temporary module table. Instances and scheduler groups reuse that table within the pass. Later passes reread source and headers, so a successful earlier query cannot hide a subsequent edit. Family dimensions do not cause member-by-member interface analysis.

`rebar3 eunit` checks macro variants, include order, changed working directories, stale transitive headers, preprocessing diagnostics, and bounded source-read counts as populations and fanout grow. `bash tools/test_source_context.sh XLS_ROOT` compares configured initial values, codecs, dispatch results, and mailbox capacities against BEAM using the DSLX interpreter and JIT. After `rebar3 as test compile`, `escript tools/profile_interfaces.escript CHECKOUT OUTPUT.json` reports seven warmed timing samples per workload, source reads, best/mean/worst milliseconds, and population variance in milliseconds squared. Run the same script against separate prepared checkouts for comparisons.
