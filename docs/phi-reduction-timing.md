# Phi reduction timing

This note is the stable description of the current distance-three phi timing
path.  The historical measurements and rejected experiments remain in
`src/examples/phi_decoder/phi_phenom_topology.md`; this file describes the
present implementation and the profiler used to change it.

## Semantic work per actor and step

The paper-parameter actor performs fifteen stateful callback transactions per
decoder step:

| callback transaction | count | result |
|---|---:|---|
| measurement receipt | 1 | update the anyon and enter diffusion |
| diffusion completion | 12 | relax two phi layers and reopen the next round |
| comparison completion | 1 | select a unique best direction and enter movement |
| movement completion | 1 | update the anyon, advance the step, and request the next measurement |

Four contributions to each barrier are not actor transactions in the batched
profile.  A source scheduler emits one four-destination batch; a per-plane
reduction process folds it into destination receptacles and sends only a
completed aggregate to the destination scheduler.  The aggregate completion
nevertheless causes one ordinary actor state read, callback execution, state
write, and effect retirement.  Consequently, batching reaches the
approximately fifteen-visit floor without lowering that floor.

The current three-shard profile measures 6,156 clocks from steps 8 through 32:
256.5 clocks per step, or about 779,727 steps/s at a hypothetical 200 MHz.
Each phi scheduler owns three actors.  The complete run records about 498
state reads per actor through step 32, consistent with the fifteen callback
transactions per steady step plus startup and closeout.

## Clock path for one completed barrier

The trace records handshakes at the VPI sampling edge.  For an aggregate that
can be accepted immediately, the destination-side path is:

| relative clock | observed event |
|---:|---|
| `t` | the reduction plane sends the aggregate; the destination scheduler receives and validates it, marks the actor's private completion ready, and selects the actor |
| `t + 1` | the actor-state RAM read is accepted; the actor is now the sole in-flight actor for that slot |
| `t + 2` | the executor dispatches the completion callback; another visit to the same slot remains hazardous |
| `t + 3` | retirement writes actor state and presents the callback's entry/effect batch; a different ready actor may be selected in the same clock |

For an intermediate diffusion round, retirement includes the fused
`repeat_phase` entry: it opens the next reduction and presents the next four
neighbor sends without a second actor visit.  A scheduler router eventually
accepts those effects, obtains its effect-window reservation, and sends one
four-destination batch to the plane.  The plane polls one of its three source
ports per input opportunity.  It gives a completed output priority, folds an
accepted batch into four current/lookahead receptacles, and polls destination
rows round-robin until it finds a complete aggregate.  This elastic portion
has no fixed clock distance: it depends on the other two source schedulers and
the plane's input and output cursors.

The batched reduction path does not occupy the destination actor mailbox or a
destination mailbox producer credit.  The source still owes its scheduler
egress credit until its complete effect batch retires, and the effect-window
arbiter still prevents inter-scheduler reservation cycles.  In the measured
profile, aggregate output itself is not backpressured: every plane send is
received and accepted in the same sampled clock.

Clock 730 in the representative trace is a useful example of overlapped work.
The X plane delivers a gathering aggregate to `phi_0` actor 0 in that clock,
but the effect egress visible on the same row is **not** caused by that new
aggregate.  It retires the older visit to actor 2: that actor received its
aggregate at clock 727, read state at 728, and writes state plus an effect batch
at 730.  Actor 2 is global X-plane actor 6, at `(x = 2, y = 0)`.  Its gathering
entry emits north/east/west/south phi messages for global destination actors
`[8, 0, 3, 7]`.  The router recognizes that fixed prefix and transports all
four messages as one batch.  Two destinations belong to `phi_0`, one to
`phi_1`, and one to `phi_2`; none of the four messages enters an actor mailbox.
They update the shared X reduction plane's register-resident receptacles.

The clock-730 batch remains in the scheduler egress FIFO until router 2 accepts
and sends it at clock 736.  The six-clock interval is head-of-line waiting, not
six cycles of arithmetic.  Router 2 had sent actor 1's preceding batch into
the depth-one reduction channel at 727, and the plane did not take that batch
until 735.  On clocks 730 through 735 the router itself reports `active = 0`
and `can_receive = 1`, but its input handshake is nevertheless not ready:
XLS couples that receive to the same activation's reduction-channel send, so
the full downstream FIFO prevents the proc from firing.  The FIFO is free on
the following clock, allowing receive and send together at 736; the source
egress credit returns at 737.  The plane accepts the new batch at 738, when its
source cursor returns to shard 0.  Those four
contributions participate in aggregates sent to actors 7, 8, 0, and 3 at
clocks 746, 747, 748, and 751 respectively.  The exact completion clocks also
depend on the other three contributors and the plane's round-robin output
cursor.

## Profiler contract

`tools/run_phi_decoder_profile.sh` produces both an aggregate text profile and
a clock trace:

* `phi_decoder_profile.scheduler_profile` contains low-volume counters.
* `phi_decoder_profile.trace.csv` contains optional clock-stamped handshakes.
* `phi_decoder_profile.timeline.svg` is generated from the trace by
  `tools/phi_profile_timeline.py`.
* `phi_decoder_profile.causality.svg` aligns all six phi shards and the two
  reduction planes, with inferred directed dependencies.

The timeline tool can select a scheduler, actor slot, reduction site, and
occurrence.  For example:

```sh
python3 tools/phi_profile_timeline.py \
  _build/xls_sim/phi_decoder_profile/phi_decoder_profile.trace.csv \
  _build/xls_sim/phi_decoder_profile/gathering.svg \
  --scheduler phi_0 --site gathering --occurrence 100
```

For a causal view, the same tool can place every X and Z phi shard on a shared
clock axis and infer directed edges across the scheduler FIFOs and reduction
planes:

```sh
python3 tools/phi_profile_timeline.py \
  _build/xls_sim/phi_decoder_profile/phi_decoder_profile.trace.csv \
  _build/xls_sim/phi_decoder_profile/causality.svg \
  --all-shards --dependencies --focus-cycle 730 \
  --before 6 --after 22
```

The solid edges follow directly observed, order-preserving handshakes:
aggregate completion to state read, read to write, retirement to effect FIFO,
FIFO to router, router output to reduction FIFO, reduction FIFO to plane, and
plane to destination scheduler.  Dashed edges are the four contribution
dependencies recovered from the generated
`phi_*_reduction_destinations` tables.  The tool also draws a capacity edge
from the plane draining one batch to the router filling that one-entry channel
with its next batch.  This adds no identifier or probe bits to the synthesized
design; it uses FIFO order plus the static topology table.  A highlighted edge
label is the observed clock delta, not a promised pipeline latency.

The following counters describe the current paths:

* `aggregate_receives`, `aggregate_accepts`, `aggregate_completions`,
  `aggregate_errors`, and `aggregate_pending_cycles` observe the destination
  scheduler's aggregate port and register receptacle.  These are the
  authoritative counters for the batched design.
* Per-plane `batch_accepts` and `batch_stalls` observe the three producer
  ports; `aggregate_sends` and `aggregate_stalls` observe the three scheduler
  outputs.  A batch-stall sample is one valid/not-ready *port-clock*, so the
  sum can exceed elapsed clocks.
* `reduction_send` observes the effect router filling its reduction channel,
  and `credit_return` observes the corresponding source-credit handshake.
  `effects_wait` records clocks on which an effect bundle is present but the
  router activation cannot fire, including its active/lookahead state.  These
  trace-only probes distinguish router state occupancy from downstream
  channel backpressure.
* State reads/writes, per-slot reads, selection buckets, RAM handshakes, and
  effect egress remain current physical observations.  The selection buckets
  become causal only when correlated with plane and aggregate events: `no
  actor work` says that the scheduler has no local candidate, not why its
  neighbors have not completed an aggregate.
* Sidecar reduction-RAM counters and direct-reduction-fold counters correctly
  read zero in this profile because those older paths are bypassed.  Historical
  profiles which called aggregate acceptance a `direct_reduction_fold` used a
  now-removed fallback probe and should not be compared under that name.
* Per-actor `actor_same_actor_only` attribution is intentionally unavailable
  for the decoupled executor.  The scheduler-wide `same_actor_only` bucket is
  still a valid physical hazard count.

In the current run, each of the six phi schedulers receives, accepts, and
completes 1,386 aggregates with no receive stall, pending cycle, or protocol
error.  Each plane accepts 4,165 batches and sends 4,158 aggregates with no
aggregate-output stall.  The 12,871 batch-stall port-clocks per plane expose
contention at the serialized input poller, but are not 12,871 elapsed clocks.

## Candidate phase collapses

Renaming or merging Erlang phase functions does not save a clock by itself;
phase entry is already fused into completion retirement.  A useful collapse
must remove an actor-state transaction.

1. **Diffusion continuation.**  Let a completed diffusion aggregate run a
   bounded continuation which computes the relaxation, advances the epoch,
   reopens the same reduction, and emits the next four-neighbor batch without
   returning to the ordinary actor scheduler.  Store the two phi values,
   anyon, epoch, and round in a small hot context.  Returning to the actor only
   after round twelve would reduce the steady floor from fifteen visits to
   four (measurement, final diffusion/comparison boundary, comparison/
   movement boundary, and movement/measurement boundary), depending on how
   aggressively the last three are combined.  This is the largest plausible
   cadence win.
2. **Completion-to-completion fusion.**  A comparison completion can derive
   the direction and initiate movement directly; a movement completion can
   update occupancy and emit status/measurement effects.  This removes one or
   two more visits, but touches more actor state and externally visible
   effects than the diffusion loop, so it should follow a diffusion-only
   prototype.
3. **Resident actor contexts.**  Cache several active actor rows in registers
   across barriers.  This removes RAM round trips but not callback visits.  A
   single pinned actor would block a three-actor shard while waiting for its
   neighbors, so this needs multiple contexts or a small associative hot-state
   cache.  It is complementary to, not a replacement for, the continuation.
4. **Bulk-synchronous family kernel.**  Compile the statically connected
   barrier region into a superstep engine with ping-pong field arrays.  This
   provides the clearest lower bound and exposes broad memory parallelism, but
   is the largest semantic step away from ordinary actor scheduling.

The least invasive next experiment is the diffusion continuation.  It tests
whether a generic phase-local barrier loop can remove eleven actor visits per
step before extending the mechanism to comparison or movement.  Improving the
plane input poller may shorten causal gaps, but cannot cross the fifteen-visit
floor and is therefore secondary.
