-module(hls_protocol_class_selection_tests).
-moduledoc "Canonical source-class selection checks only deliberate mismatches; source packer faults remain visible.".
-include_lib("eunit/include/eunit.hrl").
-export([pack/1]).

%% Different source constants disambiguate ports sharing a tag and destination with one packing call.
-spec constant_selection_test() -> ok.
constant_selection_test() ->
    Link = encoder([constant_class(2, first, 7), constant_class(5, second, 9)]),
    {Selected, 1} = counted(fun() -> hls_protocol_mixed:encode(Link, {token, 9}) end),
    ?assertEqual({5, (9 bsl 32) bor (17 bsl 24) bor 1}, Selected),
    ?assertEqual(Selected, hls_protocol_mixed:encode(Link, second, {token, 9})),
    ?assertError({no_protocol_class, token}, hls_protocol_mixed:encode(Link, {token, 8})).

%% A record valid for two distinct class slots is ambiguous, even if its ordinary bytes agree.
-spec ambiguous_selection_test() -> ok.
ambiguous_selection_test() ->
    First = constant_class(2, first, 7),
    Link = encoder([First, First#{slot := 5, port := second}]),
    ?assertError({ambiguous_protocol_classes, token, [2, 5]}, hls_protocol_mixed:encode(Link, {token, 7})).

%% Invalid record shapes and undeclared tags never invoke the source codec.
-spec malformed_selection_test() -> ok.
malformed_selection_test() ->
    Link = encoder([constant_class(2, first, 7)]),
    {ok, 0} = counted(fun() ->
        ?assertError({invalid_protocol_message, not_a_record}, hls_protocol_mixed:encode(Link, not_a_record)),
        ?assertError({invalid_protocol_message, {}}, hls_protocol_mixed:encode(Link, {})),
        ?assertError({no_protocol_class, unknown}, hls_protocol_mixed:encode(Link, {unknown, 7})),
        ok
    end).

%% A source codec crash or inconsistent checked width must not be treated as an absent candidate.
-spec packer_failure_test() -> ok.
packer_failure_test() ->
    Class = constant_class(2, first, 7),
    ?assertError(source_packer_failed, hls_protocol_mixed:encode(encoder([Class#{tag := broken}]), {broken, 7})),
    ?assertError({badmatch, 8}, hls_protocol_mixed:encode(encoder([Class#{message_bits := 16}]), {token, 7})).

-doc "Packs the tiny test record while counting calls only inside an explicitly enabled counting scope; a broken record raises the original source fault.".
-spec pack({token | broken, byte()}) -> binary().
pack({broken, _}) -> error(source_packer_failed);
pack({token, Value}) ->
    case get({?MODULE, packing_calls}) of
        undefined -> ok;
        Count -> put({?MODULE, packing_calls}, Count + 1)
    end,
    <<Value:8>>.

%% Both alternatives use a destination selector deliberately unrelated to a source tag enumeration.
-spec constant_class(byte(), atom(), byte()) -> hls_protocol_mixed:codec_class().
constant_class(Slot, Port, Value) ->
    Codec = hls_protocol_codec:plan(#{message_bits => 8, payload_bits => 0,
        fields => [#{type => {hls_type, hls_nums, uN, [8]}, message_bit_offset => 0,
            constant => <<Value:8>>}]}, 17),
    #{slot => Slot, port => Port, tag => token, codec => Codec, message_bits => 8}.

%% A standalone class-selection view has no transport session or physical capture metadata.
-spec encoder([hls_protocol_mixed:codec_class()]) -> hls_protocol_mixed:encoder_link().
encoder(Classes) -> #{source_module => ?MODULE, classes => Classes}.

%% Limit instrumentation to this process and restore it even when a checked operation raises.
-spec counted(fun(() -> Value)) -> {Value, non_neg_integer()}.
counted(Action) ->
    Previous = put({?MODULE, packing_calls}, 0),
    try {Action(), get({?MODULE, packing_calls})}
    after
        case Previous of
            undefined -> erase({?MODULE, packing_calls});
            _ -> put({?MODULE, packing_calls}, Previous)
        end
    end.
