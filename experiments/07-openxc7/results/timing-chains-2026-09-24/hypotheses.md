# Preregistered timing experiments

1. Replace absolute-value / unsigned division / sign restoration with widened, sign-biased signed division. Predict 10–20% shorter arithmetic path, unchanged cycles. Measure DSP and LUT-only mappings; the native DSP model charges arithmetic delay to cascade passthroughs, so absolute DSP delays are not qualified.

2. Positive offset divisible by the divisor replaces signed quotient restoration with constant subtraction; predict a further 5–10% path reduction at unchanged cycles.
3. The phi recurrence coefficients and four s32 neighbors sum to weight 12, fitting s36; narrowing 37→36 may shorten division by 5–10%, unchanged numerical results and cycles. Measure separately after signed bias.

4. Factor the static denominator into its power of two and odd parts before division. Truncating twice preserves the signed quotient. Predict 10–15% path reduction from narrower multiplier, possibly offset by extra sign correction.

5. Schedule the complete recurrence in two existing stages using XLS unit/asap7/sky130 models. Predict 10% path improvement by moving arithmetic across the existing boundary; keep depth, II and numerical results unchanged. ASIC models are heuristics here, not FPGA timing specifications.

6. Exact reciprocal rounding: for non-power-of-two D, K=W+ceil(log2(D)), M=ceil(2^K/D); floor((n*M+2^(K-1))/2^K) rounds with ties away from zero. Positive reciprocal error moves negative exact ties downward. Error magnitude is strictly <1/(2D), so no non-tie crosses a half integer. Predict 10–15% less delay than signed bias, unchanged cycles. Power-of-two denominators retain signed-bias division.

7. For even non-power-of-two D, non-ties are at least 1/D from a half integer (odd D: 1/(2D)). Reduce K by one for even D; error remains strictly below 1/D. Predict approximately 5% less delay/area.

8. Bulk recurrence is a convex weighted average (weights total 12), so its final saturation cannot fire for valid scalar inputs and four-neighbor sums. Remove only bulk saturation; retain center charge saturation. Predict 1–2 ns saved in the arithmetic tail, unchanged cycles and in-contract results.

9. Full baseline control path is 60.5 ns (4.2 logic / 56.3 routing), including a 14.2 ns control net. Replicate identical LUT drivers for bounded consumer groups, without registers or changed logic. Predict 10–25% shorter routed critical path with small area cost and identical cycle behavior. Measure one matched whole-core seed first.

10. Change only both reduction-batch queues from depth 1 / bypass to depth 2 / non-bypass. Predict at least 25% shorter executor-to-reduction path, but possibly one extra cycle per dependent step. Measure functional/step-rate effects first; reject a slower cycle schedule unless qualified full-design timing can establish net benefit.

11. Split the exact reciprocal multiply into two parallel constant-limb products and recombine, exposing an additional boundary to the existing two-stage scheduler. Predict 10–20% shorter arithmetic path at possible area cost, with unchanged cycles and exact arithmetic.

12. Use a 25-MHz placement/routing target instead of severely overconstraining the partial native model at 100 MHz. Predict easier congestion convergence and possibly at least 10% shorter covered control delay, with identical netlist/cycle behavior. This changes an optimization target, not the deployed clock. Checkpoint placement first so router retries need not repeat it.
