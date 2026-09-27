%%%% phenom_data_cell.erl
%%%%
%%%% One data-qubit noise source for a periodic phenomenological-noise mesh.

-module(phenom_data_cell).
-moduledoc """
A source-aware data-qubit cell for a small phenomenological-noise experiment.

## Protocol

The cell begins in `configuring`. A one-shot configuration supplies a nonzero
PRNG seed, a `u32` Bernoulli threshold, and the cell's lattice coordinate.
Neighbor queries which arrive before that configuration are retained in the
bounded mailbox.

In `collecting`, the cell accepts one query for its current step from each of
the four logical directions. The source masks identify edges rather than
processes, so a small periodic CPU topology may connect more than one edge to
the same PID. Duplicate, invalid, and stale queries fail the cell. A query for
the immediately following step is postponed.

The fourth distinct query normally advances `hls_prng:xorshift32/1` exactly
once. The round reports an error when the next random word is less than the
configured threshold. Each present binary event is interpreted as Pauli Y and
multiplied into the cell's cumulative Pauli frame. Endpoint-local
`pauli_update` messages multiply decoder corrections into that same frame.
Entering `reporting` casts the event to all four adjacent syndrome cells, with
each message labelled by the incoming edge as seen by its recipient.

A `noise_cutoff` names the first quiet step. It is consumed immediately when
received ahead of that step; at and after the boundary the actor injects zero
noise and stops advancing its PRNG. Every data reply carries that persistent
quiet state through the downstream syndrome and phi status, certifying the
whole noise neighborhood.

Once the cutoff has applied, a controller may inspect whether the stable
cumulative Pauli anticommutes with a requested measurement. This is a
nondestructive read of the simulator's classical Pauli accumulator, not a
physical qubit measurement. A memory experiment uses one basis; inspecting a
complementary basis represents a separate reset and run. A query has no round
number and is accepted from either protocol phase. The short `replying` phase
emits the reply immediately, then preserves whether the data protocol was
collecting the current round or reporting the preceding one. Further
same-basis queries repeat that phase boundary and therefore preserve reply
order.

This cell still models one binary physical-error event per round. Applying
decoder corrections is endpoint-local; the topology controller remains
responsible for ordering all correction updates before admitting a final
logical query.
""".

%% Shared protocol implementation; the default has four spatial neighbors.
-include("phenom_data_cell_impl.hrl").
