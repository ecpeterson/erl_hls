-module(hls_domain_wire_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").

%% Retained codecs preserve partial-byte records without loading an actor module.
-spec typed_call_roundtrip_test() -> ok.
typed_call_roundtrip_test() ->
    Actor = actor(),
    ok = hls_domain_wire:check(interface()),
    {Packet, [answer]} = hls_domain_wire:request(Actor, call, {sample, 5}, 41, 17, 23, 0),
    <<41:64/little,17:64/little, 3:32/little, 23:32/little, 1:32/little, 0:32/little,
        Header:32/little, Payload/binary>> = Packet,
    ?assertEqual({sample, 0, {sample, 5}}, hls_domain_wire:message(Actor, Header, Payload)),
    ?assertEqual(4, byte_size(Payload)).

%% Known schemas do not imply a legal request family or valid field value.
-spec request_contract_test() -> ok.
request_contract_test() ->
    ?assertError({invalid_request, call, trigger}, hls_domain_wire:request(actor(), call, {trigger, 1}, 41, 1, 1, 0)),
    ?assertError({invalid_request, cast, sample}, hls_domain_wire:request(actor(), cast, {sample, 1}, 41, 1, 1, 255)),
    ?assertException(error, _, hls_domain_wire:request(actor(), call, {sample, 1}, 41, 1, 1, 1)),
    ?assertException(error, _, hls_domain_wire:request(actor(), cast, {trigger, 1}, 41, 1, 1, 0)),
    ?assertError(badarg, hls_domain_wire:request(actor(), call, {sample, 8}, 41, 1, 1, 0)),
    {<<41:64/little,1:64/little,3:32/little,2:32/little,0:32/little,255:32/little,Header:32/little,Payload/binary>>, []} =
        hls_domain_wire:request(actor(), cast, {trigger, 1}, 41, 1, 2, 255),
    ?assertEqual({trigger, 0, {trigger, 1}}, hls_domain_wire:message(actor(), Header, Payload)).

%% One multicast carries both inclusive corners and the same ordinary cast frame.
-spec rectangle_cast_test() -> ok.
rectangle_cast_test() ->
    Actor = (actor())#{ingress => #{trigger => #{rectangle => {4, 8}}}},
    Encode = fun(Binding, Bounds) ->
        hls_domain_wire:request(Binding, {rectangle, Bounds}, {trigger, 5}, 41, 17, 23, 255)
    end,
    {<<41:64/little,17:64/little,3:32/little,23:32/little,2:32/little,255:32/little,
       1:16/little,2:16/little,3:16/little,7:16/little,H:32/little,P/binary>>, []} =
        Encode(Actor, {1,2,3,7}),
    {<<_:192,3:32/little,255:32/little,1:16/little,2:16/little,3:16/little,7:16/little,
       H:32/little,P/binary>>, []} =
        hls_domain_wire:request(Actor, {rectangle, {1,2,3,7}, consumed}, {trigger, 5}, 41, 17, 23, 255),
    ?assertEqual({trigger, 0, {trigger, 5}}, hls_domain_wire:message(Actor, H, P)),
    [?assertError({invalid_rectangle, B}, Encode(Actor, B)) ||
        B <- [{0,0,4,7}, {0,0,3,8}, {-1,0,3,7}, {3,2,2,2}, {1,2,1,1}]],
    ?assertError({unsupported_rectangle_cast, trigger}, Encode(actor(), {0,0,0,0})).

%% Assert the established axis header byte order independently of the decoder.
-spec canonical_header_test() -> ok.
canonical_header_test() ->
    Actor0 = #{contract := Contract} = actor(),
    Actor = Actor0#{contract := Contract#{pending_calls := 32}},
    {<<_:256, 1, 17, 0, 1, _Payload/binary>>, [answer]} =
        hls_domain_wire:request(Actor, call, {sample, 2}, 41, 1, 1, 17),
    {<<_:224, 255:32/little, 1, 0, 0, 3, _CastPayload/binary>>, []} =
        hls_domain_wire:request(Actor, cast, {trigger, 2}, 41, 1, 2, 255),
    {_, _, {sample, 2}} = hls_domain_wire:message(Actor, 16#01001101, <<2:3, 0:29>>),
    ok.

%% Padding, flags and exact physical lengths are part of the record boundary.
-spec noncanonical_frame_test() -> ok.
noncanonical_frame_test() ->
    {<<_:256, Header:32/little, Payload/binary>>, _} = hls_domain_wire:request(actor(), call, {sample, 2}, 41, 1, 1, 0),
    <<Head:8, Rest/binary>> = Payload,
    ?assertException(error, _, hls_domain_wire:message(actor(), Header, <<(Head bor 1):8, Rest/binary>>)),
    ?assertException(error, _, hls_domain_wire:message(actor(), Header bor (1 bsl 16), Payload)),
    ?assertException(error, _, hls_domain_wire:message(actor(), Header, <<Payload/binary,0:32>>)).

%% A snapshot has an explicit frontier; truncating it must not imply that no outputs were accepted.
-spec management_frontier_test() -> ok.
management_frontier_test() ->
    Interface = interface(),
    {1, <<41:64/little,9:32/little,2:32/little,7:64/little,8:64/little,10:64/little,0:32/little>>} =
        hls_domain_wire:management(41, 9, #domain_input{op=replace,expected=7,target=8,transition=10}, Interface),
    Packet = <<41:64/little,9:32/little,1:32/little,0:32/little,1:32/little,8:64/little,7:64/little,8:64/little,
        10:64/little,0:32/little,0:32/little,3:32/little,42:32/little>>,
    {41, 9, #domain_output{status=accepted,state=#domain_state{phase=ready,current=8}},0,3,42} =
        hls_domain_wire:observation(Packet, Interface),
    <<Truncated:68/binary,_:4/binary>> = Packet,
    ?assertException(error, _, hls_domain_wire:observation(Truncated, Interface)).

%% Stop occupies a distinct command code while preserving the incarnation at both endpoints.
-spec stop_roundtrip_test() -> ok.
stop_roundtrip_test() ->
    {1, <<41:64/little,9:32/little,9:32/little,7:64/little,7:64/little,7:64/little,0:32/little>>} =
        hls_domain_wire:management(41, 9, #domain_input{op=stop,expected=7,target=7,transition=7}, interface()),
    Packet = <<41:64/little,9:32/little,7:32/little,0:32/little,6:32/little,7:64/little,
        7:64/little,7:64/little,7:64/little,0:32/little,0:32/little,0:32/little,42:32/little>>,
    ?assertMatch({41,9,#domain_output{status=completed,state=#domain_state{phase=stopped,current=7,target=7}},0,0,42},
        hls_domain_wire:observation(Packet, interface())).

%% Unknown dispositions and malformed acknowledgement bodies cannot release a call slot.
-spec application_envelope_test() -> ok.
application_envelope_test() ->
    Packet = <<41:64/little,1:32/little,7:64/little,3:32/little,4:32/little,0:32/little,0:32/little,0:32/little>>,
    ?assertMatch(#{kind:=accepted,session:=41,sequence:=1,incarnation:=7,request:=4,disposition:=accepted},
        hls_domain_wire:application(2, Packet)),
    ?assertException(error, _, hls_domain_wire:application(2, <<Packet/binary,0:32>>)),
    ?assertException(error, _, hls_domain_wire:application(2,
        <<41:64/little,1:32/little,7:64/little,3:32/little,4:32/little,99:32/little,0:32/little,0:32/little>>)).

%% Every exported schema has a checked record descriptor and a unique actor-local selector.
-spec actor() -> hls_domain_wire:actor().
actor() ->
    Schemas = maps:from_list([begin
        Codec = hls_record_codec:bind(Tag, [{value,hls_nums:uN(3)}]),
        {Tag,#{name=>Tag,selector=>Selector,width=>3,codec=>Codec}}
    end || {Tag,Selector} <- [{sample,1},{answer,2},{trigger,3}]]),
    #{index=>3,schemas=>Schemas,contract=>#{calls=>#{sample=>[answer]},casts=>[trigger],pending_calls=>1},
        outputs=>#{effect=>[answer]},ports=>#{effect=>0}}.

%% Finite lifecycle enum order is fixture data for testing retained descriptor conversion.
-spec interface() -> hls_domain_wire:interface().
interface() ->
    #{actors=>#{worker=>actor()},frame_payload_words=>4,management_route=>{0,0},application_route=>{0,1},codecs=>maps:from_list([
        {Name,{hls_type,hls_enum,enum,[Members]}} || {Name,Members} <- [
            {operation,[inspect,activate,replace,fault,fenced,reset_done,initialized,abort,reject,stop]},
            {phase,[unbound,ready,closing,isolated,initializing,failed,stopped]},
            {status,[ok,accepted,replay,stale,busy,invalid,failure,completed]},
            {action,[none,fence,reset,initialize,publish]},
            {fault,[none,actor_failure,owner_down,initialization_failure,lifecycle_failure,protocol_failure]}]])}.

%% Child publication commands cannot be confused with lifecycle operations or other incarnations.
-spec publication_envelope_test() -> ok.
publication_envelope_test() ->
    ?assertEqual({2,<<41:64/little,9:32/little,7:64/little>>},hls_domain_wire:publication(41,9,{watch,7})),
    ?assertEqual({3,<<41:64/little,10:32/little,7:64/little>>},hls_domain_wire:publication(41,10,{retire_ack,7})),
    ?assertException(error,_,hls_domain_wire:publication(41,11,{watch,0})).

%% The prior failure belongs to watched epoch seven even while current epoch nine is healthy.
-spec retained_retirement_test() -> ok.
retained_retirement_test() ->
    I=(interface())#{supervision=>local},
    Base= <<41:64/little,9:32/little,0:32/little,0:32/little,1:32/little,9:64/little,8:64/little,9:64/little,
        10:64/little,0:32/little,0:32/little,3:32/little,42:32/little>>,
    Suffix= <<7:64/little,1:32/little,7:64/little,5:32/little,1:32/little,17:32/little,3:32/little,40:32/little>>,
    ?assertMatch({{41,9,#domain_output{state=#domain_state{current=9}},0,3,42},
        #{watched:=7,retirement:=#{incarnation:=7,phase:=failed,fault:=actor_failure,source:=17,frontier:=40}}},
        hls_domain_wire:supervision(<<Base/binary,Suffix/binary>>,I)),
    ?assertException(error,_,hls_domain_wire:supervision(Base,I)),
    <<_:64,Rest/binary>>=Suffix,
    ?assertException(error,_,hls_domain_wire:supervision(<<Base/binary,8:64/little,Rest/binary>>,I)).
