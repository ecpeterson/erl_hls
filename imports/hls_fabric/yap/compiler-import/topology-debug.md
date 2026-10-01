# Topology Debug implementation and validation

Maintainer reference; the [reader contract](../docs/topology-debug.md) is authoritative for usage. These details describe the current implementation and qualification procedures.

### Application memory preservation

The instrumented JSON preserves the application's cells and memory declarations, adding only observation aliases. The Verilog exporter retains synthesis attributes such as `ram_style="block"` and combines identical mux output bits before rendering writes. A shared word or byte enable therefore remains shared in the emitted RTL. Internal buses are separated at driver boundaries to avoid simulator feedback through aliases of the same packed vector; module ports stay intact. Bulky generated-source annotations (`src` and `hdlname`) remain in the JSON and are omitted from Verilog. Both representations are suitable synthesis inputs.

To check a generated application that uses RAM:

```sh
python3 tools/check_debug_memories.py _build/phi-debug/debug --map-xc7
```

The check compares memory dimensions, address origins, and synthesis attributes across the original design, instrumented JSON, and reparsed Verilog. It then maps the latter two to XC7 memory primitives and compares their counts and complete parameter sets, including initialization and collision modes. The report, source hashes, commands, and logs are retained in `memory-check/`. This stops before LUT mapping and placement; it verifies storage implementation, without measuring whole-design area or proving functional equivalence. The live regressions separately compare application behavior through stalls and recovery.

CI checks a mixed shared/direct scheduler and the complete D3 application. A small regression additionally exercises initialized distributed RAM, block RAM, byte enables, read-before-write collisions, and reset. Its negative controls require the audit to detect both lost attributes and fragmented write ports. The [RAM export qualification](../experiments/07-openxc7/results/debug-memory-export-2026-09-17.md) records the measured configurations and the scope of earlier area results.

### Complete D3 phi-memory fixture

```sh
python3 tools/build_phi_debug.py "$XLS_ROOT" --stage _build/phi-debug --yosys "$YOSYS"
python3 tools/test_phi_debug.py _build/phi-debug --stage _build/phi-debug/live
python3 tools/measure_phi_debug.py _build/phi-debug --stage _build/phi-debug/area \
  --yosys "$YOSYS" --seeds 5 --jobs 1
```

The build uses the deterministic `phi_memory_demo` workload at distance three, with one shared executor per actor family (six schedulers, 54 actors), mailbox observations enabled, and one monitor on the actual routed host boundary. It retains separately compiled production and observed applications, their DSLX/IR/RTL and build provenance. `debug/debug_top.v` is the composed deployment shell; `debug/instrumented.v` contains its application and passive aliases. The application-only Verilog renderer is `phi_memory_debug_top_v:application(Profile, Options)`; `phi_memory_gateway_dslx:to_dslx/3` forwards the optional observation channels through the gateway. The monitor-only demo renderer shares the same application body.

The live test holds the application output, queries actor and queue state, follows full queues to the external sink, and then blocks a trace reply while releasing the application. At least 512 application output beats must be accepted before the debug reader resumes, overflowing the live trace bank with explicit loss accounting. It checks the D3 result against ERTS and compares production and fully instrumented application outputs on every clock. The host uses the public clients and catalog; VPI only carries external stream words. Reports include decoded observations and output recovery cycles under that host schedule.

The production reference retains normal fail-stop actor execution and its machine-state failure field. The comparison isolates optional observation channels, query snapshots and transport, counters, and trace collection. It does not measure a hypothetical compiler that replaces diagnostic failure codes with a single failed bit.

The measurement maps both complete designs with Yosys `synth_xilinx -abc9 -arch xc7`, excluding I/O pads and clock buffers. It includes compiler-generated observation logic, shared routing, all query resources, and one boundary monitor. Distributed RAM consumes LUTs in the reported totals; BRAM and DSP are separate. The report retains source snapshots, commands, logs, and best/mean/population-variance/worst statistics. Increase `--jobs` only with memory headroom; failed jobs are reported as they complete, and successful measurements remain available. These are synthesis area estimates; they do not establish placed timing, power, or the cost of adding further monitored boundaries.

The [archived D3 measurement](../experiments/07-openxc7/results/phi-memory-debug-2026-09-13.md) includes five-seed area distributions, the public-interface stall diagnosis, and production/instrumented cycle comparison.


## Verification

`python3 tools/test_topology_debug.py` checks discovery contracts, structural noninterference, and the routed RTL protocol without XLS. `rebar3 eunit` covers manifest fingerprints, decoding, adaptive exploration, query budgets, cyclic candidates, transient waits, and timestamp regression. `python3 tools/test_sim_bridge.py` checks the real VPI transport, including debug-only mode.

The generated application integration runner takes the exporter's arguments:

```sh
python3 tools/test_topology_debug_integration.py \
  --top __ordered_egress_topology__Top_0_next \
  --stage _build/topology-debug-queries/ordered \
  _build/xls_sim/regsvc/ordered_egress_topology.v
```

It runs the Erlang client against a real Icarus/FIFO/VPI endpoint, identifies full queues, follows the external stall, and checks recovery after releasing the sink. It compares the original and diagnostic application outputs at every cycle and independently checks every FIFO occupancy with a transfer scoreboard. The same runner accepts the D3 wrapper arguments above. D3 has two sinks, so one can progress while the selected sink is blocked. CI regenerates and exercises the ordered-egress topology with its pinned XLS release.

`bash tools/test_actor_debug.sh XLS_ROOT` generates a 19-actor topology in two pipeline schedules. Public scoped queries identify failures in included helpers, an earlier bad match, explicit `fail`, and unmatched callbacks while healthy neighbors are blocked, then verify them after release. Snapshot RTL tests cover slot isolation, independent metadata updates, disabled and unused-address writes, and reset. The integration runner accepts `--actor-projection actors.json --actor-test phi` for the D3 profile and checks all 36 actors before and after release.

`bash tools/test_actor_debug.sh XLS_ROOT _build/mailbox-debug mailbox` runs a six-actor producer/consumer topology at two, three, and four pipeline stages. An external stall separates two work messages from the message that advances the consumer's phase. Public queries verify two postponed entries, then empty mailboxes and successful replay after release; CPU tests use the same consumer. The `direct_mailbox` and `mailbox_mixed` modes run the same workload at two and three stages, checking direct reservations, common capacity accounting, and placement-specific capabilities through `hls_debug`. `bash tools/test_actor_debug.sh XLS_ROOT _build/mailbox-debug-d3 phi` generates the diagnostic D3 application and checks all 36 actors under backpressure. These tests compare each generated application with and without the post-RTL query wrapper on every cycle; they do not by themselves compare independently scheduled production and diagnostic DSLX configurations.

`bash tools/test_actor_debug.sh XLS_ROOT _build/direct-actor-debug direct_reduction` checks five register-backed actors at two and three pipeline stages. Public queries distinguish a healthy incomplete reduction from a pending failed fold, inspect terminal source-located failures after the missing contributors arrive, and follow a stalled report to the external sink before release. The generated observed application and its instrumented export are compared every clock; a separately compiled diagnostics-disabled application is checked for the same complete output frame. This bounded workload does not establish equal throughput for every topology. `python3 tools/test_direct_actor_debug.py` also checks direct/mixed provider validation, passive aliasing, retained-row isolation, and reset.

## Measure diagnostic logic

The [D3 reduction-inspection measurement](../experiments/07-openxc7/results/reduction-inspection-2026-09-15.md) compares this query service with merged main using two matched seeds, including distributed-memory LUTs and the wider reply.

```sh
python3 tools/measure_topology_debug.py "$stage/topology-debug" \
  --stage "$stage/debug-area" --yosys /path/to/yosys --seeds 5
```

This compares physical-only queries with physical queries plus actor snapshots, including mailbox snapshots when selected by the supplied projection. A mailbox-enabled build also measures committed-state snapshots without mailbox retention (`actor_state`), isolating the incremental mailbox retention and selection cost. It makes application observations unconstrained inputs while retaining aliases and constants discovered during elaboration. All cases use schema 5 and the same manifest constant. The unchanged outer route adapter is excluded. It runs `synth_xilinx -flatten -abc9 -arch xc7 -noiopad` after scrambling internal names with matched seeds, retaining the generated Verilog, Yosys scripts/logs, individual logic-LUT, RAM-LUT, flip-flop, RAMB18, and RAMB36 counts, and best/mean/population-variance/worst summaries. `LUT` includes both logic and distributed-memory LUTs; a `RAM32M` or `RAM64M` occupies four SLICEM LUTs. Unknown distributed-memory primitives fail the report instead of silently disappearing from the total.

The result isolates diagnostic logic cost at its observation boundary. It does not measure complete-application area or placed/routed timing, and application-specific invariants can allow further optimization. Seed variation measures mapping sensitivity, not an unbiased statistical population. Changes to probe fanout still require timing qualification in the integrated design.

To include the boundary counters and event recorder in the same cost review, supply their generated RTL from the normal simulation build:

```sh
python3 tools/measure_topology_debug.py "$stage/debug" \
  --monitor-rtl _build/xls_sim/regsvc \
  --stage "$stage/all-debug-area" --yosys /path/to/yosys --seeds 5
```

This adds `boundary` (one routed RX/TX counter/trace monitor) and `all` (that monitor plus the selected topology/actor hooks). `--modes boundary all` restricts a run to those cases. The monitor includes its tap, XLS observer and server, snapshot-request register, and two-bank 64-event trace storage. Use `Observer` RTL lowered at two stages/II=1 and `DebugServer` at three stages/II=2, as in `tools/remote_xls_sim.sh`. The measurement uses current project RTL for the monitor shell and trace memory. Each case saves source hashes and mapping commands.

These are jointly synthesized observation-boundary components, with independent query interfaces and unconstrained application streams. They exclude application routing, debug transport arbitration, the scheduler logic that produces optional mailbox samples, and the application's own failure-handling logic. They therefore expose the cumulative instrumentation cost without claiming to be a complete deployment with every hook enabled. Whole-design synthesis and placed/routed qualification must use the actual deployed composition; multiplying the boundary-monitor cost by the number of monitored interfaces is only an estimate.

Run `python3 tools/test_actor_snapshot_formal.py --yosys /path/to/yosys` for an exhaustive eight-step comparison with a register-array reference on five bank configurations. It assumes reset on the first sampled edge and leaves later resets, writes, data, mailbox publications, and queries arbitrary. This bounded check complements the 4,096-cycle six-configuration RTL test, which includes 65-slot banks, same-edge collisions, invalid addresses, and asynchronous selection. Neither establishes physical timing closure.

For a complete direct-actor fixture comparison, run:

```sh
python3 tools/measure_direct_actor_debug.py _build/direct-actor-debug \
  --stage _build/direct-actor-debug/area --yosys "$YOSYS" --seeds 2
```

This compares the complete five-actor reduction application with physical queries against the same application with physical and semantic actor queries. It includes compiler-generated publication, snapshot retention, and query selection. It reads the preserved instrumented JSON to retain application memory attributes and reports each seed plus best, mean, population variance, and worst. The shared query transport is present in both builds; counters and event traces are absent. These are XC7 mapping estimates, not placed timing or power measurements.

The [five-actor XC7 result](../experiments/07-openxc7/results/direct-actor-debug-2026-09-17.md) records a 4.57% mean LUT increase and 129 additional flip-flops across two seeds, with no BRAM or DSP increase. The fixture has many constant metadata fields; this is not a per-actor cost bound.

The [direct-mailbox comparison](../experiments/07-openxc7/results/direct-mailbox-2026-09-17.md) measures a complete six-actor ingress design against merged main: +100 LUTs and +80 flip-flops across two matched seeds, including application routing and the query shell. `measure_direct_actor_debug.py --baseline BASELINE_DIR` compares two existing instrumented fixture directories; each must contain its `p2` build.
