-module(hls_bridge_phi_live).
-moduledoc false.
-export([run/1, connect/3, link_output/1, blocked/2, inspect/1, inspect/2, failure_inspect/1, await/2, save/3]).

%% VPI transports only these two public debug streams. All observations come
%% from the production query protocol and the public decoder event outputs.
run(Stage) ->
    {ok, _} = application:ensure_all_started(crypto),
    Connections = [connect(Stage, Device, Prefix)
        || {Device, Prefix} <- [{0, "app"}, {1, "debug"}]],
    try
        [First, _] = Connections,
        #{session := Session, manifest := Manifest} = First,
        Link = link_output(Manifest),
        await(fun() -> blocked(Session, Link) end, 30000),
        Before = [inspect(Connection) || Connection <- Connections],
        [#{seeds := [_ | _], waits := #{edges := Edges,
            reobserved_blocked := Blocked}} | _] = Before,
        true = lists:any(fun(#{kind := Kind, channel := Channel}) ->
            Kind =:= external_sink andalso Channel =:= Link
        end, Edges),
        true = lists:member(Link, Blocked),
        save(Stage, "blocked.json", Before),
        ok = file:write_file(filename:join(Stage, "pause_peer"), <<>>),
        await(fun() -> filelib:is_file(filename:join(Stage, "peer_paused")) end, 30000),
        ok = file:write_file(filename:join(Stage, "release_link"), <<>>),
        await(fun() -> filelib:is_file(filename:join(Stage, "link_released")) end, 30000),
        %% With the admission gate open, the stopped peer fills the crossing.
        %% Only query the running device; the peer cannot answer without clocks.
        await(fun() -> blocked(Session, Link) end, 30000),
        Paused = inspect(First),
        #{link := #{valid := true, ready := false}} = Paused,
        save(Stage, "paused-peer.json", Paused),
        ok = file:write_file(filename:join(Stage, "resume_peer"), <<>>),
        await(fun() -> filelib:is_file(filename:join(Stage, "peer_resumed")) end, 30000),
        {ok, OracleBytes} = file:read_file(filename:join(Stage, "oracle.json")),
        Oracle = json:decode(OracleBytes),
        {ok, [Config]} = file:consult(filename:join(Stage, "config.term")),
        {_, Placement} = hls_bridge_phi_fixture:fixture(Config),
        {ok, MetadataBytes} = file:read_file(filename:join(Stage, "bridge.json")),
        #{<<"devices">> := Devices} = json:decode(MetadataBytes),
        Streams = maps:from_list([{{Device, Index}, plane(Name)}
            || #{<<"id">> := Device, <<"externals">> := Externals} <- Devices,
               #{<<"index">> := Index, <<"name">> := Name} <- Externals]),
        Expected = per_actor(Oracle),
        await(fun() ->
            Actual = per_actor(events(Stage, Streams, Placement)),
            %% Compare every available prefix immediately, rather than turning
            %% an incorrect event into an uninformative completion timeout.
            maps:foreach(fun(Key, Values) ->
                Wanted = maps:get(Key, Expected),
                case lists:prefix(Values, Wanted) of
                    true -> ok;
                    false -> error({event_mismatch, Key, Values, Wanted})
                end
            end, Actual),
            Actual =:= Expected
        end, 600000),
        After = [inspect(Connection) || Connection <- Connections],
        save(Stage, "recovered.json", After),
        %% Recheck after the recovery queries advance the simulator: a delayed
        %% duplicate from the measured rounds must not escape on first completion.
        %% This remains a finite-run witness, ending at this final observation.
        Observed = events(Stage, Streams, Placement),
        Expected = per_actor(Observed),
        save(Stage, "observed.json", Observed),
        Leases = [begin
            ok = hls_debug:stop(Client),
            #{io := #{lease := Lease}} = hls_fabric:info(Fabric),
            ok = hls_fabric:stop(Fabric),
            Lease
        end || #{client := Client, fabric := Fabric} <- Connections],
        ok = file:write_file(filename:join(Stage, "done"), <<>>),
        [ok = hls_fabric:await_closed(Lease, 5000) || Lease <- Leases],
        io:format("PASS: two independent devices; public debug identifies held link; ~p ordered phi events match BEAM through step 32~n",
            [length(Oracle)])
    catch Class:Reason:Stack ->
        %% Preserve public evidence before tearing down either debug transport.
        %% Failure to inspect a broken device must not replace the original error.
        Diagnostics = [failure_inspect(Connection) || Connection <- Connections],
        _ = catch save(Stage, "failure-debug.json",
            #{error => error_text(Class, Reason), devices => Diagnostics}),
        erlang:raise(Class, Reason, Stack)
    after
        [begin catch hls_debug:stop(Client), catch hls_fabric:stop(Fabric) end
            || #{client := Client, fabric := Fabric} <- Connections]
    end.

-doc "Opens one device's public debug session and verifies its manifest.".
-spec connect(file:filename(), non_neg_integer(), string()) -> map().
connect(Stage, Device, Prefix) ->
    {ok, Bytes} = file:read_file(filename:join(Stage,
        "device" ++ integer_to_list(Device) ++ "-manifest.json")),
    Manifest = json:decode(Bytes),
    {ok, Fabric} = hls_fabric:start_link(filename:join(Stage, Prefix ++ "_tx"),
        filename:join(Stage, Prefix ++ "_rx")),
    {ok, Client} = hls_debug:start_link(undefined, {fabric, Fabric, 2}),
    {ok, Session} = hls_shared_observation:open(Client, Manifest),
    #{device => Device, client => Client, fabric => Fabric,
        manifest => Manifest, session => Session}.

-doc "Finds the public link-output probe in an instrumentation manifest.".
-spec link_output(map()) -> non_neg_integer().
link_output(#{<<"probes">> := Probes}) ->
    [Id] = [Id || #{<<"id">> := Id, <<"endpoints">> := Endpoints} <- Probes,
        lists:any(fun(Endpoint) ->
            maps:get(<<"external">>, Endpoint, false) andalso
                maps:get(<<"role">>, Endpoint) =:= <<"consumer">> andalso
                maps:get(<<"port">>, Endpoint) =:= <<"_link_0_out">>
        end, Endpoints)],
    Id.

-doc "Reports whether a sampled public channel currently has valid data without readiness.".
-spec blocked(map(), non_neg_integer()) -> boolean().
blocked(Session, Resource) ->
    {ok, #{valid := Valid, ready := Ready}} = hls_topology_debug:query(Session, Resource),
    Valid andalso not Ready.

-doc "Samples bounded FIFO occupancy and follows wait dependencies from full queues.".
-spec inspect(map()) -> map().
inspect(#{device := Device, session := Session, manifest := Manifest}) ->
    Link = link_output(Manifest),
    {ok, LinkSample} = hls_topology_debug:query(Session, Link),
    Queues = [Queue || Queue = #{<<"kind">> := <<"fifo">>} <- maps:get(<<"resources">>, Manifest)],
    %% Start the adaptive walk from full queues alone. The separately queried
    %% link is a predicted endpoint, not a seed which could predetermine the result.
    Samples = queue_samples(Session, Queues, 8, []),
    observation(Device, Session, LinkSample, Samples).

-doc "Rechecks selected FIFO IDs and follows any remaining full-queue dependencies.".
-spec inspect(map(), [non_neg_integer()]) -> map().
inspect(#{device := Device, session := Session, manifest := Manifest}, Queues) ->
    {ok, LinkSample} = hls_topology_debug:query(Session, link_output(Manifest)),
    Samples = [begin
        {ok, Sample = #{occupancy := _}} = hls_topology_debug:query(Session, Id), Sample
    end || Id <- Queues],
    observation(Device, Session, LinkSample, Samples).

%% Limit the dependency walk while retaining the samples that selected its seeds.
-spec observation(non_neg_integer(), map(), map(), [map()]) -> map().
observation(Device, Session, LinkSample, Samples) ->
    Full = [Id || #{id := Id, occupancy := Occupancy, free_slots := 0} <- Samples,
        Occupancy > 0],
    Seeds = lists:sublist(Full, 8),
    {ok, Waits} = hls_topology_debug:inspect_waits(Session,
        Seeds, #{max_queries => 256}),
    #{device => Device, link => LinkSample, queues => Samples, seeds => Seeds, waits => Waits}.

-doc "Preserves diagnostic failure as data without masking the original test error.".
-spec failure_inspect(map()) -> map().
failure_inspect(Connection = #{device := Device}) ->
    try inspect(Connection)
    catch Class:Reason -> #{device => Device, error => error_text(Class, Reason)}
    end.

error_text(Class, Reason) ->
    unicode:characters_to_binary(io_lib:format("~tp", [{Class, Reason}])).

events(Stage, Streams, Placement) ->
    case file:read_file(filename:join(Stage, "reports.log")) of
        {error, enoent} -> [];
        {ok, Bytes} ->
            Lines = binary:split(Bytes, <<"\n">>, [global]),
            %% Ignore the final incomplete line while the simulator is writing.
            Complete = lists:sublist(Lines, length(Lines)-1),
            [Event || Line <- Complete, Line =/= <<>>,
                Event = [_, _, _, Step, _, _] <- [event(Line, Streams, Placement)], Step =< 32]
    end.

event(Line, Streams, Placement) ->
    [DeviceText, ExternalText, FrameText] = string:lexemes(binary_to_list(Line), " \t\r"),
    Device = list_to_integer(DeviceText),
    Plane = maps:get({Device, list_to_integer(ExternalText)}, Streams),
    Frame = list_to_integer(FrameText, 16),
    Header = Frame bsr 96,
    3 = Header bsr 24,
    0 = (Header bsr 8) band 65535,
    Schema = phi_halo_cell:unpack_tag(Header band 255),
    true = lists:member(Schema, [phi_correction, phi_status]),
    {{Schema, Step, X, Y, Value}, <<>>} = phi_halo_cell:unpack(Schema, <<Frame:96/little>>),
    Family = case Plane of 0 -> phi_x; 1 -> phi_z end,
    Device = maps:get({actor, {Family, X, Y}}, Placement),
    [Plane, X, Y, Step, atom_to_binary(Schema), Value].

plane(<<"x_decoder_events">>) -> 0;
plane(<<"z_decoder_events">>) -> 1.

per_actor(Events) ->
    lists:foldr(fun([Plane, X, Y, Step, Kind, Value], Acc) ->
        maps:update_with({Plane, X, Y}, fun(Previous) -> [{Step, Kind, Value} | Previous] end,
            [{Step, Kind, Value}], Acc)
    end, #{}, Events).

-doc "Waits for a predicate or raises at its monotonic deadline.".
-spec await(fun(() -> boolean()), non_neg_integer()) -> ok.
await(Fun, Timeout) -> await_until(Fun, erlang:monotonic_time(millisecond) + Timeout).
await_until(Fun, Deadline) ->
    case Fun() of
        true -> ok;
        false ->
            case erlang:monotonic_time(millisecond) < Deadline of
                true -> timer:sleep(10), await_until(Fun, Deadline);
                false -> error({condition_timeout, Fun})
            end
    end.

-doc "Writes a JSON observation beside the simulation artifacts.".
-spec save(file:filename(), file:filename(), term()) -> ok | {error, file:posix()}.
save(Stage, Name, Value) -> file:write_file(filename:join(Stage, Name), json:encode(Value)).

%% Search the declared queue catalog until enough full queues seed the walk.
%% A prefix bound can miss every active queue in a large generated topology.
-spec queue_samples(map(), [map()], non_neg_integer(), [map()]) -> [map()].
queue_samples(_Session, [], _Remaining, Samples) -> lists:reverse(Samples);
queue_samples(_Session, _Queues, 0, Samples) -> lists:reverse(Samples);
queue_samples(Session, [#{<<"id">> := Id} | Rest], Remaining, Samples) ->
    {ok, Sample} = hls_topology_debug:query(Session, Id),
    Found = case Sample of
        #{occupancy := Occupancy, free_slots := 0} when Occupancy > 0 -> 1;
        _ -> 0
    end,
    queue_samples(Session, Rest, Remaining-Found, [Sample | Samples]).
