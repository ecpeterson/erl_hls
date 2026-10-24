# Project style

This repository is experimental. Prefer the clearest current design over
compatibility scaffolding for an obsolete internal format.

## Erlang

- Destructure tuples and maps in function heads and `case` clauses when their
  shape determines control flow.
- Bind a related group of values once instead of repeating `maps:get/2` calls.
- Use guards for scalar constraints and `case` for genuine alternatives, not
  as a substitute for pattern matching.
- In typed internal APIs, use guards for semantic bounds without repeating
  scalar type checks such as `is_integer/1`; trust specs and Dialyzer for the
  type contract. Check types explicitly at untyped or untrusted boundaries.
- Keep internal error reasons concise. Include values needed to diagnose bad
  input, but rely on the stacktrace to identify the module and validation
  layer.
- Give normalized data one authority. Recompute derived caches at a consumer
  boundary when checking them is inexpensive.
- Avoid ultra-long string literals in the Erlang source wherever possible.
  Instead, write separate DSLX modules and import them.  Make liberal use of
  DSLX's parametricity to achieve this.

## Tooling boundaries

- Keep compiler analysis, semantic transformations and hardware lowering in Erlang. Keep source build configuration and orchestration in Erlang, using rebar3 for dependencies and packaging. External tool execution is a separate boundary; optional drivers consume emitted artifacts. Python is suitable for external tool drivers, report processing and plotting. Migrate existing Python compiler transformations into Erlang when extending or promoting them; retain their validation and evidence.
- Prefer `hls_fabric`'s Erlang inspection APIs over the same manifest-backed debug channel in simulation and on-device. Extend shared snapshots, counters or bounded traces for missing observations before adding simulator-private probes. Existing probes remain diagnostics until coverage is replaced; do not equate sparse snapshots with a complete event history.

## Hardware design

- Budget simultaneous readers, writers, field widths and conflicts before adding shared state; stored bits alone do not price access logic.
- Select before expensive per-input work when accepting one input at a time, unless measured retry costs justify parallel checks.
- Keep unchanged fields local. Compose updates through the selected row or bank; make write priority and forwarding explicit.
- Expose established tags, bounds and ownership to the compiler. Retain checks wherever their preconditions are not established.
- Preregister component area and cycle budgets. Synthesize representative row counts and producer fan-in before full integration.
- Locality may spend LUTs on local storage, decode or replication. Evaluate that cost against routed timing and one cumulative whole-device budget; area neutrality is not a universal exploration gate. Apply the [campaign cost policy](yap/physical-architecture-options.md#routing-and-area-policy) to decoder experiments.
- Use IR to check dependencies, mapped area to screen capacity, and measured cycles × routed period to judge throughput. Retain the original baseline and rejected results.

## Experimental formats and generated files

- Replace obsolete internal formats directly unless compatibility is an
  explicit requirement; do not add deprecation machinery by default.
- Keep compact generated DSLX beside its source when it is useful in review.
- Keep measurement outputs outside the repository, under `HLS_ARTIFACT_ROOT` (by default the sibling `hls_artifacts/` directory). Keep generators, frozen regression inputs and small parser fixtures in source control. `_build/` is disposable. See [artifact storage](docs/artifacts.md).

## Roadmap and other working notes

- Don't manually line-wrap. Many Markdown renderers don't handle it well.
- Use checkboxes to indicate to-do items.
- Items which are checked off should have all child nodes removed.
- Keep items short. If there is more detail to include which is not itself a
  task, use sub-bullets.
- Structure tasks around executable targets which exercise the feature.
- Don't create entirely new trees. Re-organize the existing tree to accommodate
  new items.
- Keep items sorted by dependency order foremost and priority order secondmost.
- Don't use tabs.

## Source contracts and documentation

- Give every exported Erlang function, callback and type a nonempty formal `-doc`. Give every function a `-spec`. Explain each private function/type with a docstring or adjacent comment. Use native equivalents in other languages: Python docstrings/type hints, or interface comments where no formal syntax exists.
- Document handwritten DSLX functions, types and procs with adjacent behavioral comments, including each proc's `config`, `init` and `next`.
- Explain distinct requests in dispatcher clauses (`handle_call`, `handle_cast`, `handle_info`, `handle_event`); use judgment for other multi-purpose functions. Describe intent, not the pattern's spelling.
- Docstrings describe behavior, inputs/results, failure and useful usage constraints. Keep implementation details in source comments, except caller-visible surprises such as unbounded retention or expensive operations.
- Be brief and dense. Lead with the point; remove repetition, retrospective explanations and prose that merely restates names or types. Add an example only when it saves explanation.
- Human documentation belongs in `docs/`: prerequisites before dependents, general concepts before details, and intended contracts apart from incidental implementation. Keep agent working/design notes in `yap/`, outside `docs/`; link only when useful to maintainers. Record measurements as evidence, not API promises.
- Run the source-contract check and Dialyzer for every PR. Fix real type errors; any unavoidable upstream-tool exception must be narrow, explained beside the affected code and covered by regression tests. Do not add blanket suppressions or vacuous specs to obtain green checks.
- Existing documentation gaps are migration work, not a model for new code. Complete the contracts of each declaration you change. Review prose and spec accuracy manually: CI checks presence and detects changed declarations, not semantic truth.
