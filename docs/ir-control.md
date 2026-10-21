# Control identities in XLS IR

`xls_ir_control:rewrite/1` is an opt-in pass for valid, optimized, single-function XLS IR. It replaces equality or inequality of `x` with `x+y`, `x-y`, or `x xor y` by the same comparison of `y` with zero. All operands have the same finite width; overflow wraps. Reversing the equality operands is allowed; reversing subtraction's operands is not.

This removes an arithmetic dependency from the comparison while retaining the arithmetic node for its other consumers. Comparison names, ids and location attributes survive. Unrecognized lines remain unchanged. Packages with multiple functions, procs, blocks, or the reserved `hls_control_zero_` prefix are rejected. XLS remains responsible for validating input and output IR.

After `rebar3 compile`, call `xls_ir_control:write("input.opt.ir", "output.ir")` with `_build/default/lib/erl_hls/ebin` on the Erlang code path. Both output paths must be fresh. The adjacent JSON records exact input/output hashes and each cancelled dependency; it is an identity audit, not an equivalence certificate. The ordinary compiler entry point does not automatically enable this pass.

Run `rebar3 eunit --module=xls_ir_control_tests` for scope and syntax boundaries. Run `python3 tools/test_ir_control.py /path/to/xls --stage /fresh/output --yosys /path/to/yosys` for combinational proofs: all binary input valuations at widths 1, 2, 8, 12, 32, 64 and 699, add/sub/xor, eq/ne in both comparison orders, and the unchanged arithmetic result. A deliberately wrong equality sense must produce a counterexample. Logs and source/tool/BEAM hashes are retained. These checks trust valid fixture IR, XLS code generation, Yosys translation and SAT; they establish neither an all-width theorem nor timing or area improvements.
