-module(hls_actor_debug_live).
-export([inspect/3]).

%% Every observation goes through hls_debug:info and the real framed transport.
inspect(Session, Stage, Moment) ->
    case file:read_file(filename:join(Stage, "actor-test")) of
        {error, enoent} -> ok;
        {ok, Bytes} ->
            Kind = case Bytes of <<"small">> -> small; <<"phi">> -> phi end,
            {Plan, Specs} = hls_actor_debug_dslx:fixture(Kind),
            Catalog = hls_debug_catalog:hardware(Plan, Specs, [], Session),
            Ids = hls_debug_catalog:actors(Catalog),
            Observations = [begin
                {ok, Actor} = hls_debug_catalog:actor(Catalog, Id),
                Snapshot = hls_debug:info(Actor,
                    [identity, placement, phase, initialized, enter_pending, failed, failure, cycle], 10000),
                Values = maps:from_list(Snapshot),
                true = maps:get(initialized, Values),
                check(Kind, Moment, Id, Values),
                Values#{identity := iolist_to_binary(io_lib:format("~p", [Id]))}
            end || Id <- Ids],
            %% Placement contains arbitrary Erlang IDs; retain a native term report.
            ok = file:write_file(filename:join(Stage, "actors-" ++ atom_to_list(Moment) ++ ".term"),
                io_lib:format("~p.~n", [Observations])),
            io:format("PASS: ~p scoped actor snapshots (~p, ~p)~n", [length(Ids), Kind, Moment])
    end.

check(small, _, {family, cell, [Slot, 0]}, #{phase := Phase, failed := true,
        enter_pending := false, failure := #{kind := Kind, file := File, line := Line}})
        when Slot =/= 1, Slot =/= 7 ->
    Expected = case Slot of
        0 -> {active, case_clause, <<"hls_actor_debug_helpers.hrl">>, 7};
        2 -> {active, match_failure, <<"hls_actor_debug_fixture.erl">>, 28};
        3 -> {boot, case_clause, <<"hls_actor_debug_helpers.hrl">>, 7};
        4 -> {boot, explicit_fail, <<"hls_actor_debug_fixture.erl">>, 20};
        5 -> {boot, function_clause, <<"hls_actor_debug_fixture.erl">>, 16};
        6 -> {active, if_clause, <<"hls_actor_debug_helpers.hrl">>, 11}
    end,
    Expected = {Phase, Kind, File, Line},
    ok;
check(small, released, {family, cell, [Slot, 0]},
        #{phase := active, failed := false, failure := none, enter_pending := false})
        when Slot =:= 1; Slot =:= 7 -> ok;
check(small, blocked, {family, cell, [Slot, 0]}, #{phase := active, failed := false, failure := none})
        when Slot =:= 1; Slot =:= 7 -> ok;
check(phi, _, _, #{failed := false, failure := none}) -> ok;
check(Kind, Moment, Id, Snapshot) -> error({actor_snapshot, Kind, Moment, Id, Snapshot}).
