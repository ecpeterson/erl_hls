# Partition actor link

This two-board acceptance fixture places one typed actor on each Zynq PL and carries their private serial-credit traffic over the external 1000BASE-X link. BEAM attaches at each local application DMA boundary, injects or observes commands, and queries a separate routed debug DMA endpoint. It does not relay the actor-to-actor traffic.

```text
BEAM A ↔ DMA A ↔ actor A ↔ serial credit ↔ packet CDC ↔ 1000BASE-X
                                                               ↕
BEAM B ↔ DMA B ↔ actor B ↔ serial credit ↔ packet CDC ↔ 1000BASE-X

BEAM debug ↔ independent DMA bank ↔ routed passive monitor/trace
```

`build_link_application.py` normalizes the two-actor topology, partitions it into roles `a` and `b`, emits versioned deterministic deployment artifacts and compiles both role-specific wrappers. `application/link_board.py` joins one wrapper to the PS, paired DMA banks, passive monitor, private packet adapter and physical Ethernet endpoint. Its route report retains source identities, hard-boundary counts, partial timing and the independent LUT audit. Native timing remains implementation evidence rather than signoff.

## Private framing

`partition_link_packets` maps each complete one- or five-word serial-credit packet to one checked 60-byte Ethernet frame. The receiver requires the expected peer role, protocol version, word count and sequence. A malformed, lost or reordered frame latches a protocol fault; this bounded fixture does not implement recovery and is not a production network protocol.

The application and serial-credit ports run on the PS fabric clock. Complete packets cross into independent transmit and recovered receive domains through whole-frame CDC slots. The packet endpoint and GTX startup are inherited from the preceding Ethernet transport fixture.

## Debug boundary

DMA bank 0 carries the application attachment. Bank 1 fabric-routes endpoint 1 to a passive counter/trace monitor; its ingress removes exactly one route word and its egress restores the source/destination word. Optional endpoint 2 builds record scheduler-memory or private-packet boundary transitions without entering any application or link ready path.

`check_partition_link --debug-smoke` opens only bank 1, queries endpoint 1, checks trace consistency and requires clean driver state. It does not consume the one permitted application attachment.

## Portable checks

Prepare the pinned compiler checkout, then run:

```sh
python3 test_partition_link.py
```

The bounded simulations cover bidirectional one- and five-word private packets, sequence/boundary counters, first-transition packet observations and endpoint-1 route removal/restoration. The checker self-test covers soak bounds, role-specific frame totals and clean DMA-state parsing. These simulations are witnesses, not physical-link or CDC-timing proofs.

## Physical witness

Board A's actor emits a stage-one report and request, board B emits stage two and a reply, and board A emits stage three after the reply returns. On 2026-10-10 both roles first completed 16 ordered exchanges. They then completed two attached passes of 4,096 exchanges with a reverse-direction rendezvous between passes. Every pass reported exact cumulative frame counts, drained queues and zero rejected, expired, discarded or ignored-ack frames. The observed intervals were 12.964 seconds on A and 13.978 seconds on B.

This is a bounded sustained-load witness for the generated actors, DMA boundary, serial-credit framing, packet CDC and private Ethernet/DAC path. It is not BER, timing, arbitrary-load or restart qualification.

The generated gateway admits one identity attachment after PL reset. Stopping BEAM retires software routes but does not reset the gateway or actor graph; a later process receives the management fault until the PL image is reloaded. Multi-pass operation therefore reuses one attachment. Warm PL reload and application-level incarnation control are separate follow-on work.
