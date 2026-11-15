-module(hls_protocol_reply_tests).
-moduledoc "Source-protocol caller ownership and complete reply-frame publication. These checks validate lowering contracts; runtime reply ordering is exercised by the recovery-domain witness.".
-include_lib("eunit/include/eunit.hrl").

%% Dynamic reply headers and payload travel together through the one reserved publication row.
-spec complete_reply_projection_test() -> ok.
complete_reply_projection_test() ->
    Build = hls_protocol_transport:plan(config(topology)),
    #{sources := #{sources := [Source]}, actor_functions := [#{manifest := Manifest}]} =
        hls_protocol_transport:descriptor(Build),
    FrameBits = hls_frame_layout:frame_bits(hls_frame_layout:default()),
    #{retained_calls := #{port := reply, mode := immediate},
        effect_payload_bits := FrameBits, action_result_fields := Fields} = Manifest,
    ?assert(lists:member(reply, Fields)),
    ?assert(lists:member(reply_valid, Fields)),
    #{outputs := [#{width := FrameBits, destination := {external, replies}, rows := [Row]}],
        masks := Masks} = Source,
    #{layout := Layout, tag := {reply, [report]}, bits := Bits} = Row,
    ?assertEqual([{payload, I} || I <- lists:seq(0, FrameBits - 1)], Bits),
    ?assert(lists:member(#{layout => Layout, mask => 1}, Masks)),
    Frame = 16#123456789abcdef0123456789abcdef0,
    ?assertEqual(Frame, hls_protocol_projection:evaluate(Bits, Frame)).

%% Dynamic caller identity is never admitted into ordinary static internal-capture slots.
-spec internal_reply_rejected_test() -> ok.
internal_reply_rejected_test() ->
    ?assertError({unsupported_protocol_reply_route, cell, reply, [[{actor, cell}]]},
        hls_protocol_transport:plan(config(internal_reply))).

%% Internal casts cannot allocate host transactions by merely sharing a call record layout.
-spec internal_call_rejected_test() -> ok.
internal_call_rejected_test() ->
    Config = config(internal_call),
    ?assertError({hls_diagnostic, #{stage := inventory, code := unsupported_internal_call,
        context := #{source := {sender, out}, destination := {actor, cell}, schema := read}}},
        hls_protocol_transport:plan(Config#{actor_limit := 2,
            sources := [{"test/hls_protocol_call_fixture.erl", []},
                {"test/hls_protocol_call_sender_fixture.erl", []}]})).

%% Both cases compile the same complete source, changing only the declared recipient.
-spec config(atom()) -> map().
config(Function) ->
    #{sources => [{"test/hls_protocol_call_fixture.erl", []}],
        topology => {hls_protocol_call_fixture, Function, []}, actor_limit => 1}.

%% Immediate actors have no retained table, but the bridge owns one in-flight wire identity.
-spec immediate_domain_binding_test() -> ok.
immediate_domain_binding_test() ->
    Plan = hls_protocol_transport:plan(config(topology)),
    #{call_slots := 1, actors := #{cell := Actor}} =
        hls_domain_stream:bind(hls_protocol_transport:descriptor(Plan)),
    #{pending_calls := 1, contract := Contract} = Actor,
    ?assertEqual(#{read => [report]}, maps:get(calls, Contract)),
    ?assertNot(maps:is_key(pending_calls, Contract)).
