# Compiler backends

[`xls/`](xls/) is the compiler's Erlang-to-DSLX backend. It prepares hardware-reachable source, preserves Erlang callback semantics while lowering, and renders actor services and dedicated topology wiring. Start with its [stage and module map](xls/README.md).

The boundary follows the data, not just the `xls_` prefix:

- [`../frontend/`](../frontend/) owns preprocessing, source records and actor contracts. The backend consumes those forms and interfaces; shared language/type contracts live in the [`hls_runtime` API](../../apps/hls_runtime/src/api/README.md).
- [`../topology/`](../topology/) owns logical actor graphs. The backend resolves their wire layouts and emits dedicated actors; the downstream `hls_lowering` application owns RAM placement, source-protocol lowering and application composition.
- [`../toolchain/`](../toolchain/) owns build requests, packaged inputs and external execution. XLS converts DSLX to its own typed IR, optimizes and schedules it, and generates RTL. Backend modules do not run these tools.
- The [`hls_runtime` library](../../apps/hls_runtime/README.md) owns host execution and retained metadata access. Compiler artifacts are not live actor processes, transport sessions or deployment authorization.

Keep source semantics in the lowerers and target syntax in the renderer. A new execution policy should consume the checked actor specification or retained `xls_actor_program`, while ordinary algebraic optimization remains with XLS. Compiler providers selected by `xls_type` may supply opaque DSLX fragments, so `xls_dslx` is a shared deferred syntax representation rather than a complete replacement for XLS's compiler IR.

The public build path and supported source contracts are described in [actor compilation](../../docs/actor-compilation.md) and [control flow](../../docs/control-flow.md). File-level compiler entry points are internal backend APIs, not a separate application lifecycle.
