# Application RAM preservation through debug export

The debug exporter now preserves synthesis attributes and coalesces identical write-enable bits before emitting Verilog. The preserved JSON and exported RTL select the same XC7 memory configurations in the fixtures below. This closes a gap between the representation used in our area measurements and the Verilog emitted for deployment.

## Method and scope

Native Yosys 0.69+10 (`370a53acf-dirty`) runs `synth_xilinx -family xc7 -flatten -noiopad -noclkbuf -run begin:map_ffram` on each representation of the instrumented application. This includes block/distributed RAM mapping and stops before mapping remaining memories to flip-flops or running LUT mapping and placement. Each comparison requires identical multisets of primitive types and complete parameter sets, including initialization and collision modes. It also checks the memory dimensions, address origins, and synthesis attributes before mapping. Source locations and flattened-name provenance are excluded from the attribute comparison.

The [machine-readable report](debug-memory-export-2026-09-17.json) records tool versions, input digests, memory inventories, and configuration hashes. These are deterministic representation checks, not new whole-design PPA measurements; no name-scrambling seed sweep is needed. Primitive equality does not prove netlist equivalence. Separate simulations check the specified behaviors, and no placement/timing or power claim follows from these results.

## Results

| Application | Declared memories | Preserved JSON | Corrected Verilog |
| --- | ---: | --- | --- |
| Small regression | 4 | 3 RAMB18 + 6 RAM32M | Identical configurations |
| Six-actor mixed mailbox fixture | 2 | 3 RAMB36 | Identical configurations |
| Complete D3 application | 12 | 74 RAMB18 + 12 RAMB36 | Identical configurations |

The small regression includes two instances of the production 1R1W RAM, a byte-enabled block RAM, and an initialized distributed RAM with a nonzero address origin. Simulation checks all initialized rows and 1,024 randomized cycles of reads, writes, same-address collisions, port enables, request stalls, and reset. The two generated application checks reuse the public debug clients to diagnose blocked actors and queues and verify recovery; cycle comparisons cover original and instrumented application outputs.

The D3 run inspects all 54 actors, follows seven full queues to the blocked external sink, accepts 512 application beats while a debug reply is held, and matches the ERTS result. Its independently compiled production reference matches instrumented application outputs for 14,403 clocks. The run's 5,458-clock recovery interval depends on host scheduling and is not a throughput benchmark. The final export is simulated with native Icarus 12, matching CI's major version. Native validation also passes 1,102 EUnit tests and 19 existing Python/debug-tool tests.

Two negative controls distinguish the necessary export changes:

| Small regression export | RAM mapping | Audit result |
| --- | --- | --- |
| Original `opt_clean; write_verilog -noattr` | 128 RAM32M, no block RAM | Rejects missing synthesis attributes |
| Attributes retained, without `opt_reduce` | 12 RAMB36 + 32 RAM32M | Rejects changed memory configurations |
| Attributes retained, with `opt_reduce` | 3 RAMB18 + 6 RAM32M | Matches preserved JSON |

Without enable normalization, each bit of a word enable becomes a separate conditional memory write in Verilog. The subsequent read/optimization/mapping pipeline can fragment the intended ports. `opt_reduce` makes identical mux output bits aliases before emission, allowing a common word or byte write to remain common. Distinct byte enables remain independent. This uses Yosys's semantic optimization rather than editing generated Verilog text.

Export also separates internal buses at driver boundaries. The existing smaller-profile integration test exposed a zero-time simulation stall on Icarus 12 after write-enable normalization. A replay of its captured netlist reproduced the stall without the debug transport; Icarus 13 advanced normally. Driver separation lets Icarus 12 advance too, without changing module ports or introducing hardware state. The simulator issue is distinct from a logical combinational cycle. The exporter omits generated-source `src`/`hdlname` annotations from RTL while retaining synthesis attributes and the original JSON provenance; in the captured smaller profile this reduced the export from 39 MiB to 12 MiB. CI's existing timeout limits are unchanged.

The prediction registered before synthesis was that preserving attributes would restore RAM mapping, with existing JSON-based area conclusions unchanged. The first check showed that attributes alone were insufficient; enable normalization was also required. The corrected export matches both memory configurations and tested application behavior.

## Audit of earlier published costs

| Published measurement | Application synthesis input | Consequence of this export defect |
| --- | --- | --- |
| [#83 physical topology queries](https://github.com/ecpeterson/erl_hls/pull/83) | Matched flattened JSON for both full-design variants | Reported +2,994 LUT / +331 FF comparison unaffected |
| [#93 actor snapshots](https://github.com/ecpeterson/erl_hls/pull/93), [#94 source failures](https://github.com/ecpeterson/erl_hls/pull/94) | Query-only measurements replace application observations with inputs; #94's separate application comparison excludes optional diagnostics | Reported scopes unaffected |
| [#95 mailbox observations](https://github.com/ecpeterson/erl_hls/pull/95), [#96 banked snapshots](https://github.com/ecpeterson/erl_hls/pull/96) | Retained instrumented JSON for full-design measurements | Published integrated tables unaffected; archived Verilog-roundtrip exploratory runs were not the reported tables |
| [#97 complete D3 debugging](phi-memory-debug-2026-09-13.md) | Archived scripts read `instrumented.json`; its retained SHA256 matches the published report | +3.71% mean LUTs, +2,485 FF, +3 RAMB36 conclusions unaffected |
| [#115 reduction inspection](reduction-inspection-2026-09-15.md) | Isolated query hardware with application observations as inputs | +456 LUT / +55 FF scoped result unaffected |
| [#122 direct actor observations](direct-actor-debug-2026-09-17.md), [#125 direct mailbox observations](direct-mailbox-2026-09-17.md) | Preserved JSON in both comparisons; these direct fixtures have no application RAM | Published costs unaffected |

This audit concerns those published comparisons. It does not establish that an arbitrary older build synthesized from `instrumented.v` had the intended RAM layout. Regenerate exported debug RTL before using that representation for deployment or new physical measurements.

## Reproduction

```sh
python3 tools/test_debug_memories.py --yosys "$YOSYS"
YOSYS="$YOSYS" bash tools/test_actor_debug.sh "$XLS_ROOT" _build/mixed-mailbox-debug mailbox_mixed
python3 tools/check_debug_memories.py _build/mixed-mailbox-debug/p2 --yosys "$YOSYS" --map-xc7
python3 tools/build_phi_debug.py "$XLS_ROOT" --yosys "$YOSYS"
python3 tools/check_debug_memories.py _build/phi-debug/debug --yosys "$YOSYS" --map-xc7
python3 tools/test_phi_debug.py _build/phi-debug
```

CI adds the memory checks to its existing mixed-scheduler and D3 builds and retains reports, commands, and logs. The focused regression needs only Yosys and Icarus Verilog, without an XLS build.
