# Arithmetic and control timing probes

These local experiments compare covered register-to-register paths on the Zynq-7030 database. They do not qualify a board clock. Native timing omits RAM and registered-DSP boundaries, uses coarse DSP arcs, and lacks a qualified speed-grade model. See [the coverage audit](../timing_coverage/README.md) and [the measured campaign](../results/timing-chains-2026-09-24.md).

## Arithmetic

`probe.py` places a DSLX `main` between preserved fabric registers. Supply vector inputs, one vector result, and a fresh stage. `--stages 2` measures the existing two-stage schedule; omitting it measures the whole combinational function. `--no-dsp` avoids the native model's misleading DSP cascade delays. The runner fingerprints sources, the standard library, tools and outputs, checks clock-boundary coverage, and rejects changing inputs or RAM/SRL mappings.

For the bulk recurrence, prepare one directory containing `phi_field.x`, `hls_fixed.x`, `hls_vec.x`, and this `bulk.x`:

```rust
import phi_field;
pub fn main(a: s32, b: s32, sum: sN[34]) -> s32 {
  phi_field::relax_bulk(a, b, sum as s64)
}
```

With native XLS/Yosys, the coverage-enabled nextpnr from the audit, and the checked `xc7z030sbg485.bin` database:

```sh
python3 experiments/07-openxc7/timing_chains/probe.py \
  --source "$SOURCES/bulk.x" --stage "$STAGE/seed-1" \
  --xls "$XLS" --yosys "$YOSYS" --nextpnr "$NEXTPNR" --chipdb "$CHIPDB" \
  --no-dsp --stages 2 --seed 1
```

Use matched sources/tools/constraints for each comparison. Start with one seed; check promising or ambiguous candidates across a few seeds. These small probes identify arithmetic changes, while the complete decoder simulation checks step throughput and the full core reveals control/routing limits.

## Exact rounded division

For signed width W and a positive non-power-of-two divisor D, choose K = W + ceil(log2 D) and M = ceil(2^K/D). Then `floor((n*M + 2^(K-1))/2^K)` rounds n/D to nearest with ties away from zero.

The positive reciprocal error times any representable n has magnitude strictly below 1/(2D). A non-tie is at least that far from a half integer, so its rounding cannot change. Positive ties round upward; negative ties move just below the half integer and round downward. Power-of-two divisors have zero reciprocal error and use the separate widened signed-bias path. The DSLX product is wide enough to avoid overflow.

```sh
python3 experiments/07-openxc7/timing_chains/prove_rounding.py \
  --z3 "$Z3" --output "$STAGE/rounding-proofs.json"
```

The solver checks the integer identity for every input at 110 width/divisor combinations, plus the four-neighbor bulk range bound. Deliberately rounding the reciprocal downward or allowing a fifth neighbor must produce counterexamples. This proves arithmetic identities, not compiler correctness; the DSLX interpreter/JIT properties and full RTL comparisons provide separate checks. Removing bulk saturation was measured and rejected because it worsened the two-stage schedule.

## Control fan-out

`replicate.py` copies combinational LUT drivers and partitions their consumers without inserting state or changing latency:

```sh
python3 experiments/07-openxc7/timing_chains/replicate.py mapped.json \
  --output replicated.json --limit 64
```

The input must have one flattened top and no combinational loops. Fixed-location LUTs and clock/reset consumers are excluded. The verification substitutes each replica output with its original wire and requires exact recovery of every original cell, parameter, port and attribute. One pass can increase upstream fan-out; the consumer limit is not a global fan-out guarantee. Route the separate output with the same harness, device, constraints and seed. This remains an experiment rather than a synthesis default.

## Reusing placement

Generate and map the complete four-phi/D3 workloads with [the profile timing guide](../phi-timing.md), selecting `--part xc7z030sbg485-1`. The retained mapping manifests record source digests and exact synthesis scripts. Use the coverage-enabled native binary for the routing commands below.

For expensive full cores, retain a placement checkpoint before routing:

```sh
"$NEXTPNR" --chipdb "$CHIPDB" --json mapped.json --xdc timing.xdc \
  --seed 1 --freq 25 --no-route --write placed.json --log place.log
"$NEXTPNR" --chipdb "$CHIPDB" --json placed.json --seed 1 --freq 25 \
  --no-pack --no-place --router router2 --timing-allow-fail \
  --report timing.json --timing-coverage coverage.json --log route.log
```

The XDC must contain the same target period (40 ns here); `--freq` does not override an existing clock constraint. Replay retains placement and clock constraints but restarts the router RNG, so it need not reproduce a single uninterrupted run. Record both commands and input digests. Placement-only estimates and interrupted routes are not completed routed timing results.

Render the retained arithmetic/control comparison with Matplotlib: `python3 experiments/07-openxc7/timing_chains/plot.py experiments/07-openxc7/results/timing-chains-2026-09-24`.
