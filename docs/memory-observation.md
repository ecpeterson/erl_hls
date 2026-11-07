# Observing the RAM primitive

`test_data/spacetime_memory_tb.sv` is a finite passive-observation fixture for the maintained `priv/rtl/hls_1r1w_ram.v` primitive. Two four-bit lanes model independently enabled nibbles of an eight-bit word; a response register makes a request sampled before edge C visible before edge C+2. The observer reads internal memory without initializing or writing it through hierarchy.

The 17-clock stimulus includes full and nibble-masked writes, equal-valued writes, holds, address reuse, read-first collisions, and reset retirement. Reset clears response validity while retaining RAM contents. Unknown power-on words are recorded as unknown. The only supported nonzero masks are `0x0f`, `0xf0` and `0xff`.

Run it into a fresh output directory with Icarus Verilog:

```sh
mkdir _build/memory-observation
iverilog -g2012 -s spacetime_memory_tb -o _build/memory-observation/sim \
  priv/rtl/hls_1r1w_ram.v test_data/spacetime_memory_tb.sv
vvp _build/memory-observation/sim +TRACE=_build/memory-observation/trace.term
```

The caller owns output retention. The recorder's success marker means the finite stimulus and complete recording finished; it does not check every recorded value. The optional [hls_spacetime memory witness runner](https://github.com/ecpeterson/hls_spacetime/blob/main/docs/memory-witness.md) checks the recording, converts it into a cycle/version graph and exercises rejecting corruptions. That library remains separate from compiler and deployed-runtime dependencies.

This is a simulation witness of the supplied primitive and fixture. It does not establish native BRAM inference, placement, physical timing, or correctness for all inputs. Keep the primitive and its testbench here; generic observation validation, physical import and rendering belong to `hls_spacetime`.
