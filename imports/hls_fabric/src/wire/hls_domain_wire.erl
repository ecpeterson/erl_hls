-module(hls_domain_wire).
-moduledoc """
Retained codecs for the framed recovery-domain boundary. hls_domain_fabric uses
these descriptors without actor modules or compiler source. The generated bridge
owns the matching framing, incarnation admission and output sequence frontier.
""".
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").

%% Trusted emitted interface and ordinary record conversion.
-export([load/1, check/1, request/7, message/3]).
%% Management and application envelope conversion.
-export([management/4, observation/2, application/2, publication/3, supervision/2]).
-export_type([actor/0, interface/0, response/0, bounds/0, publication/0, retirement/0]).

-doc "One source actor's retained public request, reply and effect vocabulary.".
-type actor() :: #{
    index := hls_nums:u32(),
    schemas := hls_host_codec:catalog(),
    contract := hls_service_schema:contract(),
    outputs := #{atom() => [atom()]},
    ports := #{atom() => hls_nums:u32()},
    ingress => #{atom() => map()}
}.
-doc "Inclusive physical coordinates X0, Y0, X1, Y1 in the source-declared ingress.".
-type bounds() :: {hls_nums:u16(), hls_nums:u16(), hls_nums:u16(), hls_nums:u16()}.
-doc "Trusted build output; concrete descriptor providers remain runtime dependencies.".
-type interface() :: #{
    actors := #{term() => actor()},
    supervision => local,
    codecs := #{atom() => hls_type:descriptor()},
    frame_payload_words := pos_integer(),
    management_route := hls_fabric:route(),
    application_route := hls_fabric:route(),
    atom() => term()
}.
%% Parent-only adapters need lifecycle codecs; full interfaces may carry other fields.
-type control_interface() :: #{
    codecs := #{atom() => hls_type:descriptor()},
    atom() => term()
}.

-doc "One watched child lifetime's immutable terminal observation, retained until host delivery and endpoint retirement are acknowledged.".
-type retirement() :: #{
    incarnation := hls_nums:u64(),
    phase := hls_domain_lifecycle:phase(),
    fault := hls_domain_lifecycle:fault(),
    source := hls_nums:u16(),
    actor := hls_nums:u32(),
    frontier := hls_nums:u32()
}.
-doc "Bounded publication evidence for a locally supervised child; no intermediate incarnation history is retained.".
-type publication() :: #{watched := hls_nums:u64(), retirement := none | retirement()}.

-doc "One ordered application-lane observation before its record is decoded.".
-type response() :: #{
    kind := accepted | reply | effect,
    session := hls_nums:u64(),
    sequence := hls_nums:u32(),
    incarnation := hls_nums:u64(),
    actor := hls_nums:u32(),
    request := hls_nums:u32(),
    disposition := accepted | stale | invalid | busy | exhausted,
    port := hls_nums:u32(),
    header := hls_nums:u32(),
    payload := binary()
}.

-doc "Loads a trusted local emitted interface or validates an already-loaded value. Never use network terms as descriptors.".
-spec load(file:filename() | interface()) -> interface().
load(Interface) when is_map(Interface) ->
    ok = check(Interface),
    Interface;
load(Path) ->
    {ok, Bytes} = file:read_file(Path),
    load(binary_to_term(Bytes)).

-doc "Checks actor identities, retained providers, selectors, call bounds and port schemas before acquiring broker routes.".
-spec check(interface()) -> ok.
check(#{
    actors := Actors,
    codecs := Codecs,
    frame_payload_words := Words,
    management_route := ManagementRoute,
    application_route := ApplicationRoute
}) when
    map_size(Actors) > 0, is_integer(Words), Words > 0, Words =< 245
->
    ok = check_route(ManagementRoute),
    ok = check_route(ApplicationRoute),
    true = ManagementRoute =/= ApplicationRoute,
    Indices = [I || #{index := I} <- maps:values(Actors)],
    true = length(Indices) =:= length(lists:usort(Indices)),
    maps:foreach(fun(_Identity, Actor) -> check_actor(Actor, Words) end, Actors),
    [
        begin
            Descriptor = maps:get(Name, Codecs),
            _ = hls_type:width(Descriptor)
        end
     || Name <- [operation, phase, status, action, fault]
    ],
    ok.

%% All selectors and port indices are unique within their source actor.
-spec check_actor(actor(), pos_integer()) -> ok.
check_actor(
    #{
        index := Index,
        schemas := Schemas,
        contract := #{calls := Calls, casts := Casts} = Contract,
        outputs := Outputs,
        ports := Ports
    },
    Words
) ->
    true = is_integer(Index) andalso Index >= 0 andalso Index < (1 bsl 32),
    ok = hls_host_codec:check(Schemas),
    Selectors = [S || #{selector := S} <- maps:values(Schemas)],
    true = length(Selectors) =:= length(lists:usort(Selectors)),
    maps:foreach(
        fun(_Name, #{selector := Selector, width := Width}) ->
            true = Selector > 0 andalso Selector < 256 andalso Width =< Words * 32
        end,
        Schemas
    ),
    [
        true = maps:is_key(Tag, Schemas)
     || Tag <- maps:keys(Calls) ++ Casts ++ lists:append(maps:values(Calls))
    ],
    Bound = maps:get(pending_calls, Contract, 1),
    true = Bound > 0 andalso Bound < 256,
    true = lists:sort(maps:keys(Outputs)) =:= lists:sort(maps:keys(Ports)),
    PortIds = maps:values(Ports),
    true = length(PortIds) =:= length(lists:usort(PortIds)),
    [true = is_integer(I) andalso I >= 0 andalso I < (1 bsl 32) || I <- PortIds],
    maps:foreach(
        fun(_Port, Tags) -> [true = maps:is_key(Tag, Schemas) || Tag <- Tags] end, Outputs
    ),
    ok.

%% Routes are fixed by the emitted stream and validated before any broker is claimed.
-spec check_route(hls_fabric:route()) -> ok.
check_route({Source, Destination}) when
    is_integer(Source),
    is_integer(Destination),
    Source >= 0,
    Source < (1 bsl 16),
    Destination >= 0,
    Destination < (1 bsl 16)
->
    ok.

-doc "Encodes one typed call/cast before transmission. Slot is the bounded call slot or envelope sentinel 255 for a cast; cast frames retain txid zero. Session is the deployment-attested nonzero transport identity; Request is never reused within it.".
-spec request(
    actor(),
    call | cast | {rectangle, bounds()},
    tuple(),
    hls_nums:u64(),
    hls_nums:u64(),
    hls_nums:u32(),
    byte()
) ->
    {binary(), [atom()]}.
%% A rectangle is one cast, with one admission at the shared ingress register.
request(Binding, {rectangle, {X0, Y0, X1, Y1} = Bounds}, Message, Session, Epoch, Request, 255) ->
    Tag = element(1, Message),
    Address = maps:get(Tag, maps:get(ingress, Binding, #{}), #{}),
    case Address of
        #{rectangle := {W, H}} when
            is_integer(X0),
            is_integer(Y0),
            is_integer(X1),
            is_integer(Y1),
            0 =< X0,
            X0 =< X1,
            X1 < W,
            0 =< Y0,
            Y0 =< Y1,
            Y1 < H
        ->
            {<<Prefix:24/binary, 0:32/little, 255:32/little, Frame/binary>>, []} =
                request(Binding, cast, Message, Session, Epoch, Request, 255),
            {
                <<Prefix/binary, 2:32/little, 255:32/little, X0:16/little, Y0:16/little,
                    X1:16/little, Y1:16/little, Frame/binary>>,
                []
            };
        #{rectangle := _} ->
            error({invalid_rectangle, Bounds});
        _ ->
            error({unsupported_rectangle_cast, Tag})
    end;
%% A point command routes to the addressed actor's source-derived position.
request(
    #{index := Actor, schemas := Schemas, contract := Contract},
    Mode,
    Message,
    Session,
    Incarnation,
    Request,
    Slot
) when
    is_tuple(Message), tuple_size(Message) > 0, Session > 0, Session < (1 bsl 64)
->
    Tag = element(1, Message),
    Replies =
        case {Mode, Contract} of
            {call, #{calls := Calls}} ->
                true = Slot >= 0 andalso Slot < maps:get(pending_calls, Contract, 1),
                case maps:find(Tag, Calls) of
                    {ok, Tags} -> Tags;
                    error -> error({invalid_request, call, Tag})
                end;
            {cast, #{casts := Casts}} ->
                255 = Slot,
                case lists:member(Tag, Casts) of
                    true -> [];
                    false -> error({invalid_request, cast, Tag})
                end
        end,
    #{selector := Selector, codec := Codec} = maps:get(Tag, Schemas),
    Payload = hls_codec:align(hls_record_codec:pack(Codec, Message), 32),
    Kind =
        case Mode of
            cast -> 0;
            call -> 1
        end,
    Transaction =
        case Mode of
            cast -> 0;
            call -> Slot
        end,
    Header = (Selector bsl 24) bor (Transaction bsl 8) bor (byte_size(Payload) div 4),
    {
        <<Session:64/little, Incarnation:64/little, Actor:32/little, Request:32/little,
            Kind:32/little, Slot:32/little, Header:32/little, Payload/binary>>,
        Replies
    };
request(_Actor, Mode, Message, _Session, _Incarnation, _Request, _Slot) ->
    error({invalid_request, Mode, Message}).

-doc "Decodes a canonical record from its ordinary frame. Rejects unknown tags, flags, lengths and nonzero padding.".
-spec message(actor(), hls_nums:u32(), binary()) -> {atom(), byte(), tuple()}.
message(#{schemas := Schemas}, Header, Payload) ->
    Selector = Header bsr 24,
    Slot = (Header bsr 8) band 255,
    0 = (Header bsr 16) band 255,
    true = byte_size(Payload) =:= (Header band 255) * 4,
    [{Tag, #{codec := Codec, width := Width}}] =
        [
            {Tag, Schema}
         || {Tag, Schema = #{selector := S}} <- maps:to_list(Schemas), S =:= Selector
        ],
    true = byte_size(Payload) =:= ((Width + 31) div 32) * 4,
    <<Packed:Width/bitstring, _Padding/bitstring>> = Payload,
    {Message, <<>>} = hls_record_codec:unpack(Codec, Packed),
    Payload = hls_codec:align(hls_record_codec:pack(Codec, Message), 32),
    {Tag, Slot, Message}.

-doc "Encodes inspect or a shared lifecycle command with an independent management correlation identity.".
-spec management(
    hls_nums:u64(), hls_nums:u32(), none | hls_domain_lifecycle:input(), control_interface()
) ->
    {0 | 1, binary()}.
management(Session, Sequence, none, _Interface) when Session > 0, Session < (1 bsl 64) ->
    {0, <<Session:64/little, Sequence:32/little>>};
management(
    Session,
    Sequence,
    #domain_input{
        op = Op,
        expected = Expected,
        target = Target,
        transition = Transition,
        fault = Fault
    },
    #{codecs := Codecs}
) when Session > 0, Session < (1 bsl 64) ->
    Operation = code(operation, Op, Codecs),
    Cause = code(fault, Fault, Codecs),
    {1,
        <<Session:64/little, Sequence:32/little, Operation:32/little, Expected:64/little,
            Target:64/little, Transition:64/little, Cause:32/little>>}.

-doc "Decodes a complete management snapshot including its accepted-output frontier; missing or malformed evidence rejects.".
-spec observation(binary(), control_interface()) ->
    {
        hls_nums:u64(),
        hls_nums:u32(),
        hls_domain_lifecycle:output(),
        hls_nums:u16(),
        hls_nums:u32(),
        hls_nums:u32()
    }.
observation(
    <<Session:64/little, Sequence:32/little, Status:32/little, Action:32/little, Phase:32/little,
        Current:64/little, Previous:64/little, Target:64/little, Transition:64/little,
        Fault:32/little, Source:32/little, Actor:32/little, Frontier:32/little>>,
    #{codecs := Codecs}
) when Session > 0, Source < (1 bsl 16) ->
    P = value(phase, Phase, Codecs),
    State = #domain_state{
        phase = P,
        current = Current,
        previous = Previous,
        target = Target,
        transition = Transition,
        fault = value(fault, Fault, Codecs)
    },
    {Session, Sequence,
        #domain_output{
            status = value(status, Status, Codecs),
            action = value(action, Action, Codecs),
            admit = P =:= ready,
            state = State
        },
        Source, Actor, Frontier}.

-doc "Encodes a child watch or retirement acknowledgement for one exact incarnation. These commands confer observation rights, never lifecycle authority.".
-spec publication(hls_nums:u64(), hls_nums:u32(), {watch | retire_ack, hls_nums:u64()}) ->
    {2 | 3, binary()}.
publication(Session, Sequence, {Operation, Incarnation}) when
    Session > 0,
    Session < (1 bsl 64),
    Sequence > 0,
    Sequence < (1 bsl 32),
    Incarnation > 0,
    Incarnation < (1 bsl 64)
->
    Tag =
        case Operation of
            watch -> 2;
            retire_ack -> 3
        end,
    {Tag, <<Session:64/little, Sequence:32/little, Incarnation:64/little>>}.

-doc "Decodes a supervised child's complete snapshot and retained retirement evidence. Missing suffixes, mismatched watched identities and oversized enum values reject.".
-spec supervision(binary(), interface()) ->
    {
        {
            hls_nums:u64(),
            hls_nums:u32(),
            hls_domain_lifecycle:output(),
            hls_nums:u16(),
            hls_nums:u32(),
            hls_nums:u32()
        },
        publication()
    }.
supervision(
    <<Base:72/binary, Watched:64/little, Valid:32/little, Incarnation:64/little, Phase:32/little,
        Fault:32/little, Source:32/little, Actor:32/little, Frontier:32/little>>,
    Interface = #{supervision := local, codecs := Codecs}
) when (Valid =:= 0 orelse Valid =:= 1), Source < (1 bsl 16) ->
    Observation = {_, _, _, _, _, CurrentFrontier} = observation(Base, Interface),
    Receipt =
        case Valid of
            0 ->
                none;
            1 ->
                true = Incarnation > 0 andalso Incarnation =:= Watched,
                true = Frontier =< CurrentFrontier,
                #{
                    incarnation => Incarnation,
                    phase => value(phase, Phase, Codecs),
                    fault => value(fault, Fault, Codecs),
                    source => Source,
                    actor => Actor,
                    frontier => Frontier
                }
        end,
    {Observation, #{watched => Watched, retirement => Receipt}}.

-doc "Decodes the common response envelope; typed payload interpretation and current-incarnation checks belong to the backend.".
-spec application(2 | 3 | 4, binary()) -> response().
application(
    Tag,
    <<Session:64/little, Sequence:32/little, Incarnation:64/little, Actor:32/little,
        Request:32/little, Disposition:32/little, Port:32/little, Header:32/little, Payload/binary>>
) when
    Session > 0, Sequence > 0, Tag >= 2, Tag =< 4
->
    Kind =
        case Tag of
            2 -> accepted;
            3 -> reply;
            4 -> effect
        end,
    Status =
        case Disposition of
            0 -> accepted;
            1 -> stale;
            2 -> invalid;
            3 -> busy;
            4 -> exhausted
        end,
    case Kind of
        accepted ->
            0 = Port,
            0 = Header,
            <<>> = Payload;
        reply ->
            accepted = Status;
        effect ->
            accepted = Status,
            0 = Request
    end,
    #{
        kind => Kind,
        session => Session,
        sequence => Sequence,
        incarnation => Incarnation,
        actor => Actor,
        request => Request,
        disposition => Status,
        port => Port,
        header => Header,
        payload => Payload
    }.

%% Atom wire codes are derived from the same descriptors as generated hardware.
-spec code(atom(), atom(), #{atom() => hls_type:descriptor()}) -> non_neg_integer().
code(Kind, Value, Codecs) ->
    Descriptor = maps:get(Kind, Codecs),
    Width = hls_type:width(Descriptor),
    <<Code:Width>> = hls_type:pack(Value, Descriptor),
    Code.

%% Do not truncate an oversized word into a valid narrower enum member.
-spec value(atom(), non_neg_integer(), #{atom() => hls_type:descriptor()}) -> atom().
value(Kind, Code, Codecs) ->
    Descriptor = maps:get(Kind, Codecs),
    Width = hls_type:width(Descriptor),
    true = Code < (1 bsl Width),
    {Value, <<>>} = hls_type:unpack(<<Code:Width>>, Descriptor),
    Value.
