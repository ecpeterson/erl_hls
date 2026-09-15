# Direct actor admission: structure, conservation, and area

This compares main `b95cce8deb8a419b5e6ffe1060cad286086f31d7` with implementation `7ac39aca07db40afdcbaa82f88f0c042f8d4836e`. The [machine-readable report](direct-admission-2026-09-15.json) retains individual mapping samples, tool/source/RTL fingerprints, and validation evidence.

The prediction before measurement was one extra state bit per direct service, modest surrounding logic changes, and unchanged D3 hardware because that profile uses shared services. The small direct-service measurement adds **one flip-flop** and saves **six LUTs on average**. The D3 RTL and its RAM assets are **byte-identical** to the merged baseline.

## Handshake and behavior

The original direct `Service` publishes a newly computed admission credit after its current receive and egress operations. Connected through an admission-controlled receiver, this creates a combinational ready/valid cycle. The original ordered-egress topology has one structural strongly connected component even though its short simulation passes.

The service now reserves capacity in `machine_step` and publishes the credit from a separate registered bit on its next activation. `Machine.admission_pending` already counts that reservation against capacity while the credit waits. The credit send uses an independent token, avoiding a dependency on the current receive or egress. The composed topology has zero SCCs and still schedules at one XLS stage. No changes are made to shared services or to mailbox capacity/accounting.

The extra activation before publishing a new reservation can delay direct-actor admission. Its cycle cost depends on the XLS schedule and backpressure; this is not a claim of unchanged direct-actor throughput. The new regression completes sixteen repeated self-sends in source order, with a final externally visible marker proving that the last self-send was received. Reset and stalls may discard an epoch's unfinished work, as before.

## Matched area screening

Both versions compile the **original small ordered-egress actor from main**, retaining its one-shot three-output workload and one-slot mailbox. This keeps the hardware comparison independent of the expanded regression fixture in this PR. The measured top is the isolated `__ordered_egress_actor__Service_0_next`, rather than the composed baseline topology with its known loop. The committed generator reproduces the measured candidate RTL exactly for that original fixture.

Both use the same native XLS tools and standard library, one pipeline stage, the `unit` delay model, unflopped inputs, flopped outputs, synchronous reset, and XLS-generated FIFOs. Each service is flattened and optimized, renamed with seed 1 or 2, then mapped with `synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf`. All four isolated mappings pass `check -assert` and `scc -expect 0`.

| Metric | Version | Best | Mean | Population variance | Worst |
| --- | --- | ---: | ---: | ---: | ---: |
| Core LUTs | Main | 55 | 56.5 | 2.25 | 58 |
| Core LUTs | PR | 49 | 50.5 | 2.25 | 52 |
| Flip-flops | Main | 17 | 17 | 0 | 17 |
| Flip-flops | PR | 18 | 18 | 0 | 18 |

Each sample has five CARRY4 cells and zero LUT RAM, BRAM, and DSPs, with zero variance. Seed 1 changes 55 to 52 LUTs; seed 2 changes 58 to 49. Mean LUT count decreases 10.62%, but this tiny service is not representative of arbitrary actor programs. These are synthesis naming seeds, not placement or stimulus seeds. Two samples provide a screening measurement, not a confidence interval. No direct-service delay, power, or placed/routed timing was measured.

## D3 and the last routed design

The decoder-only D3 profile uses three scheduler shards per plane, two pipeline stages, II=1, and no debug instrumentation. A fresh compile with matching tools, standard library, RAM configuration, and options produces identical `phi_decoder_profile.v`, `phi_decoder_profile_top.v`, and `hls_1r1w_ram.v`. The request-paced simulation again completes every coordinate through step 32, measuring **180 cycles/step** after step-8 warmup. This establishes no hardware or cycle change for this profile; repeating its synthesis and routing would not measure this fix.

The current baseline's [PR #105 mapping report](d3-reduction-failures-2026-09-15.md) records mean **124,593.5 LUTs, 83,640 flip-flops, 104 RAMB18, 16 RAMB36, and 144 DSPs**. Those are prior measurements of the same RTL, not fresh samples. Its variable-readiness result of 182.583333 cycles/step is also inherited, not rerun here.

The last placed-and-routed design remains [PR #102](d3-arbitration-2026-09-14.md): its unrenamed core mapping had **118,906 LUTs and 81,058 flip-flops**, with the same BRAM/DSP counts. Its partial-path frequency estimates were 14.46, 11.89, and 12.62 MHz (best 14.46, mean 12.99, population variance 1.1693 MHz², worst 11.89). PR #105 subsequently changed D3 without a new routing run; this PR adds no further D3 change. Missing BRAM timing and approximate register/DSP/device models mean those historical estimates do not establish a complete-design clock limit.

## Validation and limits

- All 869 EUnit tests pass.
- The repeated self-send topology passes at channel depths one and two, each with schedules 1 stage/II=1, 2/1, and 3/2. Every generated topology passes the zero-SCC structural gate. Tests check all frame bits and source order across aliased outputs, long and variable stalls, reset while holding a frame, mid-stream reset, completion, and a quiet tail.
- The standalone service passes at all three schedules with independent credit/effect backpressure, request delays, resets, and a host-side credit ledger. The completed epoch receives 16 self-requests and 65 ordered effects; the 17th credit is a legal unused reservation.
- At each schedule, a 24-step SAT check proves bounded credit conservation and stable stalled outputs. Requests carry arbitrary data but may be asserted only with a previously accepted credit; sink readiness and later resets are arbitrary. This is a safety check for the one-slot fixture, not an unbounded liveness proof or a proof for every actor/capacity.
- Public topology debug queries find an externally blocked sink from one blocked seed using eight adaptive queries, then observe release. Structural and cycle-by-cycle instrumentation noninterference checks pass. The integration tool now always rejects combinational loops.

The [pinned Linux run for the implementation](https://github.com/ecpeterson/erl_hls/actions/runs/34951136354) passes every behavioral step, including the new admission checks, existing generated/bridged regressions, and complete D3 debug composition. Its only failure is the expected Verilog digest mismatch; the golden manifest is refreshed from that run's tested artifacts. The compact DSLX goldens match. The general-purpose service's `regsvc.v` digest is unchanged.

## Reproduction

Run `bash tools/test_direct_admission.sh "$xls"` for the complete structural, simulation, bounded-formal, and debug regression. Run `ERL_HLS_PHI_PROFILE_TRACE=0 bash tools/run_phi_decoder_profile.sh "$stage" "$xls"` for the D3 compile/profile, then compare the three RTL assets against the preserved PR #105 compilation.

For the small area comparison, use separate baseline and candidate checkouts. In each, translate the original `test/ordered_egress_actor.erl` from `b95cce8` and its topology with `xls_parse:to_xls/1` and `xls_topology_dslx:emit/2`. Compile `Top` with `ir_converter_main`, `opt_main`, then `codegen_main --pipeline_stages=1 --delay_model=unit --flop_inputs=false --flop_outputs=true --use_system_verilog=false --reset=reset --fifo_module=`. Select the isolated service for mapping with the exact Yosys scripts retained in the JSON. The JSON abbreviates the checkout as `${REPO}`; its hashes refer to original files. Generated RTL and complete solver/synthesis logs remain build artifacts.
