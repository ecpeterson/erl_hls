-module(hls_domain_endpoint_wire).
-moduledoc "Canonical management packets for independent mailbox endpoints. Binding bytes and status atoms use retained native type descriptors. The host must confirm the receiver before issuing a transmitter bind; this wire format carries that assertion, not remote liveness or application data.".
-include("hls_domain_channel_endpoints.hrl").

%% Trusted retained interfaces and bounded request/response envelopes.
-export([load/1, command/5, observation/3]).
-export_type([interface/0, endpoint/0, codecs/0, command/0, snapshot/0, observation/0]).

-doc "One statically declared endpoint; its direction cannot change through management traffic.".
-type endpoint() :: #{id := hls_nums:u32(), kind := tx | rx}.
-doc "Native shared declarations; binding is the complete endpoint_binding record, without a message tag.".
-type codecs() :: #{
    operation := hls_type:descriptor(),
    status := hls_type:descriptor(),
    binding := hls_type:descriptor()
}.
-doc "A distinct management protocol with one routed lane and immutable endpoint directions.".
-type interface() :: #{
    kind := domain_endpoint_management,
    management_route := hls_fabric:route(),
    endpoints := [endpoint(), ...],
    response_tag := 129,
    codecs := codecs()
}.
-doc "Inspect or mutate a complete namespace/generation/incarnation binding. TX bind asserts prior exact RX confirmation.".
-type command() :: inspect | {bind | fence, #endpoint_binding{}}.
-doc "Observed local ownership; inactive or faulted is not evidence of remote retirement.".
-type snapshot() :: #{
    kind := tx | rx,
    status := endpoint_status(),
    binding := #endpoint_binding{},
    packet_sequence := hls_nums:u32(),
    active := boolean(),
    fault := boolean()
}.
-doc "One canonical response; callers still correlate its session/request and validate its broker route.".
-type observation() :: #{
    session := hls_nums:u64(),
    request := hls_nums:u32(),
    endpoint := hls_nums:u32(),
    snapshot := snapshot()
}.

-doc "Checks a trusted retained interface or ETF path. Requires distinct IDs, the independent response tag and the native 256-bit binding descriptor; malformed metadata raises.".
-spec load(interface() | file:filename()) -> interface().
load(
    #{
        kind := domain_endpoint_management,
        management_route := {Source, Destination},
        endpoints := Endpoints,
        response_tag := 129,
        codecs := #{
            operation := Operation,
            status := Status,
            binding := Binding = {hls_type, hls_record, endpoint_binding, _}
        }
    } = Interface
) ->
    true = is_integer(Source) andalso Source >= 0 andalso Source < (1 bsl 16),
    true = is_integer(Destination) andalso Destination >= 0 andalso Destination < (1 bsl 16),
    true = is_list(Endpoints) andalso Endpoints =/= [],
    Ids = [
        begin
            true = is_integer(Id) andalso Id >= 0 andalso Id < (1 bsl 32),
            true = Kind =:= tx orelse Kind =:= rx,
            Id
        end
     || #{id := Id, kind := Kind} <- Endpoints
    ],
    true = length(Ids) =:= length(Endpoints),
    true = length(Ids) =:= length(lists:usort(Ids)),
    256 = hls_type:width(Binding),
    #endpoint_binding{} = hls_type:zero(Binding),
    true = hls_type:width(Status) =< 8,
    [_ = hls_type:pack(Atom, Operation) || Atom <- [tick, bind, fence]],
    [_ = hls_type:pack(Atom, Status) || Atom <- [ok, invalid]],
    Interface;
load(Path) when is_list(Path); is_binary(Path) ->
    {ok, Bytes} = file:read_file(Path),
    load(binary_to_term(Bytes)).

-doc "Encodes four inspect words or twelve mutation words. Binding uses the retained record codec; zero mutation identities reject. TX binds require prior receiver confirmation by the caller. No command is transmitted here.".
-spec command(hls_nums:u64(), hls_nums:u32(), hls_nums:u32(), command(), interface()) ->
    {0 | 1 | 2, binary()}.
command(Session, Request, Endpoint, Command, #{
    endpoints := Endpoints,
    codecs := #{binding := BindingType}
}) when
    Session > 0, Session < (1 bsl 64), Request > 0, Request < (1 bsl 32)
->
    _ = endpoint(Endpoint, Endpoints),
    Prefix = <<Session:64/little, Request:32/little, Endpoint:32/little>>,
    case Command of
        inspect ->
            {0, Prefix};
        {Operation, Binding = #endpoint_binding{}} when Operation =:= bind; Operation =:= fence ->
            true = nonzero(Binding),
            Packed = hls_type:pack(Binding, BindingType),
            32 = byte_size(Packed),
            Tag =
                case Operation of
                    bind -> 1;
                    fence -> 2
                end,
            {Tag, <<Prefix/binary, Packed/binary>>}
    end.

-doc "Decodes exactly fourteen payload words under the independent response tag, zero header flags and canonical packed status/flags. Invalid enum codes, reserved bits and inconsistent active bindings raise. Session/request correlation and route selection remain the caller's responsibility.".
-spec observation(hls_fabric:header(), binary(), interface()) -> observation().
observation(
    {129, 0, 0},
    <<Session:64/little, Request:32/little, Endpoint:32/little, Flags:32/little, Packed:32/binary,
        Sequence:32/little>>,
    #{
        response_tag := 129,
        endpoints := Endpoints,
        codecs := #{status := StatusType, binding := BindingType}
    }
) when Session > 0, Request > 0 ->
    #{kind := Kind} = endpoint(Endpoint, Endpoints),
    Width = hls_type:width(StatusType),
    Mask = (1 bsl Width) - 1,
    0 = Flags band bnot (Mask bor (1 bsl 8) bor (1 bsl 9)),
    Code = Flags band Mask,
    {Status, <<>>} = hls_type:unpack(<<Code:Width>>, StatusType),
    {Binding = #endpoint_binding{}, <<>>} = hls_type:unpack(Packed, BindingType),
    Packed = hls_type:pack(Binding, BindingType),
    Active = Flags band (1 bsl 8) =/= 0,
    Fault = Flags band (1 bsl 9) =/= 0,
    true = not Active orelse (not Fault andalso nonzero(Binding)),
    #{
        session => Session,
        request => Request,
        endpoint => Endpoint,
        snapshot => #{
            kind => Kind,
            status => Status,
            binding => Binding,
            packet_sequence => Sequence,
            active => Active,
            fault => Fault
        }
    }.

%% Declared endpoint identity comes from trusted interface metadata, never packet direction bits.
-spec endpoint(hls_nums:u32(), [endpoint()]) -> endpoint().
endpoint(Id, Endpoints) ->
    [Endpoint] = [E || E = #{id := Candidate} <- Endpoints, Candidate =:= Id],
    Endpoint.

%% Retired snapshots may retain zero identity; mutations and active snapshots may not.
-spec nonzero(#endpoint_binding{}) -> boolean().
nonzero(#endpoint_binding{
    namespace = Namespace,
    generation = Generation,
    source_incarnation = Source,
    destination_incarnation = Destination
}) ->
    Namespace > 0 andalso Generation > 0 andalso Source > 0 andalso Destination > 0.
