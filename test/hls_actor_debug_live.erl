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
                    [identity, placement, phase, initialized, enter_pending, failed, cycle], 10000),
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

check(small, _, {family, cell, [0, 0]}, #{phase := active, failed := true, enter_pending := false}) -> ok;
check(small, released, {family, cell, [1, 0]}, #{phase := active, failed := false, enter_pending := false}) -> ok;
check(small, blocked, {family, cell, [1, 0]}, #{phase := active, failed := false}) -> ok;
check(phi, _, _, #{failed := false}) -> ok;
check(Kind, Moment, Id, Snapshot) -> error({actor_snapshot, Kind, Moment, Id, Snapshot}).
