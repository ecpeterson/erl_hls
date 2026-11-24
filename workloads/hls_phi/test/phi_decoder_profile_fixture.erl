-module(phi_decoder_profile_fixture).
-moduledoc "Decoder-profile source preparation and a finite independent BEAM oracle for RTL comparison.".
-export([write/1, oracle/1]).

-doc "Writes the production profile source bundle into an existing test stage using config.term. Existing generated files are replaced for this reusable fixture; the BEAM oracle remains separate.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    {ok, [Config]} = file:consult(filename:join(Stage, "config.term")),
    #{files := Files} = phi_decoder_profile_build:emit(Config, #{}),
    maps:foreach(fun(Name, Bytes) -> ok = write(Stage, Name, Bytes) end, Files).

%% Independent BEAM actor execution: compare per-actor event order/content,
%% without imposing a global order on the concurrently merged event stream.
-doc "Runs the CPU fixture and returns its ordered observable results.".
-spec oracle(atom() | binary() | [atom() | [any()] | char()]) -> 'ok'.
oracle(Stage) ->
    {ok, [Config]} = file:consult(filename:join(Stage, "config.term")),
    Plan = #{families := Families, externals := Externals, startup := Startup} =
        hls_topology:normalize(phi_decoder_profile_topology:topology(Config)),
    Owner = self(),
    Sinks = maps:from_list([{Id, spawn_link(fun() -> forward(Owner, Id) end)}
        || #{id := Id} <- Externals]),
    Actors = maps:from_list([begin
        {ok, Pid} = Module:start_link(),
        {{Family, X, Y}, {Module, Pid}}
    end || #{id := Family, module := Module, shape := [W, H]} <- Families,
        X <- lists:seq(0, W-1), Y <- lists:seq(0, H-1)]),
    try
        lists:foreach(fun(#{target := Id, messages := Messages}) ->
            {_, Pid} = maps:get(Id, Actors),
            [hls_statem:cast(Pid, M) || M <- Messages]
        end, Startup),
        {Phi, Sources} = lists:partition(fun({_, {Module, _}}) ->
            Module =:= phi_halo_cell
        end, lists:sort(maps:to_list(Actors))),
        %% Sources must consume their startup message before phi requests
        %% can arrive at their one-slot mailbox.
        lists:foreach(fun({{Family, X, Y}, {Module, Pid}}) ->
            Outputs = maps:from_list([{Port, case Target of
                {actor, Id} -> element(2, maps:get(Id, Actors));
                {external, Stream} -> maps:get(Stream, Sinks)
            end} || #{source := {_, Port}, recipients := [Target]} <-
                hls_logical_topology:routes_for_instance(Plan, Family, [X, Y])]),
            ok = Module:connect(Pid, Outputs)
        end, Sources ++ Phi),
        #{phi_actor_count := Count} = phi_decoder_profile:manifest(Config),
        Events = collect(33 * Count, [], erlang:monotonic_time(millisecond) + 30000),
        write(Stage, "oracle.json", json:encode(lists:reverse(Events)))
    after
        maps:foreach(fun(_, {_, Pid}) -> unlink(Pid), exit(Pid, kill) end, Actors),
        maps:foreach(fun(_, Pid) -> unlink(Pid), exit(Pid, kill) end, Sinks)
    end.

%% Relays fixture messages while retaining their source identity.
-spec forward(pid(),term()) -> no_return().
forward(Owner, Stream) ->
    receive {'$gen_cast', Event} ->
        Owner ! {event, Stream, Event}, forward(Owner, Stream)
    end.

%% Collects the requested fixture results or reports a bounded-wait failure.
-spec collect(non_neg_integer(),[[any(),...]],integer()) -> [[any(),...]].
collect(0, Events, _) -> Events;
collect(Remaining, Events, Deadline) ->
    Timeout = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {event, Stream, {Kind, Step, X, Y, Value}} when Step =< 32 ->
            Plane = case Stream of x_decoder_events -> 0; z_decoder_events -> 1 end,
            Next = case Kind of phi_status -> Remaining - 1; phi_correction -> Remaining end,
            collect(Next, [[Plane, X, Y, Step, Kind, Value] | Events], Deadline);
        {event, _, _} -> collect(Remaining, Events, Deadline)
    after Timeout -> error({oracle_timeout, Remaining})
    end.

%% Writes generated DSLX and the matching oracle or wrapper files into the test stage.
-spec write(atom() | binary() | [atom() | [any()] | char()],nonempty_string(),binary() | maybe_improper_list(binary() | maybe_improper_list(any(),binary() | []) | byte(),binary() | [])) -> 'ok'.
write(Stage, Name, Contents) ->
    Path = filename:join(Stage, Name),
    ok = filelib:ensure_dir(Path),
    ok = file:write_file(Path, Contents).
