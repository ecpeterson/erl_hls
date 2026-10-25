%%%% xls_clause_lower.hrl
%%%%
%%%% Internal expression-lowering state shared by xls_clause_lower and the
%%%% actor-specific callback lowerers.

-record(clause_state, {
    anonymous_counter = 0 :: integer(),
    named_counters = #{} :: #{string() => integer()},
    %% Scalar provenance is local to this clause/branch and never reconstructed from text.
    expressions = #{} :: xls_expr_ir:definitions(),
    bindings = #{} :: #{atom() => xls_clause_lower:printable()},
    unsafe_bindings = #{} :: #{atom() => erl_anno:location()},
    live_bindings = #{} :: #{atom() => true},
    %% hls_failure::Code expressions in reverse evaluation order.
    failures = [] :: [xls_clause_lower:printable()],
    statements = [] :: xls_clause_lower:printable(),
    reference = none :: none | xls_clause_lower:ir(),
    state_name = undefined :: undefined | atom(),
    enum_atoms = #{} :: #{atom() => xls_clause_lower:printable()}
}).
