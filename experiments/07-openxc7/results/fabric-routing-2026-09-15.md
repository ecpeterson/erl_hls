# Configurable local routing: mapped area

The configurable ingress/egress pair maps to **95 LUTs and 43 flip-flops** for two endpoints, compared with **104 LUTs and 39 flip-flops** for the previous XLS pair fixture. The difference is −9 LUTs (−8.7%) and +4 flip-flops. Neither uses distributed RAM or BRAM. This is the isolated router, not the full register service or D3 application.

Before synthesis, the prediction was that registers would decrease and LUTs might decrease. The register prediction was wrong: the previous XLS router was already compact. The current implementation stores one first beat independently of output readiness; the shared output can stall while the endpoint's public TX-header event has already occurred.

| Version | Endpoints | LUTs | Flip-flops | RAM |
| --- | ---: | ---: | ---: | ---: |
| Main, XLS pair | 2 | 104 | 39 | 0 |
| Configurable | 1 | 54 | 40 | 0 |
| Configurable | 2 | 95 | 43 | 0 |
| Configurable | 3 | 139 | 47 | 0 |
| Configurable | 8 | 266 | 53 | 0 |

The comparison starts from `8b64d1a` and compiles its `PairIngress` and `PairEgress` with the same native XLS tools: one pipeline stage, unit delays, input flops disabled, output flops enabled, and active-high reset. The common wrapper exposes the same 33-bit word/last channels on both versions, ties keep to full words, fixes return destination to zero, and uses endpoint IDs 1 through N. This matches the former pair's capabilities; variable return addresses and preserved partial payload keep masks are not charged to that comparison. Unused source metadata and rejection observations are pruned on the new ingress.

Yosys `0.69+10 (370a53acf-dirty)` runs `synth_xilinx -family xc7 -flatten -noiopad -noclkbuf`. Counts include every LUT type and flip-flop; no I/O or clock-buffer cells are included. This deterministic mapping is run once per configuration. There are no placement seeds or distributions to summarize, and no claim about timing, power, or whole-design placed area. The larger configurations expose mux/arbitration scaling; they are not extrapolations from the two-port result.

The egress has one first-beat register shared by all ports. Two priority scans select the next requester without a variable-index lookup at each cursor offset. First-beat capture and body forwarding share the same wide payload selector. With ready sources and sink, an L-beat service packet costs L+2 clocks, including the routing word and one selection cycle. The router retains ownership through source gaps and output stalls, so fairness is measured in completed packets, conditional on each owner eventually terminating and the sink eventually accepting.

Reproduce with:

```sh
python3 tools/measure_fabric_router.py XLS_ROOT \
  --baseline 8b64d1a --yosys YOSYS --stage _build/frame-router/area-final
```

The companion [JSON report](fabric-routing-2026-09-15.json) records source/tool hashes and cell counts. The stage retains baseline DSLX and generated RTL, common interface wrappers, synthesis scripts, mapped JSON, and logs. `docs/fabric-routing.md` describes the current protocol and verification contract.

## Taxi comparison

The [Taxi AXI-stream arbiter mux](https://github.com/fpganinja/taxi/blob/master/src/axis/rtl/taxi_axis_arb_mux.sv) supports packet-locked round-robin selection, sideband preservation, input buffering, and a registered output/skid path. Its [demux](https://github.com/fpganinja/taxi/blob/master/src/axis/rtl/taxi_axis_demux.sv) handles selection/drop and frame locking. Our on-wire routing word would still need a parser/serializer around these components.

Taxi uses SystemVerilog interfaces and interface arrays. Adopting it would require an interface-capable frontend or adaptation in the current plain Verilog Icarus/Yosys flow; this review did not compile or benchmark Taxi. Its [published licensing choices](https://github.com/fpganinja/taxi#license) are CERN-OHL-S-2.0 or a commercial license, which is also a dependency decision for downstream designs. No Taxi code is included here. The small local router stays within the existing toolchain and has its own safety proofs; this is not a performance comparison with Taxi.
