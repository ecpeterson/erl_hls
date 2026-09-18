-module(hls_retained_calls_tests).
-moduledoc "The same retained-caller contract exercised through server and state-machine callbacks.".
-include_lib("eunit/include/eunit.hrl").

%% Both behaviours must preserve ownership independently of callback vocabulary.
-spec retained_protocol_test_() -> [term()].
retained_protocol_test_() ->
    [{atom_to_list(Kind) ++ " " ++ atom_to_list(Name), fun() -> with_server(Kind, Test) end}
        || Kind <- [server, statem], {Name, Test} <- [
            {drain, fun drain/1}, {stale, fun stale/1},
            {abandon, fun abandon/1}, {failure, fun failure/1}]].

%% Later inspection cannot overtake the internal drain; fullness cannot block its release cast.
-spec drain(pid()) -> ok.
drain(Pid) ->
    A = gen_server:send_request(Pid, {wait, 11}),
    B = gen_server:send_request(Pid, {wait, 22}),
    ?assertEqual({error, {remote_error, busy}}, gen_server:call(Pid, {wait, 33})),
    ?assertEqual(timeout, gen_server:wait_response(A, 0)),
    gen_server:cast(Pid, {release, 0}),
    C = gen_server:send_request(Pid, {read, 0}),
    ?assertEqual({reply, {report, 11}}, gen_server:receive_response(A, 1000)),
    ?assertEqual({reply, {report, 22}}, gen_server:receive_response(B, 1000)),
    ?assertEqual({reply, {report, 33}}, gen_server:receive_response(C, 1000)).

%% Completing a saved handle twice cannot complete the newer caller in its former slot.
-spec stale(pid()) -> ok.
stale(Pid) ->
    A = gen_server:send_request(Pid, {wait, 7}),
    gen_server:cast(Pid, {release, 0}),
    ?assertEqual({reply, {report, 7}}, gen_server:receive_response(A, 1000)),
    B = gen_server:send_request(Pid, {wait, 9}),
    gen_server:cast(Pid, {duplicate, 0}),
    ?assertEqual({report, 7}, gen_server:call(Pid, {read, 0})),
    ?assertEqual(timeout, gen_server:wait_response(B, 0)),
    gen_server:cast(Pid, {release, 0}),
    ?assertEqual({reply, {report, 9}}, gen_server:receive_response(B, 1000)).

%% Caller abandonment closes its alias; service ownership still retires on completion.
-spec abandon(pid()) -> ok.
abandon(Pid) ->
    A = gen_server:send_request(Pid, {wait, 1}),
    ?assertEqual(timeout, gen_server:receive_response(A, 0)),
    B = gen_server:send_request(Pid, {wait, 2}),
    ?assertEqual({error, {remote_error, busy}}, gen_server:call(Pid, {read, 0})),
    gen_server:cast(Pid, {release, 0}),
    ?assertEqual({reply, {report, 2}}, gen_server:receive_response(B, 1000)),
    ?assertEqual({report, 3}, gen_server:call(Pid, {read, 0})),
    receive Message -> error({unexpected_late_reply, Message}) after 0 -> ok end.

%% ERTS monitors notify every waiting caller when the callback violates its reply contract.
-spec failure(pid()) -> ok.
failure(Pid) ->
    unlink(Pid),
    A = gen_server:send_request(Pid, {wait, 1}),
    B = gen_server:send_request(Pid, {wait, 2}),
    gen_server:cast(Pid, {explode, 1}),
    ?assertMatch({error, {_, Pid}}, gen_server:receive_response(A, 1000)),
    ?assertMatch({error, {_, Pid}}, gen_server:receive_response(B, 1000)).

%% Keep intentional callback failures isolated from the EUnit owner.
-spec with_server(server | statem, fun((pid()) -> term())) -> ok.
with_server(Kind, Test) ->
    {ok, Pid} = case Kind of
        server -> hls_gs:start_link(hls_deferred_fixture, []);
        statem -> hls_statem:start_link(hls_statem_reply_fixture, [],
            [{mailbox_capacity, 4}, {outputs, #{reply => self()}}])
    end,
    try Test(Pid), ok after catch gen_server:stop(Pid) end.

%% Completion of a reduction must preserve a caller across phase and internal-event boundaries.
-spec reduction_retains_caller_test() -> ok.
reduction_retains_caller_test() ->
    {ok, Pid} = hls_statem:start_link(hls_statem_reduction_reply_fixture, [],
        [{mailbox_capacity, 4}, {outputs, #{reply => self()}}]),
    try
        Request = gen_server:send_request(Pid, {run, 0}),
        hls_statem:cast(Pid, {value, 11}),
        hls_statem:cast(Pid, {value, 22}),
        #{phase := ready} = hls_statem:info(Pid),
        ?assertEqual(timeout, gen_server:wait_response(Request, 0)),
        hls_statem:cast(Pid, {release, 0}),
        ?assertEqual({reply, {result, 33}}, gen_server:receive_response(Request, 1000))
    after hls_statem:stop(Pid) end.
