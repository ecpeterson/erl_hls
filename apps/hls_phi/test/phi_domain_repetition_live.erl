-module(phi_domain_repetition_live).
-moduledoc "Finite Phi memory/recovery witness through production domain and channel APIs. The simulator controls only bounded public transport delivery; this module supplies ordinary OTP supervision, source configuration, correction feedback and readout. Two fresh lifetimes reuse one retained BEAM oracle.".
-behaviour(supervisor).
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").
-include_lib("hls_fabric/include/hls_domain_channel_endpoints.hrl").

%% Public finite witness and ordinary dependent-group child declarations.
-export([run/2, run/3, run_attached/4, init/1]).
-export_type([transport/0]).

-doc "Explicit fixture transport. Independent mode uses an emitted role-network bundle and an externally excluded nonzero cold-start namespace; management sessions do not supply that namespace.".
-type transport() :: #{mode := same_clock} | #{mode := independent_endpoints,
    network_bundle := file:filename(), namespace := hls_nums:u64()}.

-doc "Runs two fresh incarnations of the emitted local composition, recording per-sender application events and canonical readout in result.json. Bundle supplies retained codecs and setup; Stage contains the live public-pin FIFO harness. No native reference is rerun here.".
-spec run(file:filename(), file:filename()) -> ok.
run(Bundle, Stage) -> run(Bundle, Stage, #{mode => same_clock}).

-doc "Runs the same application and retirement witness with explicit link transport. Independent mode checks the network bundle's retained domain interface against Bundle, opens endpoint0/1 management/session lanes and uses one pair worker per crossing. Both lifetimes retain one namespace and require increasing generations and exact fresh domain incarnations. This is a finite public-stream witness, not physical CDC or transparent reconnect qualification.".
-spec run(file:filename(), file:filename(), transport()) -> ok.
run(Bundle, Stage, Transport) ->
    {Metadata = #{actors := Actors}, InterfaceBytes, DomainRows, Crossings} = metadata(Bundle),
    Plan = link_plan(Transport, InterfaceBytes),
    Domains = [domain(Bundle, Stage, Row, Actors) || Row <- DomainRows],
    Links = links(Bundle, Stage, Plan),
    run_started(Stage, Metadata, Domains, Crossings, Links).

-doc "Runs the shared finite application witness over caller-established local brokers. Each role supplies distinct application/management brokers, one confirmed session and an existing durable incarnation_file; its endpoint adapter shares the management broker. The caller transfers broker ownership for this run. Inspect is a trusted fun(Index,Incarnation) for public platform inspection. Uses natural delivery: records actual terminal causes and fresh replacement identities, without claiming the simulator's held-output frontier witness. The external transport peer must close FIFO writers when Stage/finished appears, and report remote descriptor closure separately.".
-spec run_attached(file:filename(), file:filename(), transport(),
    #{roles := #{non_neg_integer() => map()}, inspect := fun((non_neg_integer(), pos_integer()) -> ok)}) -> ok.
run_attached(Bundle, Stage, Transport, #{roles := Attached, inspect := Inspect}) ->
    {Metadata = #{actors := Actors}, InterfaceBytes, DomainRows, Crossings} = metadata(Bundle),
    #{mode := independent_endpoints, roles := Roles, namespace := Namespace} = link_plan(Transport, InterfaceBytes),
    ok = attached_roles(Attached), true = is_function(Inspect, 2),
    attached_domains(Bundle, DomainRows, Actors, Attached, fun(Domains) ->
        attached_adapters(Roles, Attached, fun(Opened) ->
            Adapters = maps:from_list(Opened),
            Links = #{mode => independent_endpoints, namespace => Namespace, witness => attached,
                inspect => Inspect, backends => maps:values(Adapters), brokers => [],
                supervision => #{mode => independent_endpoints, namespace => Namespace, adapters => Adapters}},
            run_started(Stage, Metadata, Domains, Crossings, Links)
        end)
    end).

%% Physical banks have one local broker owner each; route sharing occurs only inside bank one.
-spec attached_roles(map()) -> ok.
attached_roles(Attached) ->
    [0, 1] = lists:sort(maps:keys(Attached)),
    Brokers = lists:append([begin
        #{application := Application, management := Management, session := Session,
            incarnation_file := _Store} = maps:get(Index, Attached),
        true = is_integer(Session) andalso Session > 0 andalso Session < (1 bsl 64),
        [Application, Management]
    end || Index <- [0, 1]]),
    true = lists:all(fun(Pid) -> is_pid(Pid) andalso node(Pid) =:= node() end, Brokers),
    4 = length(lists:usort(Brokers)), ok.

%% Partial setup failure retires every already-created local owner/backend.
-spec attached_domains(file:filename(), [map()], [map()], map(), fun(([map()]) -> ok)) -> ok.
attached_domains(_Bundle, [], _Actors, _Attached, Fun) -> Fun([]);
attached_domains(Bundle, [Row = #{index := Index} | Rest], Actors, Attached, Fun) ->
    Domain = attached_domain(Bundle, Row, Actors, maps:get(Index, Attached)),
    try attached_domains(Bundle, Rest, Actors, Attached, fun(Domains) -> Fun([Domain | Domains]) end)
    after stop(maps:get(owner, Domain)), stop(maps:get(backend, Domain)) end.

%% These adapters share the existing bank-one brokers without creating another I/O path.
-spec attached_adapters([map()], map(), fun(([{non_neg_integer(), pid()}]) -> ok)) -> ok.
attached_adapters([], _Attached, Fun) -> Fun([]);
attached_adapters([#{index := Index, interface := Interface} | Rest], Attached, Fun) ->
    #{management := Broker, session := Session} = maps:get(Index, Attached),
    {ok, Backend} = hls_domain_channel_fabric:start_link(
        #{management => Broker, session => Session}, Interface, #{management_timeout_ms => 10000}),
    unlink(Backend),
    try attached_adapters(Rest, Attached, fun(Backends) -> Fun([{Index, Backend} | Backends]) end)
    after stop(Backend) end.

%% Retained metadata is checked before opening or adopting any live transport.
-spec metadata(file:filename()) -> {map(), binary(), [map()], [map()]}.
metadata(Bundle) ->
    {ok, Bytes} = file:read_file(filename:join(Bundle, "fixture.etf")),
    Metadata = binary_to_term(Bytes),
    {ok, InterfaceBytes} = file:read_file(filename:join(Bundle, "interface.etf")),
    #{domains := DomainRows, crossings := Crossings} = binary_to_term(InterfaceBytes),
    {Metadata, InterfaceBytes, DomainRows, Crossings}.

%% Every transport mode shares application setup, correction/readout and OTP child ownership.
-spec run_started(file:filename(), map(), [map()], [map()], map()) -> ok.
run_started(Stage, Metadata, Domains, Crossings, Links) ->
    LinkBackends = maps:get(backends, Links),
    Brokers = maps:get(brokers, Links) ++ lists:append([maps:get(brokers, D) || D <- Domains]),
    Leases = [lease(B) || B <- Brokers],
    {ok, Group} = supervisor:start_link(?MODULE, {Domains, Crossings, maps:get(supervision, Links)}),
    unlink(Group),
    try
        {First, Previous = #{actors := OldActors}} = incarnation(Stage, Metadata, Domains, Crossings, Group, Links, none),
        Recovery = fail_incarnation(Stage, Metadata, Domains, Previous, Links),
        {Second, #{actors := NewActors}} = incarnation(Stage, Metadata, Domains, Crossings, Group, Links, Previous),
        true = lists:all(fun(Id) -> maps:get(Id, OldActors) =/= maps:get(Id, NewActors) end,
            maps:keys(OldActors)),
        Monitors = monitors(NewActors),
        ok = gen_server:stop(Group, shutdown, 30000),
        _ = terminal(Monitors),
        Tail = retired_tail(0),
        [stop(P) || D <- Domains, P <- [maps:get(owner, D), maps:get(backend, D)]],
        [stop(P) || P <- LinkBackends],
        [ok = hls_fabric:stop(B) || B <- Brokers],
        %% A FIFO reader blocked in the OS closes only after its simulator peer exits.
        ok = file:write_file(filename:join(Stage, "finished"), <<>>, [exclusive]),
        [ok = hls_fabric:await_closed(L, 5000) || L <- Leases],
        Result = maps:merge(#{passed => true, incarnations => [First, Second],
            descriptors_closed => true, old_pids_terminal => true,
            recovery => Recovery, final_retired_quiet_tail => Tail}, report(Links)),
        ok = file:write_file(filename:join(Stage, "result.json"), json:encode(Result), [exclusive])
    after
        stop(Group), [stop(P) || P <- LinkBackends],
        [stop(P) || D <- Domains, P <- [maps:get(owner, D), maps:get(backend, D)]],
        [catch hls_fabric:stop(B) || B <- Brokers],
        finish_failed_transport(Stage, Links)
    end.

-doc "Starts the two domain lifetimes before their dependent crossing workers. one_for_all retains the same child order in both modes; independent pairs receive the owning role's adapter and a complete namespace.".
-spec init({[map()], [map()], pid() | map()}) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init({Domains, Crossings, Links}) ->
    Children = [#{id => Id,
        start => {hls_domain_instance, start_link, [Owner, Id, #{lifetime => supervised}]},
        restart => permanent, shutdown => 10000, type => worker} ||
        #{id := Id, owner := Owner} <- Domains],
    ByIndex = maps:from_list([{I, {Owner, Id}} || #{index := I, owner := Owner, id := Id} <- Domains]),
    {ok, {#{strategy => one_for_all, intensity => 3, period => 60},
        Children ++ link_children(Links, Crossings, ByIndex)}}.

%% Common-clock child specifications retain their original worker and arguments.
-spec link_children(pid() | map(), [map()], map()) -> [supervisor:child_spec()].
link_children(Channel, Crossings, ByIndex) when is_pid(Channel) ->
    [#{id => {channel, I}, start => {hls_domain_channel_instance, start_link,
        [Channel, I, maps:get(S, ByIndex), maps:get(D, ByIndex),
            #{poll_ms => 25, request_timeout_ms => 3000}]},
        restart => permanent, shutdown => 10000, type => worker} ||
        #{index := I, source_domain := S, destination_domain := D} <- Crossings];
%% Every directed crossing owns one TX/RX capability pair on its two fixed role adapters.
link_children(#{mode := independent_endpoints, adapters := Adapters, namespace := Namespace}, Crossings, ByIndex) ->
    [#{id => {channel, I}, start => {hls_domain_endpoint_pair, start_link,
        [{maps:get(S, Adapters), I}, {maps:get(D, Adapters), I},
            maps:get(S, ByIndex), maps:get(D, ByIndex), Namespace,
            #{poll_ms => 25, request_timeout_ms => 3000}]},
        restart => permanent, shutdown => 10000, type => worker} ||
        #{index := I, source_domain := S, destination_domain := D} <- Crossings].

%% Validate retained network ownership before opening any live stream or allocating a domain lifetime.
-spec link_plan(transport(), binary()) -> map().
link_plan(#{mode := same_clock} = Options, _DomainBytes) ->
    require(maps:keys(Options) =:= [mode], transport_options),
    #{mode => same_clock};
link_plan(#{mode := independent_endpoints, network_bundle := Network, namespace := Namespace} = Options, DomainBytes) ->
    require(lists:sort(maps:keys(Options)) =:= [mode, namespace, network_bundle], transport_options),
    require(is_integer(Namespace) andalso Namespace > 0 andalso Namespace < (1 bsl 64), namespace),
    {ok, Retained} = file:read_file(filename:join([Network, "evidence", "domain-interface.etf"])),
    require(Retained =:= DomainBytes, retained_domain_interface),
    #{domains := Domains, crossings := Crossings} = binary_to_term(DomainBytes),
    {ok, Bytes} = file:read_file(filename:join(Network, "interface.etf")),
    Rows = binary_to_term(Bytes),
    require(is_list(Rows) andalso length(Rows) =:= 2, role_count),
    require(lists:sort([I || #{index := I} <- Domains]) =:= [0, 1], domain_roles),
    Ids = [I || #{index := I, source_domain := S, destination_domain := D} <- Crossings,
        S =/= D, (S =:= 0 orelse S =:= 1), (D =:= 0 orelse D =:= 1)],
    require(length(Ids) =:= length(Crossings) andalso length(Ids) =:= length(lists:usort(Ids)), crossings),
    Roles = [role_interface(Row, Crossings) || Row <- Rows],
    require(lists:sort([I || #{index := I} <- Roles]) =:= [0, 1], role_indices),
    #{mode => independent_endpoints, namespace => Namespace, roles => Roles}.

%% Role, router and parser must agree with the original directed crossing ownership.
-spec role_interface(map(), [map()]) -> map().
role_interface(#{role := #{domain_index := Index, endpoints := Endpoints},
    packets := #{routes := Routes}, management := #{interface := Interface},
    network := #{domain_index := Index}}, Crossings) ->
    #{endpoints := Managed} = hls_domain_endpoint_wire:load(Interface),
    Expected = lists:sort([{I, case Source of Index -> tx; _ -> rx end} ||
        #{index := I, source_domain := Source, destination_domain := Destination} <- Crossings,
        Source =:= Index orelse Destination =:= Index]),
    require(endpoint_ids(Endpoints) =:= Expected andalso endpoint_ids(Routes) =:= Expected
        andalso endpoint_ids(Managed) =:= Expected, endpoint_directions),
    #{index => Index, interface => Interface}.

%% Partial or duplicate retained endpoint rows cannot silently disappear during normalization.
-spec endpoint_ids([map()]) -> [{non_neg_integer(), tx | rx}].
endpoint_ids(Endpoints) ->
    Ids = [{Id, Kind} || #{id := Id, kind := Kind} <- Endpoints],
    require(length(Ids) =:= length(Endpoints), endpoint_rows),
    lists:sort(Ids).

%% Link deployment differs only in metadata/session ownership; application and recovery code stay shared.
-spec links(file:filename(), file:filename(), map()) -> map().
links(Bundle, Stage, #{mode := same_clock}) ->
    {Backend, Broker} = channel(Bundle, Stage),
    #{mode => same_clock, backends => [Backend], brokers => [Broker], supervision => Backend};
links(_Bundle, Stage, #{mode := independent_endpoints, roles := Roles, namespace := Namespace}) ->
    Opened = [endpoint_management(Stage, Role) || Role <- Roles],
    Adapters = maps:from_list([{Index, Backend} || {Index, Backend, _} <- Opened]),
    #{mode => independent_endpoints, namespace => Namespace,
        backends => [Backend || {_, Backend, _} <- Opened],
        brokers => [Broker || {_, _, Broker} <- Opened],
        supervision => #{mode => independent_endpoints, namespace => Namespace, adapters => Adapters}}.

%% Endpoint management has its own FIFO and session handshake on each independently clocked role.
-spec endpoint_management(file:filename(), map()) -> {non_neg_integer(), pid(), pid()}.
endpoint_management(Stage, #{index := Index, interface := Interface}) ->
    Prefix = filename:join(Stage, "endpoint" ++ integer_to_list(Index)),
    ok = hls_recovery_stream_live:session(Prefix, 1),
    Broker = broker(Prefix ++ "_management"),
    {ok, Backend} = hls_domain_channel_fabric:start_link(
        #{management => Broker, session => 1}, Interface, #{management_timeout_ms => 3000}),
    unlink(Backend),
    {Index, Backend, Broker}.

%% Evidence names distinguish finite independent sampling from the preserved same-clock fixture.
-spec report(map()) -> map().
report(#{witness := attached, namespace := Namespace}) ->
    #{evidence => finite_attached_independent_endpoint_public_stream_witness,
        endpoint_namespace => Namespace, recovery_delivery => natural,
        held_output_frontier_witness => false, remote_descriptor_closure => external_transport_report};
report(#{mode := same_clock}) -> #{evidence => finite_same_clock_public_stream_witness};
report(#{mode := independent_endpoints, namespace := Namespace}) ->
    #{evidence => finite_independent_endpoint_public_stream_witness, endpoint_namespace => Namespace}.

%% Invalid retained ownership fails before connecting to a different live deployment.
-spec require(boolean(), term()) -> ok.
require(true, _) -> ok;
require(false, Reason) -> error({endpoint_live, Reason}).

%% Each role keeps its host management and application traffic in distinct broker lanes.
-spec domain(file:filename(), file:filename(), map(), [map()]) -> map().
domain(Bundle, Stage, #{id := Id, index := Index}, Actors) ->
    Prefix = filename:join(Stage, "domain" ++ integer_to_list(Index)),
    ok = hls_recovery_stream_live:session(Prefix, 1),
    Management = broker(Prefix ++ "_management"),
    Application = broker(Prefix ++ "_application"),
    Store = filename:join(Stage, atom_to_list(Id) ++ ".incarnations"),
    ok = hls_domain_ids:create(Store),
    attached_domain(Bundle, #{id => Id, index => Index}, Actors,
        #{management => Management, application => Application, session => 1, incarnation_file => Store}).

%% Adopts already established broker lanes; never resets a parser or recreates a durable store.
-spec attached_domain(file:filename(), map(), [map()], map()) -> map().
attached_domain(Bundle, #{id := Id, index := Index}, Actors,
    #{management := Management, application := Application, session := Session, incarnation_file := Store}) ->
    true = is_pid(Management) andalso node(Management) =:= node(),
    true = is_pid(Application) andalso node(Application) =:= node(),
    true = Management =/= Application,
    Recipients = maps:from_list(lists:append([case Family of
        phi -> [{{Actor, correction}, self()}, {{Actor, status}, self()}];
        data -> [{{Actor, measurement}, self()}];
        syndrome -> []
    end || #{id := Actor = {Family, _, _}, domain := D} <- Actors, D =:= Id])),
    Interface = filename:join([Bundle, "domain_" ++ integer_to_list(Index), "domain", "interface.etf"]),
    {ok, Backend} = hls_domain_fabric:start_link(
        #{management => Management, application => Application, session => Session}, Interface,
        #{recipients => Recipients, management_timeout_ms => 10000, delivery_timeout_ms => 20000}),
    unlink(Backend),
    try
        {ok, Owner} = hls_domain:start_link(#{Id => automatic},
            #{module => hls_domain_fabric, endpoints => #{Id => Backend}, incarnation_file => Store}),
        unlink(Owner),
        #{id => Id, index => Index, owner => Owner, backend => Backend,
            brokers => [Management, Application]}
    catch Class:Reason:Stack -> stop(Backend), erlang:raise(Class, Reason, Stack) end.


%% Channel management never transports application payload through this host process.
-spec channel(file:filename(), file:filename()) -> {pid(), pid()}.
channel(Bundle, Stage) ->
    Prefix = filename:join(Stage, "channel"),
    ok = hls_recovery_stream_live:session(Prefix, 1),
    Broker = broker(Prefix ++ "_management"),
    {ok, Backend} = hls_domain_channel_fabric:start_link(
        #{management => Broker, session => 1},
        filename:join([Bundle, "channel_management", "interface.etf"]),
        #{management_timeout_ms => 3000}),
    unlink(Backend),
    {Backend, Broker}.

%% Resolve only fresh role handles and fresh crossing generations before application setup.
-spec incarnation(file:filename(), map(), [map()], [map()], pid(), map(), none | map()) -> {map(), map()}.
incarnation(Stage, Metadata, Domains, Crossings, Group, Links, Previous) ->
    OldActors = previous(actors, Previous),
    OldHandles = previous(handles, Previous),
    OldBindings = previous(bindings, Previous),
    Handles = maps:from_list([{Id, begin
        OldEpoch = case maps:find(Id, OldHandles) of {ok, {Id, E}} -> E; error -> 0 end,
        #{handle := Handle = {Id, Epoch}} = ready(Owner, Id, OldEpoch),
        ok = inspection(Stage, Index, Epoch, Links),
        Handle
    end} || #{id := Id, index := Index, owner := Owner} <- Domains]),
    ByIndex = maps:from_list([{Index, maps:get(Id, Handles)} || #{index := Index, id := Id} <- Domains]),
    Bindings = maps:from_list([{I, binding(Group, I,
        case maps:find(I, OldBindings) of {ok, B} -> maps:get(generation, B); error -> 0 end,
        Links, {element(2, maps:get(Source, ByIndex)), element(2, maps:get(Destination, ByIndex))})}
        || #{index := I, source_domain := Source, destination_domain := Destination} <- Crossings]),
    Owners = maps:from_list([{Id, Owner} || #{id := Id, owner := Owner} <- Domains]),
    Actors = maps:from_list([{Actor, begin
        {ok, Pid} = hls_domain:resolve(maps:get(Domain, Owners), maps:get(Domain, Handles), Actor), Pid
    end} || #{id := Actor, domain := Domain} <- maps:get(actors, Metadata)]),
    maps:foreach(fun(_, Pid) ->
        false = is_process_alive(Pid),
        ok = gen_server:cast(Pid, {pauli_update, z})
    end, OldActors),
    #{host_setup := #{prepare := Prepare, start := Start}} = Metadata,
    lists:foreach(fun(#{actor := Actor, message := Message}) ->
        ok = hls_statem:admit_cast(maps:get(Actor, Actors), Message)
    end, Prepare ++ Start),
    History = memory(Metadata, Actors),
    {maps:merge(History#{domain_incarnations => [Epoch || #{id := Id} <- Domains,
            {_, Epoch} <- [maps:get(Id, Handles)]],
        channel_generations => [maps:get(generation, maps:get(I, Bindings)) || #{index := I} <- Crossings]},
        binding_report(Links, Crossings, Bindings)),
        #{actors => Actors, handles => Handles, bindings => Bindings}}.

%% Independent results retain the entire identity, while the existing same-clock report is unchanged.
-spec binding_report(map(), [map()], map()) -> map().
binding_report(#{mode := same_clock}, _, _) -> #{};
binding_report(#{mode := independent_endpoints}, Crossings, Bindings) ->
    #{endpoint_bindings => [(maps:get(I, Bindings))#{index => I} || #{index := I} <- Crossings]}.

%% First startup has no prior identity; replacement must exceed each retained identity explicitly.
-spec previous(atom(), none | map()) -> map().
previous(_, none) -> #{};
previous(Key, Context) -> maps:get(Key, Context).

%% Transport-specific fault scheduling changes only the witness strength, never application replay.
-spec fail_incarnation(file:filename(), map(), [map()], map(), map()) -> map().
fail_incarnation(Stage, Metadata, Domains, Previous, #{witness := attached}) ->
    fail_natural(Stage, Metadata, Domains, Previous);
fail_incarnation(Stage, Metadata, Domains, Previous, _) ->
    fail_incarnation(Stage, Metadata, Domains, Previous).

%% Observe genuine source callback failure and terminal old endpoints with ordinary output delivery.
%% No held receipt, deliberately delayed frontier or physical failure injection is asserted here.
-spec fail_natural(file:filename(), map(), [map()], map()) -> map().
fail_natural(Stage, #{host_setup := #{start := [Trigger | _]}}, Domains, #{actors := Actors}) ->
    #{actor := Actor, actor_index := ActorIndex, message := Message} = Trigger,
    Monitors = monitors(Actors),
    Before = frontiers(Domains),
    ok = hls_statem:admit_cast(maps:get(Actor, Actors), Message),
    Reasons = terminal(Monitors),
    {hls_actor_failure, ActorIndex, #{source_code := Code}} = maps:get(Actor, Reasons),
    true = Code =/= 0,
    Tail = retired_tail(0),
    Evidence = #{trigger => Trigger, terminal_reasons => Reasons, before => Before,
        'after' => frontiers(Domains), retired_quiet_tail => Tail, delivery => natural},
    ok = file:write_file(filename:join(Stage, "recovery.etf"), term_to_binary(Evidence), [exclusive]),
    #{trigger_actor => tuple_to_list(Actor), trigger_message => tuple_to_list(Message),
        admission => accepted, source_failure_code => Code, old_endpoints => map_size(Reasons),
        one_for_all => true, delivery => natural, held_output_frontier_witness => false,
        retired_quiet_tail => Tail,
        reasons => [#{actor => tuple_to_list(A), reason => unicode:characters_to_binary(io_lib:format("~p", [R]))}
            || {A, R} <- lists:sort(maps:to_list(Reasons))]}.

%% A real rejected source callback faults A while accepted output holds its retirement frontier.
%% Host supervision observes lifecycle/counters; only FPGA-local supervisors publish watch receipts.
-spec fail_incarnation(file:filename(), map(), [map()], map()) -> map().
fail_incarnation(Stage, #{host_setup := #{start := [Trigger | _]}}, Domains,
    #{actors := Actors, handles := Handles}) ->
    #{actor := Actor, actor_index := ActorIndex, domain := Id, message := Message} = Trigger,
    [#{index := Index, backend := Backend}] = [D || D = #{id := Name} <- Domains, Name =:= Id],
    {Id, Epoch} = maps:get(Id, Handles),
    Monitors = monitors(Actors),
    Before = frontiers(Domains),
    ok = hls_recovery_stream_live:delivery(Stage, Index, application, hold),
    Parent = self(),
    {Submitter, SubmitMonitor} = spawn_monitor(fun() ->
        Result = hls_statem:admit_cast(maps:get(Actor, Actors), Message),
        Parent ! {fault_admission, self(), Result}
    end),
    Receipt = await(fun() ->
        case hls_domain_fabric:info(Backend) of
            #{received := Received, frontier := Frontier,
                state := #domain_state{current = Epoch, phase = Phase, fault = actor_failure}}
              when Received < Frontier,
                (Phase =:= failed orelse Phase =:= closing orelse Phase =:= stopped) ->
                {ok, #{incarnation => Epoch, phase => Phase,
                    frontier => Frontier, received_at_hold => Received}};
            _ -> wait
        end
    end),
    true = is_process_alive(maps:get(Actor, Actors)),
    ok = file:write_file(filename:join(Stage, "held-retirement.etf"),
        term_to_binary(#{trigger => Trigger, receipt => Receipt, before => Before}), [exclusive]),
    ok = hls_recovery_stream_live:delivery(Stage, Index, application, resume),
    receive {fault_admission, Submitter, ok} -> ok
    after 10000 -> error(fault_command_not_accepted) end,
    receive {'DOWN', SubmitMonitor, process, Submitter, normal} -> ok
    after 10000 -> error(fault_submitter_failed) end,
    Reasons = terminal(Monitors),
    {hls_actor_failure, ActorIndex, #{source_code := Code}} = maps:get(Actor, Reasons),
    true = Code =/= 0,
    Tail = retired_tail(0),
    After = frontiers(Domains),
    Frontier = maps:get(frontier, Receipt),
    #{received := ReceivedAfter} = maps:get(Id, After),
    true = ReceivedAfter >= Frontier,
    Evidence = #{trigger => Trigger, receipt => Receipt, terminal_reasons => Reasons,
        before => Before, 'after' => After, retired_quiet_tail => Tail},
    ok = file:write_file(filename:join(Stage, "recovery.etf"), term_to_binary(Evidence), [exclusive]),
    #{trigger_actor => tuple_to_list(Actor), trigger_message => tuple_to_list(Message),
        admission => accepted, source_failure_code => Code,
        old_endpoints => map_size(Reasons), held_frontier => Frontier,
        held_received => maps:get(received_at_hold, Receipt), received_after_retirement => ReceivedAfter,
        old_actor_alive_until_delivery_resumed => true, outputs_retirement_frontier_closed => true,
        one_for_all => true, retired_quiet_tail => Tail,
        reasons => [#{actor => tuple_to_list(A), reason => unicode:characters_to_binary(io_lib:format("~p", [R]))}
            || {A, R} <- lists:sort(maps:to_list(Reasons))]}.

%% Endpoint monitors are installed before submitting the fault or final group shutdown.
-spec monitors(map()) -> [{term(), pid(), reference()}].
monitors(Actors) -> [{Actor, Pid, monitor(process, Pid)} || {Actor, Pid} <- maps:to_list(Actors)].

%% All old endpoints must terminate for a known reason; transport uncertainty is not recovery.
-spec terminal([{term(), pid(), reference()}]) -> map().
terminal(Monitors) -> maps:from_list([receive
    {'DOWN', Ref, process, Pid, Reason} ->
        true = Reason =/= noconnection andalso Reason =/= noproc,
        {Actor, Reason}
    after 20000 -> error({actor_not_retired, Actor}) end || {Actor, Pid, Ref} <- Monitors]).

%% Public backend counters describe only accepted host-output progress, not source execution history.
-spec frontiers([map()]) -> map().
frontiers(Domains) -> maps:from_list([{Id, maps:with([received, frontier, pending],
    hls_domain_fabric:info(Backend))} || #{id := Id, backend := Backend} <- Domains]).

%% The finite closeout matches the existing reference's same-sender ordering and geometry.
-spec memory(map(), map()) -> map().
memory(#{width := Width, request := Request, basis := Basis}, Actors) ->
    Deadline = erlang:monotonic_time(millisecond) + 180000,
    {Fence, Events, Corrections} = collect(Width, Actors, #{}, [], [], Deadline),
    [ok = hls_statem:admit_cast(maps:get({data, X, 0}, Actors), {pauli_query, Request, Basis})
        || X <- lists:seq(0, Width - 1)],
    Replies = replies(Width, Request, #{}, Deadline),
    #{fence => Fence, events => lists:reverse(Events), corrections => lists:reverse(Corrections),
        replies => [[X, Bit] || {X, Bit} <- lists:sort(maps:to_list(Replies))]}.

%% Consume every correction before accepting the common quiet fence; no global sender order is assumed.
-spec collect(pos_integer(), map(), map(), [list()], [list()], integer()) ->
    {non_neg_integer(), [list()], [list()]}.
collect(Width, Actors, Rounds, Events, Corrections, Deadline) ->
    case event(Deadline) of
        Correction = {phi_correction, Step, X, 0, Direction} ->
            {{Destination, 0}, Pauli} = phi_repetition_memory:correction_update(Correction, Width),
            ok = hls_statem:admit_cast(maps:get({data, Destination, 0}, Actors), {pauli_update, Pauli}),
            collect(Width, Actors, Rounds,
                [[X, 0, Step, phi_correction, Direction] | Events],
                [[X, 0, Step, Direction, Destination] | Corrections], Deadline);
        {phi_status, Step, X, 0, Flags} when Step >= 0, Step < 512, X >= 0, X < Width,
            Flags >= 0, Flags =< 3 ->
            Round = maps:get(Step, Rounds, #{}),
            false = maps:is_key(X, Round),
            Updated = Round#{X => Flags},
            NewEvents = [[X, 0, Step, phi_status, Flags] | Events],
            case map_size(Updated) =:= Width andalso lists:all(fun(F) -> F =:= 2 end, maps:values(Updated)) of
                true -> {Step, NewEvents, Corrections};
                false -> collect(Width, Actors, Rounds#{Step => Updated}, NewEvents, Corrections, Deadline)
            end;
        Other -> error({unexpected_domain_event, Other})
    end.

%% Readout follows all correction admissions; extra empty statuses do not alter the memory result.
-spec replies(pos_integer(), non_neg_integer(), map(), integer()) -> map().
replies(Width, _, Replies, _) when map_size(Replies) =:= Width -> Replies;
replies(Width, Request, Replies, Deadline) ->
    case event(Deadline) of
        {pauli_reply, Request, X, 0, Bit} when X >= 0, X < Width, Bit >= 0, Bit =< 1 ->
            false = maps:is_key(X, Replies),
            replies(Width, Request, Replies#{X => Bit}, Deadline);
        {phi_status, _, _, _, 2} -> replies(Width, Request, Replies, Deadline);
        Other -> error({unexpected_domain_readout, Other})
    end.

%% FIFO-source effects arrive through their ordinary domain actor endpoints.
-spec event(integer()) -> tuple().
event(Deadline) ->
    receive {'$gen_cast', Event} -> Event
    after max(0, Deadline - erlang:monotonic_time(millisecond)) -> error(domain_memory_timeout) end.

%% Terminal endpoint delivery may leave only already-completed empty-status observations.
-spec retired_tail(non_neg_integer()) -> non_neg_integer().
retired_tail(Count) ->
    receive {'$gen_cast', {phi_status, _, _, _, 2}} -> retired_tail(Count + 1);
        {'$gen_cast', Other} -> error({unexpected_retired_output, Other})
    after 0 -> Count end.

%% Public inspection addresses are exercised independently from application packet lanes.
-spec inspection(file:filename(), non_neg_integer(), pos_integer(), map()) -> ok.
inspection(_Stage, Index, Epoch, #{witness := attached, inspect := Inspect}) -> Inspect(Index, Epoch);
inspection(Stage, Index, Epoch, _) ->
    file:write_file(filename:join(Stage, "domain" ++ integer_to_list(Index) ++ "_inspection.control"),
        integer_to_binary(Epoch)).

%% Readiness requires a confirmed incarnation, never elapsed time alone.
-spec ready(pid(), atom(), non_neg_integer()) -> map().
ready(Owner, Id, Previous) -> await(fun() -> case hls_domain:status(Owner, Id) of
    {ok, #{phase := ready, handle := {Id, Epoch}} = Snapshot} when Epoch > Previous -> {ok, Snapshot};
    _ -> wait end end).

%% The confirmed crossing binding fixes both endpoint lifetimes for this application run.
-spec binding(pid(), non_neg_integer(), non_neg_integer(), map(), {pos_integer(), pos_integer()}) -> map().
binding(Group, Index, Previous, Links, Incarnations) ->
    await(fun() -> case lists:keyfind({channel, Index}, 1, supervisor:which_children(Group)) of
        {{channel, Index}, Pid, worker, _} when is_pid(Pid) ->
            binding_status(Pid, Previous, Links, Incarnations);
        _ -> wait
    end end).

%% The same-clock worker retains its original readiness and generation contract.
-spec binding_status(pid(), non_neg_integer(), map(), {pos_integer(), pos_integer()}) -> {ok, map()} | wait.
binding_status(Pid, Previous, #{mode := same_clock}, _) ->
    case hls_domain_channel_instance:status(Pid) of
        #{phase := ready, active := true, generation := Generation} = Snapshot when Generation > Previous ->
            {ok, Snapshot};
        _ -> wait
    end;
%% Both independently observed endpoints must carry one complete binding matching these current domains.
binding_status(Pid, Previous, #{mode := independent_endpoints, namespace := Namespace}, {Source, Destination}) ->
    case hls_domain_endpoint_pair:status(Pid) of
        #{phase := ready, binding := Binding = #endpoint_binding{generation = Generation},
            tx := #{binding := Binding, active := true, fault := false},
            rx := #{binding := Binding, active := true, fault := false}} when Generation > Previous ->
            #endpoint_binding{namespace = Namespace, source_incarnation = Source,
                destination_incarnation = Destination} = Binding,
            {ok, #{namespace => Namespace, generation => Generation,
                source_incarnation => Source, destination_incarnation => Destination}};
        _ -> wait
    end.

%% Bound observation retries without replaying an application operation.
-spec await(fun(() -> {ok, term()} | wait)) -> term().
await(Fun) -> await(Fun, erlang:monotonic_time(millisecond) + 30000).

%% A failed readiness condition preserves an explicit timeout rather than inventing success.
-spec await(fun(() -> {ok, term()} | wait), integer()) -> term().
await(Fun, Deadline) -> case Fun() of
    {ok, Result} -> Result;
    wait -> true = erlang:monotonic_time(millisecond) < Deadline,
        receive after 2 -> await(Fun, Deadline) end
end.

%% Retain the broker's actual descriptor lease for verified shutdown.
-spec lease(pid()) -> reference().
lease(Broker) -> #{io := #{lease := Lease}} = hls_fabric:info(Broker), Lease.

%% The broker owns one bounded framed route on each independent lane.
-spec broker(file:filename()) -> pid().
broker(Prefix) ->
    {ok, Broker} = hls_fabric:start_link(Prefix ++ "_tx", Prefix ++ "_rx", #{rx_route_limit => 1}),
    unlink(Broker), Broker.

%% Cleanup also accepts a group already retired by its normal OTP shutdown path.
-spec stop(pid()) -> ok.
stop(Pid) -> catch gen_server:stop(Pid, shutdown, 10000), ok.

%% A failed attached run closes the peer transport instead of leaving a reusable uncertain session.
-spec finish_failed_transport(file:filename(), map()) -> ok.
finish_failed_transport(Stage, #{witness := attached}) ->
    case file:write_file(filename:join(Stage, "finished"), <<>>, [exclusive]) of
        ok -> ok;
        {error, eexist} -> ok;
        {error, Reason} -> error({transport_finish, Reason})
    end;
finish_failed_transport(_, _) -> ok.
