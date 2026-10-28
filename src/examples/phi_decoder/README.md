# Phi/noise example

Read [the experiment overview](phi_phenom_topology.md) for the protocol. The modules separate actor behavior, logical geometry, hardware profiles and host closeout:

| Layer | Modules |
| --- | --- |
| Arithmetic/types | `phi_field`, `hls_pauli` |
| Actors | `phi_halo_cell`, `phenom_data_cell`, `phenom_syndrome_cell` and their line wrappers |
| Shared actor bodies | `*_impl.hrl`; `phi_neighborhood.hrl` selects bounded geometry |
| Logical applications | `phi_noise_topology`, `phi_phenom_topology`, `phi_torus_topology`, `phi_repetition_topology` |
| Dedicated DSLX fixtures | `*_topology_dslx`; the repetition module also exposes its example profile |
| Host wire boundary | `phi_memory_boundary`, `phi_memory_wire` |
| Finite closeout | `phi_memory_experiment`, `phi_memory_runner`, `phi_memory_demo`, `phi_repetition_memory` |
| CPU transport substitute | `phi_memory_cpu_fabric` |
| Diagnostic input actor | `phi_syndrome_replay_cell` |

Actors use `hls_statem` and `hls_pack`; shared protocol records live in `include/phi_protocol.hrl`. Grid and line wrappers select compile-time geometry before including the same callback bodies. Topology modules describe logical routes; `*_dslx` callers select a profile for `xls_topology_dslx`. `phi_field.x` is a handwritten arithmetic companion, while actor/topology generated files are retained fixtures.

`phi_memory_runner` feeds decoded events into the pure experiment reducer and sends its ordered commands through either `hls_fabric` or `phi_memory_cpu_fabric`. `phi_repetition_memory` similarly returns local/peer effects for two partition runners without owning sockets. These finite workloads motivate compiler development; they are not general decoder validation or board-programming tooling.
