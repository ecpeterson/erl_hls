-module(hls_domain_board_client_tests).
-moduledoc "Finite platform wire/client witnesses using an isolated fake broker. No DMA device, generated RTL or board is opened; these cases check exact framing, correlation and uncertain session mutation.".
-include_lib("eunit/include/eunit.hrl").

%% The platform client is intentionally outside generic runtime src_dirs. This
%% selected fixture compiles its exact local source once, without adding a
%% compiler dependency to deployed runtime code or writing a shared BEAM file.
-spec board_client_test_() -> term().
board_client_test_() ->
    {setup, fun load_client/0, fun unload_client/1,
        [fun canonical_commands_case/0, fun canonical_observations_case/0,
         fun lost_establish_reply_case/0, fun current_and_stale_headers_case/0,
         fun inspection_scope_case/0]}.

%% Fail on any source warning before exercising the platform-only client.
-spec load_client() -> ok.
load_client() ->
    Source = "platforms/xc7/application/hls_domain_board_client.erl",
    {ok, hls_domain_board_client, Beam, []} = compile:file(Source,
        [binary, debug_info, warnings_as_errors, return_errors, return_warnings]),
    {module, hls_domain_board_client} = code:load_binary(hls_domain_board_client, Source, Beam),
    ok.

%% Every individual witness stops its clients before this code is retired.
-spec unload_client(ok) -> ok.
unload_client(ok) ->
    _ = code:delete(hls_domain_board_client), _ = code:purge(hls_domain_board_client), ok.

%% The platform uses native routed framing and retains all session/lifetime words.
-spec canonical_commands_case() -> ok.
canonical_commands_case() ->
    Session = 16#123456789abcdef0, Epoch = 16#23456789abcdef01,
    ?assertEqual({{0, 4}, {0, 0, 0}, <<7:32/little>>}, hls_domain_board_client:command(7, status)),
    Establish = {{0, 4}, {1, 0, 0}, <<7:32/little, Session:64/little>>},
    ?assertEqual(Establish, hls_domain_board_client:command(7, {establish, Session})),
    {Route, Header, Payload} = Establish,
    {ok, Encoded} = hls_fabric_io:encode(Route, Header, Payload),
    ?assertEqual(<<4:32/little, 3, 0, 0, 1, Payload/binary>>, Encoded),
    ?assertEqual({{0, 3}, {0, 0, 0}, <<Session:64/little, Epoch:64/little, 23:32/little, 8:32/little>>},
        hls_domain_board_client:command(8, {inspect, Session, Epoch, 23})),
    [?assertException(error, _, hls_domain_board_client:command(1, Bad)) || Bad <-
        [{establish, 0}, {establish, 1 bsl 64}, {inspect, Session, 0, 23}, {inspect, Session, Epoch, 1 bsl 32}]],
    ok.

%% Health reserves eight carrier causes; session changes cannot hide carrier/router failure.
-spec canonical_observations_case() -> ok.
canonical_observations_case() ->
    Health = 2 bor (1 bsl 3) bor (1 bsl 4) bor (1 bsl 7) bor (16#40 bsl 8) bor (1 bsl 16),
    Snapshot = hls_domain_board_client:observation({0, 4}, {128, 0, 0}, board(7, 0, 12, 12, Health)),
    ?assertMatch(#{kind := board, status := ok, role := 2, domain_session := 12,
        endpoint_session := 12, incarnation := 16#123456789abcdef0,
        health := #{domain_attached := true, endpoint_attached := true,
            carrier_fault := 16#40, router_fault := true, carrier_armed := true}}, Snapshot),
    ?assertException(error, _, hls_domain_board_client:observation({0, 4}, {128, 0, 0},
        board(7, 0, 12, 12, 1 bsl 17))),
    ?assertException(error, _, hls_domain_board_client:observation({4, 0}, {128, 0, 0}, board(7, 0, 12, 12, 0))),
    ?assertException(error, _, hls_domain_board_client:observation({0, 4}, {128, 1, 0}, board(7, 0, 12, 12, 0))),
    Value = <<1:32/little, 2:32/little, 3:32/little, 4:32/little>>,
    ?assertMatch(#{kind := inspection, status := ok, session := 9, incarnation := 10, actor := 23, value := Value},
        hls_domain_board_client:observation({0, 3}, {128, 0, 0}, inspection(7, 0, 9, 10, 23, Value))),
    ?assertMatch(#{status := unsupported, value := <<0:128>>},
        hls_domain_board_client:observation({0, 3}, {128, 0, 0}, inspection(7, 5, 9, 10, 23, <<0:128>>))),
    ?assertException(error, _, hls_domain_board_client:observation({0, 3}, {128, 0, 0},
        inspection(7, 5, 9, 10, 23, Value))),
    ok.

%% A lost session response requires fresh status and never retransmits the original mutation.
-spec lost_establish_reply_case() -> ok.
lost_establish_reply_case() ->
    with_client(30, fun(Client, Broker) ->
        Request = gen_server:send_request(Client, {establish, 9}),
        ?assertEqual({{0, 4}, {1, 0, 0}, <<101:32/little, 9:64/little>>}, sent(Broker)),
        ?assertEqual({reply, {error, {outcome_unknown, 9}}}, gen_server:receive_response(Request, 1000)),
        ?assertEqual({error, {outcome_unknown, 9}}, hls_domain_board_client:establish(Client, 10)),
        Inspect = gen_server:send_request(Client, status),
        ?assertEqual({{0, 4}, {0, 0, 0}, <<102:32/little>>}, sent(Broker)),
        deliver(Client, {0, 4}, {128, 0, 0}, board(101, 0, 9, 9, 24)),
        deliver(Client, {0, 4}, {128, 0, 0}, board(102, 0, 9, 9, 24)),
        ?assertMatch({reply, {ok, #{domain_session := 9, endpoint_session := 9}}},
            gen_server:receive_response(Inspect, 1000)),
        Next = gen_server:send_request(Client, {establish, 10}),
        ?assertEqual({{0, 4}, {1, 0, 0}, <<103:32/little, 10:64/little>>}, sent(Broker)),
        deliver(Client, {0, 4}, {128, 0, 0}, board(103, 0, 10, 10, 24)),
        ?assertMatch({reply, {ok, #{status := ok}}}, gen_server:receive_response(Next, 1000))
    end).

%% Old replies are discarded before header validation, while current malformed evidence stops the client.
-spec current_and_stale_headers_case() -> ok.
current_and_stale_headers_case() ->
    with_client(200, fun(Client, Broker) ->
        Request = gen_server:send_request(Client, status), _ = sent(Broker),
        deliver(Client, {0, 4}, {0, 7, 9}, board(100, 0, 9, 9, 24)),
        deliver(Client, {0, 4}, {128, 0, 0}, board(101, 0, 9, 9, 24)),
        ?assertMatch({reply, {ok, _}}, gen_server:receive_response(Request, 1000)),
        Monitor = monitor(process, Client),
        _ = gen_server:send_request(Client, status), _ = sent(Broker),
        Receipt = deliver(Client, {0, 4}, {128, 0, 1}, board(102, 0, 9, 9, 24)),
        receive {'DOWN', Monitor, process, Client, {invalid_board_frame, _}} -> ok
        after 1000 -> error(current_invalid_header_accepted) end,
        receive {ack, Broker, Receipt} -> ok after 1000 -> error(receipt_not_released) end
    end).

%% A scoped inspection response cannot be substituted from another native incarnation.
-spec inspection_scope_case() -> ok.
inspection_scope_case() ->
    with_client(200, fun(Client, Broker) ->
        Request = gen_server:send_request(Client, {inspect, 9, 10, 23}), _ = sent(Broker),
        deliver(Client, {0, 3}, {128, 0, 0}, inspection(101, 5, 9, 10, 23, <<0:128>>)),
        ?assertMatch({reply, {ok, #{status := unsupported}}}, gen_server:receive_response(Request, 1000)),
        Monitor = monitor(process, Client),
        _ = gen_server:send_request(Client, {inspect, 9, 10, 23}), _ = sent(Broker),
        deliver(Client, {0, 3}, {128, 0, 0}, inspection(102, 0, 9, 11, 23, <<0:128>>)),
        receive {'DOWN', Monitor, process, Client, {invalid_board_frame, _}} -> ok
        after 1000 -> error(wrong_inspection_scope_accepted) end
    end).

%% Independent tests share only the public broker route/send/receipt contract.
-spec with_client(pos_integer(), fun((pid(), pid()) -> term())) -> ok.
with_client(Timeout, Fun) ->
    Parent = self(), Broker = spawn(fun() -> broker(Parent) end),
    {ok, Client} = hls_domain_board_client:start_link(Broker, #{first_request => 101, timeout_ms => Timeout}),
    unlink(Client),
    try Fun(Client, Broker), ok
    after catch hls_domain_board_client:stop(Client), exit(Broker, kill), flush(Broker) end.

%% Physical writes succeed immediately; the test controls each separate device response.
-spec broker(pid()) -> ok.
broker(Parent) -> receive
    {'$gen_call', From, {register_route, Route, _}} when Route =:= {0, 3}; Route =:= {0, 4} ->
        gen_server:reply(From, ok), broker(Parent);
    {'$gen_call', From, {send, Route, Header, Payload, _}} ->
        gen_server:reply(From, ok), Parent ! {sent, self(), Route, Header, Payload}, broker(Parent);
    {'$gen_cast', {ack, _, Receipt}} -> Parent ! {ack, self(), Receipt}, broker(Parent)
end.

%% Each test inspects complete payload bytes before returning any response.
-spec sent(pid()) -> {hls_fabric:route(), hls_fabric:header(), binary()}.
sent(Broker) -> receive {sent, Broker, Route, Header, Payload} -> {Route, Header, Payload}
    after 1000 -> error(no_board_control_packet) end.

%% Device responses take the ordinary broker callback and receipt-release path.
-spec deliver(pid(), hls_fabric:route(), hls_fabric:header(), binary()) -> reference().
deliver(Client, Route, Header, Payload) ->
    Receipt = make_ref(), gen_server:cast(Client, {'$hls_fabric_frame', Receipt, Route, Header, Payload}), Receipt.

%% Canonical route-four observations retain all identity words even on error responses.
-spec board(non_neg_integer(), 0..5, non_neg_integer(), non_neg_integer(), non_neg_integer()) -> binary().
board(Request, Status, Domain, Endpoint, Health) ->
    <<Request:32/little, Status:32/little, 1:32/little, 2:32/little,
        Domain:64/little, Endpoint:64/little, 16#123456789abcdef0:64/little, Health:32/little>>.

%% The sparse inspector returns its exact requested scope and four untouched words.
-spec inspection(non_neg_integer(), 0..5, non_neg_integer(), non_neg_integer(), non_neg_integer(), binary()) -> binary().
inspection(Request, Status, Session, Epoch, Actor, Value) ->
    <<Request:32/little, Status:32/little, Session:64/little, Epoch:64/little, Actor:32/little, Value/binary>>.

%% Retire only this isolated broker's diagnostic messages.
-spec flush(pid()) -> ok.
flush(Broker) -> receive {sent, Broker, _, _, _} -> flush(Broker); {ack, Broker, _} -> flush(Broker)
    after 0 -> ok end.
