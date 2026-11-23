# Virtual-node boundaries

`Notes/erl_xls/Roadmap.md` is the sole active task list. This note supports G1 (distribution semantics), G3 (routing/conformance), G4 (diagnostics) and P6 (physical deployment). [Device sessions](../docs/device-sessions.md) specify the current API; the older “define failure before recovery” sequence is superseded by managed domains.

## Supervision and ownership

`hls_fabric_sup:start_node/4` creates a temporary node supervisor. Its manager, acceptor and connection supervisor are significant temporary children with `auto_shutdown => any_significant`; losing one stops that node subtree without silently restarting its identity. Individual peer connections are temporary children of their connection supervisor, so losing one leaves other peers alive. OTP owns shutdown and partial-start rollback.

Deployment supervisors own physical brokers. Broker loss produces connection uncertainty, not proof that accepted device work failed. Managed domains additionally propagate actual endpoint death, explicitly publish fresh incarnation PIDs, and permit same-incarnation reattachment after connection loss without reviving old monitors or replaying old work. Replacing a physical broker still requires old-output exclusion and confirmed descriptor release. A new EPMD creation alone cannot fence hardware completions.

Current distribution supports authenticated protocol-v6 connections, PID/name sends, monitors/demonitors, aliases and ping. Remote links/exit propagation, RPC, spawn, sequential tracing and outgoing connections are unsupported. Extend that set only through a selected application requirement; G1 owns relationship and exhaustion semantics.

## Routed conformance boundaries — G3/P6

Finite framing, routing, backpressure, delayed-reply and exhaustion fixtures exist. They do not establish a composed proof of accepted-beat/frame conservation and per-sender order across receiver, serializer, allocator and actor admission under arbitrary legal stalls. A selected proof must state those composition assumptions and its quantified domain. Actual physical keep/TLAST, packet integrity, teardown and reset exclusion belong to P6.

The [legacy return-context contract](../docs/return-contexts.md) assumes complete valid requests and exactly one reply after request-header acceptance. A never-replying request can retain its slot indefinitely; arbitrary duplicate replies after slot reuse are outside that contract. Its busy-mask and dropped-reply outputs are not yet host-query diagnostics. The [legacy device bridge](../docs/device-bridge.md) detects specific tag/lane/length/credit faults but assumes ordered, exactly-once, uncorrupted transport; it cannot detect every dropped or duplicated complete packet.

New [domain channels](../docs/domain-recovery.md) enforce exact generation/sequence ownership, but payload integrity remains an assumption. Their guarantees do not upgrade the legacy paths. New managed streams have nonwrapping identities and output-delivery frontiers, but no automatic application retry. Arbitration preserves its documented service ordering under accepted transfers; blocked receivers and a single ordered physical lane can still cause head-of-line delay. Finite contention tests are not an unrestricted progress proof.

## Conditional diagnostics and optimization

G4 covers current context occupancy, source/transaction associations and bounded actor send/receive/failure observations when an application or investigation needs them. Failure reporting must distinguish terminal actor failure, transport loss and uncertain completion; a failed link cannot be its only reporting route.

ETF/controller allocation changes require a current carrier/proxy profile. Rewriting return-context allocation in DSLX requires a concrete maintenance or mapped-area benefit. Neither is an active optimization queue. OTP-version and physical-interface discovery belong to the selected deployment acceptance, rather than a default expansion of the signal set.
