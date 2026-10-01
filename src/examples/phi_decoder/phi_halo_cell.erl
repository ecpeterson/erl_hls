%%%% phi_halo_cell.erl
%%%%
%%%% One cell from a two-layer, three-dimensional phi-decoder relaxation mesh.

-module(phi_halo_cell).
-moduledoc """
An autonomous cell for a small phi-decoder protocol experiment.

## Protocol

The cell begins quiescent in `configuring`. A single nonzero seed selects its
coin stream and advances it to the four control phases with direct protocol
meanings:

  * On entering `measuring`, it asks its paired phenomenological syndrome cell
    for the detection event at the current step. The reply is XORed into the
    local anyon before diffusion begins. Halo traffic from a faster neighbor is
    postponed at this boundary, so an absent reply is never interpreted as a
    zero measurement.

  * On entering `gathering`, it casts its current two-layer phi value to each
    of four neighbors. Four phi messages complete one diffusion round. An
    intermediate round explicitly repeats `gathering`, which sends the updated
    value and releases messages for the next diffusion epoch. The final round
    moves the cell to `comparing`.
  * On entering `comparing`, it casts its final layer-zero value to each
    neighbor. Each message identifies the incoming edge as seen by its
    recipient. Four distinct sources complete the comparison and record both
    the largest neighboring value and all directions attaining it. A
    pseudorandom choice among those directions breaks ties independently of
    arrival order. The cell then moves to `flipping`.
  * On entering `flipping`, it advances a small pseudorandom generator and
    moves a local anyon toward the selected comparison winner on heads. Exactly
    one neighbor receives a present anyon update for a move; the other three
    receive an absent update. Four incoming anyon messages complete the step
    and move the cell back to `measuring`.

Phi messages carry a wrapping diffusion epoch in their first `u32` word. The
cell derives that epoch from its decoder step and diffusion round, so repeated
diffusion does not widen the 96-bit phi frame. Messages for the next diffusion
epoch or phase may arrive early. Each cell stores the absolute diffusion epoch
and advances it once per completed round. Early messages are postponed until
the phase changes or is explicitly repeated, then retried in their original
arrival order. Partial sums, receive masks, and receive counts live in
actor-owned reduction state and do not themselves retry a postponed message.
Their completion events perform the one ordinary actor-state update at each
barrier.

The generated module exposes seven separately backpressured output ports:
`north`, `east`, `west`, and `south` for the decoder mesh, `syndrome` for its
measurement source, and provisional `correction` and `status` event streams. A
physical correction belongs to the data-qubit edge between this syndrome
location and the selected neighboring syndrome location. The compact event
identifies that edge by syndrome coordinate and direction; it is not a claim
that a phi cell has only one neighboring data qubit. Status is emitted after
all four incoming moves complete the step and reports both the resulting local
anyon occupancy and the quiet certificate propagated from that step's
syndrome neighborhood. For one cell, its optional correction precedes its
status on the source-ordered egress. Complete same-step quiet and empty status
sets from both decoder planes can therefore fence all earlier correction
events. The CPU scheduler maps output names to the PIDs passed to
`start_link/1`; no recipient is hidden in the cell. To build a cyclic CPU
topology, start every cell with `start_link/0` and then call `connect/2`; its
initial measurement request runs once both connection and configuration are
complete.

The diffusion and anyon joins rely on the topology delivering exactly one
message per incoming edge in each phase. The comparison join is source-aware:
it rejects an invalid or duplicate direction instead of allowing it to satisfy
the four-way barrier. The five-slot mailbox holds one complete early barrier
plus the message which lets the current barrier advance. Direct-neighbor
causality prevents a sender from reaching a second future barrier before this
cell has emitted the message needed to release the first.

## Deliberate simplifications

This distance-three slice performs twelve diffusion rounds per anyon step. The
paper prescribes `c = 10 log^2(L)` field updates; twelve is the nearest whole
number at `L = 3`. The coin is the most-significant bit of a deterministic
`xorshift32` sequence. The lower 31 bits of the same word select among tied
maxima without consuming an extra word or changing the coin stream.
Each cell receives a nonzero seed before it begins, so a topology can give
statically instantiated cells distinct reproducible streams. The paired
syndrome input supplies nontrivial noise; its data and measurement generators
are separate actors.

An outgoing move toggles the local anyon before incoming moves are combined by
parity. Consequently, simultaneous arrivals and departures produce the same
occupancy regardless of message order. Like the reference phi implementation,
this fixture constructs and emits a correction only in the selected move
branch, after the four neighbor messages. Correction traffic scales with
applied moves rather than physical qubits and steps.

A fuller decoder needs a configurable diffusion stopping rule and richer
noise/measurement configuration. Those additions should preserve the four
genuine barrier phases; a parity-only wakeup phase would not have direct
protocol meaning.

## Field arithmetic

For the distance-three torus, reflection symmetry about the syndrome plane
makes the `z = 1` and `z = -1` values equal, so the complete field needs only
two stored layers. `phi_field` composes a fixed-size vector of signed Q15.16
scalars and owns the coupled layer recurrence.
Each recurrence widens its complete rational numerator to 64 bits, rounds once
to the nearest stored value with ties away from zero, then saturates to the
32-bit field. For the paper's `eta = 1/2`, the center plane retains `1/2` of
its old value and receives `1/12` of each of its six spatial neighbors. The
charge-free bulk layer receives the same coefficient from each neighbor; one
of its two z-neighbors is the center plane and the other is its reflected bulk
counterpart.
""".

%% Shared protocol implementation; the default has four spatial neighbors.
-include("phi_halo_cell_impl.hrl").
