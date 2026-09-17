# Direct mailbox observations: complete-fixture XC7 area

This compares the six-direct-actor rectangle-ingress fixture on merged main `e2857d9` (PR #124) with mailbox observations at `594cd3b`. Both configurations include the application, its routing, physical channel/FIFO probes, actor snapshots, query service, and debug route. The candidate adds committed mailbox depth, postponed count, and outstanding admission reservations. Boundary counters/event traces, board I/O, placement, timing, and power are outside this measurement.

XLS uses two pipeline stages, unit delay, input flops disabled, and output flops enabled. Yosys runs `synth_xilinx -flatten -abc9 -arch xc7 -noiopad` with matched name-scrambling seeds 1 and 2. Every mapping passes `check -assert` and `scc -expect 0`. The application enters synthesis through its preserved instrumented JSON so memory attributes survive. The [machine-readable report](direct-mailbox-2026-09-17.json) contains exact input and compiler hashes, individual runs, and distributions.

| Metric | Configuration | Best | Mean | Population variance | Worst |
| --- | --- | ---: | ---: | ---: | ---: |
| LUT | Merged main | 5713 | 5713 | 0 | 5713 |
| LUT | Mailbox observations | 5813 | 5813 | 0 | 5813 |
| FF | Merged main | 4691 | 4691 | 0 | 4691 |
| FF | Mailbox observations | 4771 | 4771 | 0 | 4771 |

The complete design adds **100 LUTs (+1.75%) and 80 flip-flops (+1.71%)**. Distributed-memory LUTs, RAMB18, RAMB36, and DSP counts are zero in every run. Best, mean, and worst are equal for those metrics too, with population variance zero.

The prediction registered before synthesis was fewer than 200 additional LUTs and 200 flip-flops across this design. The result is within that prediction. The mailbox projection derives counts from existing committed state; it adds observation logic and retained metadata, not another application mailbox or payload copy. Constants and capacity bounds optimize away many nominal wire bits. This fixture is not a per-actor cost bound, and two identical mappings do not establish behavior across arbitrary implementations.

The all-shared D3 profile's generated actor DSLX, topology DSLX, and RTL application wrapper are byte-identical to merged main, including the mailbox-enabled configuration. Their hashes are recorded in the report. The compiler projection changes to schema 4; regenerating its manifest is required. Diagnostics-disabled DSLX goldens remain unchanged.

Native simulations at pipeline depths two and three check direct-only and mixed producer/consumer placements through the public framed `hls_debug` interface. With output blocked, direct consumers report two postponed entries, one reservation, and zero free slots out of capacity three. Releasing output permits the phase change and replay; all consumers reach `done` with empty mailboxes. The wait probes identify the external stall. The rectangle-ingress fixture also passes with direct and mixed placements at both depths. Each instrumented application matches its uninstrumented RTL cycle by cycle.

The five-actor reduction regression checks pending/terminal failures and healthy completion at both depths with the expanded observation. Its independently compiled diagnostics-disabled reference emits the same application frame. A focused RTL bench checks initial publication, a blocked entry effect, and reservation publication after retirement; retention/reset and invalid-manifest tests cover the query path. These bounded comparisons do not establish equal throughput for every workload.

To reproduce, generate the baseline with its own checkout of merged main, then the candidate with this checkout:

```sh
# In the baseline checkout:
bash tools/test_mixed_topology.sh XLS_ROOT BASELINE_DIR ingress_direct
# In the candidate checkout:
bash tools/test_mixed_topology.sh XLS_ROOT CANDIDATE_DIR ingress_direct
python3 tools/measure_direct_actor_debug.py CANDIDATE_DIR/ingress_direct \
  --baseline BASELINE_DIR/ingress_direct --stage AREA_DIR \
  --yosys "$YOSYS" --seeds 2 \
  --scope 'Complete six-direct-actor ingress fixture; merged main versus mailbox observations'
```
