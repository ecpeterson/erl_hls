# Compiler and runtime roadmap

Maintained task index for `erl_hls` and its `hls_runtime` library, reconciled on 2026-11-09. Supported behavior belongs in [docs/](../docs/README.md); implementation notes retain their original evidence. Fabric lowering, application and deployment work belongs in the [hls_fabric roadmap](https://github.com/ecpeterson/hls_fabric/blob/main/yap/README.md); visualization and prediction work belongs in the [hls_spacetime campaign](https://github.com/ecpeterson/hls_spacetime/blob/main/yap/spacetime-visualization.md).

## Awaiting review

- [ ] Merge the qualified source-helper module emission in [PR #36](https://github.com/ecpeterson/erl_hls/pull/36); implementation is complete, including cross-module XLS constant-folding checks.

## Compiler usability, in priority order

- [x] Map generated DSLX diagnostics to actor/include/imported-helper Erlang origins; [local qualification](source-diagnostics.md).
- [x] Extend differential checking to finite actor transitions, with BEAM/RTL witnesses and an injected-defect shrink/replay check; implemented on `codex/actor-differential` (separate review).
- [ ] Package a communicating telemetry topology through `hlsc`.
  - Expose existing compiler topology/bundle APIs through the CLI; keep fabric scheduling and deployment policy downstream.
  - Finish when the [telemetry project](../src/examples/telemetry/README.md) has one documented packaging command, a relocatable bundle and a focused public-port RTL witness. Small-to-medium toolchain task.

## Next assessment

- [ ] Define failure, reset and retry semantics after the remaining low-hanging compiler usability work has been assessed.
  - Start with concrete actor/runtime ownership and observable failure cases; coordinate fabric transport and deployment semantics downstream. Do not silently broaden reset, replay or progress guarantees while improving compiler tests.

## Deferred or gated work

- [ ] Support concrete source-helper type aliases, then qualify source-only Phi line arithmetic with explicit widths and rounding.
  - Coordinate the arithmetic consumer with hls_fabric. Grid arithmetic has additional handwritten implementation choices; eliminating every geometry conditional is not the acceptance target.
- [ ] Extend field/effect/state-demand analysis when a consumer names the storage or dependency it will remove.
  - Message facts, known-bit compaction and phase-value analysis already exist. Additional analysis must preserve evaluated failures, effect order and unknown-provider behavior.
- [ ] Add structural callback helpers, actor parameterization, timeouts or supervised topology reconnection when an application requires their semantics.
  - Avoid runtime geometry branches or superset state solely to erase source conditionals. CPU restart ownership is a separate runtime contract.
- [ ] Recheck retained XLS workarounds during a deliberate pinned-toolchain refresh.
  - The signed-remainder fix ([#4978](https://github.com/google/xls/pull/4978)) and XOR cancellation ([#5190](https://github.com/google/xls/pull/5190)) are merged upstream; verify pinned-binary adoption rather than reimplementing them. RAM reservations ([#4952](https://github.com/google/xls/pull/4952)) remain open and Darwin subprocess support ([#4951](https://github.com/google/xls/pull/4951)) closed without merge. Retain the generic-struct mangling and signed-remainder reproducers when qualifying a refresh.
- [ ] Complete inherited source contracts and generated API documentation as modules are maintained.
  - The source audit still reports migration gaps; presence checks do not establish documentation quality.

## Completed foundations

- [x] Native compiler CLI, portable source bundles and detachable XLS execution: [toolchain ownership](compiler-toolchain.md).
- [x] Structured expression emission and source-located failure metadata: [expression IR](../docs/expression-ir.md) and [control-flow failures](../docs/control-flow.md).
- [x] Source closure, outgoing-message/known-bit facts and phase-value analysis: current `src/backend/xls/analysis/` modules.
- [x] Static integer semantics and the maintained compiler-only telemetry example: [qualification note](static-integer-semantics.md).
- [x] Public documentation currency review: [audit](documentation-audit.md).
- [x] Move the XOR-equality optimization to XLS: [upstream #5190](https://github.com/google/xls/pull/5190) merged; this does not establish adoption by our pinned binary.

## Audit scope and historical notes

This index reconciles main `ba179c3`, the pending PR #36, compiler/runtime guides and source TODOs, and distinct `compiler-message-facts.md` revisions retained in older `.codex/worktrees`. Their unchecked lists are historical proposals, not parallel active roadmaps. Completed message/known-bit/phase work is represented once above; additional ownership or specialization proposals require a current consumer and the [optimization review](../docs/optimization.md).

The former working-note links for reductions and debug pointed to absent files. Their current contracts are [actor reductions](../docs/actor-reductions.md), [topology observation](../docs/topology-debug.md) and [debug targets](../docs/debug-targets.md).
