# Node implementation and follow-ups

Working material; use [node semantics](../docs/device-sessions.md) for the current contract.

## Supervision and recovery

`hls_fabric_sup:start_node/4` creates a temporary node supervisor. Its manager, acceptor and connection supervisor are significant temporary children with `auto_shutdown => any_significant`. Losing any of these stops the node subtree without silently restarting its incarnation. Individual connections are temporary children of the connection supervisor; losing one leaves the node and other peers alive. OTP owns child shutdown and partial-start rollback.

Physical brokers remain owned by the deployment's transport supervisor. Losing either broker shuts down the virtual node and all its peer connections, producing ordinary `noconnection` outcomes. The surviving broker is left intact. These failures do not prove that accepted FPGA work was unexecuted.

Reattaching to persistent brokers preserves their retirement history. Replacing the physical brokers empties that history and requires a device-work drain/reset boundary covering old output, plus confirmed descriptor release. A new EPMD creation alone cannot fence old hardware completions. Hardware reset while an adapter remains active is outside this contract.

## Follow-up experiments

- [ ] Reduce remaining ETF and controller allocation overhead, using the local carrier/proxy benchmark and the routed RTL regressions; qualify any changes to negotiated distribution flags independently.
- [ ] Define actor failure, link/exit and reset-incarnation behavior before broadening the supported distribution signal set.
- [ ] Exercise discovery and supported operations across the intended deployed OTP versions and physical interfaces.
- [ ] Expose current context occupancy and source/transaction associations through debug queries.
- [ ] Express return-context allocation and rewriting in DSLX, preserving handshake behavior and comparing mapped area; retain the structural RTL shell where appropriate.
