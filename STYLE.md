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

## Experimental formats and generated files

- Replace obsolete internal formats directly unless compatibility is an
  explicit requirement; do not add deprecation machinery by default.
- Keep compact generated DSLX beside its source when it is useful in review.
- Store digests rather than checked-in generated Verilog when regression jobs
  already regenerate, simulate, and retain that Verilog as an artifact.
