-module(hls_protocol_application_codec_tests).
-moduledoc "Runtime application codecs consume retained geometry and record schemas without source modules, compiler programs or hardware plans. Independent wire vectors cover selection and canonical padding.".
-include_lib("eunit/include/eunit.hrl").

%% The descriptor contains only runtime fields, so encoding cannot require a source actor or plan.
-spec retained_control_test() -> ok.
retained_control_test() ->
    Application = binding(),
    Record = {work, 16#5a, 16#beef},
    Command = {host, all, {0, 0, 1, 0}, Record},
    Expected = <<0:16/little, 0:16/little, 1:16/little, 0:16/little,
        2:32/little, 1, 0, 0, 7, 16#5a, 16#ef, 16#be, 0>>,
    ?assertEqual({Expected, [4, 9], Record},
        hls_protocol_application_codec:delivery(Application, Command)),
    ?assertEqual(Expected, hls_protocol_application_codec:control(Application, Command)),
    {_, [9], Record} = hls_protocol_application_codec:delivery(Application,
        {host, all, {1, 0, 1, 0}, Record}),
    ?assertException(error, _, hls_protocol_application_codec:control(Application,
        {host, all, {2, 0, 2, 0}, Record})),
    ?assertException(error, _, hls_protocol_application_codec:control(Application,
        {host, all, {0, 0, 3, 0}, Record})),
    ?assertException(error, _, hls_protocol_application_codec:control(Application,
        {host, all, {0, 0, 1, 0}, {other, 16#5a, 16#beef}})),
    ok.

%% A valid word can still have invalid record padding; device ownership remains part of decoding.
-spec retained_event_test() -> ok.
retained_event_test() ->
    Application = binding(),
    Frame = 1 bor (7 bsl 24) bor (16#beef5a bsl 32),
    ?assertEqual({reports, {work, 16#5a, 16#beef}},
        hls_protocol_application_codec:event(Application, board, 0, Frame)),
    lists:foreach(fun(BadFrame) ->
        ?assertException(error, _, hls_protocol_application_codec:event(Application, board, 0, BadFrame))
    end, [Frame bor (1 bsl 8), Frame bor (1 bsl 16), Frame bor (1 bsl 56),
        Frame bor (1 bsl 64), Frame bxor 3]),
    ?assertException(error, _, hls_protocol_application_codec:event(Application, board, 1, Frame)),
    ?assertException(error, _, hls_protocol_application_codec:event(Application, absent, 0, Frame)),
    ok.

%% Both directions retain the same generic codec; no actor module or planner is consulted.
-spec binding() -> hls_protocol_application_schema:control_view() | hls_protocol_application_schema:event_view().
binding() ->
    Layout = hls_frame_layout:default(),
    Codec = hls_record_codec:bind(work, [{code, hls_nums:u8()}, {value, hls_nums:u16()}]),
    Schema = #{name => work, selector => 7, width => 24, codec => Codec},
    Recipients = [#{index => Index, device => board, point => [X, 0],
        targets => [all], schemas => #{work => Schema}} || {Index, X} <- [{4, 0}, {9, 1}]],
    #{partition => #{frame_layout => Layout, ingresses => [#{id => host, shape => [3, 1],
        targets => [#{id => all, selector => 2, schemas => [work]}], bindings => Recipients}]},
      devices => #{board => #{host => 1, frame_layout => Layout,
        events => #{8 => #{id => reports, port => "external_0", schemas => #{7 => Schema}}}}}}.
