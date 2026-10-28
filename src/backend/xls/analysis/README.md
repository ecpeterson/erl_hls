# Source closure and value facts

Actor preparation uses `xls_hardware_source` to select the local function/type/record closure reachable from hardware callbacks. This mandatory source selection happens before semantic validation; the full original source still identifies the compilation and remains available for BEAM execution.

`xls_type_shape` and `xls_pattern_totality` check source-only shapes for contribution extraction without invoking provider lowering. `xls_known_bits`, `xls_message_bits` and `xls_message_facts` supply conservative facts about already evaluated outgoing values. [Actor entry storage](../actors/README.md) and topology/transport consumers use those facts without dropping source evaluation or failures.

`xls_phase_eval` and `xls_phase_values` infer value sets at successful callback boundaries. `xls_phase_specialize` is their opt-in source-rewrite consumer; it does not change default compilation. These facts are not reachability, protocol progress or physical-performance guarantees.

Executable source normalization and scope handling belong to [expressions](../expressions/README.md); actor semantics and storage contracts belong to [actors](../actors/README.md). Algebraic simplification and target scheduling remain the external XLS toolchain's responsibility.
