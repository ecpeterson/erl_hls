-module(hls_protocol_inventory_validation).
-moduledoc "Checks the actual preflight command's fresh application bundles and structural rejection paths.".
-export([run/1]).

-doc "Checks N2/N3/N6 repetition and D3 noise inventories, including complete source families, channels, startup, spatial recipients and unresolved obligations. Mutated plans exercise diagnostic failures and bounded expansion. Reads only trusted local test outputs; no simulation, progress or hardware equivalence is asserted.".
-spec run(file:filename()) -> ok.
run(Stage) ->
    Results = [check(Name, Stage) || Name <- ["repetition-2", "repetition-3", "repetition-6", "noise-3"]],
    {ok, Bytes} = file:read_file(filename:join(Stage, "summary.json")),
    #{<<"eligible">> := false, <<"rtl_generated">> := false, <<"inputs">> := Inputs,
        <<"compiler_beams">> := Beams, <<"topologies">> := Summaries} = json:decode(Bytes),
    4 = length(Summaries),
    lists:foreach(fun(#{<<"path">> := Path, <<"sha256">> := Expected}) ->
        {ok, Content} = file:read_file(Path),
        Expected = binary:encode_hex(crypto:hash(sha256, Content), lowercase)
    end, Inputs ++ Beams),
    ok = file:write_file(filename:join(Stage, "validation.json"),
        json:encode(#{passed => true, applications => Results, evidence => source_inventory_checks,
            hardware_generated => false}), [exclusive]),
    io:format("SOURCE_PROTOCOL_PREFLIGHT_PASS ~p applications; no hardware admission~n", [length(Results)]).

%% Fresh source artifacts are the authority; independent geometry detects dropped or duplicate actors.
-spec check(string(), file:filename()) -> map().
check(Name, Stage) ->
    {ok, Bytes} = file:read_file(filename:join(Stage, Name ++ ".etf")),
    #{normalized := Normal, topology := T = #{actors := Actors, routes := Routes},
        modules := Modules, inventory := R = #{channels := Channels, diagnostics := [],
            obligations := Obligations, eligible := false}} = binary_to_term(Bytes),
    {Data, Noise, ExpectedActors} = geometry(Name),
    ExpectedActors = lists:sort([Id || #{id := Id} <- Actors]),
    [#{targets := Targets}] = maps:get(ingresses, T),
    [DT] = [Target || Target = #{id := data} <- Targets],
    [NT] = [Target || Target = #{id := noise} <- Targets],
    Data = points(DT), Noise = points(NT),
    StartupActors = lists:sort([Id || #{target := Id, messages := [_ | _]} <- maps:get(startup, T)]),
    ExpectedActors = StartupActors,
    [] = lists:append([maps:get(K, T) || K <- [families, route_relations, lane_relations]]),
    true = length(Obligations) =:= 5 * length(Actors),
    ExpectedChannels = lists:usort(lists:append([begin
        #{program := Program} = maps:get(Module, Modules),
        #{entries := Entries} = xls_actor_program:spec(Program),
        Tags = lists:usort([Tag || #{layouts := Layouts} <- Entries,
            #{storage := #{effects := Effects}} <- Layouts,
            #{port := P, tag := Tag} <- Effects, P =:= Port]),
        [{Id, Port, Tag, Destination} || Tag <- Tags, Destination <- Recipients]
    end || #{id := Id, module := Module} <- Actors,
        #{source := {Source, Port}, recipients := Recipients} <- Routes, Source =:= Id])),
    ExpectedChannels = lists:sort([{S, P, Tag, D} ||
        #{source := S, port := P, tag := Tag, destination := D} <- Channels]),
    maps:foreach(fun(Module, #{program := Program}) ->
        Spec = xls_actor_program:spec(Program),
        Plan = xls_actor_program:plan(Program),
        #{families := Families, alternatives := Alternatives} = maps:get(Module, maps:get(modules, R)),
        true = lists:sum([length(Cs) || #{clauses := Cs} <- Families]) =:= length(xls_statem_plan:callbacks(Plan)),
        true = length(Alternatives) =:= lists:sum([length(Effects) ||
            #{layouts := Layouts} <- maps:get(entries, Spec), #{storage := #{effects := Effects}} <- Layouts])
    end, Modules),
    ok = reject_expansion(Normal, length(Actors)),
    ok = reject_inventory(T, Modules),
    #{name => list_to_binary(Name), actors => length(Actors), routes => length(Routes),
        channels => length(Channels), obligations => length(Obligations)}.

%% Coordinate expectations come from the application's geometry, not from the elaborator.
-spec geometry(string()) -> {[tuple()], [tuple()], [term()]}.
geometry("noise-3") ->
    Data = [{{data_even, X, Y}, [X, 2*Y]} || X <- lists:seq(0,2), Y <- lists:seq(0,2)] ++
        [{{data_odd, X, Y}, [X, 2*Y+1]} || X <- lists:seq(0,2), Y <- lists:seq(0,2)],
    Noise = Data ++ [{{F, X, Y}, [X, 2*Y]} || F <- [syndrome_x, syndrome_z], X <- lists:seq(0,2), Y <- lists:seq(0,2)],
    Phi = [{F, X, Y} || F <- [phi_x, phi_z], X <- lists:seq(0,2), Y <- lists:seq(0,2)],
    {lists:sort(Data), lists:sort(Noise), lists:sort([Id || {Id, _} <- Noise] ++ Phi)};
geometry(Name) ->
    N = case Name of "repetition-2" -> 2; "repetition-3" -> 3; "repetition-6" -> 6 end,
    Data = [{{data, X, 0}, [X, 0]} || X <- lists:seq(0,N-1)],
    Noise = Data ++ [{{syndrome, X, 0}, [X, 0]} || X <- lists:seq(0,N-1)],
    {lists:sort(Data), lists:sort(Noise), lists:sort([Id || {Id, _} <- Noise] ++ [{phi, X, 0} || X <- lists:seq(0,N-1)])}.

%% Keep exact identities alongside embedded coordinates, including co-located distinct families.
-spec points(map()) -> [tuple()].
points(#{recipients := Recipients}) -> lists:sort([{Id, At} || #{actor := Id, at := At} <- Recipients]).

%% Bad limits and spatial bindings must fail before any inventory or hardware can be emitted.
-spec reject_expansion(map(), pos_integer()) -> ok.
reject_expansion(Normal, Count) ->
    reject(fun() -> hls_protocol_topology:elaborate(Normal, Count-1) end),
    [I] = maps:get(ingresses, Normal), [T | Ts] = maps:get(targets, I), [R | Rs] = maps:get(recipients, T),
    lists:foreach(fun(Recipients) ->
        Bad = Normal#{ingresses := [I#{targets := [T#{recipients := Recipients} | Ts]}]},
        reject(fun() -> hls_protocol_topology:elaborate(Bad, 64) end)
    end, [[R, R | Rs], [R#{family => absent} | Rs], [R#{offset => [1000,0]} | Rs]]).

%% Direct API callers receive explicit missing-source, producer, port, recipient and coverage diagnostics.
-spec reject_inventory(map(), map()) -> ok.
reject_inventory(T = #{routes := [Route = #{source := {Id, _}, recipients := Recipients} | Rest]}, Modules) ->
    [M | _] = maps:keys(Modules),
    Cases = [
        {missing_source_plan, T, maps:remove(M, Modules)},
        {route_coverage, T#{routes := Rest}, Modules},
        {route_coverage, T#{routes := [Route, Route | Rest]}, Modules},
        {unknown_producer, T#{routes := [Route#{source := {absent, missing}} | Rest]}, Modules},
        {undeclared_port, T#{routes := [Route#{source := {Id, missing}} | Rest]}, Modules},
        {unknown_consumer, T#{routes := [Route#{recipients := [{actor, absent} | Recipients]} | Rest]}, Modules},
        {undeclared_boundary, T#{routes := [Route#{recipients := [{external, absent} | Recipients]} | Rest]}, Modules}],
    lists:foreach(fun({Code, Topology, Plans}) ->
        #{diagnostics := Diagnostics, eligible := false} = hls_protocol_inventory:inspect(Topology, Plans),
        true = lists:any(fun(#{code := C}) -> C =:= Code end, Diagnostics)
    end, Cases).

%% Wrong exception classes are test failures rather than accepted negative evidence.
-spec reject(fun(() -> term())) -> ok.
reject(Fun) ->
    try Fun() of Value -> error({not_rejected, Value})
    catch error:{hls_diagnostic, #{stage := topology}} -> ok end.
