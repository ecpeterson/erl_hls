# Maintainer working material

`Notes/erl_xls/Roadmap.md` is the sole active task list across the project. It owns priority, status and the stable P1–P6 / G1–G8 identifiers. This directory supplies supporting designs, acceptance criteria and retained evidence; it does not select another campaign. Use [docs](../../docs/hls_fabric/README.md) for supported behavior and the [external artifact archive](../../docs/hls_fabric/artifacts.md) for measurements.

## Supporting material

| Master item | Fabric reference and scope |
|---|---|
| P1–P3: native baseline, bounded memory and sealed collection | Application consumers select concrete requirements; the generic [collection contracts](../../docs/hls_fabric/execution/actor-reductions.md) remain distinct from application result validity. |
| P4: timed acquisition | The [clock-domain contract](../../docs/hls_fabric/clock-domains.md) and [digital crossing evidence](clock-validation.md) supply existing mechanisms. They do not establish independently offered acquisition or physical CDC qualification. |
| P5 / G1: application recovery, links and collective retirement | [Current domain contract](../../docs/hls_fabric/domain-recovery.md), [recovery qualification](actor-recovery.md) and [remaining recovery boundaries](scoped-recovery.md). |
| P6 / G7: selected deployment and alternative platforms | [TE0715 evidence and acceptance boundaries](topology-specialization.md#te0715-deployment-evidence), [platform guides](../../platforms/xc7/README.md) and [conditional timing retargeting](../../platforms/xc7/yap/timing-model/retargeting.md). |
| G2 / G3: consumer-driven compiler work, bounded routing and collectors | [Source-toolchain history](erlang-source-toolchain.md), [closed bridge review](source-partition-bridge-review.md), [adapter schedules](handoff-schedules.md) and [node/conformance boundaries](node-implementation.md). |
| G4: observation and predictive models | [Inspection](../../docs/hls_fabric/execution/debug-targets.md), [passive capture](../../docs/hls_fabric/spacetime-capture.md), [spacetime working evidence](https://github.com/ecpeterson/hls_spacetime/tree/main/yap) and [node diagnostics](node-implementation.md). |
| G5: selected decoder/performance work | [Service acceptance](decoder-service-investigations.md), [closed topology campaign](topology-specialization.md), [historical architecture options](physical-architecture-options.md) and [collection stopping decision](collection-communication.md). |
| G6 / G8: pinned tools, contracts, documentation and CI | [Compiler reliability evidence](compiler-reliability.md), [source quality](../../docs/hls_fabric/source-quality.md) and [CI cost record](ci-budget.md). |

## Historical records

The post-campaign source/control-flow cleanup, typed plans, canonical identities/layouts, frame-width parameterization, package separation and experiment promotion are complete. [Retired experiments](retired-experiments-01-06.md) and [source-toolchain history](erlang-source-toolchain.md) retain their scope. The digital recovery campaign is also complete within its [finite evidence boundaries](actor-recovery.md); physical deployment and application recovery meaning are not implied.

Original experiment checklists, including the architecture, Snowflake and XC7 timing notes, preserve registered hypotheses and outcomes. Their unchecked boxes and old “next” instructions are historical records, not additional active queues or authorization to repeat completed jobs. Per-image board checklists are acceptance procedures for a selected candidate. Select any new work in the master before applying those procedures; retain failures, frozen inputs and original measurement limits.
