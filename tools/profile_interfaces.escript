#!/usr/bin/env escript
%%! -noshell
-mode(compile).

%% Usage: tools/profile_interfaces.escript CHECKOUT OUTPUT.json
%% Prepare CHECKOUT with `rebar3 as test compile` first. Run the same script
%% against two checkouts to compare source parsing and topology planning.
main([Checkout0, Output0]) ->
    Checkout = filename:absname(Checkout0),
    Output = filename:absname(Output0),
    ok = file:set_cwd(Checkout),
    true = code:add_patha(filename:join(Checkout, "_build/test/lib/erl_hls/ebin")),
    true = code:add_patha(filename:join(Checkout, "_build/test/lib/erl_hls/test")),
    Cases = [{"exact_1", exact(1, 1)}, {"exact_32", exact(32, 1)},
        {"exact_256", exact(256, 1)}, {"fanout_256x8", exact(256, 8)},
        {"families_1", families(1, 8)}, {"families_32", families(32, 8)},
        {"families_32x64x64", families(32, 64)}],
    Normalization = [measure(Name, fun() -> hls_topology:normalize(Spec) end)
        || {Name, Spec} <- Cases],
    Exact = hls_topology:normalize(exact(256, 1)),
    Groups = maps:from_list([{Id, #{members => [{actor, Id}],
        state_storage => registers, mailbox_storage => registers}}
        || #{id := Id} <- maps:get(actors, Exact)]),
    Scheduler = measure("scheduler_256", fun() -> hls_scheduler_plan:normalize(Exact, Groups) end),
    Phi = measure("phi_d3_sharded_plan", fun() ->
        phi_noise_topology_dslx:scheduler_plan({phi_shards, 3})
    end),
    ok = file:write_file(Output, json:encode(Normalization ++ [Scheduler, Phi])),
    io:format("Wrote ~s~n", [Output]).

measure(Name, Fun) ->
    _ = Fun(),
    Session = trace:session_create(interface_profile, self(), []),
    try
        1 = trace:function(Session, {epp, open, 1}, true, [call_count]),
        Samples = [begin
            erlang:garbage_collect(),
            {Micros, _} = timer:tc(Fun),
            Micros / 1000
        end || _ <- lists:seq(1, 7)],
        {call_count, Reads} = trace:info(Session, {epp, open, 1}, call_count),
        Mean = lists:sum(Samples) / length(Samples),
        #{name => list_to_binary(Name), samples_ms => Samples,
            best_ms => lists:min(Samples), mean_ms => Mean,
            variance_ms2 => lists:sum([math:pow(S - Mean, 2) || S <- Samples]) / length(Samples),
            worst_ms => lists:max(Samples), source_reads => Reads / length(Samples)}
    after
        trace:session_destroy(Session)
    end.

exact(Count, Fanout) ->
    Externals = lists:sublist([out_a, out_b, out_c, out_d, out_e, out_f, out_g, out_h], Fanout),
    Ids = [{actor, N} || N <- lists:seq(1, Count)],
    (empty())#{actors := maps:from_list([{Id, hls_topology_source_fixture} || Id <- Ids]),
        externals := [{Id, out, [message]} || Id <- Externals],
        routes := [{{Id, out}, queued, [{actor, Id} | [{external, E} || E <- Externals]]}
            || Id <- Ids]}.

families(Count, Dimension) ->
    Ids = [{family, N} || N <- lists:seq(1, Count)],
    (empty())#{families := maps:from_list([{Id, #{module => hls_topology_source_fixture,
            shape => [Dimension, Dimension]}} || Id <- Ids]),
        externals := [{out_a, out, [message]}],
        route_relations := [{{Id, out}, queued,
            [{family, Id, {translate, [0, 0], wrap}}, {external, out_a}]} || Id <- Ids]}.

empty() -> #{version => 1, actors => #{}, families => #{}, externals => [],
    routes => [], route_relations => [], startup => [], ingresses => []}.
