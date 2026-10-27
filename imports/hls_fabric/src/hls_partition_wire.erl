-module(hls_partition_wire).
-moduledoc "Checked application bindings and codecs for one rectangle ingress per device.".
-export([deployment/1, binding/4, command/2, control_payload/1, event/4, wrapper/3, check/1]).
-export_type([command/0, rectangle/0]).

%% Fixed application-gateway bindings, unrelated to actor IDs or geometry.
%% The values are arbitrary; the XLS gateway shares FIRST_EVENT_ENDPOINT.
-define(CONTROL_ENDPOINT, 7).
-define(FIRST_EVENT_ENDPOINT, 8).

-doc "A typed rectangle record, or start for every explicitly activated device. Start admission is distinct from the returned started event.".
-type command() :: start | rectangle().

-doc "A typed record addressed to one ingress target within inclusive rectangle bounds. Encoding validates bounds and the target's accepted schemas.".
-type rectangle() :: {atom(), atom(), {integer(), integer(), integer(), integer()}, tuple()}.

-doc "Derives fixed control/event endpoints and a per-device SHA-256 identity covering placement, startup and wire bindings.".
-spec deployment(map()) -> map().
deployment(Partition = #{devices := Devices}) ->
    #{partition => Partition, devices => maps:from_list([begin
        Local = hls_partition:device(Partition, Device),
        {Device, (binding(Partition, Device, Host, Local))#{local => Local}}
    end || {Host, Device} <- lists:enumerate(1, Devices)])}.

-doc "Binds one device's declared ingress and external codecs to shared endpoints. The caller must supply checked producer encodings and local port order; this does not validate a runtime implementation. Identity covers the supplied partition and derived wire binding.".
-spec binding(map(), term(), 1 .. ((1 bsl 16) - 1), map()) -> map().
binding(Partition, Device, Host, #{ingresses := [#{id := Ingress}], externals := Externals})
        when Host > 0, Host < 65536 ->
    true = length(Externals) > 0,
    Events = maps:from_list([{?FIRST_EVENT_ENDPOINT + Index, external(Partition, Device, E)}
        || {Index, E} <- lists:enumerate(0, Externals),
           Index < (1 bsl 16) - ?FIRST_EVENT_ENDPOINT]),
    true = map_size(Events) =:= length(Externals),
    Binding = #{host => Host, control => ?CONTROL_ENDPOINT, ingress => Ingress, events => Events},
    Identity = crypto:hash(sha256, term_to_binary(
        {partition_application, 1, Partition, Device, Binding}, [deterministic])),
    Binding#{identity => Identity}.

%% All producers of an external already agree on each schema's representation.
-spec external(map(), term(), map()) -> map().
external(#{actors := Actors, routes := Routes}, Device, #{id := Id, port := Port}) ->
    Producers = [{Actor, Output} || #{source := {Id0, Output}, recipients := Recipients} <- Routes,
        lists:member({external, Id}, Recipients),
        Actor = #{identity := A, device := D} <- Actors, A =:= Id0, D =:= Device],
    Schemas = lists:append([[begin
        Schema = #{selector := Selector} = maps:get(Name, Codecs),
        {Selector, Schema}
    end || Name <- maps:get(Output, Outputs, [])]
        || {#{schemas := Codecs, output_schemas := Outputs}, Output} <- Producers]),
    #{id => Id, port => Port, schemas => maps:from_list(Schemas)}.

-doc "Checks current command and event codec availability and retained widths before host attachment. The descriptor is trusted build output; this does not validate encoding compatibility, transport or actor behavior.".
-spec check(map()) -> ok.
check(#{partition := #{ingresses := Ingresses}, devices := Devices}) ->
    lists:foreach(fun(#{bindings := Bindings}) ->
        lists:foreach(fun(#{schemas := Schemas}) -> hls_host_codec:check(Schemas) end, Bindings)
    end, Ingresses),
    maps:foreach(fun(_, #{events := Events}) ->
        maps:foreach(fun(_, #{schemas := Schemas}) ->
            maps:foreach(fun(_, #{codec := Codec}) -> hls_record_codec:check(Codec) end, Schemas)
        end, Events)
    end, Devices).

-doc "Validates a rectangle command or explicit start before returning routed packets. Start targets every bound device; the stream client separately enforces single-use admission.".
-spec command(map(), command()) ->
    [{term(), hls_fabric:route(), hls_fabric:header(), binary()}].
command(#{devices := Devices}, start) ->
    [begin
        #{activation := explicit_start, host := Host, control := Control} = Binding,
        {Device, {Host, Control}, {3, 0, 0}, <<0:32>>}
    end || {Device, Binding} <- lists:sort(maps:to_list(Devices))];
command(#{partition := Partition, devices := Devices}, {Ingress, Target, Bounds, Message}) ->
    [begin
        #{host := Host, control := Control, ingress := Ingress} = maps:get(Device, Devices),
        {Device, {Host, Control}, {2, 0, 0}, control_payload(Packet)}
    end || {Device, Packet} <- hls_partition_ingress:commands(Partition, Ingress, Target, Bounds, Message)].

-doc "Converts a checked spatial command with any ordinary-frame capacity to its routed little-endian rectangle payload. Keeps global bounds and sends exactly the declared ordinary payload words. This is wire packing, not source schema validation; use select/5 or commands/5 in hls_partition_ingress first.".
-spec control_payload(bitstring()) -> binary().
control_payload(<<X0:16, Y0:16, X1:16, Y1:16, Kind:2, Words:8, 0:16, Tag:8, Bits/bitstring>>)
        when Words =< 3, bit_size(Bits) rem 32 =:= 0, Words * 32 =< bit_size(Bits) ->
    %% The external rectangle envelope stays fixed; a wider native capacity
    %% is valid only when the actual message and all unused bits fit it.
    Capacity = bit_size(Bits),
    <<Payload:Capacity>> = Bits,
    true = Payload < (1 bsl (Words * 32)),
    Header = binary:decode_unsigned(<<Words:8, 0:16, Tag:8>>, little),
    hls_protocol_envelope:pack_rectangle(#{x0 => X0, y0 => Y0, x1 => X1, y1 => Y1,
        target => Kind, header => Header, payload => Payload}, Words).

-doc "Decodes a bound external record or canonical application started reply, rejecting wrong routes, headers, lengths and nonzero codec padding. The stream client checks that activation was requested.".
-spec event(map(), hls_fabric:route(), hls_fabric:header(), binary()) -> {term(), tuple()}.
event(#{activation := explicit_start, host := Host, control := Control},
        {Control, Host}, {16#83, 0, 0}, <<0:32>>) -> {application, {started}};
event(#{host := Host, events := Events}, {Endpoint, Host}, {Tag, 0, 0}, Payload) ->
    #{id := Id, schemas := Schemas} = maps:get(Endpoint, Events),
    #{codec := Codec, width := Width} = maps:get(Tag, Schemas),
    true = byte_size(Payload) =:= ((Width+31) div 32)*4,
    <<Packed:Width/bitstring, _Padding/bitstring>> = Payload,
    {Message, <<>>} = hls_record_codec:unpack(Codec, Packed),
    Payload = hls_codec:align(hls_record_codec:pack(Codec, Message), 32),
    {Id, Message}.

-doc "Wraps a generated device graph with the static routed application gateway; link ports remain separate. Rejects ordinary layouts above the fixed eight-word event envelope before rendering.".
-spec wrapper(map(), term(), atom()) -> iolist().
wrapper(#{devices := Devices}, Device, Graph) ->
    #{identity := Identity, host := Host, control := Control,
      local := Local = #{ingresses := [#{input_name := Input}],
        externals := Externals}} = maps:get(Device, Devices),
    Words = hls_frame_layout:payload_words(maps:get(frame_layout, Local)),
    case Words =< 8 of
        true -> ok;
        false -> hls_diagnostic:raise(partition, gateway_payload_capacity,
            <<"The partition application gateway supports at most eight payload words.">>,
            #{payload_words => Words, maximum => 8})
    end,
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
