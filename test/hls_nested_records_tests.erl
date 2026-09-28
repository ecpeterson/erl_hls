-module(hls_nested_records_tests).
-moduledoc false.
-include_lib("eunit/include/eunit.hrl").

%% The host and wire representations differ only by structural record tags.
-spec nested_codec_test() -> ok.
nested_codec_test() ->
    Sample = {sample, {vector2, 29, -31}, true},
    Message = {snapshot, Sample},
    Bits = <<29:5/little, -31:7/little-signed, 1:1>>,
    ?assertEqual(13, hls_nested_records_fixture:pack_width(snapshot)),
    ?assertEqual(Bits, hls_nested_records_fixture:pack(Message)),
    ?assertEqual({Message, <<5:3>>}, hls_nested_records_fixture:unpack(snapshot, <<Bits/bitstring, 5:3>>)),
    Cell = {cell, Sample, {sample, {vector2, 0, 0}, false}},
    ?assertEqual(26, hls_nested_records_fixture:pack_width(cell)),
    ?assertEqual({Cell, <<>>}, hls_nested_records_fixture:unpack(cell, hls_nested_records_fixture:pack(Cell))),
    ?assertEqual(3, hls_nested_records_fixture:pack_tag(snapshot)),
    ?assertEqual(4, hls_nested_records_fixture:pack_tag(report)),
    ok.

%% Zero expansion is recursive; helper updates keep their ordinary Erlang semantics.
-spec nested_actor_test() -> ok.
nested_actor_test() ->
    Zero = {sample, {vector2, 0, 0}, false},
    {ok, boot, Initial} = hls_nested_records_fixture:init([]),
    ?assertEqual({cell, Zero, Zero}, Initial),
    Input = {sample, {vector2, 31, -4}, true},
    {active, Cell, consume} = hls_nested_records_fixture:boot(cast, {snapshot, Input}, Initial),
    ?assertEqual({cell, {sample, {vector2, 0, -4}, true}, Zero}, Cell),
    {Cell, [{cast, out, {report, Current, Zero}}]} = hls_nested_records_fixture:active(enter, boot, Cell),
    ?assertEqual(element(2, Cell), Current),
    ok.

%% Shape and width violations are rejected at the nested codec boundary.
-spec malformed_nested_values_test() -> ok.
malformed_nested_values_test() ->
    ?assertError({invalid_hls_record_value, sample, {wrong, 0}},
        hls_nested_records_fixture:pack({snapshot, {wrong, 0}})),
    ?assertException(error, _, hls_nested_records_fixture:pack({snapshot, {sample, {vector2, 32, 0}, false}})),
    ok.

%% Recursive layouts and nested callback records cannot acquire a finite untagged layout.
-spec recursive_layout_test() -> ok.
recursive_layout_test() ->
    Header = [form("-hls_data(cell)."), form("-hls_tags([request]).")],
    Self = Header ++ [form("-record(value, {next = hls_type:zero() :: #value{}}).")],
    ?assertError({recursive_hls_record, [value, value]}, hls_records:resolve(Self)),
    Mutual = Header ++ [form("-record(a, {b = hls_type:zero() :: #b{}})."),
        form("-record(b, {a = hls_type:zero() :: #a{}}).")],
    ?assertError({recursive_hls_record, [a, b, a]}, hls_records:resolve(Mutual)),
    Wire = Header ++ [form("-record(value, {nested = hls_type:zero() :: #cell{}}).")],
    ?assertError({nested_hls_wire_record, cell}, hls_records:resolve(Wire)),
    ok.

%% Normal actor compilation emits dependency-ordered structs and no internal wire selectors.
-spec normal_lowering_test() -> ok.
normal_lowering_test() ->
    File = "test/hls_nested_records_fixture.erl",
    Text = iolist_to_binary(xls_parse:to_xls(File)),
    ?assertNotEqual(nomatch, binary:match(Text, <<"pub struct Vector2">>)),
    ?assertNotEqual(nomatch, binary:match(Text, <<"pub struct Sample">>)),
    ?assertEqual(nomatch, binary:match(Text, <<"Tag::SAMPLE">>)),
    ?assertEqual(nomatch, binary:match(Text, <<"Tag::VECTOR2">>)),
    Interface = xls_parse:actor_interface(File),
    ?assert(is_map(Interface)),
    ok.

%% Parse one declaration without requiring its dependencies to compile on the BEAM.
-spec form(string()) -> tuple().
form(Source) ->
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, Form} = erl_parse:parse_form(Tokens),
    Form.
