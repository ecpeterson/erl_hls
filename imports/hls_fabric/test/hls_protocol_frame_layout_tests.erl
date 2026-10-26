-module(hls_protocol_frame_layout_tests).
-moduledoc "Checks ordinary frame capacity through source projections, compact codecs and retained transport plans. These finite unit cases do not establish native timing or temporal progress.".
-include_lib("eunit/include/eunit.hrl").

%% Changing capacity preserves every bit of the unaligned physical field stream.
-spec projection_and_codec_layouts_test() -> ok.
projection_and_codec_layouts_test() ->
    lists:foreach(fun(Words) ->
        Layout = hls_frame_layout:new(Words),
        Effect = #{tag => message, fields => [#{type => type(3), constant => <<5:3>>},
            #{type => type(13), offset => 0}, #{type => type(1), constant => <<1:1>>}]},
        Projection = hls_protocol_projection:frame(Effect, [message], Layout),
        Codec = hls_protocol_codec:plan(#{message_bits => 17, payload_bits => 13,
            fields => [#{type => type(3), message_bit_offset => 0, constant => <<5:3>>},
                #{type => type(13), message_bit_offset => 3, capture_bit_offset => 0},
                #{type => type(1), message_bit_offset => 16, constant => <<1:1>>}]}, 3, Layout),
        FrameBits = hls_frame_layout:frame_bits(Layout),
        ?assertEqual(FrameBits, length(Projection)),
        ?assertEqual(Layout, maps:get(frame_layout, Codec)),
        lists:foreach(fun(Value) ->
            Field = hls_type:pack_exact(Value, type(13)),
            Frame = hls_frame_layout:pack_integer(Layout, 3, <<5:3, Field/bitstring, 1:1>>),
            ?assertEqual(Frame, hls_protocol_projection:evaluate(Projection, Value)),
            {ok, Compact} = hls_protocol_codec:encode(Codec, Frame),
            ?assertEqual(Frame, hls_protocol_codec:decode(Codec, Compact)),
            ?assertEqual({error, invalid_frame}, hls_protocol_codec:encode(Codec, Frame bor (1 bsl FrameBits))),
            ?assertEqual({error, invalid_frame}, hls_protocol_codec:encode(Codec, Frame bxor (1 bsl (FrameBits-1))))
        end, [0, 8191 | [1 bsl I || I <- lists:seq(0,12)]])
    end, [1,2,3,5]).

%% A wider declared layout admits fields above the historical three-word capacity.
-spec wider_payload_roundtrip_test() -> ok.
wider_payload_roundtrip_test() ->
    Layout = hls_frame_layout:new(4),
    Codec = hls_protocol_codec:plan(#{message_bits => 113, payload_bits => 113,
        fields => [#{type => type(113), message_bit_offset => 0, capture_bit_offset => 0}]}, 7, Layout),
    Value = (1 bsl 112)+17,
    Payload = hls_type:pack_exact(Value, type(113)),
    Frame = hls_frame_layout:pack_integer(Layout, 7, Payload),
    Projection = hls_protocol_projection:frame(#{tag => message, fields =>
        [#{type => type(113), offset => 0}]}, [reserved0,reserved1,reserved2,reserved3,message], Layout),
    ?assertEqual(Frame, hls_protocol_projection:evaluate(Projection, Value)),
    {ok, Compact} = hls_protocol_codec:encode(Codec, Frame),
    ?assertEqual(Frame, hls_protocol_codec:decode(Codec, Compact)),
    ?assertMatch({_,_}, binary:match(iolist_to_binary(hls_protocol_codec:emit(Codec,"convert")), <<"bits[160]">>)).

%% Explicit codec layouts cannot disagree with a source channel's retained capacity.
-spec mismatched_codec_layout_test() -> ok.
mismatched_codec_layout_test() ->
    Channel = #{frame_layout => hls_frame_layout:new(1), message_bits => 0, payload_bits => 0, fields => []},
    ?assertException(error, {badmatch,_}, hls_protocol_codec:plan(Channel, 3, hls_frame_layout:new(2))).

%% Startup and host domains derive from the same compiler program even after its file is removed.
-spec startup_and_domain_layout_test() -> ok.
startup_and_domain_layout_test() ->
    Layout = hls_frame_layout:new(1),
    Source = hls_protocol_schema_test_source:compile([{message,[{value,"hls_nums:uN(13)"}]}], Layout),
    [Frame] = hls_protocol_schema:frames(Source, [{message,16#1234}]),
    ?assertEqual(hls_frame_layout:pack_integer(Layout,3,hls_type:pack_exact(16#1234,type(13))), Frame),
    [#{mask := Mask,value := Value}] = hls_protocol_schema:domains(Source,[message]),
    ?assertEqual(Value, Frame band Mask),
    ?assertEqual(Value, (Frame bxor (1 bsl 32)) band Mask),
    ?assertNotEqual(Value, (Frame bxor (1 bsl 63)) band Mask),
    ?assertEqual(Layout, maps:get(frame_layout,hls_local_actor:descriptor(Source))).

%% The build's selected capacity reaches external publications, startup, captures and raw crossings.
-spec retained_transport_layout_test() -> ok.
retained_transport_layout_test() ->
    Layout = hls_frame_layout:new(1),
    Config = #{sources => [{"test/hls_protocol_inbox_fixture.erl",[]}],
        topology => {hls_protocol_inbox_fixture,topology,[]}, actor_limit => 3,
        frame_payload_words => 1, native_actors => [left,sink]},
    Build = hls_protocol_transport:plan(Config),
    #{frame_layout := Layout, bundle := #{frame_layout := Layout}, capture := Capture,
        fabric := Fabric = #{frame_layout := Layout,boundaries := Boundaries}, receivers := Receivers} =
        hls_protocol_transport:descriptor(Build),
    ?assert(lists:all(fun(#{output := #{width := W}}) -> W =:= 64 end,Boundaries)),
    ?assert(lists:all(fun(#{frame_layout := L}) -> L =:= Layout end,maps:get(channels,Capture))),
    ?assert(lists:all(fun(#{manifest := #{frame_layout := L,inbox := #{frame_layout := L}}}) -> L =:= Layout end,Receivers)),
    {Inputs,Outputs} = xls_protocol_partition:ports(Fabric),
    FramePorts = [Width || {Name,Width} <- Inputs++Outputs, lists:suffix("_frame",Name)],
    ?assert(FramePorts =/= []),
    ?assertEqual([64],lists:usort(FramePorts)).

%% Standalone artifact consumers receive the same selected capacity as both scheduler representations.
-spec scheduler_artifact_layout_test() -> ok.
scheduler_artifact_layout_test() ->
    Module = hls_topology_source_fixture,
    Common = #{version => 1, ingresses => [], startup => [],
        externals => [{values,out,[message]}]},
    Exact = hls_topology:normalize(Common#{actors => #{left => Module,right => Module},
        families => #{}, route_relations => [], routes =>
            [{{left,out},[{actor,right}]},{{right,out},[{external,values}]}]}),
    Family = hls_topology:normalize(Common#{actors => #{}, routes => [],
        families => #{left => #{module => Module,shape => [2,2]},
            right => #{module => Module,shape => [2,2]}}, route_relations =>
            [{{left,out},[{family,right,{translate,[0,0],wrap}}]},
                {{right,out},[{external,values}]}]}),
    lists:foreach(fun({Topology,Kind}) ->
        Profile = #{name => frame_layout_fixture, channel_depth => 1, actor_egress_depth => burst,
            frame_payload_words => 1, scheduler_groups => #{workers => #{
                members => [{Kind,left},{Kind,right}], state_storage => block_ram,mailbox_storage => block_ram}}},
        Requirements = xls_shared_topology_dslx:artifact_requirements(Topology,Profile),
        ?assertMatch(#{hls_topology_source_fixture := #{frame_payload_words := 1}},Requirements)
    end,[{Exact,actor},{Family,family}]).

%% Standalone owner emission carries the same selected layout as the full source builder.
-spec local_actor_layout_files_test() -> ok.
local_actor_layout_files_test() ->
    Layout = hls_frame_layout:new(1),
    Schema = [{message,[{value,"hls_nums:uN(13)"}]}],
    Actor = hls_protocol_schema_test_source:compile(Schema, Layout),
    Expected = iolist_to_binary(hls_frame_layout:config_dslx(Layout)),
    Files = hls_local_actor:emit(Actor, "nested/owner.x"),
    ?assertEqual(Expected, iolist_to_binary(maps:get("nested/frame_config.x", Files))),
    #{frame_config_sha256 := Hash} = hls_local_actor:manifest(Actor),
    ?assertEqual(hls_generated_files:hash(Expected), Hash),
    Root = filename:join("_build", "local-frame-layout-" ++ integer_to_list(erlang:unique_integer([positive]))),
    First = filename:join(Root, "first.x"),
    ok = filelib:ensure_dir(First),
    _ = hls_local_actor:write(Actor, First),
    _ = hls_local_actor:write(Actor, filename:join(Root, "second.x")),
    ConfigPath = filename:join(Root, "frame_config.x"),
    ?assertEqual({ok, Expected}, file:read_file(ConfigPath)),
    Wide = hls_protocol_schema_test_source:compile(Schema, hls_frame_layout:new(3)),
    Rejected = filename:join(Root, "rejected.x"),
    ?assertError({local_actor_frame_config_mismatch, ConfigPath}, hls_local_actor:write(Wide, Rejected)),
    ?assertNot(filelib:is_file(Rejected)),
    ?assertNot(filelib:is_file(Rejected ++ ".json")),
    ?assertEqual({ok, Expected}, file:read_file(ConfigPath)).

%% Provider descriptors preserve partial-byte widths through both host and DSLX codecs.
-spec type(pos_integer()) -> hls_type:descriptor().
type(Width) -> {hls_type,hls_nums,uN,[Width]}.
