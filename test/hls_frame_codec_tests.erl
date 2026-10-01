-module(hls_frame_codec_tests).
-include_lib("eunit/include/eunit.hrl").

service_codec_test() ->
    {Tag, Payload, Context} = hls_gs:encode_request(regsvc, call, {ping, 42}),
    ?assertEqual(regsvc:pack_tag(ping), Tag),
    ?assertEqual(<<42:32/little>>, Payload),
    ?assertEqual({reply, {ack, 42}},
        hls_gs:decode_reply(regsvc:pack_tag(ack), regsvc:pack({ack, 42}), Context)),
    ?assertEqual(ignore, hls_gs:decode_reply(regsvc:pack_tag(ack), <<42:16>>, Context)),
    ?assertException(error, {invalid_request, call, set},
        hls_gs:encode_request(regsvc, call, {set, 0, 42, 16#ffffffff})),
    ?assertMatch({_, _, {regsvc, none}},
        hls_gs:encode_request(regsvc, cast, {set, 0, 42, 16#ffffffff})).

debug_codec_test() ->
    {1, <<>>, Context} = hls_debug:encode_request(regsvc, get_counters),
    ?assertEqual(ignore, hls_debug:response(16#83, <<>>, Context)),
    {7, <<1:32>>, RawContext} = hls_debug:encode_request(regsvc, {query, 7, <<1:32>>}),
    ?assertEqual({reply, {ok, <<2:32>>}}, hls_debug:response(16#87, <<2:32>>, RawContext)),
    ?assertException(error, function_clause,
        hls_debug:encode_request(regsvc, {query, 7, <<1:8>>})).
