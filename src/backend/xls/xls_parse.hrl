%%%% xls_parse.hrl
%%%%
%%%% Internal expression-lowering state shared by xls_parse and the
%%%% actor-specific callback lowerers.

-record(clause_state, {
    anonymous_counter = 0 :: integer(),
    named_counters = #{} :: #{string() => integer()},
    bindings = #{} :: #{atom() => xls_parse:printable()},
    unsafe_bindings = #{} :: #{atom() => erl_anno:location()},
    live_bindings = #{} :: #{atom() => true},
    failures = [] :: [xls_parse:printable()],
    statements = [] :: xls_parse:printable(),
    reference = none :: none | xls_parse:ir(),
    state_name = undefined :: undefined | atom(),
    enum_atoms = #{} :: #{atom() => xls_parse:printable()}
}).
