-module(hls_protocol_wait_graph_tests).
-moduledoc "Finite graph-ranking checks, independent of source execution or hardware.".
-include_lib("eunit/include/eunit.hrl").

%% Two independent senders can publish concurrently; only both captured values precede collection.
-spec independent_senders_test() -> ok.
independent_senders_test() ->
    {ok, #{ranks := Ranks}} = hls_protocol_wait_graph:check([a, b, collect, release],
        [edge(collect, a), edge(collect, b), edge(release, collect),
         reuse(a, release, a_slot), reuse(b, release, b_slot)]),
    ?assert(maps:get(a, Ranks) < maps:get(collect, Ranks)),
    ?assert(maps:get(b, Ranks) < maps:get(collect, Ranks)).

%% A real same-generation publication/receipt cycle is rejected even if other storage edges are marked.
-spec current_generation_cycle_test() -> ok.
current_generation_cycle_test() ->
    ?assertMatch({error, {same_generation_wait_cycle, _}},
        hls_protocol_wait_graph:check([a, b], [edge(a, b), edge(b, a)])),
    ?assertMatch({error, {same_generation_wait_cycle, _}},
        hls_protocol_wait_graph:check([a], [edge(a, a)])).

%% Missing endpoints and arbitrary generation skips must not manufacture a progress certificate.
-spec incomplete_model_test() -> ok.
incomplete_model_test() ->
    ?assertEqual({error, empty_event_graph}, hls_protocol_wait_graph:check([], [])),
    ?assertEqual({error, duplicate_event_identity}, hls_protocol_wait_graph:check([a, a], [])),
    ?assertEqual({error, {unknown_prerequisite, missing}},
        hls_protocol_wait_graph:check([a], [edge(a, missing)])),
    ?assertMatch({error, {invalid_wait_edge, _}},
        hls_protocol_wait_graph:check([a, b], [(edge(a, b))#{lag := 1}])),
    ?assertMatch({error, {invalid_wait_edge, _}},
        hls_protocol_wait_graph:check([a, b], [(reuse(a, b, slot))#{lag := 2}])).

%% Compiler-declared sender order is a current-generation prerequisite, never a global inbox order.
-spec sender_order_test() -> ok.
sender_order_test() ->
    {ok, #{source_refinement := unestablished, ranks := Ranks}} =
        hls_protocol_wait_graph:check([first, second], [(edge(second, first))#{kind := sender_order}]),
    ?assert(maps:get(first, Ranks) < maps:get(second, Ranks)).

%% Test records use the public graph schema, independent of the sorting implementation.
-spec edge(term(), term()) -> map().
edge(Waiter, Prerequisite) -> #{waiter => Waiter, prerequisite => Prerequisite, lag => 0, kind => dependency}.
%% Reuse waits cross at least one logical generation after a named resource was released.
-spec reuse(term(), term(), term()) -> map().
reuse(Waiter, Prerequisite, Resource) ->
    #{waiter => Waiter, prerequisite => Prerequisite, lag => 1, kind => storage_reuse, resource => Resource}.
