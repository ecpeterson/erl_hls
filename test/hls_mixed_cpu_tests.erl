-module(hls_mixed_cpu_tests).
-include_lib("eunit/include/eunit.hrl").

complete_rounds_match_arithmetic_oracle_test() ->
    ?assertEqual([{report, Round, 80 * Round + 30} || Round <- lists:seq(0, 31)],
        hls_mixed_topology_dslx:cpu()).

repeated_runs_leave_the_caller_unchanged_test() ->
    %% EUnit normally traps exits. The fixture must not leak linked actor EXIT
    %% messages or late application reports into the test's own mailbox.
    Before = erlang:process_info(self(), [links, messages]),
    lists:foreach(fun(_) ->
        ?assertEqual(32, length(hls_mixed_topology_dslx:cpu()))
    end, lists:seq(1, 3)),
    ?assertEqual(Before, erlang:process_info(self(), [links, messages])).

collector_rejects_reordered_output_aliases_test() ->
    {ok, collecting, Cell} = hls_mixed_collector:init([]),
    ?assertError({badmatch, false},
        hls_mixed_collector:collecting(cast, {result, 0, 1}, Cell)).

collector_accepts_independent_worker_interleaving_test() ->
    {ok, collecting, Initial} = hls_mixed_collector:init([]),
    Results = [{result, Id, Sequence} || Sequence <- lists:seq(0, 3),
        Id <- [4, 1, 3, 0, 2]],
    {reporting, _Cell} = lists:foldl(fun(Result, {collecting, Cell}) ->
        {Phase, Next, consume} = hls_mixed_collector:collecting(cast, Result, Cell),
        {Phase, Next}
    end, {collecting, Initial}, Results).
