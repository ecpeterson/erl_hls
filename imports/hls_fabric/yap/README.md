# Maintainer working material

Use [docs/](../docs/README.md) for supported behavior. Keep design exploration here and retained measurements in the [external artifact archive](../docs/artifacts.md), outside repositories.

- [Decoder service investigations](decoder-service-investigations.md): objectives, workload gates and deferred alternatives.
- [Topology specialization](topology-specialization.md): completed campaign, selected physical baseline and remaining obligations.
- [Architecture options](physical-architecture-options.md): approved physical-locality/protocol plan and maintained task list.
- [Independent collectors](independent-collectors.md): historical hypotheses and outcomes through merged PR #59.
- [Node implementation](node-implementation.md), [actor PID qualification](actor-pid-validation.md), [clock crossings](clock-validation.md) and [scoped recovery](scoped-recovery.md): deployment follow-ons; each measurement retains its original scope.

Other experiment notes preserve original hypotheses and results. Their unchecked historical lists are not additional active campaigns; use workload acceptance and the architecture review above before selecting new work.

- [Collection communication](collection-communication.md): final placement/receiver probes and the decision to close this performance campaign.

- [Erlang source toolchain](erlang-source-toolchain.md): native source command, standard dependency packaging and independent external compilation.

- [Compiler reliability integration](compiler-reliability.md): merged compiler pin, inline source attribution, generated-source refresh and local qualification.
