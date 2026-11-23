# Partitioned actor reductions

An offloaded reduction collects contributions outside the destination actor's mailbox and state RAM. Once its complete population arrives, one executor visit validates the aggregate, runs the completion callback and enters the next phase. The Erlang actor API and wire messages are unchanged.

After scheduling the partition, select eligible families with `hls_partition_reduction:attach(LogicalPlan, Partition, #{Family => source_fragments})`. Compile each module using the options returned by `hls_partition_reduction:requirements/1`; selected modules require `aggregate_only`. Every instance of a compiled module must use the same reduction mode.

Selection applies the public source-fragment proof to the complete logical topology before distributing its storage. Contributions must form a fixed, inverse-closed exchange, originate only from the proved entry prefixes, and depend only on their messages. The application's reduction windows must remain coherent, and their completion must commute with unrelated ordinary mail. These are the existing offload assumptions, not properties inferred from a successful simulation.

Each destination receives local and remote contributions over its existing ordered lanes. Aliased source ports occupy consecutive positions in that lane's reduction window. Each position has bounded, ordered storage. A lane with one position feeds the collector directly; aliased lanes split into separate queues for the current and following windows. Direct lanes retain the removed staging capacity upstream. Incoming lanes from one peer share a depth, so this can also enlarge ordinary queues on that peer. A token from the destination's committed opening batch prevents an aggregate from overtaking its open operation. No transport credit is shared across lanes or devices.

The collector waits for the full population before invoking the public typed fold. Key/member validation and absorbing reduction failures retain their existing semantics: a failed fold does not release the actor before the other contributions arrive. A missing contribution leaves the window waiting. Ordinary messages continue through the mailbox. Reset remains coordinated; this does not implement link-failure recovery.

Public FIFO queries expose fragment and aggregate occupancy; actor queries expose committed reduction state. Partial offloaded progress is not reflected in the actor's remaining count. Capture the FIFO channels alongside actor writes when interpreting [timing profiles](profiling.md).

## Effect publication

A proved reduction prefix may publish one contribution per distinct destination lane in the same clock. Ports which alias the same lane remain in source order. Publication advances through contiguous portions of the original prefix, ending each portion before a destination repeats; a later blocked effect therefore cannot prevent an earlier effect from being attempted. A blocked destination may let other lanes accept their current contribution; it cannot duplicate them, release the actor's batch reservation, or let the ordinary tail overtake the prefix. Ordinary effects still use the actor's serial router.

This changes publication timing, not reducer membership, per-lane capacity, or the number of outstanding batches per actor. It does not provide additional write ports to ordinary mailbox RAM. The observer retains an independent payload and acceptance event for each output lane; simultaneous events imply no causal order between lanes.
