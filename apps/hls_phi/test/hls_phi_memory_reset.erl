-module(hls_phi_memory_reset).
-moduledoc "Active-reset witness using only routed streams, public queries and transport closure acknowledgments.".
-export([run/2]).

-define(OLD_REQUEST, 16#deadbeef).

-doc "Aborts accepted queries, unread replies and partial commands; resets both devices only after retiring host ownership.".
-spec run(file:filename(), map()) -> ok.
run(Stage, Resources = #{application := Stream, deployment := Deployment, brokers := Brokers}) ->
    {ok, [Options]} = file:consult(filename:join(Stage, "config.term")),
    true = maps:get(request_id, Options) =/= ?OLD_REQUEST,
    {Experiment, _} = phi_memory_experiment:new(Options#{request_id := ?OLD_REQUEST}),
    State = (hls_phi_memory_live:initial(Stage, Resources))#{experiment := Experiment},
    #{sequences := Sequences} = until_queries(State),
    Accepted = lists:sum(maps:values(Sequences)),
    true = Accepted > 2,
    await(fun() -> hls_phi_memory_live:command_count(Stage, 0) =:= Accepted end),
    %% Consume one old measurement, then deliberately retain the other replies.
    OldReply = first_reply(Stream),
    await(fun() -> replies_retained(Deployment, Brokers) end),
    ok = touch(Stage, "hold_commands"),
    await(fun() -> exists(Stage, "commands_armed") end),
    Query = {control_router, data, {0, 0, 2, 5}, {pauli_query, ?OLD_REQUEST, z}},
    %% Fill the bounded host queue beyond the simulator ring and OS pipe capacity.
    %% This ensures reset must unblock actual raw writes, not only idle workers.
    [{ok, 2} = hls_partition_stream:submit(Stream, Query) || _ <- lists:seq(1, 8192)],
    await(fun() -> lists:all(fun(D) -> exists(Stage, "partial-command-" ++ integer_to_list(D)) end, [0, 1]) end),
    Accepted = hls_phi_memory_live:command_count(Stage, 0),
    await(fun() -> lists:all(fun(B) ->
        #{tx := #{active := Active}} = hls_fabric:info(B), Active =/= none
    end, maps:values(Brokers)) end),
    #{buffered := Buffered, pending := Pending} = Info = hls_partition_stream:info(Stream),
    true = Buffered > 0,
    true = Pending > 0,
    ok = hls_bridge_phi_live:save(Stage, "before-reset.json", #{
        accepted_commands => Accepted, buffered_events => Buffered,
        old_request_id => ?OLD_REQUEST, old_reply => tuple_to_list(OldReply), host => Info}),
    ok = hls_phi_memory_live:stop(Resources),
    %% The idle debug reader is blocked in a raw read. Broker death alone must
    %% not allow a second descriptor owner to reopen its path.
    ok = rejects_competing_open(Stage),
    ok = touch(Stage, "reset_hold"),
    await(fun() -> exists(Stage, "reset_held") andalso exists(Stage, "transport_held") end),
    ok = hls_phi_memory_live:closed(Resources, 5000),
    {ok, RetiredBytes} = file:read_file(filename:join(Stage, "retired-transport.json")),
    Retired = maps:from_list([{maps:get(<<"stream">>, Entry), Entry} || Entry <- json:decode(RetiredBytes)]),
    [true = maps:get(<<"input_bytes">>, maps:get(Name, Retired)) > 0 || Name <- [<<"data0">>, <<"data1">>]],
    %% Only this explicit closure barrier permits replacing FIFO objects and
    %% releasing the common graph/link reset. No elapsed delay substitutes for it.
    ok = touch(Stage, "leases_closed"),
    ok = touch(Stage, "reset_release"),
    await(fun() -> exists(Stage, "reactivated") andalso exists(Stage, "transport_reopened") end),
    ok = hls_bridge_phi_live:save(Stage, "reset-result.json", #{
        accepted_before_reset => Accepted, pending_host_commands => Pending,
        blocked_writers => map_size(Brokers), leases_closed => length(maps:get(leases, Resources)),
        competing_open_rejected => true, old_request_id => ?OLD_REQUEST}),
    io:format("Retired ~p complete commands, unread measurements and two partial commands; all raw I/O leases closed before restart~n", [Accepted]),
    ok.

%% Stop immediately after closeout emits both queries, before reducing their replies.
-spec until_queries(map()) -> map().
until_queries(State = #{experiment := #{phase := querying}}) -> State;
until_queries(State) ->
    {continue, Next} = hls_phi_memory_live:step(State),
    until_queries(Next).

%% An observed old request ID makes stale replies distinguishable after reset.
-spec first_reply(pid()) -> tuple().
first_reply(Stream) -> first_reply(Stream, erlang:monotonic_time(millisecond) + 30000).

%% Decoder status may precede the measurement on the shared physical stream.
-spec first_reply(pid(), integer()) -> tuple().
first_reply(Stream, Deadline) ->
    true = erlang:monotonic_time(millisecond) < Deadline,
    case hls_partition_stream:next(Stream, 1000) of
        {ok, _, data_measurements, Reply = {pauli_reply, ?OLD_REQUEST, _, _, _}} -> Reply;
        {ok, _, data_measurements, Other} -> error({wrong_old_reply, Other});
        _ -> first_reply(Stream, Deadline)
    end.

%% Each device must retain a measurement receipt, not merely a decoder status.
-spec replies_retained(map(), map()) -> boolean().
replies_retained(#{devices := Devices}, Brokers) ->
    lists:all(fun({D, #{host := Host, events := Events}}) ->
        [Endpoint] = [E || {E, #{id := data_measurements}} <- maps:to_list(Events)],
        #{routes := Routes} = hls_fabric:info(maps:get(D, Brokers)),
        #{outstanding := Count} = maps:get({Endpoint, Host}, Routes),
        Count =:= 1
    end, maps:to_list(Devices)).

%% Attempt the conflicting open in an isolated caller so its expected start_link
%% failure cannot become the application's exit signal.
-spec rejects_competing_open(file:filename()) -> ok.
rejects_competing_open(Stage) ->
    Parent = self(),
    {Pid, Ref} = spawn_monitor(fun() ->
        process_flag(trap_exit, true),
        Result = hls_fabric:start_link(filename:join(Stage, "app_tx"), filename:join(Stage, "app_rx")),
        Parent ! {self(), Result},
        case Result of {ok, Broker} -> hls_fabric:stop(Broker); _ -> ok end
    end),
    receive
        {Pid, {error, {device_owned, _, _}}} -> ok;
        {Pid, Other} -> error({competing_open, Other})
    after 5000 -> error(competing_open_timeout) end,
    receive {'DOWN', Ref, process, Pid, normal} -> ok after 5000 -> error(competing_open_leak) end.

%% Bound reset-control and observation waits independently of the memory run.
-spec await(fun(() -> boolean())) -> ok.
await(Fun) -> hls_bridge_phi_live:await(Fun, 30000).

%% Publish an out-of-band test transport action after its prerequisite completes.
-spec touch(file:filename(), file:filename()) -> ok.
touch(Stage, Name) -> file:write_file(filename:join(Stage, Name), <<>>).

%% Check an acknowledgment of the simulator's public transport/reset action.
-spec exists(file:filename(), file:filename()) -> boolean().
exists(Stage, Name) -> filelib:is_file(filename:join(Stage, Name)).
