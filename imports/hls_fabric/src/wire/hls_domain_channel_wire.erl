-module(hls_domain_channel_wire).
-moduledoc "Canonical management packets for declared reset-domain mailbox channels. The retained interface supplies channel indices and source-derived status codes; application data and returned credits use separate hardware lanes.".

%% Trusted local interface and fixed-size management envelopes.
-export([load/1, command/5, observation/2]).
-export_type([interface/0, command/0, snapshot/0, observation/0]).

-doc "One shared management route for a fixed nonempty set of channel indices.".
-type interface() :: #{
    kind := domain_channel_management,
    management_route := hls_fabric:route(),
    channels := [hls_nums:u32()],
    codecs := #{status := hls_type:descriptor()}
}.
-doc "Inspection or one exact-generation mutation; bind additionally names both intended endpoint incarnations.".
-type command() ::
    inspect
    | {bind, hls_nums:u64(), hls_domain:incarnation(), hls_domain:incarnation()}
    | {fence, hls_nums:u64()}.
-doc "Observed binding and packet identity; inactive does not reverse previously delivered application effects.".
-type snapshot() :: #{
    status := hls_domain_channel:status(),
    generation := hls_nums:u64(),
    source_incarnation := hls_nums:u64(),
    destination_incarnation := hls_nums:u64(),
    packet_sequence := hls_nums:u32(),
    active := boolean(),
    fault := boolean()
}.
-doc "A complete snapshot correlated to one session, request and declared channel.".
-type observation() :: #{
    session := hls_nums:u64(),
    request := hls_nums:u32(),
    channel := hls_nums:u32(),
    snapshot := snapshot()
}.

-doc "Checks a trusted generated channel interface, enclosing bundle or local ETF path.".
-spec load(interface() | map() | file:filename()) -> interface().
load(#{channel_stream := #{interface := Interface}}) ->
    load(Interface);
load(
    #{
        kind := domain_channel_management,
        management_route := {Source, Destination},
        channels := Channels,
        codecs := #{status := Status}
    } = Interface
) when
    is_integer(Source),
    Source >= 0,
    Source < (1 bsl 16),
    is_integer(Destination),
    Destination >= 0,
    Destination < (1 bsl 16),
    is_list(Channels)
->
    true = Channels =/= [],
    true = lists:all(
        fun(Index) -> is_integer(Index) andalso Index >= 0 andalso Index < (1 bsl 32) end, Channels
    ),
    true = length(Channels) =:= length(lists:usort(Channels)),
    _ = hls_type:width(Status),
    Interface;
load(Path) when is_list(Path); is_binary(Path) ->
    {ok, Bytes} = file:read_file(Path),
    load(binary_to_term(Bytes)).

-doc "Encodes a nonzero session/request with an explicit channel; mutation fields remain full-width.".
-spec command(hls_nums:u64(), hls_nums:u32(), hls_nums:u32(), command(), interface()) ->
    {0 | 1 | 2, binary()}.
command(Session, Request, Channel, Command, #{channels := Channels}) when
    Session > 0, Session < (1 bsl 64), Request > 0, Request < (1 bsl 32)
->
    true = lists:member(Channel, Channels),
    Prefix = <<Session:64/little, Request:32/little, Channel:32/little>>,
    case Command of
        inspect ->
            {0, Prefix};
        {bind, Expected, Source, Destination} when
            Expected >= 0,
            Expected < (1 bsl 64),
            Source > 0,
            Source < (1 bsl 64),
            Destination > 0,
            Destination < (1 bsl 64)
        ->
            {1, <<Prefix/binary, Expected:64/little, Source:64/little, Destination:64/little>>};
        {fence, Expected} when Expected >= 0, Expected < (1 bsl 64) ->
            {2, <<Prefix/binary, Expected:64/little>>}
    end.

-doc "Decodes exactly fourteen canonical words; unused status encodings and nonboolean flags reject.".
-spec observation(binary(), interface()) -> observation().
observation(
    <<Session:64/little, Request:32/little, Channel:32/little, Status:32/little,
        Generation:64/little, Source:64/little, Destination:64/little, Sequence:32/little,
        Active:32/little, Fault:32/little>>,
    #{channels := Channels, codecs := #{status := Type}}
) when
    Session > 0, Request > 0, Active =< 1, Fault =< 1
->
    true = lists:member(Channel, Channels),
    Width = hls_type:width(Type),
    true = Status < (1 bsl Width),
    {Value, <<>>} = hls_type:unpack(<<Status:Width>>, Type),
    true =
        not (Active =:= 1) orelse
            (Generation > 0 andalso Source > 0 andalso Destination > 0 andalso Fault =:= 0),
    #{
        session => Session,
        request => Request,
        channel => Channel,
        snapshot => #{
            status => Value,
            generation => Generation,
            source_incarnation => Source,
            destination_incarnation => Destination,
            packet_sequence => Sequence,
            active => Active =:= 1,
            fault => Fault =:= 1
        }
    }.
