-module(xls_statem_mask_reduction_tests).
-moduledoc "Runtime member masks remain bounded and checked through ordinary actor lowering.".
-include_lib("eunit/include/eunit.hrl").

%% A dynamic population changes only reduction storage, not the ordinary mailbox path.
-spec mask_lowering_test() -> ok.
mask_lowering_test() ->
    Text = iolist_to_binary(xls_parse:to_xls("test_data/hls_statem_mask_reduction_fixture.erl")),
    lists:foreach(fun(Part) -> ?assertNotEqual(nomatch, binary:match(Text, Part)) end,
        [<<"expected: ReductionMembers">>, <<"expected: raw[44:50]">>,
         <<"raw: bits[74]">>, <<"state.expected & member_bit">>,
         <<"evaluated.1.2 as ReductionMembers">>, <<"import hls_integer;">>]).

%% An explicit unsigned conversion permits a bounded computed numeric member index.
-spec converted_member_expression_test() -> ok.
converted_member_expression_test() ->
    with_changed_fixture(<<"Key, Member, #parity{value = Value}">>,
        <<"Key, hls_type:as(hls_nums:u32(), Member - 1), #parity{value = Value}">>, fun(Spec) ->
            ?assertMatch(#{sites := [_]}, maps:get(reductions, Spec))
        end).

%% Materialize a focused source variation without changing the committed fixture.
-spec with_changed_fixture(binary(), binary(), fun((map()) -> term())) -> term().
with_changed_fixture(From, To, Check) ->
    Path = filename:join("_build/mask-source-check", integer_to_list(erlang:unique_integer([positive])) ++ ".erl"),
    ok = filelib:ensure_dir(Path),
    {ok, Source} = file:read_file("test_data/hls_statem_mask_reduction_fixture.erl"),
    ok = file:write_file(Path, binary:replace(Source, From, To)),
    try Check(xls_parse:actor_artifact(Path, [])) after file:delete(Path) end.
