-module(xls_init_tests).
-include_lib("eunit/include/eunit.hrl").
-export([init/1]).

init({cpu_only, 42}) -> ok.

cpu_only_initialization_keeps_its_argument_test() ->
    {ok, Actor} = hls_gs:start_link(?MODULE, {cpu_only, 42}),
    hls_gs:stop(Actor).

gs_cold_start_and_restart_test() ->
    lists:foreach(fun(_) ->
        {ok, Actor} = hls_gs:start_link(xls_init_gs_fixture, []),
        try
            ?assertEqual({report, 42, 0}, gen_server:call(Actor, {query, 0})),
            gen_server:cast(Actor, {change, 99}),
            ?assertEqual({report, 99, 0}, gen_server:call(Actor, {query, 0}))
        after
            hls_gs:stop(Actor)
        end
    end, [cold, restart]).

statem_cold_start_and_restart_test() ->
    lists:foreach(fun(_) ->
        ?assertEqual({report, 51, 0, 7}, xls_init_dslx:statem_oracle(8)),
        ?assertEqual({report, 59, 0, 7}, xls_init_dslx:statem_oracle(16))
    end, [cold, restart]).

hardware_proxy_rejects_ignored_argument_test() ->
    %% Reject before contacting a fabric or registering a route.
    ?assertEqual({stop, {unsupported_hls_init_argument, [42]}},
        hls_gs:init({xls_init_gs_fixture, [42], [{fabric, self(), 1}]})).

unsupported_init_heads_test_() ->
    [?_assertException(error, {unsupported_hls_init_head, Behaviour, _, _, _},
        xls_init:clause(forms(Source), Behaviour))
        || Behaviour <- [hls_gs, hls_statem], Source <- [
            "init(Arg) -> Arg.",
            "init(_) -> 0.",
            "init([]) when false -> 0.",
            "init([Value]) -> Value."
        ]].

multiple_init_clauses_test_() ->
    [?_assertError({unsupported_hls_init_clauses, Behaviour, 2},
        xls_init:clause(forms("init([]) -> 0; init(_) -> 1."), Behaviour))
        || Behaviour <- [hls_gs, hls_statem]].

forms(Source) ->
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, Form} = erl_parse:parse_form(Tokens),
    [Form].
