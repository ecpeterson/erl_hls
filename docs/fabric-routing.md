# Local service routing

`priv/rtl/fabric/hls_fabric_ingress.v` and `hls_fabric_egress.v` multiplex independent services on one device. A physical packet starts with `{source[15:0], destination[15:0]}`, followed by the service's unchanged frame through `TLAST`. Routing does not interpret application tags, transaction IDs, or payload lengths. Endpoint IDs are transport addresses, not Erlang PIDs.

Both modules use `PORTS` and a packed `ENDPOINTS` table. The least-significant 16 bits name port zero. For example, `.PORTS(3), .ENDPOINTS({16'd42,16'd9,16'd2})` assigns ports 0, 1, and 2 to endpoints 2, 9, and 42. IDs must be unique; duplicate IDs and invalid port counts fail elaboration/simulation. Set the table explicitly when changing the port count. The verification matrix covers 1, 2, 3, 5, and 8 ports; larger configurations need their own implementation-cost review.

## Receive path

Ingress consumes the route word, then presents the remaining stream on exactly one bit of `m_valid`. `m_data`, `m_keep`, `m_last`, and `m_source` are shared buses; only the selected port's ready signal participates in the handshake. The source is captured from the route word and remains associated with that packet. A service that needs a return address must retain this metadata with its accepted request. Sampling the latest source when a delayed reply is produced is not sufficient.

Unknown destinations, partial route words (`s_keep != 4'hf`), and route-only packets reach no service. An invalid unterminated route drains through the actual `TLAST`, regardless of whether its payload resembles another route. `route_error` reports a rejected routing handshake: 1 for a partial route word, 2 for an unknown destination, and 3 for a route-only packet, in that precedence order. It is a one-handshake observation, not a queued error response or acknowledgement of application execution.

Payload keep masks pass through unchanged. The router does not buffer an entire packet and cannot retract an already forwarded prefix. Word-only application adapters still require full-word payloads; [application framing](application-framing.md) describes their length checks and admission ownership. Debug services can validate the keep masks they receive. Missing `TLAST` requires coordinated reset/abort; no timeout or header heuristic reconstructs a lost boundary.

Ingress has no payload storage. Its ready path connects the selected sink to the source, and its data path is combinational after the registered route decision. A source must keep valid and all beat fields stable while stalled, and must not wait for ready before asserting valid.

## Transmit path

Egress accepts the first offered beat from the next round-robin contender into one register. It captures that beat's `s_destination` and takes the source from the selected `ENDPOINTS` entry. It then emits a full-word route, the saved first beat, and the rest of that endpoint's stream. Destination metadata is required only on the first beat, including while that first beat is stalled. Data, keep, and last obey the ordinary hold-until-ready contract on every beat.

Only the owner can transfer until its final beat is accepted by the shared sink. A gap in the owner's valid signal does not relinquish its grant. A stalled route or payload is stable. No other endpoint is prefetched while a packet owns the output. Independent receive/transmit instances and independent application/debug streams have separate ownership.

After a completed packet, selection starts at the next port and wraps, skipping absent requesters. A continuously offered packet can be preceded by at most `PORTS - 1` other selections once arbitration is available. If it arrives while a packet already owns the stream, that packet may also need to finish. These are packet bounds: eventual service additionally requires the shared sink to accept beats and every selected source to terminate its packet. There is no finite cycle bound for an arbitrarily stalled or unterminated owner. Ingress likewise has head-of-line blocking while its selected destination is stalled.

With continuous source and sink availability, a packet containing `L >= 1` service beats uses `L + 2` clocks: one first-beat acceptance cycle, one routing beat, and `L` emitted service beats. Consecutive packets therefore have one output bubble between them; within a packet the body can transfer one beat per clock. Storage is one 37-bit beat, a 16-bit destination, and control state, independent of packet length. Synthesis removes unused keep/destination fields when tied to constants. This avoids per-port packet buffers but retains a combinational body mux and ready path.

Synchronous active-high reset cancels buffered words and packet ownership. Valid and ready are suppressed while reset is asserted. Reset producers, consumers, and their admission/transaction ownership together; resetting just the router can leave an endpoint waiting for the rest of an abandoned packet.

## Existing compositions

`test/rtl/regsvc_fabric_fixture.sv` instantiates a configurable number of independent generated register services, each with its own passive debug monitor. The default is endpoints 1 and 2; a second live test uses 2, 9, and 42. Both application and debug replies return to host endpoint zero in this fixture. The phi memory debug wrapper uses the same router with one monitor at endpoint 1. Its application gateway retains the exact-source DSLX `EndpointIngress` and compact-frame `HostRoutedTx` serializer.

The topology debug wrapper's `hls_debug_route` has a different ownership contract: it serializes an entire request/reply transaction and retains its caller's return route until the reply finishes. It remains appropriate for those management services. The packet mux here allows independent services to have outstanding responses concurrently; it does not supply a transaction table or copy request routes into replies automatically.

A boundary TX trace records the accepted service header. The egress router may already have buffered that header while its physical output is blocked. Neither that trace event nor a host write completion proves delivery of the complete response to its final consumer. Use boundary stall counters, pending client transactions, and broker queues together when diagnosing a blocked path.

## Verification

Run `python3 tools/test_fabric_router.py --yosys YOSYS`. Deterministic simulations cover 1, 2, 3, 5, and 8 ports, non-contiguous IDs, changing destinations, partial keep masks, one-beat and long packets, contention, source gaps, sink stalls, unknown/partial/route-only routing words, long rejected drains, and reset recovery. Scoreboards compare every accepted payload beat and enforce packet ownership and the waiting bound.

For each of those port counts, Yosys temporal induction proves the ingress/egress contracts for arbitrary data, lengths, gaps, stalls, and subsequent resets, assuming one initial reset and stable unaccepted source beats. A public-port reference monitor tracks packet ownership and the one outstanding buffered beat. Explicit refinement equalities connect monitor state to implementation registers to make the property inductive; these equalities are proved, not assumed. Selection is compared with a separate circular-distance minimum. The proofs establish safety and selection policy, not unconditional liveness or correctness of connected application logic. Five deliberately faulty routers must produce bounded counterexamples using the public-port monitor without the refinement equalities.

After `rebar3 as test compile` and the normal generated-RTL build, run `python3 tools/test_fabric_services.py _build/xls_sim/regsvc`. This checks the two-service cycle-controlled scenario and a three-service host workload, including 960 concurrent pings, isolated state, variable-length replies, and public counter/trace queries while application output is blocked. It saves `blocked.term` and `recovered.term`; VPI carries external stream traffic only. CI runs both suites and retains their diagnostics.

`python3 tools/measure_fabric_router.py XLS_ROOT --baseline COMMIT --yosys YOSYS` compares the former two-endpoint XLS fixture with current routing under the same word-only interface, endpoint IDs, and fixed return destination. It also maps current one-, three-, and eight-endpoint configurations. Input hashes, compiler hashes, commands, generated RTL, synthesis logs, and a JSON count report are retained. These are isolated Xilinx 7-series mapped counts, not placed timing or whole-application area.
