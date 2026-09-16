-module(hls_service_contract_tests).
-include_lib("eunit/include/eunit.hrl").

contract_test() ->
    Expected = #{calls => #{query => [small, large], read => [small]}, casts => [change]},
    ?assertEqual(Expected, hls_service_contract:from_forms(forms())),
    ?assertEqual({ok, Expected}, hls_service_contract:from_module(hls_reply_fixture)).

declarations_test_() ->
    [?_assertError(Reason, hls_service_contract:from_forms(replies(Declaration)))
        || {Declaration, Reason} <- [
            {[], {hls_reply_requests, #{missing => [query, read], extra => []}}},
            {[{query, [small]}], {hls_reply_requests, #{missing => [read], extra => []}}},
            {[{query, [small]}, {read, [small]}, {change, [large]}],
                {hls_reply_requests, #{missing => [], extra => [change]}}},
            {[{query, [small]}, {query, [large]}], {duplicate_hls_reply_request, query}},
            {[{query, []}], {invalid_hls_reply_declaration, {query, []}}},
            {[{query, [small, small]}], {invalid_hls_reply_records, query, [small, small]}},
            {[{query, [missing]}], {invalid_hls_reply_records, query, [missing]}},
            {[{query, [ledger]}], {invalid_hls_reply_records, query, [ledger]}},
            {[{query, [error]}], {invalid_hls_reply_records, query, [error]}},
            {[{query, [17]}], {invalid_hls_reply_records, query, [17]}},
            {[{query, small}], {invalid_hls_reply_declaration, {query, small}}},
            {not_a_list, {invalid_hls_replies, not_a_list}}
        ]].

declarations_accumulate_test() ->
    Base = [F || F <- forms(), element(1, F) =/= attribute orelse element(3, F) =/= hls_replies],
    Declared = Base ++ [{attribute, 1, hls_replies, [{query, [small, large]}]},
        {attribute, 2, hls_replies, [{read, [small]}]}],
    ?assertEqual(hls_service_contract:from_forms(forms()), hls_service_contract:from_forms(Declared)),
    ?assertError({duplicate_hls_reply_request, query}, hls_service_contract:from_forms(
        Declared ++ [{attribute, 3, hls_replies, [{query, [small]}]}])).

both_compilers_validate_test() ->
    Forms = replies([{query, [small]}]),
    ?assertError({hls_reply_requests, #{missing := [read], extra := []}},
        hls_pack:parse_transform(Forms, [])),
    ?assertError({hls_reply_requests, #{missing := [read], extra := []}},
        xls_gs_lower:callback_arms(Forms, ledger)).

cpu_contract_test() ->
    {ok, Actor} = hls_gs:start_link(hls_reply_fixture, []),
    try
        ?assertEqual({small, 7}, gen_server:call(Actor, {read, 0})),
        ?assertEqual({small, 19}, gen_server:call(Actor, {query, 0, 19})),
        ?assertEqual({large, 23, 19}, gen_server:call(Actor, {query, 1, 23})),
        ?assertEqual({small, 23}, gen_server:call(Actor, {read, 0})),
        ?assertEqual({error, {invalid_request, call, change}}, gen_server:call(Actor, {change, 99})),
        ?assertEqual({small, 23}, gen_server:call(Actor, {read, 0}))
    after hls_gs:stop(Actor) end.

cpu_bad_reply_test() ->
    %% Exercise the adapter directly to inspect the error without spawning an
    %% expected crashing process. The callback result must pass through it.
    {ok, State} = hls_gs:init({hls_reply_fixture, [], []}),
    ?assertError({reply_contract, query, {wrong, 99}, [small, large]},
        hls_gs:handle_call({query, 2, 99}, {self(), make_ref()}, State)),
    ?assertError({badmatch, false},
        hls_gs:handle_call({query, 3, 99}, {self(), make_ref()}, State)),
    ?assertError({invalid_request, cast, query},
        hls_gs:handle_cast({query, 0, 99}, State)).

missing_proxy_contract_test() ->
    ?assertEqual({stop, {missing_hls_service_contract, ?MODULE}},
        hls_gs:init({?MODULE, [], [{fabric, self(), 1}]})).

forms() ->
    {ok, Forms} = xls_parse:parse_file("test/hls_reply_fixture.erl"),
    Forms.

replies(Declaration) ->
    [case Form of
        {attribute, Line, hls_replies, _} -> {attribute, Line, hls_replies, Declaration};
        _ -> Form
    end || Form <- forms()].
