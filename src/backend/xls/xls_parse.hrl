%%%% xls_parse.hrl
%%%%
%%%% Internal expression-lowering state shared by xls_parse and the
%%%% actor-specific callback lowerers.

-record(clause_state, {
    anonymous_counter = 0 :: integer(),
    match_counter = 0 :: integer(),
    named_counters = #{} :: #{atom() | string() => integer()},
    statements = [] :: xls_parse:printable(),
    reference = none :: none | xls_parse:ir(),
    state_name = undefined :: undefined | atom(),
    enum_atoms = #{} :: #{atom() => xls_parse:printable()}
}).
