%%%% phi_memory_wire
%%%%
%%%% Example-local host/fabric boundary for the phi memory experiment.

-module(phi_memory_wire).
-moduledoc """
Encodes the direct host boundary around one generated phi/noise fabric.

The ordinary routed fabric envelope addresses one `control_router` endpoint.
Its inner frame retains the actor message selector, but prefixes the payload
with an inclusive rectangle packed as four little-endian `u16` values. The
generated gateway derives the internal data/noise target from that selector.
Its host-facing frame is width-parametric, while actor-local frames retain the
compact three-word payload used by the current generated actors.

FPGA outputs use one source endpoint per generated external channel. Their
actor frames are otherwise unchanged. Route identity therefore supplies the
X/Z plane or measurement-stream identity which is intentionally absent from
the actor records.

Flags value one versions this example boundary. Commands are ordered and
at-most-once: transport failure aborts an experiment rather than retrying a
possibly applied Pauli update.
""".

-include("phi_protocol.hrl").

-export([
    version/0,
    control_route/0,
    event_routes/0,
    encode_command/2,
    decode_event/4
]).
-export_type([route/0, header/0]).

-define(VERSION, 1).
-define(HOST_ENDPOINT, 0).
-define(CONTROL_ENDPOINT, 1).
-define(DATA_MEASUREMENTS_ENDPOINT, 2).
-define(X_ANNOUNCEMENTS_ENDPOINT, 3).
-define(X_DECODER_EVENTS_ENDPOINT, 4).
-define(Z_ANNOUNCEMENTS_ENDPOINT, 5).
-define(Z_DECODER_EVENTS_ENDPOINT, 6).
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
version() -> ?VERSION.

-doc "Returns the one host-to-control-router route.".
-spec control_route() -> route().
control_route() -> {?HOST_ENDPOINT, ?CONTROL_ENDPOINT}.

-doc "Returns each FPGA-to-host route and its logical output stream.".
-spec event_routes() -> [{route(), phi_memory_experiment:stream()}].
event_routes() ->
    [
        {{?DATA_MEASUREMENTS_ENDPOINT, ?HOST_ENDPOINT}, data_measurements},
        {{?X_ANNOUNCEMENTS_ENDPOINT, ?HOST_ENDPOINT}, x_announcements},
        {{?X_DECODER_EVENTS_ENDPOINT, ?HOST_ENDPOINT}, x_decoder_events},
        {{?Z_ANNOUNCEMENTS_ENDPOINT, ?HOST_ENDPOINT}, z_announcements},
        {{?Z_DECODER_EVENTS_ENDPOINT, ?HOST_ENDPOINT}, z_decoder_events}
    ].

-doc "Encodes one reducer command for a fabric with the given distance.".
-spec encode_command(phi_memory_experiment:command(), pos_integer()) ->
    {ok, route(), header(), binary()} | {error, atom()}.
encode_command(
    {control_router, data, Rectangle, Message = #pauli_query{
        request_id = RequestId,
        measurement = Measurement
    }},
    Distance
) when RequestId >= 0, RequestId =< ?U32_MAX ->
    case hls_pauli:is_pauli(Measurement) of
        true -> encode(Rectangle, Message, phenom_data_cell, Distance);
        false -> {error, message}
    end;
encode_command(
    {control_router, data, Rectangle, Message = #pauli_update{
        pauli = Pauli
    }},
    Distance
) ->
    case hls_pauli:is_pauli(Pauli) of
        true -> encode(Rectangle, Message, phenom_data_cell, Distance);
        false -> {error, message}
    end;
encode_command(
    {control_router, noise, Rectangle, Message = #noise_cutoff{
        first_quiet_step = Step
    }},
    Distance
) when Step >= 0, Step =< ?U32_MAX ->
    encode(Rectangle, Message, phenom_data_cell, Distance);
encode_command(_Command, _Distance) ->
    {error, command}.

-doc "Decodes and validates one routed FPGA event.".
-spec decode_event(route(), header(), binary(), pos_integer()) ->
    {ok, phi_memory_experiment:stream(), tuple()} | {error, atom()}.
decode_event(Route, {Tag, 0, ?VERSION}, Payload, Distance)
        when is_binary(Payload), Distance > 0 ->
    case lists:keyfind(Route, 1, event_routes()) of
        {Route, Stream} -> decode_stream(Stream, Tag, Payload, Distance);
        false -> {error, route}
    end;
decode_event(_Route, _Header, _Payload, _Distance) ->
    {error, frame}.

encode(Rectangle, Message, Module, Distance) ->
    case encode_rectangle(Rectangle, Distance) of
        {ok, Bounds} ->
            Tag = Module:pack_tag(element(1, Message)),
            Payload = Module:pack(Message),
            {ok, control_route(), {Tag, 0, ?VERSION},
                <<Bounds/binary, Payload/binary>>};
        {error, _Reason} = Error ->
            Error
    end.

encode_rectangle({X0, Y0, X1, Y1}, Distance)
        when Distance > 0,
             X0 >= 0, X0 =< X1, X1 < Distance,
             Y0 >= 0, Y0 =< Y1, Y1 < 2 * Distance,
             X1 =< 16#ffff, Y1 =< 16#ffff ->
    {ok, <<
        X0:16/little-unsigned-integer,
        Y0:16/little-unsigned-integer,
        X1:16/little-unsigned-integer,
        Y1:16/little-unsigned-integer
    >>};
encode_rectangle(_Rectangle, _Distance) ->
    {error, rectangle}.

decode_stream(data_measurements, Tag, Payload, Distance) ->
    decode_one(
        data_measurements,
        phenom_data_cell,
        pauli_reply,
        Tag,
        Payload,
        Distance
    );
decode_stream(Stream, Tag, Payload, Distance)
        when Stream =:= x_announcements; Stream =:= z_announcements ->
    decode_one(
        Stream,
        phenom_syndrome_cell,
        phenom_anyon,
        Tag,
        Payload,
        Distance
    );
decode_stream(Stream, Tag, Payload, Distance)
        when Stream =:= x_decoder_events; Stream =:= z_decoder_events ->
    CorrectionTag = phi_halo_cell:pack_tag(phi_correction),
    StatusTag = phi_halo_cell:pack_tag(phi_status),
    case Tag of
        CorrectionTag ->
            decode_one(
                Stream,
                phi_halo_cell,
                phi_correction,
                Tag,
                Payload,
                Distance
            );
        StatusTag ->
            decode_one(
                Stream,
                phi_halo_cell,
                phi_status,
                Tag,
                Payload,
                Distance
            );
        _ ->
            {error, selector}
    end.

decode_one(Stream, Module, Schema, Tag, Payload, Distance) ->
    ExpectedTag = Module:pack_tag(Schema),
    Width = schema_width(Schema),
    case {Tag, bit_size(Payload)} of
        {ExpectedTag, Width} ->
            {Record, <<>>} = Module:unpack(Schema, Payload),
            validate_event(Stream, Record, Distance);
        {ExpectedTag, _OtherWidth} ->
            {error, payload};
        _ ->
            {error, selector}
    end.

%% Every event crosses the current actor-local three-word Frame ABI. Keeping
%% this boundary width explicit avoids loading compiler-analysis modules in the
%% deployed ERTS node; codec tests compare it with each generated packer.
schema_width(phenom_anyon) -> 96;
schema_width(phi_correction) -> 96;
schema_width(phi_status) -> 96;
schema_width(pauli_reply) -> 96.

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
