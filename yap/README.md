# Compiler and runtime working material

This directory retains compiler/runtime design rationale and qualification history. Supported behavior belongs in [docs/](../docs/README.md). The private cross-repository roadmap in `Notes/erl_xls/Roadmap.md` owns the sole active task list; this index and older experiment checklists are references, not additional campaigns. The private roadmap is a maintainer note, not a compiler dependency.

Compiler extensions and typed-plan work are tracked under G2, pinned-toolchain qualification under G6, and source-contract/documentation maintenance under G8. Recovery relationship policy and physical qualification belong to G1 and P6. Those identifiers refer to the master list rather than duplicating its scope or priority here.

## Contracts and retained evidence

| Area | Current contract | Qualification or design history |
| --- | --- | --- |
| Standalone compilation and portable bundles | [Toolchain](../docs/toolchain.md) | [Toolchain ownership](compiler-toolchain.md), [reliability closeout](compiler-reliability.md) |
| Source selection, snapshots and imported helpers | [Actor compilation](../docs/actor-compilation.md), [source context](../docs/source-context.md), [local helpers](../docs/local-helpers.md) | [Helper module emission](source-helper-modules.md) |
| Structured emission and source attribution | [Expression representation](../docs/expression-ir.md), [tool diagnostics](../docs/toolchain.md#optional-xls-invocation) | [Source diagnostics](source-diagnostics.md) |
| Finite compiler and actor comparisons | [Differential checks](../docs/compiler-differential.md) | [Actor transition qualification](actor-transition-differential.md) |
| Integer and provider semantics | [Numeric contract](../docs/numeric-contract.md), [provider extensions](../docs/type-providers.md) | [Static integer qualification](static-integer-semantics.md) |
| Actor lifetimes and supervision | [Actor domains](../docs/actor-domains.md) | [Recovery qualification](actor-recovery.md) |
| Documentation and package boundaries | [Source quality](../docs/source-quality.md), [source map](../src/README.md) | [Documentation audit](documentation-audit.md) |

The digital recovery campaign is complete, including the downstream [framed-crossing closeout](https://github.com/ecpeterson/hls_fabric/blob/main/yap/actor-recovery.md#framed-crossing-closeout). Its finite witnesses do not establish physical exclusion, live-device operation or application retry validity. Compiler/runtime contracts remain application-neutral.

## Evidence boundaries

Historical notes retain their tested revisions, rejected alternatives and failed attempts. Their test counts, physical results and remaining limitations describe those recorded configurations, not a new qualification of current source. Older worktrees and external artifacts are not branch bases or active work queues.

Current source-helper type limits are documented in [local helpers](../docs/local-helpers.md), and provider/enum limits in [type providers](../docs/type-providers.md). Additional analysis or representation changes need a concrete consumer and the [optimization review](../docs/optimization.md). Retained upstream reproducers establish behavior of their pinned tools; an upstream merge does not establish adoption by the installed binary. The source audit still reports inherited contract gaps, and no generated HTML documentation build is supplied.
