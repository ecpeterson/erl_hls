-module(hls_partition_outbox_tests).
-moduledoc "Parallel prefix planning and a small generated RTL fixture.".
-include_lib("eunit/include/eunit.hrl").
-export([write/2]).

%% Aliasing changes rounds, never contribution count or eligibility.
-spec lanes_test() -> ok.
lanes_test() ->
    lists:foreach(fun(N) ->
        {Local, A} = fixture(N),
        Lanes = hls_partition_outbox:lanes(A, Local),
        ?assertEqual(N, length(Lanes)),
        ?assertEqual(4, lists:sum([length(P) || #{ports := P} <- Lanes])),
        ?assertEqual([], hls_partition_outbox:ordinary(A, Local)),
        ?assertEqual([], hls_partition_outbox:lanes(A, maps:remove(reduction_inputs, Local))),
        ?assertEqual(Lanes, hls_partition_outbox:ordinary(A, maps:remove(reduction_inputs, Local)))
    end, [2, 3, 4]).

%% The generated prefix gets one output per destination, not per source port.
-spec source_test() -> ok.
source_test() ->
    {Local, _} = fixture(2),
    Text = iolist_to_binary(hls_partition_outbox:support(Local)),
    ?assertNotEqual(nomatch, binary:match(Text, <<"selected_fragment_0.2 < limit">>)),
    ?assertNotEqual(nomatch, binary:match(Text, <<"count == u8:4">>)),
    ?assertNotEqual(nomatch, binary:match(Text, <<"slot: u32:0">>)).

-doc "Writes the production-generated drain into a tiny typed fixture with two, three or four destination lanes.".
-spec write(file:filename(), 2 | 3 | 4) -> ok.
write(Path, N) ->
    {Local, _} = fixture(N),
    Name = "parallel_outbox_actor_ParallelActorOutboxDrainB0S0",
    Outputs = [["fragment_", integer_to_list(I)] || I <- lists:seq(0, N-1)],
    ok = file:write_file(Path, ["import axis;\nimport parallel_outbox_actor;\n",
        hls_partition_outbox:support(Local),
        "pub proc Top {\n  config(batches: chan<parallel_outbox_actor::ScheduledEffects> in,\n",
        "    effects: chan<parallel_outbox_actor::Egress> out, credits: chan<parallel_outbox_actor::ScheduledRequest> out,\n",
        lists:join(",\n", [["    ", P, ": chan<parallel_outbox_actor::Egress> out"] || P <- Outputs]), ") {\n",
        "    spawn ", Name, "(batches, effects, credits, ", lists:join(", ", Outputs), "); ()\n",
        "  }\n  init { () }\n  next(state: ()) { state }\n}\n"]).

%% A closed four-port prefix may map its opposite directions onto two lanes.
-spec fixture(2 | 3 | 4) -> {map(), map()}.
fixture(N) ->
    Id = {family, sample, [0, 0]},
    A = #{identity => Id, module => parallel_outbox_actor, slot => 0},
    Groups = case N of 2 -> [[a, b], [c, d]]; 3 -> [[a, b], [c], [d]]; 4 -> [[a], [b], [c], [d]] end,
    Lanes = [#{id => I, source => Id, ports => Ports} || {I, Ports} <- lists:enumerate(0, Groups)],
    G = #{index => 0, actors => [A]},
    {#{lanes => Lanes, schedulers => [G], reduction_inputs => #{Id => Lanes}}, A}.
