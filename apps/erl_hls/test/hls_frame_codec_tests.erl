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

%% Diagnostic decoding is deliberately separate from actor-lifetime handling.
-spec terminal_failure_codec_test() -> ok.
terminal_failure_codec_test() ->
    {_, _, Context} = hls_gs:encode_request(regsvc, call, {ping, 1}),
    Tag = regsvc:pack_tag(error),
    Source = (37 bsl 4) bor 13,
    ?assertEqual({reply, {error, {remote_failure,
        #{reason => badarith, source_code => Source, source_site => 37}}}},
        hls_gs:decode_reply(Tag, <<(16#c0000000 bor Source):32/little>>, Context)),
    ?assertEqual({reply, {error, {remote_failure, #{reason => reply_handle_exhausted}}}},
        hls_gs:decode_reply(Tag, <<16#80000011:32/little>>, Context)),
    %% Source code 17 is site 1/function_clause, not generic handle exhaustion.
    ?assertEqual({reply, {error, {remote_failure,
        #{reason => function_clause, source_code => 17, source_site => 1}}}},
        hls_gs:decode_reply(Tag, <<16#c0000011:32/little>>, Context)),
    [?assertEqual(ignore, hls_gs:decode_reply(Tag, <<Code:32/little>>, Context))
        || Code <- [16#40000011, 16#c0000000, 16#c0000010, 16#c001000d]],
    ok.
