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
the actor records. Endpoints three and five are reserved for the
visualization-only announcement streams removed from this lossless boundary.

Boundary version one is carried in the frame flags byte. Commands are ordered
and at-most-once: transport failure aborts an experiment rather than retrying
a possibly applied Pauli update.

Called by phi_memory_runner and phi_memory_cpu_fabric. Derives endpoint/schema choices from phi_memory_boundary, independently of XLS generation.
""".

-include("../include/phi_protocol.hrl").

%% Boundary version and routed endpoints.
-export([version/0, control_route/1, event_routes/1]).

%% Host command and event codecs.
-export([encode_command/2, decode_command/4, encode_event/3, decode_event/4]).
%% Shared type contracts.
-export_type([route/0, header/0]).

%% Inclusive spatial bounds in the contract's physical data-grid coordinate space.
-type rectangle() :: {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}.
%% A successful routed encoding carries the boundary header and byte-aligned actor payload.
-type encoded() :: {ok, route(), header(), binary()} | {error, atom()}.
%% A decoded command keeps its target and inclusive rectangle for CPU or hardware delivery.
-type decoded_command() :: {ok, phi_memory_experiment:command()} | {error, atom()}.
%% Route identity restores the plane or measurement stream omitted from the record itself.
-type decoded_event() :: {ok, phi_memory_experiment:stream(), tuple()} | {error, atom()}.

-define(U32_MAX, 16#ffffffff).

%% Unsigned address carried in the fabric envelope.
-type endpoint() :: 0..((1 bsl 16) - 1).
-doc "Source and destination endpoint addresses in the outer fabric envelope.".
-type route() :: {endpoint(), endpoint()}.
-doc "Actor selector, transaction byte, and boundary-version flags; this protocol uses transaction zero.".
-type header() :: {
    Tag :: byte(),
    TxID :: byte(),
    Flags :: byte()
}.

-doc "Returns the boundary version carried in the frame flags byte.".
-spec version() -> 1.
version() -> phi_memory_boundary:version().

-doc "Returns the contract's one host-to-control-router route.".
-spec control_route(phi_memory_boundary:contract()) -> route().
control_route(Contract) ->
    #{
        host_endpoint := Host,
        ingress := #{endpoint := Gateway}
    } = Contract,
    {Host, Gateway}.

-doc "Returns the contract's FPGA-to-host routes and logical output streams.".
-spec event_routes(phi_memory_boundary:contract()) -> [{route(), phi_memory_experiment:stream()}].
event_routes(#{host_endpoint := Host, outputs := Outputs}) ->
    [
        {{Endpoint, Host}, Stream}
     || #{endpoint := Endpoint, stream := Stream} <- Outputs
    ].

-doc "Encodes one reducer command using the generated boundary contract.".
-spec encode_command(phi_memory_experiment:command(), phi_memory_boundary:contract()) ->
    {ok, route(), header(), binary()} | {error, atom()}.
encode_command(
    {control_router, data, Rectangle,
        Message = #pauli_query{
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
    {control_router, data, Rectangle,
        Message = #pauli_update{
            pauli = Pauli
        }},
    Contract
) ->
    case hls_pauli:is_pauli(Pauli) of
        true -> encode(data, Rectangle, Message, Contract);
        false -> {error, message}
    end;
encode_command(
    {control_router, noise, Rectangle,
        Message = #noise_cutoff{
            first_quiet_step = Step
        }},
    Contract
) when Step >= 0, Step =< ?U32_MAX ->
    encode(noise, Rectangle, Message, Contract);
encode_command(_Command, _Contract) ->
    {error, command}.

-doc "Decodes one routed command using the generated boundary contract.".
-spec decode_command(route(), header(), binary(), phi_memory_boundary:contract()) ->
    {ok, phi_memory_experiment:command()} | {error, atom()}.
decode_command(
    Route,
    {Tag, 0, Version},
    Payload,
    Contract = #{version := Version}
) when is_binary(Payload) ->
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
-spec encode_event(phi_memory_experiment:stream(), tuple(), phi_memory_boundary:contract()) ->
    {ok, route(), header(), binary()} | {error, atom()}.
encode_event(Stream, Event, Contract) when
    is_tuple(Event), tuple_size(Event) > 0
->
    Schema = element(1, Event),
    Distance = contract_distance(Contract),
    case
        {
            output_schema(Stream, Schema, Contract),
            validate_event(Stream, Event, Distance)
        }
    of
        {
            {ok, #{endpoint := Endpoint}, #{
                module := Module,
                selector := Selector,
                width := Width
            }},
            {ok, Stream, Event}
        } ->
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
-spec decode_event(route(), header(), binary(), phi_memory_boundary:contract()) ->
    {ok, phi_memory_experiment:stream(), tuple()} | {error, atom()}.
decode_event(Route, {Tag, 0, Version}, Payload, Contract) when
    is_binary(Payload)
->
    #{version := ExpectedVersion} = Contract,
    case Version of
        ExpectedVersion -> decode_route(Route, Tag, Payload, Contract);
        _ -> {error, frame}
    end;
decode_event(_Route, _Header, _Payload, _Contract) ->
    {error, frame}.

%% Validate spatial bounds and target schema before prefixing the actor bytes with the rectangle.
-spec encode(data | noise, rectangle(), tuple(), phi_memory_boundary:contract()) -> encoded().
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
    case
        {
            encode_rectangle(Rectangle, Shape),
            command_schema(Target, Schema, Targets)
        }
    of
        {{ok, Bounds}, {ok, #{module := Module, selector := Selector}}} ->
            Payload = Module:pack(Message),
            {ok, {Host, Gateway}, {Selector, 0, Version}, <<Bounds/binary, Payload/binary>>};
        {{error, _Reason} = Error, _CommandSchema} ->
            Error;
        {_Rectangle, error} ->
            {error, command}
    end.

%% Look up the unique actor schema allowed by the selected multicast target.
-spec command_schema(data | noise, atom(), [phi_memory_boundary:target()]) ->
    {ok, phi_memory_boundary:schema()} | error.
command_schema(Target, Schema, Targets) ->
    case
        [
            Descriptor
         || #{id := Id, schemas := Schemas} <- Targets,
            Id =:= Target,
            Descriptor = #{name := Name} <- Schemas,
            Name =:= Schema
        ]
    of
        [Descriptor] -> {ok, Descriptor};
        [] -> error
    end.

%% Resolve the selector across all targets before checking its rectangle and actor payload.
-spec decode_command_payload(byte(), binary(), phi_memory_boundary:contract()) -> decoded_command().
decode_command_payload(
    Tag,
    Payload,
    Contract = #{
        ingress := #{shape := Shape, targets := Targets}
    }
) ->
    case command_schema_by_selector(Tag, Targets) of
        {ok, Target, #{name := Schema, module := Module, width := Width}} ->
            decode_command_message(
                Target, Schema, Module, Width, Payload, Shape, Contract
            );
        error ->
            {error, selector}
    end.

%% Recover the target from the globally unique ingress selector established by the boundary contract.
-spec command_schema_by_selector(byte(), [phi_memory_boundary:target()]) ->
    {ok, data | noise, phi_memory_boundary:schema()} | error.
command_schema_by_selector(Selector, Targets) ->
    case
        [
            {Target, Descriptor}
         || #{id := Target, schemas := Schemas} <- Targets,
            Descriptor = #{selector := Candidate} <- Schemas,
            Candidate =:= Selector
        ]
    of
        [{Target, Descriptor}] -> {ok, Target, Descriptor};
        [] -> error
    end.

%% Require exact payload width and legal raw Pauli codes, then recheck the decoded command through the encoder.
-spec decode_command_message(
    data | noise,
    atom(),
    module(),
    pos_integer(),
    binary(),
    [pos_integer()],
    phi_memory_boundary:contract()
) -> decoded_command().
decode_command_message(
    Target,
    Schema,
    Module,
    Width,
    <<Bounds:8/binary, ActorPayload/binary>>,
    Shape,
    Contract
) when bit_size(ActorPayload) =:= Width ->
    case
        {
            decode_rectangle(Bounds, Shape),
            command_payload_valid(Schema, ActorPayload)
        }
    of
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

%% Reject unknown schema shapes and non-Pauli u32 encodings before invoking actor unpack callbacks.
-spec command_payload_valid(atom(), binary()) -> boolean().
command_payload_valid(
    pauli_query,
    <<_RequestId:32/little, Pauli:32/little>>
) ->
    Pauli =< 3;
command_payload_valid(pauli_update, <<Pauli:32/little>>) ->
    Pauli =< 3;
command_payload_valid(noise_cutoff, <<_FirstQuietStep:32/little>>) ->
    true;
command_payload_valid(_Schema, _Payload) ->
    false.

%% Decode exactly four u16 bounds and apply the same ordered, in-range checks used for encoding.
-spec decode_rectangle(<<_:64>>, [pos_integer()]) -> {ok, rectangle()} | {error, rectangle}.
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

%% Select the unique schema associated with one named lossless output stream.
-spec output_schema(phi_memory_experiment:stream(), atom(), phi_memory_boundary:contract()) ->
    {ok, phi_memory_boundary:output(), phi_memory_boundary:schema()} | {error, event}.
output_schema(Stream, Schema, #{outputs := Outputs}) ->
    case
        [
            {Output, Descriptor}
         || Output = #{stream := Candidate, schemas := Schemas} <- Outputs,
            Candidate =:= Stream,
            Descriptor = #{name := Name} <- Schemas,
            Name =:= Schema
        ]
    of
        [{Output, Descriptor}] -> {ok, Output, Descriptor};
        [] -> {error, event}
    end.

%% Accept only contract output endpoints addressed to the host, then validate the selected stream payload.
-spec decode_route(route(), byte(), binary(), phi_memory_boundary:contract()) -> decoded_event().
decode_route(
    Route,
    Tag,
    Payload,
    Contract = #{
        host_endpoint := Host,
        outputs := Outputs
    }
) ->
    Distance = contract_distance(Contract),
    case
        [
            Output
         || Output = #{endpoint := Source} <- Outputs,
            Route =:= {Source, Host}
        ]
    of
        [Output] -> decode_output(Output, Tag, Payload, Distance);
        [] -> {error, route}
    end.

%% Check the actor selector and exact width before unpacking and validating event coordinates and flags.
-spec decode_output(phi_memory_boundary:output(), byte(), binary(), pos_integer()) ->
    decoded_event().
decode_output(#{stream := Stream, schemas := Schemas}, Tag, Payload, Distance) ->
    case
        [
            Schema
         || Schema = #{selector := Selector} <- Schemas,
            Selector =:= Tag
        ]
    of
        [#{name := Name, module := Module, width := Width}] when
            bit_size(Payload) =:= Width
        ->
            {Record, <<>>} = Module:unpack(Name, Payload),
            validate_event(Stream, Record, Distance);
        [#{}] ->
            {error, payload};
        [] ->
            {error, selector}
    end.

%% Encode inclusive ordered bounds only when they fit the selected shape and four u16 fields.
-spec encode_rectangle(rectangle(), [pos_integer()]) -> {ok, <<_:64>>} | {error, rectangle}.
encode_rectangle({X0, Y0, X1, Y1}, [Width, Height]) when
    X0 >= 0,
    X0 =< X1,
    X1 < Width,
    Y0 >= 0,
    Y0 =< Y1,
    Y1 < Height,
    X1 =< 16#ffff,
    Y1 =< 16#ffff
->
    {ok, <<
        X0:16/little-unsigned-integer,
        Y0:16/little-unsigned-integer,
        X1:16/little-unsigned-integer,
        Y1:16/little-unsigned-integer
    >>};
encode_rectangle(_Rectangle, _Shape) ->
    {error, rectangle}.

%% Require the data-grid shape to have twice as many rows as columns and return its code distance.
-spec contract_distance(phi_memory_boundary:contract()) -> pos_integer().
contract_distance(#{ingress := #{shape := [Distance, DataHeight]}}) ->
    DataHeight = 2 * Distance,
    Distance.

%% Event-specific semantic checks supplement the schema-derived selector and
%% payload-width validation above.
-spec validate_event(phi_memory_experiment:stream(), tuple(), pos_integer()) -> decoded_event().
validate_event(
    data_measurements,
    Reply = #pauli_reply{x = X, y = Y, anticommutes = Anticommutes},
    Distance
) when
    X >= 0,
    X < Distance,
    Y >= 0,
    Y < 2 * Distance,
    Anticommutes < 2
->
    {ok, data_measurements, Reply};
validate_event(
    Stream,
    Correction = #phi_correction{x = X, y = Y, direction = Direction},
    Distance
) when
    (Stream =:= x_decoder_events orelse Stream =:= z_decoder_events),
    X >= 0,
    X < Distance,
    Y >= 0,
    Y < Distance,
    (Direction =:= ?PHI_NORTH_MASK orelse
        Direction =:= ?PHI_EAST_MASK orelse
        Direction =:= ?PHI_WEST_MASK orelse
        Direction =:= ?PHI_SOUTH_MASK)
->
    {ok, Stream, Correction};
validate_event(
    Stream,
    Status = #phi_status{x = X, y = Y, flags = Flags},
    Distance
) when
    (Stream =:= x_decoder_events orelse Stream =:= z_decoder_events),
    X >= 0,
    X < Distance,
    Y >= 0,
    Y < Distance,
    Flags < 4
->
    {ok, Stream, Status};
validate_event(_Stream, _Record, _Distance) ->
    {error, event}.
