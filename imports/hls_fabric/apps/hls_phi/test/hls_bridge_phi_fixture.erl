-module(hls_bridge_phi_fixture).
-moduledoc false.
-export([fixture/1, oracle/1, write/1]).

%% Shape counts phi cells in each selected plane, not physical qubits. The
%% split changes placement only: routes and PRNG seeds retain global geometry.
fixture(Options) ->
    Config = #{shape := [Width, Height]} = config(Options),
    case Height rem 2 of
        0 -> ok;
        _ -> error({unequal_y_partition, Height})
    end,
    Semantic = #{families := Families, externals := Externals} =
        phi_decoder_profile_topology:topology(Config),
    FamilyPlan = #{startup := Startup} = hls_topology:normalize(Semantic),
    Actors = maps:from_list([{{Family, X, Y}, Module}
        || {Family, #{module := Module}} <- lists:sort(maps:to_list(Families)),
           X <- lists:seq(0, Width-1), Y <- lists:seq(0, Height-1)]),
    Routes = lists:append([hls_topology:routes_for_instance(FamilyPlan, Family, [X, Y])
        || {Family, X, Y} <- lists:sort(maps:keys(Actors))]),
    Plan = hls_topology:normalize(#{version => 1, actors => Actors, families => #{},
        ingresses => [], externals => Externals, route_relations => [],
        routes => [{Source, Recipients}
            || #{source := Source, recipients := Recipients, delivery := direct} <- Routes],
        startup => [{Id, Messages} || #{target := Id, messages := Messages} <- Startup]}),
    Placement = maps:from_list([{{actor, Id}, Y div (Height div 2)}
        || Id = {_, _, Y} <- maps:keys(Actors)]),
    {Plan, Placement}.

config(Options) ->
    case maps:keys(Options) -- [shape, planes] of
        [] -> ok;
        Unknown -> error({unknown_bridge_fixture_options, Unknown})
    end,
    #{shape := Shape, planes := Planes} = phi_decoder_profile:normalize(
        maps:merge(#{shape => [4, 2], planes => [x]}, Options)),
    #{shape => Shape, planes => Planes}.

-doc "Writes generated DSLX and the matching oracle or wrapper files into the test stage.".
-spec write(atom() | binary() | [atom() | [any()] | char()]) -> 'ok'.
write(Stage) ->
    Options = case file:consult(filename:join(Stage, "config.term")) of
        {ok, [Existing]} -> config(Existing);
        {error, enoent} -> config(#{})
    end,
    {Plan, Placement} = fixture(Options),
    Partition = hls_partition:normalize(Plan, Placement),
    Dependency = code:lib_dir(hls_phi),
    lists:foreach(fun(Module) ->
        Source = filename:join([Dependency, "src",
            atom_to_list(Module) ++ ".erl"]),
        Artifact = xls_scheduler_actor:to_xls(Source),
        write(Stage, atom_to_list(Module) ++ ".x", Artifact)
    end, [phi_halo_cell, phi_syndrome_replay_cell]),
    Devices = [begin
        #{tx_lanes := Tx, rx_lanes := Rx, externals := Externals} =
            hls_partition:device(Partition, Device),
        Name = list_to_atom("device_" ++ integer_to_list(Device) ++ "_graph"),
        Graph = hls_partition_dslx:emit(Partition, Device, #{name => Name,
            channel_depth => 1, actor_egress_depth => burst}),
        write(Stage, atom_to_list(Name) ++ ".x", Graph),
        #{id => Device, graph => Name, rx_lanes => length(Rx), tx_lanes => length(Tx),
            externals => [#{index => Index, port => iolist_to_binary(Port), name => Id}
                || #{id := Id, index := Index, port := Port} <- Externals]}
    end || Device <- [0, 1]],
    %% Keep the complete logical-to-wire mapping beside the compiled devices.
    %% Its digest is build provenance, not a link handshake or an ABI tag.
    Fingerprint = binary:encode_hex(crypto:hash(sha256,
        term_to_binary(Partition, [deterministic])), lowercase),
    write(Stage, "deployment.term", unicode:characters_to_binary(io_lib:format("~tp.~n", [Partition]))),
    write(Stage, "bridge.json", json:encode(#{devices => Devices, config => Options,
        partition_fingerprint => Fingerprint})),
    write(Stage, "config.term", io_lib:format("~p.~n", [Options])),
    ok.

%% Independent BEAM actors establish the content and order at each logical
%% actor output. Cross-actor merge order is deliberately absent from the oracle.
oracle(Stage) ->
    {ok, [Options]} = file:consult(filename:join(Stage, "config.term")),
    {#{actors := Definitions, externals := Externals, routes := Routes,
        startup := Startup}, _Placement} = fixture(Options),
    Owner = self(),
    Sinks = maps:from_list([{Id, spawn_link(fun() -> forward(Owner, Id) end)}
        || #{id := Id} <- Externals]),
    Actors = maps:from_list([begin
        {ok, Pid} = Module:start_link(),
        {Id, {Module, Pid}}
    end || #{id := Id, module := Module} <- Definitions]),
    try
        lists:foreach(fun(#{target := Id, messages := Messages}) ->
            {_, Pid} = maps:get(Id, Actors),
            [hls_statem:cast(Pid, Message) || Message <- Messages]
        end, Startup),
        {Phi, Sources} = lists:partition(fun({_, {Module, _}}) ->
            Module =:= phi_halo_cell
        end, lists:sort(maps:to_list(Actors))),
        %% The one-slot replay actors must consume startup before their first
        %% request. Connect them before releasing the phi actors' initial entry.
        lists:foreach(fun({Id, {Module, Pid}}) ->
            Outputs = maps:from_list([{Port, case Target of
                {actor, TargetId} -> element(2, maps:get(TargetId, Actors));
                {external, Stream} -> maps:get(Stream, Sinks)
            end} || #{source := {SourceId, Port}, recipients := [Target]} <- Routes,
                SourceId =:= Id]),
            ok = Module:connect(Pid, Outputs)
        end, Sources ++ Phi),
        Count = length(Phi),
        Events = collect(33 * Count, [], erlang:monotonic_time(millisecond) + 60000),
        write(Stage, "oracle.json", json:encode(lists:reverse(Events)))
    after
        maps:foreach(fun(_, {_, Pid}) -> unlink(Pid), exit(Pid, kill) end, Actors),
        maps:foreach(fun(_, Pid) -> unlink(Pid), exit(Pid, kill) end, Sinks)
    end.

forward(Owner, Stream) ->
    receive {'$gen_cast', Event} ->
        Owner ! {bridge_phi_event, Stream, Event},
        forward(Owner, Stream)
    end.

collect(0, Events, _) -> Events;
collect(Remaining, Events, Deadline) ->
    Timeout = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {bridge_phi_event, Stream, {Kind, Step, X, Y, Value}} when Step =< 32 ->
            Plane = case Stream of x_decoder_events -> 0; z_decoder_events -> 1 end,
            Next = case Kind of phi_status -> Remaining-1; phi_correction -> Remaining end,
            collect(Next, [[Plane, X, Y, Step, Kind, Value] | Events], Deadline);
        {bridge_phi_event, _, _} -> collect(Remaining, Events, Deadline)
    after Timeout -> error({oracle_timeout, Remaining})
    end.

write(Stage, Name, Contents) ->
    ok = file:write_file(filename:join(Stage, Name), Contents).
