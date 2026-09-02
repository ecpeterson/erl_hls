%%%% phi_memory_wire
%%%%
%%%% Example-local host/fabric boundary for the phi memory experiment.

-module(phi_memory_wire).
-moduledoc """
Encodes the direct host boundary around one generated phi/noise fabric.

The routed fabric envelope addresses the `control_router`. The command frame
prefixes its actor payload with an inclusive rectangle of four little-endian
`u16` values. The generated gateway maps the actor message selector to its
internal data or noise target. Host-facing frames are width-parametric;
actor-local frames retain the current compact three-word payload.

FPGA outputs use one source endpoint per generated external channel. Their
actor frames are otherwise unchanged. Route identity therefore supplies the
X/Z plane or measurement-stream identity which is intentionally absent from
the actor records.

Boundary version one is carried in the frame flags byte. Commands are ordered
and at-most-once: transport failure aborts an experiment rather than retrying
a possibly applied Pauli update.
""".

-include("phi_protocol.hrl").

-export([
    version/0,
    control_route/1,
    event_routes/1,
    encode_command/2,
    decode_command/4,
    encode_event/3,
    decode_event/4
]).
-export_type([route/0, header/0]).

-define(U32_MAX, 16#ffffffff).

-type endpoint() :: 0..65535.
-type route() :: {endpoint(), endpoint()}.
-type header() :: {
    Tag :: byte(),
    TxID :: byte(),
    Flags :: byte()
}.

-doc "Returns the boundary version carried in the frame flags byte.".
-spec version() -> 1.
version() -> phi_memory_boundary:version().

-doc "Returns the contract's one host-to-control-router route.".
-spec control_route(map()) -> route().
control_route(Contract) ->
    #{
        host_endpoint := Host,
        ingress := #{endpoint := Gateway}
    } = Contract,
    {Host, Gateway}.

-doc "Returns the contract's FPGA-to-host routes and logical output streams.".
-spec event_routes(map()) -> [{route(), phi_memory_experiment:stream()}].
event_routes(#{host_endpoint := Host, outputs := Outputs}) ->
    [
        {{Endpoint, Host}, Stream}
        || #{endpoint := Endpoint, stream := Stream} <- Outputs
    ].

-doc "Encodes one reducer command using the generated boundary contract.".
-spec encode_command(phi_memory_experiment:command(), map()) ->
    {ok, route(), header(), binary()} | {error, atom()}.
encode_command(
    {control_router, data, Rectangle, Message = #pauli_query{
        request_id = RequestId,
        measurement = Measurement
    }},
    Contract
) when RequestId >= 0, RequestId =< ?U32_MAX ->
    case hls_pauli:is_pauli(Measurement) of
        true -> encode(data, Rectangle, Message, Contract);
        false -> {error, message}
    end;
encode_command(
    {control_router, data, Rectangle, Message = #pauli_update{
        pauli = Pauli
    }},
    Contract
) ->
    case hls_pauli:is_pauli(Pauli) of
        true -> encode(data, Rectangle, Message, Contract);
        false -> {error, message}
    end;
encode_command(
    {control_router, noise, Rectangle, Message = #noise_cutoff{
        first_quiet_step = Step
    }},
    Contract
) when Step >= 0, Step =< ?U32_MAX ->
    encode(noise, Rectangle, Message, Contract);
encode_command(_Command, _Contract) ->
    {error, command}.

-doc "Decodes one routed command using the generated boundary contract.".
-spec decode_command(route(), header(), binary(), map()) ->
    {ok, phi_memory_experiment:command()} | {error, atom()}.
decode_command(Route, {Tag, 0, Version}, Payload,
        Contract = #{version := Version}) when is_binary(Payload) ->
    ExpectedRoute = control_route(Contract),
    case Route of
        ExpectedRoute ->
            decode_command_payload(Tag, Payload, Contract);
        _ ->
            {error, route}
    end;
decode_command(_Route, _Header, _Payload, _Contract) ->
    {error, frame}.

-doc "Encodes one validated FPGA event using its contract output route.".
-spec encode_event(phi_memory_experiment:stream(), tuple(), map()) ->
    {ok, route(), header(), binary()} | {error, atom()}.
encode_event(Stream, Event, Contract)
        when is_tuple(Event), tuple_size(Event) > 0 ->
    Schema = element(1, Event),
    Distance = contract_distance(Contract),
    case {
        output_schema(Stream, Schema, Contract),
        validate_event(Stream, Event, Distance)
    } of
        {{ok, #{endpoint := Endpoint}, #{
            module := Module,
            selector := Selector,
            width := Width
        }}, {ok, Stream, Event}} ->
            #{version := Version, host_endpoint := Host} = Contract,
            Payload = Module:pack(Event),
            Width = bit_size(Payload),
            {ok, {Endpoint, Host}, {Selector, 0, Version}, Payload};
        {{error, _Reason} = Error, _Validation} ->
            Error;
        {_Schema, {error, _Reason} = Error} ->
            Error
    end;
encode_event(_Stream, _Event, _Contract) ->
    {error, event}.

-doc "Decodes and validates one routed FPGA event.".
-spec decode_event(route(), header(), binary(), map()) ->
    {ok, phi_memory_experiment:stream(), tuple()} | {error, atom()}.
decode_event(Route, {Tag, 0, Version}, Payload, Contract)
        when is_binary(Payload) ->
    #{version := ExpectedVersion} = Contract,
    case Version of
        ExpectedVersion -> decode_route(Route, Tag, Payload, Contract);
        _ -> {error, frame}
    end;
decode_event(_Route, _Header, _Payload, _Contract) ->
    {error, frame}.

encode(Target, Rectangle, Message, Contract) ->
    #{
        version := Version,
        host_endpoint := Host,
        ingress := #{
            endpoint := Gateway,
            shape := Shape,
            targets := Targets
        }
    } = Contract,
    Schema = element(1, Message),
    case {
        encode_rectangle(Rectangle, Shape),
        command_schema(Target, Schema, Targets)
    } of
        {{ok, Bounds}, {ok, #{module := Module, selector := Selector}}} ->
            Payload = Module:pack(Message),
            {ok, {Host, Gateway}, {Selector, 0, Version},
                <<Bounds/binary, Payload/binary>>};
        {{error, _Reason} = Error, _CommandSchema} ->
            Error;
        {_Rectangle, error} ->
            {error, command}
    end.

command_schema(Target, Schema, Targets) ->
    case [
        Descriptor
        || #{id := Id, schemas := Schemas} <- Targets,
           Id =:= Target,
           Descriptor = #{name := Name} <- Schemas,
           Name =:= Schema
    ] of
        [Descriptor] -> {ok, Descriptor};
        [] -> error
    end.

decode_command_payload(Tag, Payload, Contract = #{
    ingress := #{shape := Shape, targets := Targets}
}) ->
    case command_schema_by_selector(Tag, Targets) of
        {ok, Target, #{name := Schema, module := Module, width := Width}} ->
            decode_command_message(
                Target, Schema, Module, Width, Payload, Shape, Contract
            );
        error ->
            {error, selector}
    end.

command_schema_by_selector(Selector, Targets) ->
    case [
        {Target, Descriptor}
        || #{id := Target, schemas := Schemas} <- Targets,
           Descriptor = #{selector := Candidate} <- Schemas,
           Candidate =:= Selector
    ] of
        [{Target, Descriptor}] -> {ok, Target, Descriptor};
        [] -> error
    end.

decode_command_message(
    Target,
    Schema,
    Module,
    Width,
    <<Bounds:8/binary, ActorPayload/binary>>,
    Shape,
    Contract
) when bit_size(ActorPayload) =:= Width ->
    case {
        decode_rectangle(Bounds, Shape),
        command_payload_valid(Schema, ActorPayload)
    } of
        {{ok, Rectangle}, true} ->
            {Message, <<>>} = Module:unpack(Schema, ActorPayload),
            Command = {control_router, Target, Rectangle, Message},
            case encode_command(Command, Contract) of
                {ok, _Route, _Header, _Payload} -> {ok, Command};
                {error, _Reason} = Error -> Error
            end;
        {{error, _Reason} = Error, _Valid} ->
            Error;
        {_Rectangle, false} ->
            {error, message}
    end;
decode_command_message(
    _Target, _Schema, _Module, _Width, _Payload, _Shape, _Contract
) ->
    {error, payload}.

command_payload_valid(pauli_query,
        <<_RequestId:32/little, Pauli:32/little>>) ->
    Pauli =< 3;
command_payload_valid(pauli_update, <<Pauli:32/little>>) ->
    Pauli =< 3;
command_payload_valid(noise_cutoff, <<_FirstQuietStep:32/little>>) ->
    true;
command_payload_valid(_Schema, _Payload) ->
    false.

decode_rectangle(
    Bounds = <<
        X0:16/little,
        Y0:16/little,
        X1:16/little,
        Y1:16/little
    >>,
    Shape
) ->
    Rectangle = {X0, Y0, X1, Y1},
    case encode_rectangle(Rectangle, Shape) of
        {ok, Bounds} -> {ok, Rectangle};
        {error, _Reason} = Error -> Error
    end.

output_schema(Stream, Schema, #{outputs := Outputs}) ->
    case [
        {Output, Descriptor}
        || Output = #{stream := Candidate, schemas := Schemas} <- Outputs,
           Candidate =:= Stream,
           Descriptor = #{name := Name} <- Schemas,
           Name =:= Schema
    ] of
        [{Output, Descriptor}] -> {ok, Output, Descriptor};
        [] -> {error, event}
    end.

decode_route(Route, Tag, Payload, Contract = #{
    host_endpoint := Host,
    outputs := Outputs
}) ->
    Distance = contract_distance(Contract),
    case [
        Output
        || Output = #{endpoint := Source} <- Outputs,
           Route =:= {Source, Host}
    ] of
        [Output] -> decode_output(Output, Tag, Payload, Distance);
        [] -> {error, route}
    end.

decode_output(#{stream := Stream, schemas := Schemas}, Tag, Payload, Distance) ->
    case [
        Schema
        || Schema = #{selector := Selector} <- Schemas,
           Selector =:= Tag
    ] of
        [#{name := Name, module := Module, width := Width}]
                when bit_size(Payload) =:= Width ->
            {Record, <<>>} = Module:unpack(Name, Payload),
            validate_event(Stream, Record, Distance);
        [#{}] ->
            {error, payload};
        [] ->
            {error, selector}
    end.

encode_rectangle({X0, Y0, X1, Y1}, [Width, Height])
        when X0 >= 0, X0 =< X1, X1 < Width,
             Y0 >= 0, Y0 =< Y1, Y1 < Height,
             X1 =< 16#ffff, Y1 =< 16#ffff ->
    {ok, <<
        X0:16/little-unsigned-integer,
        Y0:16/little-unsigned-integer,
        X1:16/little-unsigned-integer,
        Y1:16/little-unsigned-integer
    >>};
encode_rectangle(_Rectangle, _Shape) ->
    {error, rectangle}.

contract_distance(#{ingress := #{shape := [Distance, DataHeight]}}) ->
    DataHeight = 2 * Distance,
    Distance.

%% Event-specific semantic checks supplement the schema-derived selector and
%% payload-width validation above.
validate_event(
    data_measurements,
    Reply = #pauli_reply{x = X, y = Y, anticommutes = Anticommutes},
    Distance
) when X >= 0, X < Distance,
        Y >= 0, Y < 2 * Distance,
        Anticommutes < 2 ->
    {ok, data_measurements, Reply};
validate_event(
    Stream,
    Announcement = #phenom_anyon{x = X, y = Y, flags = Flags},
    Distance
) when (Stream =:= x_announcements orelse Stream =:= z_announcements),
        X >= 0, X < Distance, Y >= 0, Y < Distance, Flags < 4 ->
    {ok, Stream, Announcement};
validate_event(
    Stream,
    Correction = #phi_correction{x = X, y = Y, direction = Direction},
    Distance
) when (Stream =:= x_decoder_events orelse Stream =:= z_decoder_events),
        X >= 0, X < Distance, Y >= 0, Y < Distance,
        (Direction =:= ?PHI_NORTH_MASK orelse
         Direction =:= ?PHI_EAST_MASK orelse
         Direction =:= ?PHI_WEST_MASK orelse
         Direction =:= ?PHI_SOUTH_MASK) ->
    {ok, Stream, Correction};
validate_event(
    Stream,
    Status = #phi_status{x = X, y = Y, flags = Flags},
    Distance
) when (Stream =:= x_decoder_events orelse Stream =:= z_decoder_events),
        X >= 0, X < Distance, Y >= 0, Y < Distance, Flags < 4 ->
    {ok, Stream, Status};
validate_event(_Stream, _Record, _Distance) ->
    {error, event}.
