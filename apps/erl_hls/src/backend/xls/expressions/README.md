# Expression lowering

Actor and server preparation call `xls_callback_lower` for ordered callback families; `xls_helpers` prepares and emits their reachable local helper functions. Both use `xls_clause_lower` to retain source evaluation order, bindings and the first selected failure.

Pattern, guard, case, binary and comparison lowerers own their respective Erlang semantics. `xls_static_integer` evaluates untyped integer constants and local aliases before `xls_literal_types` propagates expected helper/record types into the resulting literals; `xls_var_scope` annotates which bindings must survive branch joins. The adjacent `xls_clause_lower.hrl` is private shared evaluation state for clause, callback, pattern and case lowering.

[Type providers](../types/README.md) lower selected source operations through this state API. Results use deferred [DSLX documents](../emission/README.md), which [actor renderers](../actors/README.md) compose into complete artifacts. These modules do not own actor storage, topology wiring or XLS optimization.
