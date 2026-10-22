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
    lists:foreach(fun(Port) ->
        C = channel(Port, constant),
        ?assertEqual(3, maps:get(payload_bits, C)),
        ?assertNot(maps:is_key(constant, hd(maps:get(fields, C))))
    end, [varying, conditional]).

%% Startup values and partial numeric masks are not promoted to whole-field source constants.
-spec conservative_unknowns_test() -> ok.
conservative_unknowns_test() ->
    ?assertEqual(5, maps:get(payload_bits, channel(partial, small))),
    ?assertEqual(3, maps:get(payload_bits, channel(state_value, constant))).

%% The old API cannot supply a handpicked subset or manufacture omitted constants.
-spec supplied_alternatives_rejected_test() -> ok.
supplied_alternatives_rejected_test() ->
    ?assertError(function_clause, hls_protocol_capture:plan(
        inventory(unaligned, unaligned), #{a => [#{fields => []}]})).

%% A request for a nonexistent send fails instead of inventing a zero-width channel.
-spec absent_send_rejected_test() -> ok.
absent_send_rejected_test() ->
    ?assertError({missing_channel_alternatives, _}, channel(missing, constant)),
    ?assertError({missing_channel_alternatives, _}, channel(unaligned, missing)).

%% Reply effects are outside entry layouts and therefore cannot silently evade the join.
-spec retained_replies_rejected_test() -> ok.
retained_replies_rejected_test() ->
    File = "test/hls_statem_reply_fixture.erl",
    ?assertError({unsupported_capture_replies, File}, hls_protocol_capture:plan(
        inventory(reply, constant), #{a => #{file => File, options => []}})).

%% External publication is not an internal capture slot, and the proposal grants no runtime eligibility.
-spec external_is_not_internal_slot_test() -> ok.
external_is_not_internal_slot_test() ->
    #{channels := [C]} = inventory(unaligned, unaligned),
    R = hls_protocol_capture:plan(#{channels => [C#{destination := {external, out}}]}, #{}),
    ?assertEqual([], maps:get(channels, R)),
    ?assertEqual(false, maps:get(eligible, R)).

%% Every plan recompiles the current file; saved alternative hashes do not authorize a stale layout.
-spec changed_source_is_replanned_test() -> ok.
changed_source_is_replanned_test() ->
    {ok, Original} = file:read_file("test/hls_protocol_capture_fixture.erl"),
    File = filename:join("_build", "capture_changed_" ++ integer_to_list(erlang:unique_integer([positive])) ++ ".erl"),
    Sources = #{a => #{file => File, options => []}},
    try
        ok = file:write_file(File, Original, [exclusive]),
        #{channels := [Before], sources := #{a := BP}} = hls_protocol_capture:plan(inventory(varying, constant), Sources),
        Edited = binary:replace(Original, <<"{cast, varying, #constant{id = 2}}">>,
            <<"{cast, varying, #constant{id = 1}}">>),
        ok = file:write_file(File, Edited),
        #{channels := [After], sources := #{a := AP}} = hls_protocol_capture:plan(inventory(varying, constant), Sources),
        ?assertEqual({3, 0}, {maps:get(payload_bits, Before), maps:get(payload_bits, After)}),
        ?assertNotEqual(maps:get(source_sha256, BP), maps:get(source_sha256, AP))
    after
        ok = file:delete(File)
    end.

%% Exercise the public source-file API, not synthetic compiler facts.
-spec channel(atom(), atom()) -> map().
channel(Port, Tag) ->
    #{channels := [C]} = hls_protocol_capture:plan(inventory(Port, Tag),
        #{a => #{file => "test/hls_protocol_capture_fixture.erl", options => []}}),
    C.

%% Bind the requested port and schema to an explicit producer and recipient.
-spec inventory(atom(), atom()) -> map().
inventory(Port, Tag) ->
    #{channels => [#{source => a, port => Port, tag => Tag, destination => {actor, b}}]}.
