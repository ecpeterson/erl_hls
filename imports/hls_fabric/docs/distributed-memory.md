# Distributed phi memory

The D3 regression places the existing data, syndrome and phi actors on two devices. Global coordinates, routes, PRNG seeds and the BEAM reference remain unchanged. Family row zero belongs to device 0; rows one and two belong to device 1. The direct register-backed reference and the shared-RAM placement run the same witness. Neither simulation establishes board fit or timing.

## Actor storage

RAM placement retains independent actor outboxes and local credit returns under the [shared placement contract](device-bridge.md). Choose the sharing granularity explicitly:

| Placement | Executors per device | Actors per executor, device 0 / 1 |
| --- | ---: | ---: |
| `shared` | Six, one per family | 3 / 6 |
| `coalesced` | Three, one per actor module | 6 / 12 |

`coalesced` shares data-even/data-odd, syndrome-X/syndrome-Z and phi-X/phi-Z executors. It preserves all 54 actors, both planes, routes, coordinates, startup messages, mailboxes and per-actor output reservations. The twelve-actor cap is a fixture choice; the planner accepts another bound. The retained direct/coalesced experiments compare these placements, exercising RAM requests, shared scheduling and actor debug observations alongside the application/link paths. Current [CI coverage](ci.md) selects only the noisy D2 coalesced integration with ordinary reductions.

The direct reference remains the default (`--placement direct`). Compare the complete witnesses before interpreting a resource or throughput difference; an area reduction is not permission to omit application work.

## Completion and ordering

Each noise actor receives its cutoff after configuration and before routed requests. The experiment therefore has no live-cutoff delivery race. The host consumes both devices' ordered correction/status outputs and translates each correction into a point-addressed Pauli update for the owning data actor.

Closeout requires a complete same-step quiet/empty status set from every phi actor in both planes. Per-source correction-before-status order fences earlier corrections. The host then sends one query to each device, after that device's earlier updates on the same control stream. Each actor has one control lane across targets, so its query cannot overtake its corrections. Admission to a router is not proof of execution; the measurement reply completes the request.

The host compares the full correction list, closeout step and every final data measurement with BEAM. The current D3 witness has 77 corrections, closes at step 18 and produces Z-row parity 0 ([validation](artifacts.md#historical-reports) (`experiments/results/phi-ready-arbitration-2026-09-22.md`)). Measuring X requires a fresh activation.

## Failure and inspection

The current backend treats link loss or reset as an abort of the entire experiment. Both graphs and all intervening storage restart together; partially delivered commands are never retried. See the [bridge contract](device-bridge.md) for transport assumptions.

The regression diagnoses a held link, stopped peer clock and blocked event output through public queries. It then reaches measurement, retains unread replies, and interrupts a further command inside each gateway. Broker retirement must exclude a competing open until raw descriptors close. A coordinated graph/link/transport reset permits fresh attachment; the restarted experiment must match every BEAM correction and measurement. The abandoned run uses a distinct request ID so stale measurements are rejected.

Application commands and events use [checked routed streams](application-streams.md) over real `hls_fabric` brokers. VPI carries the four public application/debug streams through simulated physical adapters; it does not inspect internal state. Out-of-band reset control retires those adapters, confirms old descriptor closure and replaces their byte FIFOs. The same lifecycle requires qualification against PS–PL DMA before board deployment.

```sh
rebar3 as test compile
python3 apps/hls_phi/tools/test_phi_memory.py "$XLS_ROOT" --stage _build/phi-memory
```

Use `--reuse-build` for another clock ratio after input/output hashes match. The shared witness permits 25 minutes for both activations and diagnostic queries (`--simulation-timeout`); each activation still has its own ten-minute progress deadline. `--clock-halves 7 3` reverses device rates. Shared runs also save actor phase, mailbox depth/free space, work-in-flight and egress-wait observations while the peer or event sink is blocked and after completion. Artifacts include deployment mappings, compiler inputs, debug observations, command counts per activation, retired transport occupancy, host queue statistics and complete BEAM/RTL witnesses.

## Resource measurements

`apps/hls_phi/tools/measure_phi_memory.py BUILD --stage OUTPUT --yosys YOSYS` maps an unchanged completed build with explicitly selected XC7 mapping seeds (`--seeds 1` suffices for an initial matched comparison). It includes both complete devices, RAM where present, application gateways, credited links, public topology/actor query services and five clock crossings per device. The pair owns one receive crossing per link direction and four host crossings per device. Reports retain all samples and their best, mean, population variance and worst cell counts; one seed does not estimate mapping variance. LUT totals include the footprint of distributed RAM but do not predict post-placement LUT sharing.

The measurement excludes optional counter/trace services, PS, DMA, Ethernet/GT, I/O pads and clock buffers. It is synthesis accounting, not placed timing or evidence that a device fits the board. Use the same toolchain, clock-crossing scope and seeds for both placements.

The [coalesced comparison](artifacts.md#historical-reports) (`experiments/results/coalesced-executors-2026-09-22.md`) records matched area and step-rate measurements against independent family outboxes. The [coordinated reference](artifacts.md#historical-reports) (`experiments/results/partition-shared-schedulers-2026-09-21.md`) retains the earlier baseline and routed timing context.

## Service profiles

`apps/hls_phi/tools/profile_phi_memory.py` measures an existing shared/coalesced build without rebuilding XLS. It runs the ordinary Erlang experiment reducer synchronously at accepted public packets: host work consumes wall time but zero simulated time. The actors remain autonomous; gateways, link framing, actor outboxes, RAM and clock crossings remain active. Every correction and final measurement must match BEAM. The report measures consecutive complete status intervals starting at round 8, ending at round 18 or earlier closeout, and records the sample count. This finite fixture does not test independently offered measurement traffic or sustained backlog.

```sh
rebar3 as test compile
python3 apps/hls_phi/tools/profile_phi_memory.py _build/phi-memory --stage _build/service
python3 apps/hls_phi/tools/plot_phi_service.py _build/service _build/service/timeline.svg
python3 apps/hls_phi/tools/plot_phi_service.py _build/service _build/service/zoom.svg --zoom-ns 1000
```

The plotter requires Matplotlib. Use `--clock-halves 4 4` for simulated 125 MHz devices, `--stalls` to restore the regression's periodic link stalls, and `--no-debug` for a query-free control. `--reuse-testbench PREVIOUS_STAGE` reuses Icarus output only after hardware-source, simulator-version and artifact hashes match. Device outputs must match their original build provenance.

VPI samples every cycle from existing debug projection signals: physical FIFO depths and committed actor state/mailbox publications. It neither reads application RAM nor drives internal signals. These are committed observations, not a trace of execution inside a handler. Sparse public debug queries independently check the reconstructed values at their capture cycles; plots never interpolate those queries into cycle histories. A credit-return FIFO's depth measures pending returns, not the transmitter's available-credit bitmap.

Profiles retain interval distributions, per-port accepted/blocked cycles, wire-word composition, time-weighted occupancy and query/tap comparisons. Timelines align both clock domains by simulation time; resource names identify actors and logical lanes. See the [service-capacity measurements](artifacts.md#historical-reports) (`experiments/results/phi-service-capacity-2026-09-22.md`) for the current bottleneck and scope.

## Board-shaped experiments

A physical board owns a 4×2 patch of the 2d×2d qubit checkerboard: four data, four syndrome and four co-located phi actors. Family indices are not physical sites. With wrapping modulo 2d, the sites are `data_even=(2X,2Y)`, `data_odd=(2X+1,2Y+1)`, `syndrome_x/phi_x=(2X+1,2Y)` and `syndrome_z/phi_z=(2X+2,2Y+1)`. `hls_phi_board_geometry` assigns boards from those sites and audits actual topology routes.

At d=2, the two boards each own twelve actors and three shared executors. East/west wrap locally; north/south share the other board and the current single peer stream. At d=6 there are 3×6 boards and four distinct neighbors per board. The geometry audit counts each logical send even when ports alias, and charges credits to the reverse direction. Its traffic budget assumes twelve field rounds, the demo's d=3 setting, and the current wire encoding; it does not qualify that round count for d=6 or qualify physical Ethernet capacity. The separate four-neighbor RTL experiment uses that same finite workload.

Both d=2 cases use ordinary quiet closeout and final measurements:

- `board_memory`: deterministic nonzero noise, correction feedback and all eight data measurements.
- `board_quiet`: zero-noise closeout at step 18, followed by all eight data measurements. It exercises the same field protocol but has no corrections.

```sh
python3 apps/hls_phi/tools/test_phi_memory.py "$XLS_ROOT" --placement coalesced --memory-case board_memory --stage _build/board-memory --build-only
python3 apps/hls_phi/tools/profile_phi_memory.py _build/board-memory --stage _build/board-profile --clock-halves 4 4
```

Use `board_quiet` in a fresh build for the zero-noise control. D3 remains this driver's default. CI explicitly selects `board_memory`, coalesced placement and ordinary reductions; the larger D3 and zero-noise controls are optional experiments. Each selected run compares with independently scheduled BEAM actors.

At d=2, each phi cell's north/south neighbors coincide, as do east/west. The decoder selects among tied maxima using its seeded pseudorandom stream, independently of arrival order, then applies its separate move coin. The [board-geometry audit](artifacts.md#historical-reports) (`experiments/results/phi-board-geometry-2026-09-22.md`) records directional traffic; the [arbitration comparison](artifacts.md#historical-reports) (`experiments/results/phi-ready-arbitration-2026-09-22.md`) measures the current complete workload.


## Four distinct neighbor links

The D6 experiment instantiates the full torus: eighteen independent devices in a 3×6 board grid, 216 actors and 36 duplex links. Every board owns twelve actors. Each north, south, east and west neighbor has its own bridge, credit state and bounded clock crossing. Local actor messages remain local. Ordinary five-word frames and one-word credit returns are unchanged; neither sender/recipient pairing nor message contents are compressed.

The default enables [source-fragment reductions](partitioned-reductions.md) and uses one executor for each of the three actor modules. `--reductions ordinary` routes individual contributions through actor mailboxes instead. `--phi-actors-per-scheduler 4`, `2`, or `1` assigns the four local phi actors to one, two, or four RAM executors; data and syndrome each retain one executor. Contribution collectors remain per actor in every offloaded configuration. Compile each setting into a fresh stage before profiling it.

```sh
rebar3 as test compile
python3 apps/hls_phi/tools/test_phi_mesh.py --xls "$XLS_ROOT" --stage _build/phi-mesh --jobs 2
python3 apps/hls_phi/tools/profile_phi_mesh.py _build/phi-mesh --stage _build/phi-mesh-profile
python3 apps/hls_phi/tools/plot_phi_service.py _build/phi-mesh-profile _build/phi-mesh-profile/timeline.svg --devices 0
```

For congruent boards, `--tiles` compiles one [shared RTL tile](tiles.md) and binds board-specific constants in separate wrappers.

Compilation is resumable: rerun the same build command to verify and reuse completed devices. Its source/tool hashes must still match. Failed partial devices remain available for diagnosis; remove only the failed device directory before retrying. After checking passive instrumentation and combinational loops, the builder removes disposable elaboration JSON and compresses verbose logs, retaining their digests alongside RTL and manifests. Profiling uses that verified RTL and does not repeat XLS compilation.

The default simulation runs all eighteen device clocks at nominal 125 MHz with differing phases, and the host at 100 MHz. Every directed link retains an elastic beat stage and an eight-word asynchronous FIFO. `--stalls` adds bounded periodic admission stalls; `--clock-half` selects another simulated half-period in ns. These are ready/valid links, without Ethernet serialization, packet overhead or propagation delay. They establish neither physical clock feasibility nor decoder quality at D6.

All corrections, closeout and 72 final data measurements must match fresh independent BEAM execution. The host reducer consumes zero simulated time, as in the two-board service profile. Every link has separate accepted/blocked accounting and payload/credit counts. The cycle trace covers all boards’ existing FIFO and committed actor projections; public queries cross-check selected resources on every board. `--devices` limits the rendered timeline, not the simulated population or captured data.

The former CI matrix retained direct/shared ordinary D3, shared offloaded D3 and noisy offloaded D2 witnesses. Those drivers remain explicit experiments; current CI runs only noisy D2 with coalesced storage and ordinary reductions. A focused collector probe checks opening order, aliased lookahead, delayed contributors, output stalls and full-population failure. A small four-peer RTL regression checks reused wire IDs, exact frame delivery and independent progress while one peer is blocked. The eighteen-board run is an explicit experiment outside the manual CI suite.

`apps/hls_phi/tools/measure_phi_mesh.py BUILD --stage OUTPUT --yosys YOSYS` synthesizes one representative complete device, including its query interface. It retains raw primitive counts and source/tool hashes. Unlike the two-device area helper, it excludes external clock-crossing FIFOs; compare results only within the same scope. The default is one matched naming seed, which does not estimate mapping variance. No placement or physical clock qualification is performed.

The [D6 measurement report](artifacts.md#historical-reports) (`experiments/results/phi-neighbor-links-2026-09-22.md`) includes the complete BEAM witness, per-direction load, interval distributions and cycle timelines.

Use `--transport` on a fresh mesh profile to record transport FIFO handshakes through the existing debug projections. `transport.json` separates idle cycles with no offered work, unavailable credits, or arbitration delays; it also reports frame wait and credit round-trip distributions. Reconstruction starts at reset and must explain every frame/credit acceptance and emitted word. This analysis currently requires unstalled links and the current packetizer; mismatches fail rather than produce an attribution.

```sh
python3 apps/hls_phi/tools/profile_phi_mesh.py _build/phi-mesh --stage _build/transport-profile --transport
python3 apps/hls_phi/tools/plot_phi_transport.py _build/transport-profile --output _build/transport-profile/transport
python3 tools/test_credit_service.py "$XLS_ROOT" --stage _build/credit-service
```

The last command measures saturated, bidirectional opaque traffic with 1/2/4/8 active lanes and 0/2/8/16/64 buffered wire stages in each direction. It isolates lane-credit and latency limits from actor execution; it does not model Ethernet packetization. See the [transport service report](artifacts.md#historical-reports) (`experiments/results/phi-transport-service-2026-09-22.md`).
