%%%% xls_clause_lower.hrl
%%%%
%%%% Internal source-evaluation state shared by xls_clause_lower and its
%%%% callback, pattern and case collaborators. Renderable references and
%%%% statements use xls_dslx; compile-time phantom values remain local. This is
%%%% neither a persistent actor artifact nor the external XLS compiler IR.

-record(clause_state, {
    anonymous_counter = 0 :: integer(),
    named_counters = #{} :: #{string() => integer()},
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
