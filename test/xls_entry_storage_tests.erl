-module(xls_entry_storage_tests).
-include_lib("eunit/include/eunit.hrl").

%% Repeated fields collapse while unrelated computed bindings remain separate.
-spec storage_width_and_capacity_test() -> ok.
storage_width_and_capacity_test() ->
    Dslx = iolist_to_binary(xls_parse:to_xls("test/xls_entry_storage_fixture.erl")),
    ?assertNotEqual(nomatch, binary:match(Dslx, <<"ENTRY_EFFECT_PAYLOAD_BITS = u32:64;">>)),
    ?assertNotEqual(nomatch, binary:match(Dslx, <<"ENTRY_EFFECT_CAPACITY = u32:3;">>)),
    ?assertEqual(3, hls_actor_interface:max_entry_effects(
        hls_actor_interface:from_module(xls_entry_storage_fixture))).

%% Variable identity, not source spelling, decides whether fields may share.
-spec distinct_bindings_and_unknown_expressions_test() -> ok.
distinct_bindings_and_unknown_expressions_test() ->
    Variable = {var, 0, 'Value'},
    A = xls_entry_storage:origin(Variable, #{'Value' => {value, xls_entry_storage:identity()}}),
    B = xls_entry_storage:origin(Variable, #{'Value' => {value, xls_entry_storage:identity()}}),
    ?assertNotEqual(A, B),
    Call = {call, 0, {atom, 0, unknown}, []},
    ?assertNotEqual(xls_entry_storage:origin(Call, #{}), xls_entry_storage:origin(Call, #{})).

%% Interning and declaration order remain stable despite compiler-local identity tokens.
-spec generated_output_is_deterministic_test() -> ok.
generated_output_is_deterministic_test() ->
    Path = "test/xls_entry_storage_fixture.erl",
    ?assertEqual(iolist_to_binary(xls_parse:to_xls(Path)), iolist_to_binary(xls_parse:to_xls(Path))).
