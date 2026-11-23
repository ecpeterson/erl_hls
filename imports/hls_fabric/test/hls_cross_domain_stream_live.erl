-module(hls_cross_domain_stream_live).
-moduledoc "Finite production-bridge witness for an OTP-supervised A/B crossing and independent C. Real distributed clients observe source reports and incarnation-specific PIDs; the simulator changes only public transport delivery.".
-behaviour(supervisor).
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").

%% External witness and ordinary OTP group declaration.
-export([run/2, init/1]).
%% Monitor installation runs on the separate real ERTS peer.
-export([watch/3]).

-doc "Matches the retained native source history through production framed endpoints, then records bounded transport-failure observations. Inputs are a live simulator directory and the previous native-history.etf; no native evidence is rerun.".
-spec run(file:filename(), file:filename()) -> ok.
run(Stage, NativeFile) ->
    {ok, NativeBytes} = file:read_file(NativeFile),
    #{passed := true, history := Expected} = binary_to_term(NativeBytes),
    Domains = [domain(Id, Index, Stage) || {Id, Index} <- [{a, 0}, {b, 1}, {c, 2}]],
    [A, B, C] = Domains,
    {Channel, ChannelBroker} = channel(Stage),
    Brokers = [ChannelBroker | lists:append([maps:get(brokers, D) || D <- Domains])],
    Leases = [lease(P) || P <- Brokers],
    signal(Stage, "channel0_drop_bind_reply", 1),
    ack(Stage, "channel0_drop_bind_reply", 1),
    {ok, Group} = supervisor:start_link(?MODULE, {A, B, Channel}),
    unlink(Group),
    #{owner := OC} = C,
    {ok, _} = hls_domain:activate(OC, c),
    ready(OC, c),
    #{generation := 1} = binding(Group),
    observed(Stage, "channel0_drop_bind_reply", 1),
    hls_test_nodes:distribution(),
    {ok, _} = application:ensure_all_started(crypto),
    Name = list_to_atom("crossing_" ++ integer_to_list(erlang:unique_integer([positive])) ++ "@localhost"),
    Services = [#{name => Id, domain => #{owner => Owner, id => Id}} ||
        #{id := Id, owner := Owner} <- Domains],
    {ok, Node} = hls_node:start_link(Name, #{}, Services, #{}),
    unlink(Node),
    {Peer, Remote} = hls_test_nodes:start_peer(),
    try
        {History, Evidence} = scenario(Stage, Domains, Channel, Group, Node, Remote),
        Expected = History,
        ok = gen_server:stop(Group, shutdown, 10000),
        [stop(P) || D <- Domains, P <- [maps:get(owner, D), maps:get(backend, D)]],
        stop(Channel),
        [ok = hls_fabric:stop(P) || P <- Brokers],
        ok = file:write_file(filename:join(Stage, "finished"), <<>>, [exclusive]),
        [ok = hls_fabric:await_closed(L, 5000) || L <- Leases],
        Result = Evidence#{passed => true, evidence => finite_production_framed_crossing_witness,
            native_history_matches => true, real_erts_peer => true,
            descriptor_closure => true, lost_bind_reply_reconciled => true},
        ok = file:write_file(filename:join(Stage, "result.etf"), term_to_binary(History), [exclusive]),
        ok = file:write_file(filename:join(Stage, "result.json"), json:encode(Result), [exclusive])
    after
        catch peer:stop(Peer), catch hls_node:stop(Node), stop(Group), stop(Channel),
        [stop(P) || D <- Domains, P <- [maps:get(owner, D), maps:get(backend, D)]],
        [catch hls_fabric:stop(P) || P <- Brokers]
    end.

-doc "Declares A and B as supervised domain lifetimes, followed by their exact-incarnation channel worker. OTP one_for_all owns dependent replacement; C is outside the subtree.".
-spec init({map(), map(), pid()}) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init({#{owner := OA}, #{owner := OB}, Channel}) ->
    Children = [#{id => Id,
        start => {hls_domain_instance, start_link, [Owner, Id, #{lifetime => supervised}]},
        restart => permanent, shutdown => 5000, type => worker} || {Id, Owner} <- [{a, OA}, {b, OB}]],
    Crossing = #{id => channel,
        start => {hls_domain_channel_instance, start_link,
            [Channel, 0, {OA, a}, {OB, b}, #{poll_ms => 10, request_timeout_ms => 250}]},
        restart => permanent, shutdown => 5000, type => worker},
    {ok, {#{strategy => one_for_all, intensity => 3, period => 60}, Children ++ [Crossing]}}.

%% Each production backend owns separate management/application lanes and one source actor.
-spec domain(atom(), non_neg_integer(), file:filename()) -> map().
domain(Id, Index, Stage) ->
    Prefix = filename:join(Stage, "domain" ++ integer_to_list(Index)),
    ok = hls_recovery_stream_live:session(Prefix, 2),
    Management = broker(Prefix ++ "_management"),
    Application = broker(Prefix ++ "_application"),
    {ok, Backend} = hls_domain_fabric:start_link(
        #{management => Management, application => Application, session => 2},
        filename:join(Prefix, "interface.etf"),
        #{recipients => #{{Id, out} => self()}, management_timeout_ms => 3000,
            delivery_timeout_ms => 10000}),
    unlink(Backend),
    Store = filename:join(Stage, atom_to_list(Id) ++ ".incarnations"),
    ok = hls_domain_ids:create(Store),
    {ok, Owner} = hls_domain:start_link(#{Id => automatic},
        #{module => hls_domain_fabric, endpoints => #{Id => Backend}, incarnation_file => Store}),
    unlink(Owner),
    #{id => Id, owner => Owner, backend => Backend, brokers => [Management, Application],
        interface => filename:join(Prefix, "interface.etf")}.

%% Channel control has its own bounded framed management lane, never an application relay.
-spec channel(file:filename()) -> {pid(), pid()}.
channel(Stage) ->
    Prefix = filename:join(Stage, "channel0"),
    ok = hls_recovery_stream_live:session(Prefix, 1),
    Broker = broker(Prefix ++ "_management"),
    {ok, Backend} = hls_domain_channel_fabric:start_link(
        #{management => Broker, session => 1}, filename:join(Prefix, "interface.etf"),
        #{management_timeout_ms => 200}),
    unlink(Backend),
    {Backend, Broker}.

%% The ordinary broker consumes actual FIFO frames; routes remain isolated by lane.
-spec broker(file:filename()) -> pid().
broker(Prefix) ->
    {ok, Broker} = hls_fabric:start_link(Prefix ++ "_tx", Prefix ++ "_rx", #{rx_route_limit => 1}),
    unlink(Broker), Broker.

%% Comparable source history excludes transport-only probes and runtime identity numbers.
-spec scenario(file:filename(), [map()], pid(), pid(), pid(), node()) -> {map(), map()}.
scenario(Stage, Domains = [A = #{owner := OA}, B = #{owner := OB}, #{owner := OC}], Channel, Group, Node, Remote) ->
    VA = virtual(Node, a), VB = virtual(Node, b), VC = virtual(Node, c),
    HA = maps:get(handle, ready(OA, a)), HB = maps:get(handle, ready(OB, b)),
    HC = maps:get(handle, ready(OC, c)),
    Initial = #{a => command(Remote, VA, {read, 1, 0}, produced),
        b => command(Remote, VB, {read, 2, 0}, received),
        c => command(Remote, VC, {add, 3, 7}, value)},
    BeforeBurst = burst(Remote, VA, 10, 3),
    BeforeReadouts = #{a => command(Remote, VA, {read, 12, 0}, produced),
        b => command(Remote, VB, {read, 13, 0}, received),
        c => command(Remote, VC, {read, 14, 0}, value)},
    WA = watched(Remote, VA, 901, produced),
    WB = watched(Remote, VB, 902, received),
    {ok, LocalB} = hls_domain:resolve(OB, HB, b),
    BMonitor = monitor(process, LocalB),
    signal(Stage, "crossing_data_delivery", 1),
    %% Arm the external hold before the actor can produce its first packet. The
    %% later acknowledgement separately proves that a real packet is retained.
    file_value(filename:join(Stage, "crossing_data_delivery.armed"), 1),
    checkpoint(Stage, "before-held-publication", Domains, Channel),
    ok = erpc:call(Remote, gen_server, cast, [VA, {burst, 90, 99}]),
    ack(Stage, "crossing_data_delivery", 1),
    checkpoint(Stage, "held-publication", Domains, Channel),
    #{backend := BBackend} = B,
    #{received := Received} = hls_domain_fabric:info(BBackend),
    ok = hls_recovery_stream_live:delivery(Stage, 1, application, hold),
    ok = erpc:call(Remote, gen_server, cast, [VB, {read, 21, 0}]),
    await(fun() -> case hls_domain_fabric:info(BBackend) of
        #{received := Received, frontier := F} when F >= Received + 2 -> {ok, ok}; _ -> wait end end),
    checkpoint(Stage, "held-host-output", Domains, Channel),
    %% The peer's ordered B lane awaits read21's held admission receipt. A separate
    %% local caller reaches the same production endpoint without bypassing its framing.
    ok = gen_server:cast(LocalB, {explode, 20, 0}),
    %% The owner's ordered lifecycle lane may already be waiting for this held
    %% output. Its backend's public snapshot observes failure without joining that wait.
    await(fun() -> case hls_domain_fabric:info(BBackend) of
        #{state := #domain_state{phase = Phase}}
          when Phase =:= failed; Phase =:= closing; Phase =:= stopped -> {ok, ok};
        _ -> wait end end),
    {value, 22, 7} = command(Remote, VC, {read, 22, 0}, value),
    HC = maps:get(handle, ready(OC, c)),
    true = is_process_alive(LocalB),
    receive {'DOWN', BMonitor, process, LocalB, WhyEarly} -> error({down_before_output, WhyEarly}) after 0 -> ok end,
    ok = hls_recovery_stream_live:delivery(Stage, 1, application, resume),
    receive
        {'$gen_cast', {received, 21, 7, 1}} -> ok;
        {'DOWN', BMonitor, process, LocalB, Why} -> error({down_before_output, Why})
    after 10000 -> error(prior_output_missing) end,
    receive {'DOWN', BMonitor, process, LocalB, WhyB} ->
        true = WhyB =/= noconnection andalso WhyB =/= noproc
    after 10000 -> error(old_endpoint_survived) end,
    AReason = down(WA), BReason = down(WB),
    true = AReason =/= noconnection andalso BReason =/= noconnection,
    #{generation := 2, source_incarnation := FreshA, destination_incarnation := FreshB} = binding(Group),
    #{handle := {a, FreshA}} = ready(OA, a), #{handle := {b, FreshB}} = ready(OB, b),
    true = {a, FreshA} =/= HA andalso {b, FreshB} =/= HB,
    signal(Stage, "crossing_data_delivery", 2), ack(Stage, "crossing_data_delivery", 2),
    NewA = publish(Node, a), NewB = publish(Node, b),
    true = NewA =/= VA andalso NewB =/= VB,
    VC = virtual(Node, c), HC = maps:get(handle, ready(OC, c)),
    ok = erpc:call(Remote, gen_server, cast, [VA, {burst, 90, 99}]),
    ok = erpc:call(Remote, gen_server, cast, [VB, {item, 91, 999}]),
    ok = stale_frames(A, B, FreshA, FreshB),
    AfterReset = #{a => command(Remote, NewA, {read, 30, 0}, produced),
        b => command(Remote, NewB, {read, 31, 0}, received),
        c => command(Remote, VC, {read, 32, 0}, value)},
    signal(Stage, "crossing_data_delivery", 3),
    signal(Stage, "crossing_credit_delivery", 3),
    file_value(filename:join(Stage, "crossing_data_delivery.armed"), 3),
    file_value(filename:join(Stage, "crossing_credit_delivery.armed"), 3),
    AfterBurst = burst(Remote, NewA, 40, 5),
    ack(Stage, "crossing_data_delivery", 3), ack(Stage, "crossing_credit_delivery", 3),
    {ok, #{generation := 2, active := true}} = hls_domain_channel_fabric:status(Channel, 0),
    Independent = [command(Remote, VC, {add, 50, 2}, value),
        command(Remote, VC, {read, 51, 0}, value)],
    Final = #{a => command(Remote, NewA, {read, 52, 0}, produced),
        b => command(Remote, NewB, {read, 53, 0}, received)},
    History = #{initial => Initial, before_burst => BeforeBurst,
        before_readouts => BeforeReadouts, after_reset => AfterReset,
        after_burst => AfterBurst, independent_c => Independent, final => Final},
    {History, #{ordered_source_postponement => true, one_for_all => true,
        held_output_before_old_pid_down => true, held_crossing_cancelled => true,
        both_incarnations_fresh => true, old_pids_terminal => true,
        independent_c_progress_during_retirement => true, c_pid_and_incarnation_preserved => true,
        stale_framed_session_and_incarnation => true, stale_data_and_credit => true,
        application_commands_and_monitors => real_erts_peer,
        held_output_fault_trigger => local_production_endpoint,
        channel_generations => [1, 2]}}.

%% Validly shaped stale envelopes must not become source work or fault the replacement.
-spec stale_frames(map(), map(), pos_integer(), pos_integer()) -> ok.
stale_frames(#{brokers := [_, Application], interface := APath},
    #{brokers := [Management, _], interface := BPath}, FreshA, FreshB) ->
    #{actors := #{a := Binding}, application_route := ApplicationRoute} = hls_domain_wire:load(APath),
    {OldSession, []} = hls_domain_wire:request(Binding, cast, {burst, 92, 999},
        1, FreshA, 700, 255),
    {OldIncarnation, []} = hls_domain_wire:request(Binding, cast, {burst, 93, 999},
        2, FreshA - 1, 701, 255),
    ok = hls_fabric:send(Application, ApplicationRoute, {2, 0, 0}, OldSession),
    ok = hls_fabric:send(Application, ApplicationRoute, {2, 0, 0}, OldIncarnation),
    Interface = #{management_route := ManagementRoute} = hls_domain_wire:load(BPath),
    {Tag, Fault} = hls_domain_wire:management(1, 700,
        #domain_input{op = fault, expected = FreshB, fault = protocol_failure}, Interface),
    hls_fabric:send(Management, ManagementRoute, {Tag, 0, 0}, Fault).

-doc "Installs a real distribution monitor, then sends a read from that same process to order monitor setup before the acknowledged source command.".
-spec watch(pid(), pid(), non_neg_integer()) -> pid().
watch(Actor, Parent, Request) ->
    spawn(fun() ->
        Monitor = monitor(process, Actor),
        ok = hls_statem:admit_cast(Actor, {read, Request, 0}),
        Parent ! {watching, self()},
        receive {'DOWN', Monitor, process, Actor, Reason} -> Parent ! {retired, self(), Reason}
        after 20000 -> error(remote_monitor_timeout) end
    end).

%% Consume the monitor barrier's source report before the comparable application history continues.
-spec watched(node(), pid(), non_neg_integer(), atom()) -> pid().
watched(Remote, Actor, Request, Tag) ->
    Watcher = erpc:call(Remote, ?MODULE, watch, [Actor, self(), Request]),
    receive {watching, Watcher} -> ok after 10000 -> error(monitor_not_installed) end,
    report(Tag, Request), Watcher.

%% Remote monitor reasons distinguish actual retirement from transport uncertainty.
-spec down(pid()) -> term().
down(Watcher) -> receive {retired, Watcher, Reason} -> Reason after 10000 -> error(remote_pid_survived) end.

%% One public trigger drives all three ordered source entries on the real crossing.
-spec burst(node(), pid(), non_neg_integer(), non_neg_integer()) -> [tuple()].
burst(Remote, Actor, Request, Value) ->
    ok = erpc:call(Remote, hls_statem, admit_cast, [Actor, {burst, Request, Value}]),
    [report(received, Request), report(received, Request + 1)].

%% Explicit admission observes the same source tuple used by the retained native reference.
-spec command(node(), pid(), tuple(), atom()) -> tuple().
command(Remote, Actor, Message, Tag) ->
    ok = erpc:call(Remote, hls_statem, admit_cast, [Actor, Message]),
    report(Tag, element(2, Message)).

%% The next source report must have the expected identity; selective tag matching cannot hide reordering.
-spec report(atom(), non_neg_integer()) -> tuple().
report(Tag, Request) ->
    receive {'$gen_cast', Message} -> Tag = element(1, Message), Request = element(2, Message), Message
    after 10000 -> error({report_missing, Tag, Request}) end.

%% Managed-node publication explicitly creates the replacement's distributed PID.
-spec publish(pid(), atom()) -> pid().
publish(Node, Id) ->
    await(fun() -> case hls_node:publish_domain(Node, Id) of
        {ok, #{actors := Actors}} -> {ok, maps:get(Id, Actors)}; _ -> wait end end).

%% Source actor names and domain names coincide in this three-actor fixture.
-spec virtual(pid(), atom()) -> pid().
virtual(Node, Id) -> #{actors := Actors} = maps:get(Id, hls_node:services(Node)), maps:get(Id, Actors).

%% Bind readiness requires the channel coordinator's confirmed hardware snapshot.
-spec binding(pid()) -> map().
binding(Group) ->
    await(fun() -> case lists:keyfind(channel, 1, supervisor:which_children(Group)) of
        {channel, Pid, worker, _} when is_pid(Pid) ->
            try hls_domain_channel_instance:status(Pid) of
                #{phase := ready, active := true} = Snapshot -> {ok, Snapshot}; _ -> wait
            catch exit:_ -> wait end;
        _ -> wait end end).

%% Readiness polling never submits replacement or reconstructs an application operation.
-spec ready(pid(), atom()) -> hls_domain:snapshot().
ready(Owner, Id) -> await(fun() -> case hls_domain:status(Owner, Id) of
    {ok, #{phase := ready} = Snapshot} -> {ok, Snapshot}; _ -> wait end end).

%% Driver controls select public transport schedules; no source or lifecycle register is edited.
-spec signal(file:filename(), string(), pos_integer()) -> ok.
signal(Stage, Name, Value) ->
    Prefix = filename:join(Stage, Name),
    ok = file:write_file(Prefix ++ ".next", integer_to_binary(Value)),
    file:rename(Prefix ++ ".next", Prefix ++ ".control").

%% A transport control acknowledgement is not a hardware lifecycle fence.
-spec ack(file:filename(), string(), pos_integer()) -> ok.
ack(Stage, Name, Value) -> file_value(filename:join(Stage, Name ++ ".ack"), Value).

%% The driver separately records that an armed loss actually consumed one complete response.
-spec observed(file:filename(), string(), pos_integer()) -> ok.
observed(Stage, Name, Value) -> file_value(filename:join(Stage, Name ++ ".observed"), Value).

%% Bounded file observations synchronize only the simulator's external transport policy.
-spec file_value(file:filename(), pos_integer()) -> ok.
file_value(Path, Value) ->
    Bytes = integer_to_binary(Value),
    await(fun() -> case file:read_file(Path) of
        {ok, Data} -> case string:trim(Data) =:= Bytes of true -> {ok, ok}; false -> wait end;
        _ -> wait end end).

%% Small public snapshots survive a failed transport schedule without reading private simulator state.
-spec checkpoint(file:filename(), string(), [map()], pid()) -> ok.
checkpoint(Stage, Name, Domains, Channel) ->
    Snapshot = #{domains => maps:from_list([{Id, hls_domain_fabric:info(Backend)} ||
        #{id := Id, backend := Backend} <- Domains]),
        channel => hls_domain_channel_fabric:info(Channel)},
    file:write_file(filename:join(Stage, Name ++ ".etf"), term_to_binary(Snapshot), [exclusive]).

%% Completion requires every broker's actual descriptor lease to close.
-spec lease(pid()) -> reference().
lease(Broker) -> #{io := #{lease := Lease}} = hls_fabric:info(Broker), Lease.

%% Observation deadlines preserve uncertainty instead of treating elapsed time as acknowledgement.
-spec await(fun(() -> {ok, term()} | wait)) -> term().
await(Fun) -> await(Fun, erlang:monotonic_time(millisecond) + 15000).

%% Failed asynchronous progress ends the finite witness with its last observation intact.
-spec await(fun(() -> {ok, term()} | wait), integer()) -> term().
await(Fun, Deadline) -> case Fun() of
    {ok, Result} -> Result;
    wait -> true = erlang:monotonic_time(millisecond) < Deadline,
        receive after 2 -> await(Fun, Deadline) end
end.

%% Teardown accepts processes already terminated by the observed recovery policy.
-spec stop(pid()) -> ok.
stop(Pid) -> catch gen_server:stop(Pid, shutdown, 5000), ok.
