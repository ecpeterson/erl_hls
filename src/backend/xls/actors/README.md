# Actor and server compilation

The parent `xls_parse` facade selects the state-machine or server path. `xls_statem_lower` prepares and lowers state machines; `xls_gs_lower`, `xls_gs_immediate` and `xls_gs_deferred` handle server callback and retained-reply contracts. `xls_actor_program` retains a checked spec and `xls_statem_plan` sidecar for consumers sharing one source analysis.

| Family | Responsibility |
| --- | --- |
| `xls_init`, `xls_callback_result`, `xls_statem_callbacks`, `xls_statem_entry` | Normalize callback/entry contracts; select and lower constant initialization |
| `xls_entry_storage` | Encode and reconstruct already evaluated entry effects without losing source evaluation |
| `xls_actor_codegen`, `xls_statem_codegen` | Assemble common definitions and the dedicated register-backed execution body |
| `xls_statem_continuation`, `xls_statem_event_codegen`, `xls_statem_reply_codegen` | Validate finite internal events and render continuation/caller ownership |
| `xls_statem_reduction_*`, `xls_statem_gather_*` | Keep each collection feature's lowering, semantic/layout contract and rendering together |
| `xls_actor_observation`, `xls_actor_debug` | Render committed-state observation and bind retained failure metadata to logical identities |

These families consume [expression lowering](../expressions/README.md), [types/codecs](../types/README.md) and [source analyses](../analysis/README.md). Their fragments remain structured until [artifact finalization](../emission/README.md). Dedicated wiring belongs to [topology](../topology/README.md); shared-memory/source-protocol execution policies belong to the fabric lowering application. Live processes and debug queries remain runtime operations.
