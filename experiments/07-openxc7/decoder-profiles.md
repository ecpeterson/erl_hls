# Configurable decoder profiles

The decoder-only profile accepts rectangular phi grids, either or both decoder planes, and a scheduler shard count. It retains request-paced syndrome replay and the current phi kernel: two stored field layers, twelve diffusion rounds per step, and the existing fixed-point arithmetic. Changing the profile shape measures that fixed kernel on another graph; it does not select a different code distance or field-depth algorithm.

The default remains a 3×3 phi grid in each of X and Z, with three schedulers per plane. The DSLX generated for that default is unchanged by the configuration support. The full phenomenological data/measurement network, correction feedback, board links, and external debug gateway are excluded from the profile.

## Geometry and populations

`shape` counts phi cells **per plane**. In the full checkerboard fixture, a 4×4 physical grid has eight data qubits, eight syndrome qubits, and eight phi cells: four in each plane. The intended 4×2 physical board partition owns four data, four syndrome, and four phi cells total. A single-plane 2×2 phi profile also contains four phi cells, but has a different executor/source arrangement from a partition with two cells from each plane.

The profiles are closed periodic graphs. Reducing the rectangle and wrapping its edges is not equivalent to cutting a larger graph into board partitions: the latter retains remote neighbors and needs transport queues, credits, reset behavior, and clock-domain crossings. Population measurements are inputs to that design, not demonstrated board fits.

Small periodic graphs also have a behavioral limitation. When both dimensions are at most two, opposing ports name the same neighbor, so the unique-maximum comparison cannot select a correction. Tests still check every status and complete BEAM/RTL agreement, but use a 2×3 single-plane case and D3 for nontrivial correction coverage. The full D3 fixture remains the nondegenerate throughput reference.

## Run a profile

From the repository root, select the native XLS tools and profile dimensions explicitly:

```sh
ERL_HLS_PHI_PROFILE_WIDTH=2 \
ERL_HLS_PHI_PROFILE_HEIGHT=2 \
ERL_HLS_PHI_PROFILE_PLANES=x \
ERL_HLS_PHI_PROFILE_SHARDS=2 \
ERL_HLS_PHI_PROFILE_TRACE=0 \
bash tools/run_phi_decoder_profile.sh _build/profile-2x2-x "$XLS_ROOT"
```

Planes are `x`, `z`, or `xz` (the default). Width and height each default to three. The shell runner defaults to three shards; set fewer for populations with fewer than three cells per plane. The Erlang configuration API instead defaults to the smaller of three and the cell count. Empty planes, duplicate planes, nonpositive dimensions, unknown configuration keys, and more shards than cells are rejected.

The Erlang entry points `phi_decoder_profile_topology:topology/1`, `phi_decoder_profile_topology_dslx:to_dslx/1`, and `phi_decoder_profile_top_v:to_verilog/1` accept a map such as `#{shape => [2,3], planes => [z], shards => 2}`. Existing integer arguments retain their meanings: topology distance for the first function, shard count for the latter two. A removed plane has no XLS actors, schedulers, or RAMs; its fixed shell event output is tied inactive.

The staged `phi_decoder_profile.json` records dimensions, selected planes, shards, and actor/scheduler counts. Compilation snapshots it alongside the RTL shell and checks its dimensions and plane selection against the generated DSLX. RAM configurations, simulation parameters, and optional profiling traces use those counts. The published build manifest records the configuration and tool/source hashes.

The normal runner measures completed external events and RAM-port activity without a VPI plugin. Set `ERL_HLS_PHI_PROFILE_TRACE=1` to record optional inter-proc RAM, effect, and reduction handshakes and render their timeline. That tracer checks the generated aggregate wire layout and fails if the interface changes; it does not depend on XLS's optimized scheduler-local variable names. Actor state, mailbox/credit information, and adaptive wait inspection are available through the public debug tools on an instrumented profile.

## Validate and measure

```sh
python3 tools/test_decoder_profiles.py "$XLS_ROOT"
python3 tools/test_decoder_profiles.py "$XLS_ROOT" --cases d3
python3 experiments/07-openxc7/measure_decoder_profiles.py \
    _build/decoder-profiles/board-sized \
    _build/decoder-profiles/small-both \
    _build/decoder-profiles/small-x \
    --stage _build/decoder-profile-area
```

The integration runner compares actual BEAM actor execution with RTL under always-ready and independently stalled event outputs. It checks complete coordinate/status sets, per-actor event order and content, and stable payloads under backpressure. Cross-actor merge order is intentionally unconstrained. The default matrix covers a 2×1 two-plane population, a 2×2 two-plane population, the same 2×2 X plane alone, and a nondegenerate 2×3 Z plane. Add `--trace` to validate the optional traces and shell runner as well. CI runs the first and last with tracing, and inspects an injected stall through `hls_topology_debug` over the framed debug transport.

Area measurements reuse the D3 XC7 mapping recipe with two signal-name seeds by default, reporting best, mean, population variance, and worst. They check matched XLS tools, RAM recipe, and codegen settings across configurations. The resulting LUT/FF/BRAM/DSP counts describe the core and its scheduler RAM shell. Mapping delay is not placed-and-routed timing, and the results exclude the physical transport and additional debug gateway. Use the separately qualified D3 timing harness for historical timing comparisons.

The [2026-09-15 population report](results/decoder-populations-2026-09-15.md) records the first four-phi/eight-phi and plane-removal measurements, functional checks, and comparison with the historical D3 results.
