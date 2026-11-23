-module(hls_domain_endpoint_packets_tests).
-moduledoc "Source-emission and canonical-restoration checks for the independent endpoint packet router. Real source captures supply all masks and values. These checks do not execute router RTL, establish carrier integrity or measure mapped area.".
-include_lib("eunit/include/eunit.hrl").

%% Resolve the source capture fixture once before checking emission, restoration and rejected metadata.
-spec packets_emission_test_() -> term().
packets_emission_test_() -> {timeout, 120, fun packets_emission/0}.

%% The router must expose atomic packet pins while retaining no application payload state.
-spec packets_emission() -> ok.
packets_emission() ->
    Config = fixture(),
    #{files := Files, result := Result} = hls_domain_endpoint_packets:emit(Config),
    #{inputs := Inputs, outputs := Outputs, routes := Routes, unit := Unit} = Result,
    ?assertMatch(#{state_bit_budget := 2, cursor_bits := 1, payload_registers := 0,
        canonical_comparisons := #{tx := 1, rx := 1}}, Result),
    ?assertMatch(#{bits := 1024, data_words := 32, ack_words := 11,
        binding_bits := {64, 256}, sequence_bits := {320, 32}, frame_bits := {352, 672}},
        maps:get(packet_format, Result)),
    ?assertEqual(<<"endpoint_packets_clock">>, maps:get(top, Unit)),
    ?assert(lists:member({"packet_tx", 1024}, Outputs)),
    ?assert(lists:member({"packet_rx_words", 6}, Inputs)),
    ?assert(lists:member({"endpoint_8_credit_ready", 1}, Inputs)),
    ?assert(lists:member({"endpoint_8_data_tx_ready", 1}, Outputs)),
    ?assert(lists:member({"endpoint_61_ack_valid", 1}, Inputs)),
    ?assert(lists:member({"endpoint_61_data_frame", 672}, Outputs)),
    Names = [Name || {Name, _} <- Inputs ++ Outputs],
    ?assertEqual(length(Names), length(lists:usort(Names))),
    ?assertEqual([], [N || N <- Names, string:find(N, "local_") =/= nomatch orelse
        string:find(N, "session") =/= nomatch]),
    ?assertEqual([], [N || {N, _} <- Outputs, lists:suffix("reset", N)]),
    Text = iolist_to_binary(maps:get("endpoint_packets/endpoint_packets.x", Files)),
    ?assertEqual(nomatch, binary:match(Text, <<"@@">>)),
    includes(Text, "pub struct State { cursor: Cursor, fault: bool }"),
    includes(Text, "let selected = select(io, s.cursor)"),
    includes(Text, "let outgoing = offer(io, selected.index)"),
    includes(Text, "uN[1]:0 => io.endpoint_8_tx_valid"),
    includes(Text, "uN[1]:1 => Offer"),
    includes(Text, "selected.known && (frame & selected.mask) == selected.value"),
    includes(Text, "io.packet_rx_words == u6:11 && rx_slot == u8:0 && rx_frame == Frame:0"),
    includes(Text, "else if tx_valid { selected.index } else { s.cursor }"),
    includes(Text, "let live = !io.reset && !s.fault && !io.carrier_fault && !bad_rx"),
    includes(Text, "router_fault: !io.reset && s.fault"),
    [restore(Route) || Route <- Routes],
    rejected(Config),
    eight_offers(Config),
    named_roles(Config),
    ok.

%% Distinct checked top names generate disjoint files and exact core instances without RTL rewriting.
-spec named_roles(hls_domain_endpoint_packets:config()) -> ok.
named_roles(Config) ->
    #{files := A, result := #{top_module := "role_a_packets", core_module := "role_a_packets_core", unit := UnitA}} =
        hls_domain_endpoint_packets:emit(Config#{top_module => "role_a_packets"}),
    #{files := B} = hls_domain_endpoint_packets:emit(Config#{top_module => "role_b_packets"}),
    ?assertEqual([], [Path || Path <- maps:keys(A), maps:is_key(Path, B)]),
    ?assertEqual(<<"role_a_packets_core">>, maps:get(module, UnitA)),
    ?assertEqual(<<"endpoint_packets_clock">>, maps:get(top, UnitA)),
    includes(iolist_to_binary(maps:get("role_a_packets/packets.sv", A)), "module role_a_packets"),
    includes(iolist_to_binary(maps:get("role_a_packets/packets.sv", A)), "role_a_packets_core"),
    ?assertException(error, _, hls_domain_endpoint_packets:emit(Config#{top_module => "../unsafe"})),
    ok.

%% Common constants preserve every valid source frame and never force class-varying or dynamic bits.
-spec restore(map()) -> ok.
restore(#{classes := Classes, common_mask := Mask, common_value := Value, common_fixed_bits := Count}) ->
    [#{codec := #{value := First}} | _] = Classes,
    ExpectedMask = lists:foldl(fun(I, Acc) ->
        Bit = 1 bsl I,
        Fixed = lists:all(fun(#{codec := #{mask := M, value := V}}) ->
            M band Bit =/= 0 andalso (V band Bit) =:= (First band Bit)
        end, Classes),
        case Fixed of true -> Acc bor Bit; false -> Acc end
    end, 0, lists:seq(0, 671)),
    ?assertEqual(ExpectedMask, Mask),
    ?assertEqual(First band ExpectedMask, Value),
    ?assertEqual(length([I || I <- lists:seq(0, 671), Mask band (1 bsl I) =/= 0]), Count),
    ?assert(Count > 500),
    lists:foreach(fun(#{codec := Codec = #{payload_bits := Width}}) ->
        Payloads = lists:usort([0, (1 bsl Width) - 1 | [1 bsl I || I <- lists:seq(0, Width - 1)]]),
        [begin
            Frame = hls_protocol_codec:decode(Codec, Payload),
            ?assertEqual({ok, Payload}, hls_protocol_codec:encode(Codec, Frame)),
            ?assertEqual(Frame, (Frame band bnot Mask) bor Value)
        end || Payload <- Payloads]
    end, Classes),
    [#{codec := #{mask := M0, value := V0}}, #{codec := #{mask := M1, value := V1}}] = Classes,
    Varying = M0 band M1 band (V0 bxor V1),
    ?assert(Varying =/= 0),
    ?assertEqual(0, Mask band Varying),
    ?assertEqual(0, Mask band bnot (M0 band M1)),
    ok.

%% Incomplete or contradictory source-class metadata cannot silently weaken packet validation.
-spec rejected(hls_domain_endpoint_packets:config()) -> ok.
rejected(Config = #{crossings := [C | Rest], endpoints := Endpoints}) ->
    #{link := Link = #{classes := [First | _]}} = C,
    ?assertException(error, _, hls_domain_endpoint_packets:emit(Config#{crossings := []})),
    ?assertException(error, _, hls_domain_endpoint_packets:emit(Config#{endpoints := Endpoints ++ Endpoints})),
    ?assertException(error, _, hls_domain_endpoint_packets:emit(Config#{crossings :=
        [C#{link := Link#{classes := [First]}} | Rest]})),
    ?assertException(error, _, hls_domain_endpoint_packets:emit(Config#{crossings :=
        [C#{link := Link#{classes := [First, First]}} | Rest]})),
    #{codec := Codec} = First,
    Wrong = First#{codec := Codec#{frame_layout := hls_frame_layout:new(3)}},
    ?assertException(error, _, hls_domain_endpoint_packets:emit(Config#{crossings :=
        [C#{link := Link#{classes := [Wrong, First#{slot := 1}]}} | Rest]})),
    ok.

%% Four DATA and four ACK offers fit the preregistered three-bit selection cursor plus one fault bit.
-spec eight_offers(hls_domain_endpoint_packets:config()) -> ok.
eight_offers(#{codecs := Codecs, crossings := [#{link := Link} | _]}) ->
    Endpoints = [#{id => I, kind => case I < 4 of true -> tx; false -> rx end} || I <- lists:seq(0, 7)],
    Crossings = [#{index => I, source_domain => 0, destination_domain => 1, link => Link#{index := I}}
        || I <- lists:seq(0, 7)],
    #{result := Result} = hls_domain_endpoint_packets:emit(#{endpoints => Endpoints, crossings => Crossings, codecs => Codecs}),
    ?assertMatch(#{state_bit_budget := 4, cursor_bits := 3, payload_registers := 0}, Result),
    ?assertException(error, _, hls_domain_endpoint_packets:emit(#{endpoints =>
        [E#{kind := tx} || E <- Endpoints], crossings => Crossings, codecs => Codecs})),
    ok.

%% Ordinary source capture analysis supplies distinct unaligned/small schemas at the actual wide frame capacity.
-spec fixture() -> hls_domain_endpoint_packets:config().
fixture() ->
    Program = xls_actor_program:from_file("apps/hls_fabric/test/hls_protocol_capture_fixture.erl", [], hls_frame_layout:new(20)),
    Channels = [#{source => a, port => Tag, tag => Tag, destination => {actor, b}} || Tag <- [unaligned, small]],
    #{channels := Captures} = hls_protocol_capture:plan(#{channels => Channels}, #{a => Program}),
    Classes = [#{slot => I, codec => hls_protocol_codec_plan:plan(Channel, Operation)}
        || {I, Channel = #{source_operation := Operation}} <- lists:enumerate(0, Captures)],
    Crossings = [#{index => I, source_domain => 0, destination_domain => 1,
        link => #{index => I, direction => outgoing, source_index => 0, destination_index => 1,
            slots => 2, classes => Classes}} || I <- [8, 61]],
    Source = hls_source:library_file(hls_fabric, "runtime/domain/hls_domain_channel_tx.erl"),
    {ok, Parsed} = hls_source:parse_file(Source),
    Forms = hls_records:resolve(Parsed),
    Inputs = maps:from_list(hls_records:fields(hls_records:find(Forms, endpoint_tx_input))),
    Outputs = maps:from_list(hls_records:fields(hls_records:find(Forms, endpoint_tx_output))),
    #{endpoints => [#{id => 8, kind => tx}, #{id => 61, kind => rx}], crossings => Crossings,
        codecs => #{operation => maps:get(op, Inputs), binding => maps:get(binding, Inputs), status => maps:get(status, Outputs)}}.

%% Interface-critical fragments check source structure without claiming generated RTL behavior.
-spec includes(binary(), iodata()) -> ok.
includes(Text, Fragment) ->
    ?assertNotEqual(nomatch, binary:match(Text, iolist_to_binary(Fragment))),
    ok.
