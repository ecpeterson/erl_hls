-module(hls_protocol_capture_tests).
-include_lib("eunit/include/eunit.hrl").

%% A literal identity disappears, while the entire two variable fields retain ABI order.
-spec source_constants_test() -> ok.
source_constants_test() ->
    C = channel(unaligned, unaligned),
    ?assertEqual(63, maps:get(message_bits, C)),
    ?assertEqual(59, maps:get(payload_bits, C)),
    [Id, Epoch, Value, Flag] = maps:get(fields, C),
    ?assertEqual(<<5:3>>, maps:get(constant, Id)),
    ?assertEqual(<<1:1>>, maps:get(constant, Flag)),
    ?assertEqual(3, maps:get(message_bit_offset, Epoch)),
    ?assertEqual(0, maps:get(capture_bit_offset, Epoch)),
    ?assertEqual(13, maps:get(capture_bit_offset, Value)).

%% Every phase and conditional arm contributes even when a first alternative has a literal.
-spec all_sends_participate_test() -> ok.
all_sends_participate_test() ->
    Program = fixture_program(),
    lists:foreach(fun(Port) ->
        C = channel(Program, Port, constant),
        ?assertEqual(3, maps:get(payload_bits, C)),
        ?assertNot(maps:is_key(constant, hd(maps:get(fields, C))))
    end, [varying, conditional]).

%% Startup values and partial numeric masks are not promoted to whole-field source constants.
-spec conservative_unknowns_test() -> ok.
conservative_unknowns_test() ->
    Program = fixture_program(),
    ?assertEqual(5, maps:get(payload_bits, channel(Program, partial, small))),
    ?assertEqual(3, maps:get(payload_bits, channel(Program, state_value, constant))).

%% Only a complete compiled program enters capture planning; source, selected and saved maps are not programs.
-spec supplied_alternatives_rejected_test() -> ok.
supplied_alternatives_rejected_test() ->
    Program = fixture_program(),
    Spec = #{entries := [First | _]} = xls_actor_program:spec(Program),
    Invalid = [[#{fields => []}], Spec#{entries := [First]},
        #{file => "test/hls_protocol_capture_fixture.erl", options => []},
        #{spec => Spec, plan => xls_actor_program:plan(Program)}],
    lists:foreach(fun(Supplied) ->
        ?assertError(function_clause, hls_protocol_capture:plan(
            inventory(unaligned, unaligned), #{a => Supplied}))
    end, Invalid).

%% A request for a nonexistent send fails instead of inventing a zero-width channel.
-spec absent_send_rejected_test() -> ok.
absent_send_rejected_test() ->
    Program = fixture_program(),
    ?assertError({missing_channel_alternatives, _}, channel(Program, missing, constant)),
    ?assertError({missing_channel_alternatives, _}, channel(Program, unaligned, missing)).

%% Reply effects are outside entry layouts and therefore cannot silently evade the join.
-spec retained_replies_rejected_test() -> ok.
retained_replies_rejected_test() ->
    File = "test/hls_statem_reply_fixture.erl",
    Program = xls_actor_program:from_file(File, []),
    ?assertError({unsupported_capture_replies, File}, hls_protocol_capture:plan(
        inventory(reply, constant), #{a => Program})).

%% External publication is not an internal capture slot, and the proposal grants no runtime eligibility.
-spec external_is_not_internal_slot_test() -> ok.
external_is_not_internal_slot_test() ->
    #{channels := [C]} = inventory(unaligned, unaligned),
    R = hls_protocol_capture:plan(#{channels => [C#{destination := {external, out}}]}, #{}),
    ?assertEqual([], maps:get(channels, R)),
    ?assertEqual(false, maps:get(eligible, R)).

%% Existing programs retain their snapshot; constructing a fresh program must read changed source.
-spec changed_source_is_replanned_test() -> ok.
changed_source_is_replanned_test() ->
    {ok, Original} = file:read_file("test/hls_protocol_capture_fixture.erl"),
    File = filename:join("_build", "capture_changed_" ++ integer_to_list(erlang:unique_integer([positive])) ++ ".erl"),
    try
        ok = file:write_file(File, Original, [exclusive]),
        Program = xls_actor_program:from_file(File, []),
        BeforePlan = #{channels := [Before], sources := #{a := BP}} =
            hls_protocol_capture:plan(inventory(varying, constant), #{a => Program}),
        Edited = binary:replace(Original, <<"{cast, varying, #constant{id = 2}}">>,
            <<"{cast, varying, #constant{id = 1}}">>),
        ?assertNotEqual(Original, Edited),
        ok = file:write_file(File, Edited),
        ?assertEqual(BeforePlan, hls_protocol_capture:plan(inventory(varying, constant), #{a => Program})),
        Fresh = xls_actor_program:from_file(File, []),
        #{channels := [After], sources := #{a := AP}} =
            hls_protocol_capture:plan(inventory(varying, constant), #{a => Fresh}),
        ?assertEqual({3, 0}, {maps:get(payload_bits, Before), maps:get(payload_bits, After)}),
        ?assertNotEqual(maps:get(source_sha256, BP), maps:get(source_sha256, AP))
    after
        ok = file:delete(File)
    end.

%% A fresh compiler program retains all entry alternatives before selecting a channel.
-spec fixture_program() -> xls_actor_program:program().
fixture_program() -> xls_actor_program:from_file("test/hls_protocol_capture_fixture.erl", []).

%% Convenience for an independently compiled source case.
-spec channel(atom(), atom()) -> map().
channel(Port, Tag) -> channel(fixture_program(), Port, Tag).

%% Channel selection consumes the complete program rather than caller-supplied constant facts.
-spec channel(xls_actor_program:program(), atom(), atom()) -> map().
channel(Program, Port, Tag) ->
    #{channels := [C]} = hls_protocol_capture:plan(inventory(Port, Tag), #{a => Program}),
    C.

%% Bind the requested port and schema to an explicit producer and recipient.
-spec inventory(atom(), atom()) -> map().
inventory(Port, Tag) ->
    #{channels => [#{source => a, port => Port, tag => Tag, destination => {actor, b}}]}.
