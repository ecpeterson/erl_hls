# Shared RTL tiles

Congruent devices can share one XLS compilation. Each device has a small Verilog wrapper that binds its startup frames, global rectangle-filter points, host address and deployment identity. The wrapper also connects the usual RAMs. Configuration is constant throughout reset and execution; there is no boot-time configuration protocol or promise of an identical bitstream.

The D6 experiment supports this mode:

```sh
rebar3 as test compile
python3 tools/test_phi_mesh.py --xls "$XLS_ROOT" --stage _build/d6-tiles \
  --tiles --phi-actors-per-scheduler 2 --link-words 4 --link-credits 4
```

Actor roles are physical positions within a 4×2 patch, separated by family. Peer ports are ordered south, east, north, west. Scheduler slots and routing use these local orders; logical actor identities and startup values retain global coordinates. Wire lane IDs are assigned once per directed peer pair, so both endpoints agree even across the torus seam. Changing arbitration order can change simulated timing; reuse does not claim cycle equivalence with the older globally numbered layout.

Every device must emit exactly the same complete graph and top-level DSLX. Different topology, scheduler counts, frame layouts or transport settings require a different tile. Smaller tori with aliased neighbors still use independent compilation. The equality check rejects incompatible placements before compiling or reusing RTL.

`_build/phi-tile-cache/` holds content-addressed compiler products. Its key covers shared DSLX, libraries, compiler binaries, standard library, RAM helper, codegen options and adapter-scheduling driver. Per-device constants and debug identities are outside that key. Retained products are checked against their digests before reuse. An incomplete or modified entry is rejected; inspect it before removing that entry and retrying. `--tile-cache` selects another persistent location.

Each board is still elaborated and instrumented separately. Its manifest binds the actual constant wrapper and logical actor names; `hls_partition_tile_debug:catalog/3` validates the physical schedule and logical mapping before constructing ordinary public debug targets. Profiles use the same mapping, including tile-local collector indices. Identical compiled RTL does not make the devices share state or clocks.

To use an installed XC7 estimator, add `--delay-model xc7_7030 --delay-table /path/to/xc7_7030.tsv` to the tile command. The default remains `unit`. The table is copied into retained compiler artifacts and its content hash participates in the cache key. The selected estimator also schedules specialized transport adapters. Unsupported shapes fail compilation; the model is an approximation to operation delay, not assembled RTL timing or a board-clock guarantee. [The D6 measurement](artifacts.md#historical-reports) (`experiments/results/phi-tile-timing-model-2026-09-26.md`) records coverage, throughput and area.
