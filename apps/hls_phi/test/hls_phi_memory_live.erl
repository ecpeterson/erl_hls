-module(hls_phi_memory_live).
-moduledoc "Compare routed two-device memory I/O with BEAM and diagnose stalls through public queries.".
-export([run/1, initial/2, step/1, stop/1, closed/2, command_count/2]).

-doc "Interrupts an active experiment, resets its transports, then verifies a fresh complete witness.".
-spec run(file:filename()) -> ok.
run(Stage) ->
    {ok, _} = application:ensure_all_started(crypto),
    Before = with_activation(Stage, #{queue_limit => 16384, write_timeout => 60000}, fun(Resources = #{connections := Connections}) ->
        Observed = timed(diagnose, fun() -> diagnose(Stage, Connections) end),
        ok = touch(Stage, "release_events"),
        ok = timed(active_reset, fun() -> hls_phi_memory_reset:run(Stage, Resources) end),
        Observed
    end),
    with_activation(Stage, #{}, fun(Resources = #{application := Application, connections := Connections}) ->
        {ok, [Expected]} = file:consult(filename:join(Stage, "oracle.term")),
        {Actual, Final} = timed(fresh_experiment, fun() -> collect(initial(Stage, Resources)) end),
        case Actual =:= Expected of
            true -> ok;
            false -> error({witness_mismatch, Expected, Actual})
        end,
        #{crossed := Crossed, records := Records, sequences := Sequences} = Final,
        true = Crossed > 0,
        ExpectedCommands = length(maps:get(corrections, Actual)) + 2,
        ExpectedCommands = lists:sum(maps:values(Sequences)),
        await(fun() -> command_count(Stage, 1) =:= ExpectedCommands end),
        #{written := ExpectedCommands} = hls_partition_stream:info(Application),
        ok = hls_bridge_phi_live:save(Stage, "host-stream.json", hls_partition_stream:info(Application)),
        ok = hls_bridge_phi_live:save(Stage, "memory-result.json", #{
            summary => phi_memory_demo:summary(Actual), crossing_corrections => Crossed,
            events => Records, accepted_commands => Sequences}),
        ok = file:write_file(filename:join(Stage, "observed.term"), io_lib:format("~tp.~n", [Actual])),
        [First | _] = Connections,
        ok = hls_bridge_phi_live:save(Stage, "recovered.json",
            timed(recovered_queues, fun() -> hls_bridge_phi_live:inspect(First, maps:get(seeds, Before)) end)),
        ok = hls_bridge_phi_live:save(Stage, "actors-complete.json",
            timed(actors_complete, fun() -> [actor_samples(C) || C <- Connections] end)),
        ok = hls_phi_memory_metrics:write(Stage),
        ok = stop(Resources),
        ok = touch(Stage, "done"),
        ok = closed(Resources, 5000),
        io:format("PASS: complete D3 memory after active reset; ~p corrections cross ownership; ~p events; witness matches BEAM~n", [Crossed, Records])
    end).

%% Scope all host users and capture physical leases before any member can be retired.
-spec with_activation(file:filename(), map(), fun((map()) -> Result)) -> Result.
with_activation(Stage, Options, Fun) ->
    Connections = [actor_catalog(Stage, hls_bridge_phi_live:connect(Stage, D, Prefix))
        || {D, Prefix} <- [{0, "app"}, {1, "debug"}]],
    {ok, [Partition]} = file:consult(filename:join(Stage, "deployment.term")),
    Brokers = maps:from_list([begin
        Prefix = filename:join(Stage, "data" ++ integer_to_list(D)),
        {ok, Broker} = hls_fabric:start_link(Prefix ++ "_tx", Prefix ++ "_rx", #{rx_route_limit => 1}),
        {D, Broker}
    end || D <- [0, 1]]),
    Deployment = hls_partition_binding:deployment(Partition),
    Artifact = hls_deployment_artifact:new(partition_application, Deployment),
    Physical = maps:values(Brokers) ++ [B || #{fabric := B} <- Connections],
    Leases = [begin #{io := #{lease := L}} = hls_fabric:info(B), L end || B <- Physical],
    {ok, Application} = hls_partition_stream:start_link(Artifact, Brokers, Options),
    Resources = #{application => Application, brokers => Brokers, connections => Connections,
        physical => Physical, leases => Leases, partition => Partition, deployment => Deployment},
    try Fun(Resources)
    catch Class:Reason:Stack ->
        io:format(standard_error, "FAIL: ~tp~n~tp~n", [{Class, Reason}, Stack]),
        _ = catch hls_bridge_phi_live:save(Stage, "failure-debug.json",
            [#{boundaries => failure_inspect(C), actors => actor_samples(C)} || C <- Connections]),
        erlang:raise(Class, Reason, Stack)
    after stop(Resources)
    end.

%% Bind RAM observations from the same checked deployment, never from private RTL paths.
-spec actor_catalog(file:filename(), map()) -> map().
actor_catalog(Stage, C = #{device := Device, session := Session}) ->
    Path = filename:join(Stage, "phi_device_" ++ integer_to_list(Device) ++ "_schedule.term"),
    case file:consult(Path) of
        {error, enoent} -> C;
        {ok, [{Plan, Specs}]} -> C#{catalog => hls_partition_tile_debug:catalog(Plan, Specs, Session)}
    end.

%% Current state/depth/work flags describe pressure without retaining execution history.
-spec actor_samples(map()) -> map().
actor_samples(#{device := Device, catalog := Catalog}) ->
    #{device => Device, actors => [begin
        {ok, Target} = hls_debug_catalog:actor(Catalog, Id),
        Values = hls_debug:info(Target, [phase, failure, message_queue_len, free_slots,
            postponed, in_flight, waiting_for_egress, initialized, mailbox_initialized], 10000),
        #{actor => iolist_to_binary(io_lib:format("~p", [Id])), values => maps:from_list(Values)}
    end || Id <- hls_debug_catalog:actors(Catalog)]};
actor_samples(#{device := Device}) -> #{device => Device, actors => []}.

%% Bound failure diagnosis to the public application/link boundaries. A full
%% FIFO scan can obscure a host error behind minutes of irrelevant queries.
-spec failure_inspect(map()) -> map().
failure_inspect(#{device := Device, session := Session, manifest := Manifest}) ->
    IDs = [Id || #{<<"id">> := Id, <<"endpoints">> := Endpoints} <- maps:get(<<"probes">>, Manifest),
        lists:any(fun(E) -> maps:get(<<"external">>, E, false) andalso
            lists:member(maps:get(<<"port">>, E), [<<"_app_in">>, <<"_app_out">>, <<"_link_0_in">>, <<"_link_0_out">>])
        end, Endpoints)],
    Samples = [try
        {ok, Sample} = hls_topology_debug:query(Session, Id), Sample
    catch Class:Reason -> #{id => Id, error => unicode:characters_to_binary(io_lib:format("~tp", [{Class, Reason}]))}
    end || Id <- IDs],
    #{device => Device, boundaries => Samples}.

-doc "Creates fresh host experiment state; no prior activation state is retained.".
-spec initial(file:filename(), map()) -> map().
initial(Stage, #{application := Application, partition := Partition}) ->
    {ok, [Options]} = file:consult(filename:join(Stage, "config.term")),
    {Experiment, [_Cutoff]} = phi_memory_experiment:new(Options),
    #{stage => Stage, partition => Partition, application => Application,
        experiment => Experiment, sequences => #{0 => 0, 1 => 0},
        crossed => 0, records => 0, deadline => erlang:monotonic_time(millisecond) + 600000}.

-doc "Retires host admission and route owners before stopping the physical brokers; does not await raw I/O.".
-spec stop(map()) -> ok.
stop(#{application := Application, connections := Connections, physical := Brokers}) ->
    catch hls_partition_stream:stop(Application),
    [catch hls_debug:stop(Client) || #{client := Client} <- Connections],
    [catch hls_fabric:stop(Broker) || Broker <- Brokers],
    ok.

-doc "Requires explicit closure of every saved lease within one total deadline.".
-spec closed(map(), non_neg_integer()) -> ok.
closed(#{leases := Leases}, Timeout) ->
    Deadline = erlang:monotonic_time(millisecond) + Timeout,
    [ok = hls_fabric:await_closed(L, max(0, Deadline-erlang:monotonic_time(millisecond))) || L <- Leases],
    ok.

-doc "Counts complete public gateway command transfers for one activation.".
-spec command_count(file:filename(), non_neg_integer()) -> non_neg_integer().
command_count(Stage, Activation) ->
    Prefix = integer_to_binary(Activation),
    length([ok || Line <- lines(Stage, "commands.log"),
        [Epoch, _, _] <- [binary:split(Line, <<" ">>, [global])], Epoch =:= Prefix]).

%% Query blocked public boundaries before releasing each deliberately stalled path.
-spec diagnose(file:filename(), [map()]) -> map().
diagnose(Stage, Connections = [First = #{session := Session, manifest := Manifest}, _]) ->
    Link = hls_bridge_phi_live:link_output(Manifest),
    await(fun() -> hls_bridge_phi_live:blocked(Session, Link) end),
    %% Diagnose the injected source-side stall; the peer's idle queues add no evidence.
    Before = timed(blocked_queues, fun() -> hls_bridge_phi_live:inspect(First) end),
    ok = blocked_link(Before),
    ok = hls_bridge_phi_live:save(Stage, "blocked.json", [Before]),
    ok = touch(Stage, "pause_peer"),
    await(fun() -> exists(Stage, "peer_paused") end),
    ok = touch(Stage, "release_link"),
    await(fun() -> exists(Stage, "link_released") end),
    await(fun() -> hls_bridge_phi_live:blocked(Session, Link) end),
    Paused = timed(paused_queues, fun() -> hls_bridge_phi_live:inspect(First) end),
    ok = blocked_link(Paused),
    ok = hls_bridge_phi_live:save(Stage, "paused-peer.json", Paused),
    ok = hls_bridge_phi_live:save(Stage, "actors-paused-peer.json",
        timed(actors_paused, fun() -> actor_samples(First) end)),
    ok = touch(Stage, "resume_peer"),
    await(fun() -> exists(Stage, "peer_resumed") end),
    %% Either board may report first; an idle board can be waiting on its blocked peer.
    Outputs = [{Device, PeerSession, Id} ||
        #{device := Device, session := PeerSession, manifest := PeerManifest} <- Connections,
        #{<<"id">> := Id, <<"endpoints">> := Endpoints} <- maps:get(<<"probes">>, PeerManifest),
        lists:any(fun(E) -> maps:get(<<"external">>, E, false) andalso
            maps:get(<<"role">>, E) =:= <<"consumer">> andalso
            maps:get(<<"port">>, E) =:= <<"_app_out">>
        end, Endpoints)],
    await(fun() -> lists:any(fun({_, S, Id}) -> hls_bridge_phi_live:blocked(S, Id) end, Outputs) end),
    Samples = [begin
        {ok, Sample} = hls_topology_debug:query(S, Id), Sample#{device => Device}
    end || {Device, S, Id} <- Outputs],
    ok = hls_bridge_phi_live:save(Stage, "blocked-events.json", Samples),
    ok = hls_bridge_phi_live:save(Stage, "actors-blocked-events.json",
        timed(actors_blocked, fun() -> [actor_samples(C) || C <- Connections] end)),
    Before.

%% Require the queue-seeded walk to find the stalled link without seeding that endpoint.
-spec blocked_link(map()) -> ok.
blocked_link(#{link := #{valid := true, ready := false}, waits := #{edges := Edges}}) ->
    true = lists:any(fun
        (#{kind := external_sink, endpoint := <<"_link_0_out">>}) -> true;
        (_) -> false
    end, Edges),
    ok.

%% Complete only this activation's reducer; no old host state is replayed after reset.
-spec collect(map()) -> {map(), map()}.
collect(State) ->
    case step(State) of
        {continue, Next} -> collect(Next);
        {done, Witness, Final} -> {Witness, Final}
    end.

-doc "Consumes one credited event and submits its effects, or checks the whole-run deadline on timeout.".
-spec step(map()) -> {continue, map()} | {done, map(), map()}.
step(State = #{application := Application, deadline := Deadline, experiment := Experiment, records := N}) ->
    case hls_partition_stream:next(Application, 1000) of
        timeout ->
            true = erlang:monotonic_time(millisecond) < Deadline,
            {continue, State};
        {ok, Device, Stream, Event} ->
            ok = owner(Device, Stream, Event, maps:get(partition, State)),
            Next = State#{records := N+1},
            case phi_memory_experiment:event(Stream, Event, Experiment) of
                {done, Witness, Updated} -> {done, Witness, Next#{experiment := Updated}};
                {error, Reason, _} -> error({experiment, Reason, Event});
                {Updated, Commands} ->
                    Applied = lists:foldl(fun(Command, Acc) -> dispatch(Device, Command, Acc) end,
                        Next#{experiment := Updated}, Commands),
                    {continue, Applied}
            end
    end.

%% Host admission preserves per-device order; final replies, not writes, fence completion.
-spec dispatch(non_neg_integer(), phi_memory_experiment:command(), map()) -> map().
dispatch(Source, Command = {Ingress, Target, Bounds, Message}, State = #{partition := Partition,
        application := Application, sequences := Sequences, crossed := Crossed}) ->
    Packets = hls_partition_ingress:commands(Partition, Ingress, Target, Bounds, Message),
    Count = length(Packets),
    {ok, Count} = hls_partition_stream:submit(Application, Command),
    NextSequences = lists:foldl(fun({Device, _}, Acc) ->
        Acc#{Device := maps:get(Device, Acc)+1}
    end, Sequences, Packets),
    Delta = case element(1, Message) of
        pauli_update -> length([ok || {Device, _} <- Packets, Device =/= Source]);
        _ -> 0
    end,
    State#{sequences := NextSequences, crossed := Crossed+Delta}.

%% Reject a source record attributed to the wrong device, even if its payload otherwise matches.
-spec owner(non_neg_integer(), atom(), tuple(), map()) -> ok.
owner(Device, Stream, Event, #{actors := Actors}) ->
    {Family, X, Y} = case {Stream, Event} of
        {data_measurements, {pauli_reply, _Request, DX, DY, _Value}} ->
            {case DY rem 2 of 0 -> data_even; 1 -> data_odd end, DX, DY div 2};
        {x_decoder_events, {_, _Step, PX, PY, _Value}} -> {phi_x, PX, PY};
        {z_decoder_events, {_, _Step, PX, PY, _Value}} -> {phi_z, PX, PY}
    end,
    [Device] = [D || #{identity := {family, F, [AX, AY]}, device := D} <- Actors,
        F =:= Family, AX =:= X, AY =:= Y],
    ok.

%% Ignore a trailing incomplete line while the simulator appends public observations.
-spec lines(file:filename(), file:filename()) -> [binary()].
lines(Stage, Name) ->
    case file:read_file(filename:join(Stage, Name)) of
        {error, enoent} -> [];
        {ok, Bytes} ->
            Split = binary:split(Bytes, <<"\n">>, [global]),
            [Line || Line <- lists:droplast(Split), Line =/= <<>>]
    end.

%% Bound test-control waits separately from the experiment's whole-run deadline.
-spec await(fun(() -> boolean())) -> ok.
await(Fun) -> hls_bridge_phi_live:await(Fun, 30000).

%% Publish a testbench action after its preceding checks have completed.
-spec touch(file:filename(), file:filename()) -> ok.
touch(Stage, Name) -> ok = file:write_file(filename:join(Stage, Name), <<>>).

%% Observe acknowledgment of a testbench-only clock or link control.
-spec exists(file:filename(), file:filename()) -> boolean().
exists(Stage, Name) -> filelib:is_file(filename:join(Stage, Name)).

%% Separate host/debug wall time from simulated device progress, including failed phases.
-spec timed(atom(), fun(() -> Result)) -> Result.
timed(Phase, Fun) ->
    Start = erlang:monotonic_time(millisecond),
    io:format("START ~p~n", [Phase]),
    try Fun()
    after
        io:format("TIME ~p ~.3f s~n", [Phase,
            (erlang:monotonic_time(millisecond)-Start)/1000])
    end.
