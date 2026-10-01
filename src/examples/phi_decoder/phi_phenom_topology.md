# Phi/noise actor topology

The phenomenological example composes data-qubit, syndrome-qubit and phi-field actors. `phi_noise_topology:topology/2` describes a periodic grid; `phi_repetition_topology:topology/2` restricts the same protocols to one periodic line. Both have CPU deployments and dedicated-actor DSLX renderers.

Each actor has its own bounded mailbox and callback state. Routes connect declared output ports to recipients; a send can stall on downstream capacity. Source seeds and coordinates are initialization data. The CPU and hardware paths use the same message codecs and reduction callbacks.

See [topology composition](../../../docs/mixed-topologies.md), [reductions](../../../docs/actor-reductions.md) and [repetition code](../../../docs/repetition-code.md). These examples exercise translation and communication; generated RTL does not imply a board-specific resource or timing guarantee.
