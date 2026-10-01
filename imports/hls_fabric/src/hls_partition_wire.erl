-module(hls_partition_wire).
-moduledoc "Checked application bindings and codecs for one rectangle ingress per device.".
-export([deployment/1, command/2, event/4, wrapper/3]).
-export_type([command/0]).

%% Fixed application-gateway bindings, unrelated to actor IDs or geometry.
%% The values are arbitrary; the XLS gateway shares FIRST_EVENT_ENDPOINT.
-define(CONTROL_ENDPOINT, 7).
-define(FIRST_EVENT_ENDPOINT, 8).

-doc "A typed record addressed to one ingress target within inclusive global bounds.".
-type command() :: {atom(), atom(), {integer(), integer(), integer(), integer()}, tuple()}.

-doc "Derives fixed control/event endpoints and a per-device SHA-256 identity covering placement, startup and wire bindings.".
-spec deployment(map()) -> map().
deployment(Partition = #{devices := Devices}) ->
    #{partition => Partition, devices => maps:from_list([begin
        Local = #{ingresses := [#{id := Ingress}], externals := Externals} =
            hls_partition:device(Partition, Device),
        true = length(Externals) > 0,
        Events = maps:from_list([{?FIRST_EVENT_ENDPOINT + Index, external(Partition, Device, E)}
            || {Index, E} <- lists:enumerate(0, Externals),
               Index < (1 bsl 16) - ?FIRST_EVENT_ENDPOINT]),
        true = map_size(Events) =:= length(Externals),
        Binding = #{host => Host, control => ?CONTROL_ENDPOINT, ingress => Ingress, events => Events},
        Identity = crypto:hash(sha256, term_to_binary(
            {partition_application, 1, Partition, Device, Binding}, [deterministic])),
        {Device, Binding#{identity => Identity, local => Local}}
    end || {Host, Device} <- lists:enumerate(1, Devices)])}.

%% All producers of an external already agree on each schema's representation.
-spec external(map(), term(), map()) -> map().
external(#{actors := Actors, routes := Routes}, Device, #{id := Id, port := Port}) ->
    Producers = [{Module, Output} || #{source := {Actor, Output}, recipients := Recipients} <- Routes,
        lists:member({external, Id}, Recipients),
        #{identity := A, module := Module, device := D} <- Actors, A =:= Actor, D =:= Device],
    Schemas = lists:append([begin
        Interface = hls_actor_interface:from_module(Module),
        [begin
            #{fields := Fields} = hls_actor_interface:schema(Interface, Name),
            Width = Module:pack_width(Name),
            {Module:pack_tag(Name), #{module => Module, name => Name, width => Width, fields => Fields}}
        end || Name <- hls_actor_interface:output_schemas(Interface, Output)]
    end || {Module, Output} <- Producers]),
    #{id => Id, port => Port, schemas => maps:from_list(Schemas)}.

-doc "Validates a complete rectangle command before returning ordered routed packets for its selected devices.".
-spec command(map(), command()) ->
    [{term(), hls_fabric:route(), hls_fabric:header(), binary()}].
command(#{partition := Partition, devices := Devices}, {Ingress, Target, Bounds, Message}) ->
    [begin
        #{host := Host, control := Control, ingress := Ingress} = maps:get(Device, Devices),
        <<X0:16, Y0:16, X1:16, Y1:16, Kind:2, Words:8, 0:16, Tag:8, Payload:96>> = Packet,
        Bytes = <<X0:16/little, Y0:16/little, X1:16/little, Y1:16/little,
            Kind:32/little, Words:8, 0:16, Tag:8, Payload:(Words*32)/little>>,
        {Device, {Host, Control}, {2, 0, 0}, Bytes}
    end || {Device, Packet} <- hls_partition_ingress:commands(Partition, Ingress, Target, Bounds, Message)].

-doc "Decodes a bound external record, rejecting wrong routes, headers, lengths and nonzero codec padding.".
-spec event(map(), hls_fabric:route(), hls_fabric:header(), binary()) -> {atom(), tuple()}.
event(#{host := Host, events := Events}, {Endpoint, Host}, {Tag, 0, 0}, Payload) ->
    #{id := Id, schemas := Schemas} = maps:get(Endpoint, Events),
    #{module := Module, name := Name, width := Width} = maps:get(Tag, Schemas),
    true = byte_size(Payload) =:= ((Width+31) div 32)*4,
    <<Packed:Width/bitstring, _Padding/bitstring>> = Payload,
    {Message, <<>>} = Module:unpack(Name, Packed),
    Payload = hls_codec:align(Module:pack(Message), 32),
    {Id, Message}.

-doc "Wraps a generated device graph with the static routed application gateway; link ports remain separate.".
-spec wrapper(map(), term(), atom()) -> iolist().
wrapper(#{devices := Devices}, Device, Graph) ->
    #{identity := Identity, host := Host, control := Control,
      local := Local = #{ingresses := [#{input_name := Input}],
        externals := Externals}} = maps:get(Device, Devices),
    IdentityArgs = lists:join(", ", ["u64:" ++ integer_to_list(Word) || <<Word:64/little>> <= Identity]),
    Tile = maps:get(tile, Local, false),
    Count = length(Externals),
    RamParameters = hls_partition_shared_dslx:parameters(Local),
    RamNames = hls_partition_shared_dslx:names(Local),
    ConfigParameters = hls_partition_tile:parameters(Local) ++ case Tile of
        true -> ["tile_gateway: chan<bits[272]> in", "tile_host: chan<u16> in"]; false -> [] end,
    Args = lists:join(", ", hls_partition_links:frame_arguments(Local) ++
        ["events_p[u32:" ++ integer_to_list(I) ++ "]" || I <- lists:seq(0, Count-1)] ++ [Input ++ "_c"] ++ RamNames ++ hls_partition_tile:names(Local)),
    ["import axis;\n", hls_partition_links:imports(Local), case Tile of true -> "import hls_partition_tile_io;\n"; false -> [] end, "import hls_spatial_router;\nimport hls_partition_io;\nimport ", atom_to_list(Graph), ";\n\n",
     [["import ", atom_to_list(M), ";\n"] || M <- lists:usort([Module || #{module := Module} <- maps:get(schedulers, Local)])],
     "pub proc Top {\n",
     "  config(", lists:join(",\n      ", hls_partition_links:parameters(Local)), ",\n",
     "      app_in: chan<axis::Beat> in, app_out: chan<axis::Beat> out",
     [[",\n      ", P] || P <- RamParameters ++ ConfigParameters], ") {\n",
     hls_partition_links:frame_channels(Local),
     "    let (events_p, events_c) = chan<axis::Frame, u32:1>[", integer_to_list(Count), "](\"events\");\n",
     "    let (", Input, "_p, ", Input, "_c) = chan<hls_spatial_router::SpatialFrame, u32:1>(\"control\");\n",
     "    spawn ", atom_to_list(Graph), "::Top(", Args, ");\n",
     hls_partition_links:spawn(Local),
     case Tile of
        true -> ["    spawn hls_partition_tile_io::Boundary<u32:", integer_to_list(Count), ", u16:", integer_to_list(Control),
            ">(tile_gateway, tile_host, app_in, app_out, ", Input, "_p, events_c);\n"];
        false -> ["    spawn hls_partition_io::Boundary<u32:", integer_to_list(Count), ", ",
            IdentityArgs, ", u16:", integer_to_list(Host), ", u16:", integer_to_list(Control),
            ">(app_in, app_out, ", Input, "_p, events_c);\n"]
     end,
     "    ()\n  }\n  init { () }\n  next(state: ()) { state }\n}\n"].
