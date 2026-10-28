-module(hls_partition_wire).
-moduledoc "Runtime framed commands, events and codec availability checks over retained partition bindings. This module neither derives placement nor emits hardware; hls_partition_binding and xls_partition_application own those build boundaries.".

%% Pre-session checks and codecs share the same retained record descriptors.
-export([check/1, command/2, control_payload/1, event/4]).
-export_type([command/0, rectangle/0]).

-doc "A typed rectangle record, or start for every explicitly activated device. Start admission is distinct from the returned started event.".
-type command() :: start | rectangle().

-doc "A typed record addressed to one ingress target within inclusive rectangle bounds. Encoding validates bounds and the target's accepted schemas.".
-type rectangle() :: {atom(), atom(), {integer(), integer(), integer(), integer()}, tuple()}.

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
