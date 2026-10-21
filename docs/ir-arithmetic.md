# Prefix arithmetic in XLS IR

Three opt-in passes reshape long arithmetic dependencies in valid, optimized, single-function XLS IR:

- `xls_ir_increment_compare`: equality/inequality against a same-width increment by literal one becomes comparisons of at most four bits, with carries derived from the original operand's lower bits.
- `xls_ir_conditional_increment`: addition of literal one or a structurally zero-extended single bit becomes sums of at most four bits. Each higher carry depends on the original lower bits and the increment bit.
- `xls_ir_small_add`: addition of a structurally zero-extended unsigned two-to-four-bit value first computes a five-bit low-nibble sum. Higher chunks depend on its carry and the original prefix bits, rather than preceding chunk sums.

All preserve modular overflow for arbitrary binary inputs. The passes recognize zero extension and zero-prefixed concatenation, never an application-specific range or reachable-state assumption. Widths at most eight and unrecognized nodes remain unchanged. Comparison and addition operands may be reversed. Original result ids, names and location attributes survive; original arithmetic remains available to other consumers. This changes dependency structure, but is not a timing or area prediction. Later optimization can reconstruct a carry chain, so inspect the final generated circuit before measuring performance.

Each module exports `rewrite(Binary) -> {Binary, Changes}` and `write(InputPath, FreshOutputPath) -> ok`. The latter writes an adjacent JSON with source/output hashes and changes. Both output paths must be fresh; I/O failure can leave partial output. Multiple functions, procs, blocks and pass-reserved names (`hls_inc_`, `hls_wordinc_`, `hls_smalladd_`, respectively) are rejected. The text recognizers require standard optimized XLS formatting and trust XLS type validation. The ordinary compilation entry point does not enable these passes automatically.

After `rebar3 compile`, call the desired module with `_build/default/lib/erl_hls/ebin` on the Erlang code path. Run `rebar3 eunit --module=xls_ir_arithmetic_tests` for admission boundaries and `python3 tools/test_ir_arithmetic.py /path/to/xls --stage /fresh/output --yosys /path/to/yosys` for combinational proofs. The complete generated outputs are equal for every binary operand valuation in each of 36 circuits: comparison widths 1/8/9/16/31/32/33/65; addition widths 8/9/16/31/32/33/65 with one-bit and two/three/four-bit small operands. Both operand orders and all recognized encodings are covered. Each pass has a broken-prefix negative that must produce a counterexample.

The finite proofs trust fixture IR, XLS code generation, Yosys translation and SAT. They are neither an all-width theorem nor a sequential or native-performance claim. Source, tool, BEAM and input/output identities and solver logs are retained in the fresh stage. No certificate is inferred from the change audit alone.
