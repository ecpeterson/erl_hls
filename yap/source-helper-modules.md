# Source helper module emission

- [x] Preserve imported Erlang module ownership in generated DSLX, with public exports, private callees and qualified calls.
- [x] Publish generated imports with the actor under one failure-code allocation and integrity seal.
- [x] Check module cycles, visibility, overloads, import-name collisions, source reselection and dependency packaging.
- [x] Confirm XLS removes constant selection across generated imports while retaining dynamic selection.

The pinned local XLS toolchain converted the same generated public selector with constant and dynamic Boolean inputs. The constant top reduced to `param(name=x)`; the dynamic top reduced to one `sel(keep_left, cases=[y, x])`. The unoptimized IR retains the source-module invocation in both cases. Forty-eight finite BEAM-derived scalar assertions and sixty finite generated-owner cases (sixteen clocks each, including stalls and selected failures) pass. These are finite witnesses and optimizer-output checks, not hardware area or timing measurements.

The Phi consumer separately passes its retained 950 direction cases. Fixed-mask public calls to the generated line/grid helper modules reduce to single literals 2 and 4. Generated dependencies remain actor-owned because failure codes and reachable function subsets belong to that compilation. Shared library compilation and independent helper codebooks are not part of this change.

Revision evidence, including preserved setup/test failures and their corrections: `/Users/ecpeterson/Documents/code/hls_artifacts/runs/spacetime-2026-11-09/source-helper-modules-1/`.
