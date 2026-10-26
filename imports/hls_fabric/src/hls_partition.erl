-module(hls_partition).
-moduledoc """
Expands a logical topology into an explicit multi-device deployment.

Actor placement uses the same identities as the actor catalog: `{actor, Id}`
or `{family, Family, Coordinates}`. Each directed source/recipient pair owns
one lane, including when several output ports alias that recipient. Remote
lane numbers are dense within each direction and belong to this deployment,
not to Erlang PIDs or the public application endpoint namespace.

Direct routes, queued fanout and rectangle control ingress retain their global
identities. `hls_partition_schedule:shared/2` optionally binds every actor to a
device-local RAM executor. `hls_partition_reduction:attach/3` can then offload
eligible closed family exchanges while retaining these same transport lanes.
""".
-export([normalize/2, normalize/3, device/2]).

-doc "Builds a checked multi-device deployment from actor placements. Rejects incompatible encodings and unsupported route delivery.".
-spec normalize(hls_topology:plan(), map()) -> map().
normalize(Plan, Placement) -> normalize(Plan, Placement, hls_frame_layout:default()).

-doc "Builds a deployment with one checked ordinary-frame capacity. Every actor, mailbox, startup table and support bundle must use this same layout; bridge envelopes retain their independent limits.".
-spec normalize(hls_topology:plan(), map(), hls_frame_layout:layout()) -> map().
normalize(Plan = #{actors := Exact, families := Families, ingresses := _Ingresses,
        externals := Externals, startup := Startup}, Placement, Layout) when is_map(Placement) ->
    Expanded = expand_actors(Exact, Families),
    Identities = [Id || #{identity := Id} <- Expanded],
    ok = check_placement(Identities, Placement),
    Devices = lists:usort(maps:values(Placement)),
    case length(Devices) of
        N when N >= 2 -> ok;
        _ -> error({partition_device_count, Devices})
    end,
    RawIds = maps:from_list([{Raw, Id} || #{raw_id := Raw, identity := Id} <- Expanded]),
    Interfaces = hls_actor_interface:from_modules([M || #{module := M} <- Expanded], Layout),
    StartupIndex = maps:from_list([{maps:get(Target, RawIds), Messages}
        || #{target := Target, messages := Messages} <- Startup]),
    Actors = [actor(A, Index, Placement, Interfaces, StartupIndex, Layout)
        || {Index, A} <- lists:enumerate(0, Expanded)],
    ActorIndex = maps:from_list([{Id, A} || A = #{identity := Id} <- Actors]),
    Routes = routes(Plan, Expanded, RawIds),
    ok = validate_routes(Routes, ActorIndex, Interfaces, Layout),
    ok = validate_external_encodings(Routes, ActorIndex, Interfaces, Layout),
    Lanes = lanes(Routes, ActorIndex),
    #{version => 1, frame_layout => Layout, devices => Devices, actors => local_slots(Actors),
        routes => Routes, lanes => Lanes,
        ingresses => hls_partition_ingress:lower(Plan, Actors, Interfaces),
        externals => [E#{index => I, port => "external_" ++ integer_to_list(I) ++ "_out"}
            || {I, E} <- lists:enumerate(0, Externals)]};
normalize(_Plan, _Placement, _Layout) -> error(invalid_partition_input).

-doc "Returns derived local bindings; the deployment remains their authority.".
-spec device(map(), term()) -> map().
device(Partition = #{devices := Devices, actors := Actors, lanes := Lanes, externals := Externals,
        ingresses := Ingresses}, Device) ->
    case lists:member(Device, Devices) of
        true -> ok;
        false -> error({unknown_partition_device, Device})
    end,
    LocalActors = [A || A = #{device := D} <- Actors, D =:= Device],
    LocalLanes = [L || L = #{source_device := D} <- Lanes, D =:= Device],
    Tx = [L || L = #{kind := remote} <- LocalLanes],
    Rx = [L || L = #{kind := remote, destination_device := D} <- Lanes, D =:= Device],
    ExternalIds = lists:usort([Id || #{destination := {external, Id}} <- LocalLanes]),
    hls_partition_tile:local(Partition, hls_partition_schedule:local(Partition, #{id => Device, actors => LocalActors, lanes => LocalLanes,
        transport => maps:get(transport, Partition, serial),
        frame_layout => maps:get(frame_layout, Partition, hls_frame_layout:default()),
        reduction_inputs => maps:with([Id || #{identity := Id} <- LocalActors],
            maps:get(reduction_inputs, Partition, #{})),
        tx_lanes => Tx, rx_lanes => Rx, links => links(Tx, Rx),
        ingresses => [I#{bindings := Local} || I = #{bindings := Bindings} <- Ingresses,
            Local <- [[A || A = #{device := D} <- Bindings, D =:= Device]], Local =/= []],
        externals => [E || E = #{id := Id} <- Externals, lists:member(Id, ExternalIds)]})).

%% Expand family coordinates into stable logical identities alongside singleton actors.
-spec expand_actors([map()], [map()]) -> [map()].
expand_actors(Exact, Families) ->
    lists:sort(fun(#{identity := A}, #{identity := B}) -> A < B end,
        [A#{identity => {actor, Id}, raw_id => Id} || A = #{id := Id} <- Exact] ++
        lists:append([[#{identity => {family, Id, Coordinates},
            raw_id => list_to_tuple([Id | Coordinates]), module => Module,
            outputs => Outputs, mailbox_capacity => Capacity}
            || Coordinates <- coordinates(Shape)]
            || #{id := Id, module := Module, shape := Shape,
                outputs := Outputs, mailbox_capacity := Capacity} <- Families])).

%% Enumerate each coordinate in row-major Cartesian product order.
-spec coordinates([pos_integer()]) -> [[non_neg_integer()]].
coordinates([]) -> [[]];
coordinates([Size | Rest]) -> [[I | Tail] || I <- lists:seq(0, Size-1), Tail <- coordinates(Rest)].

%% Require exactly one placement for every expanded actor.
-spec check_placement([term()], map()) -> ok.
check_placement(Identities, Placement) ->
    Keys = maps:keys(Placement),
    case {Identities -- Keys, Keys -- Identities} of
        {[], []} -> ok;
        {Missing, Extra} -> error({partition_placement, Missing, lists:sort(Extra)})
    end.

%% Attach device assignment and packed startup messages; reject conflicting initial effects.
-spec actor(map(), non_neg_integer(), map(), map(), map(), hls_frame_layout:layout()) -> map().
actor(A = #{identity := Id, module := Module}, Index, Placement, Interfaces, Startup, Layout) ->
    Interface = maps:get(Module, Interfaces),
    Messages = maps:get(Id, Startup, []),
    case {Messages, hls_actor_interface:initial_effects(Interface)} of
        {[], _} -> ok;
        {_, []} -> ok;
        {_, Effects} -> error({partition_startup_initial_effects, Id, Effects})
    end,
    _ = xls_shared_topology_profile:identifier(Module, partition_actor),
    A#{index => Index, device => maps:get(Id, Placement),
        max_entry_effects => hls_actor_interface:max_entry_effects(Interface),
        startup => [pack_startup(Id, Module, Message, Layout) || Message <- Messages]}.

%% Number actors densely within each device while retaining global order.
-spec local_slots([map()]) -> [map()].
local_slots(Actors) ->
    {Result, _} = lists:mapfoldl(fun(A = #{device := D}, Counts) ->
        Slot = maps:get(D, Counts, 0),
        {A#{local_slot => Slot}, Counts#{D => Slot+1}}
    end, #{}, Actors),
    Result.

%% Encode one startup record and enforce the ordinary frame bound.
-spec pack_startup(term(), module(), tuple(), hls_frame_layout:layout()) -> map().
pack_startup(Id, Module, Message, Layout) when is_tuple(Message), tuple_size(Message) > 0 ->
    Tag = Module:pack_tag(element(1, Message)),
    Payload = hls_codec:align(Module:pack(Message), 32),
    case Tag >= 0 andalso Tag =< 255 andalso bit_size(Payload) =< hls_frame_layout:payload_bits(Layout) of
        true -> #{selector => Tag, payload => Payload};
        false -> error({partition_startup_encoding, Id, Message})
    end;
pack_startup(Id, _Module, Message, _) -> error({partition_startup_message, Id, Message}).

%% Expand compact routes and replace raw names by canonical logical identities.
-spec routes(hls_topology:plan(), [map()], map()) -> [map()].
routes(Plan = #{routes := Exact}, Actors, RawIds) ->
    Expanded = Exact ++ lists:append([hls_topology:routes_for_instance(Plan, Id, Coordinates)
        || #{identity := {family, Id, Coordinates}} <- Actors]),
    lists:sort([R#{source := {maps:get(Source, RawIds), Port},
        recipients := [case Recipient of
            {actor, Target} -> {actor, maps:get(Target, RawIds)};
            {external, _} -> Recipient
        end || Recipient <- Recipients]}
        || R = #{source := {Source, Port}, recipients := Recipients} <- Expanded]).

%% Check delivery policy and exact schema compatibility on every actor-to-actor route.
-spec validate_routes([map()], map(), map(), hls_frame_layout:layout()) -> ok.
validate_routes(Routes, Actors, Interfaces, Layout) ->
    lists:foreach(fun(#{source := Source = {Id, Port}, delivery := Delivery,
            recipients := Recipients}) ->
        case {Delivery, length(Recipients)} of
            {direct, 1} -> ok;
            {queued, N} when N > 1 -> ok;
            _ -> error({partition_route_delivery, Source, Delivery})
        end,
        #{module := Module} = maps:get(Id, Actors),
        Interface = maps:get(Module, Interfaces),
        Schemas = hls_actor_interface:output_schemas(Interface, Port),
        lists:foreach(fun(Schema) ->
            Encoding = encoding(Interface, Schema, Layout),
            lists:foreach(fun
                ({actor, Target}) ->
                    #{module := TargetModule} = maps:get(Target, Actors),
                    TargetEncoding = encoding(maps:get(TargetModule, Interfaces), Schema, Layout),
                    case Encoding =:= TargetEncoding of
                        true -> ok;
                        false -> error({partition_route_encoding, Source, Target, Schema})
                    end;
                ({external, _}) -> ok
            end, Recipients)
        end, Schemas)
    end, Routes).

%% Read a schema's selector and fields, rejecting representations outside the ordinary frame ABI.
-spec encoding(hls_actor_interface:summary(), atom(), hls_frame_layout:layout()) -> {byte(), [map()]}.
encoding(Interface, Schema, Layout) ->
    #{selector := Selector, fields := Fields} = hls_actor_interface:schema(Interface, Schema),
    Width = lists:sum([hls_type:width(Type) || #{type := Type} <- Fields]),
    case Selector >= 0 andalso Selector =< 255 andalso Width =< hls_frame_layout:payload_bits(Layout) of
        true -> {Selector, Fields};
        false -> error({partition_frame_encoding, Schema, Selector, Width})
    end.

%% Require all producers of each external schema/selector to agree on its encoding.
-spec validate_external_encodings([map()], map(), map(), hls_frame_layout:layout()) -> ok.
validate_external_encodings(Routes, Actors, Interfaces, Layout) ->
    _ = lists:foldl(fun(#{source := {Id, Port}, recipients := Recipients}, Acc0) ->
        #{module := Module} = maps:get(Id, Actors),
        Interface = maps:get(Module, Interfaces),
        lists:foldl(fun({External, Schema}, Acc) ->
            Encoding = {Selector, _Fields} = encoding(Interface, Schema, Layout),
            Acc1 = consistent({External, schema, Schema}, Encoding, Acc),
            consistent({External, selector, Selector}, Schema, Acc1)
        end, Acc0, [{External, Schema} || {external, External} <- Recipients,
            Schema <- hls_actor_interface:output_schemas(Interface, Port)])
    end, #{}, Routes),
    ok.

%% Insert an external encoding fact or reject a conflicting previous fact.
-spec consistent(term(), term(), map()) -> map().
consistent(Key, Value, Map) ->
    case Map of
        #{Key := Value} -> Map;
        #{Key := Other} -> error({partition_external_encoding, Key, Other, Value});
        _ -> Map#{Key => Value}
    end.

%% Share a lane across aliased ports and allocate dense wire IDs per device direction.
-spec lanes([map()], map()) -> [map()].
lanes(Routes, Actors) ->
    LanePorts = lists:foldl(fun(#{source := {Source, Port}, recipients := Recipients}, Acc0) ->
        lists:foldl(fun(Recipient, Acc) ->
            maps:update_with({Source, Recipient}, fun(Ports) -> [Port | Ports] end, [Port], Acc)
        end, Acc0, Recipients)
    end, #{}, Routes),
    Lanes = [lane(Id, Source, Recipient, Ports, Actors)
        || {Id, {{Source, Recipient}, Ports}} <- lists:enumerate(0, lists:sort(maps:to_list(LanePorts)))],
    {Numbered, _} = lists:mapfoldl(fun
        (L = #{kind := remote, source_device := Source, destination_device := Target}, Counts) ->
            Key = {Source, Target},
            Wire = maps:get(Key, Counts, 0),
            case Wire < 32768 of
                true -> {L#{wire_id => Wire}, Counts#{Key => Wire+1}};
                false -> error({partition_lane_count, Key})
            end;
        (L, Counts) -> {L, Counts}
    end, #{}, Lanes),
    Numbered.

%% Classify one source/destination pair as local, remote or external.
-spec lane(non_neg_integer(), term(), {actor | external, term()}, [atom()], map()) -> map().
lane(Id, Source, Recipient, Ports, Actors) ->
    #{device := Device} = maps:get(Source, Actors),
    {Kind, Destination} = case Recipient of
        {actor, Target} ->
            #{device := TargetDevice} = maps:get(Target, Actors),
            {case Device =:= TargetDevice of true -> local; false -> remote end, TargetDevice};
        {external, _} -> {external, Device}
    end,
    #{id => Id, source => Source, destination => Recipient,
        source_device => Device, destination_device => Destination,
        kind => Kind, ports => lists:sort(Ports)}.

%% Physical peers have independent wire namespaces and frame arrays.
-spec links([map()], [map()]) -> [map()].
links(Tx, Rx) ->
    Peers = lists:usort([D || #{destination_device := D} <- Tx] ++
        [D || #{source_device := D} <- Rx]),
    [#{index => I, peer => Peer,
        tx_lanes => [L || L = #{destination_device := D} <- Tx, D =:= Peer],
        rx_lanes => [L || L = #{source_device := D} <- Rx, D =:= Peer]}
        || {I, Peer} <- lists:enumerate(0, Peers)].
