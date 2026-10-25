# Scalar expression IR

Clause lowering retains add/sub/xor and integer-comparison nodes until `xls_clause_lower:print/1` renders DSLX. `xls_expr_ir` records those definitions and binding aliases within each clause or branch. Opaque calls, casts, textual leaves and branch joins supply no arithmetic definition; generated text is never parsed back into operations.

This extends the existing clause IR. Source classification identifies integer comparisons, while DSLX still enforces arithmetic widths and signedness; other expression kinds remain rendered leaves. Original statements, evaluation order and eager failure checks are preserved. The representation introduces no optimization pass or compiler option. Algebraic bit-vector simplifications belong to XLS, where operand types and node identities are available.

`rebar3 eunit` checks structured lowering, alias resolution, opaque boundaries, rendering and eager failure preservation. `tools/test_comparisons.sh /path/to/xls` exercises the existing mixed-width comparison semantics through BEAM, DSLX, JIT and RTL simulation; these executions are witnesses, not universal equivalence proofs.
