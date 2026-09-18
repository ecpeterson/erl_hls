-module(hls_deferred_tests).
-include_lib("eunit/include/eunit.hrl").

%% Calls survive intervening casts; continuation completion precedes a later read.
-spec bounded_drain_test() -> ok.
bounded_drain_test() ->
    with_server(fun(Pid) ->
        A = gen_server:send_request(Pid, {wait, 11}),
        B = gen_server:send_request(Pid, {wait, 22}),
        ?assertEqual({error, {remote_error, busy}}, gen_server:call(Pid, {wait, 33})),
        ?assertEqual(timeout, gen_server:wait_response(A, 0)),
        gen_server:cast(Pid, {release, 0}),
        Read = gen_server:send_request(Pid, {read, 0}),
        ?assertEqual({reply, {report, 11}}, gen_server:receive_response(A, 1000)),
        ?assertEqual({reply, {report, 22}}, gen_server:receive_response(B, 1000)),
        ?assertEqual({reply, {report, 33}}, gen_server:receive_response(Read, 1000))
    end).

%% Finishing a handle cannot make a later caller vulnerable to the old handle.
-spec stale_handle_test() -> ok.
stale_handle_test() ->
    with_server(fun(Pid) ->
        Old = gen_server:send_request(Pid, {wait, 7}),
        gen_server:cast(Pid, {release, 0}),
        ?assertEqual({reply, {report, 7}}, gen_server:receive_response(Old, 1000)),
        New = gen_server:send_request(Pid, {wait, 9}),
        gen_server:cast(Pid, {duplicate, 0}),
        ?assertEqual({report, 7}, gen_server:call(Pid, {read, 0})),
        ?assertEqual(timeout, gen_server:wait_response(New, 0)),
        gen_server:cast(Pid, {release, 0}),
        ?assertEqual({reply, {report, 9}}, gen_server:receive_response(New, 1000))
    end).

%% Abandonment retires caller interest; service reply ownership lasts until completion.
-spec abandoned_call_test() -> ok.
abandoned_call_test() ->
    with_server(fun(Pid) ->
        A = gen_server:send_request(Pid, {wait, 1}),
        ?assertEqual(timeout, gen_server:receive_response(A, 0)),
        B = gen_server:send_request(Pid, {wait, 2}),
        ?assertEqual({error, {remote_error, busy}}, gen_server:call(Pid, {read, 0})),
        gen_server:cast(Pid, {release, 0}),
        ?assertEqual({reply, {report, 2}}, gen_server:receive_response(B, 1000)),
        ?assertEqual({report, 3}, gen_server:call(Pid, {read, 0})),
        receive Unexpected -> error({late_reply, Unexpected}) after 0 -> ok end
    end).

%% Actual callback failure releases all ERTS request monitors, including retained calls.
-spec callback_failure_test() -> ok.
callback_failure_test() ->
    with_server(fun(Pid) ->
        unlink(Pid),
        A = gen_server:send_request(Pid, {wait, 1}),
        B = gen_server:send_request(Pid, {wait, 2}),
        gen_server:cast(Pid, {explode, 1}),
        ?assertMatch({error, {_, Pid}}, gen_server:receive_response(A, 1000)),
        ?assertMatch({error, {_, Pid}}, gen_server:receive_response(B, 1000))
    end).

%% Compile the exact fixture exercised by CPU tests, with all native source annotations.
-spec lowering_test() -> ok.
lowering_test() ->
    X = iolist_to_binary(xls_parse:to_xls("test/hls_deferred_fixture.erl")),
    ?assertNotEqual(nomatch, binary:match(X, <<"hls_server::Driver">>)),
    ?assertNotEqual(nomatch, binary:match(X, <<"reply_allowed">>)),
    ok.

%% Keep actor shutdown local even in deliberately failing fixtures.
-spec with_server(fun((pid()) -> term())) -> ok.
with_server(Fun) ->
    {ok, Pid} = hls_gs:start_link(hls_deferred_fixture, []),
    try Fun(Pid), ok after catch hls_gs:stop(Pid) end.

%% Reject invalid resource declarations before either adapter starts executing callbacks.
-spec declaration_bounds_test() -> ok.
declaration_bounds_test() ->
    {ok, Forms} = xls_parse:parse_file("test/hls_deferred_fixture.erl"),
    [?assertError(invalid_hls_pending_calls,
        hls_service_contract:from_forms(attribute(Forms, hls_pending_calls, N))) || N <- [0, 256, bad]],
    [?assertError({invalid_hls_continuations, Names},
        hls_service_contract:from_forms(attribute(Forms, hls_continuations, Names)))
        || Names <- [[drain, drain], [none], [true], [42], bad]],
    Missing = [F || F <- Forms, not (element(1,F) =:= attribute andalso element(3,F) =:= hls_pending_calls)],
    ?assertError(invalid_hls_pending_calls, hls_service_contract:from_forms(Missing)),
    Two = {function, 1, handle_call, 2, [{clause, 1, [{var,1,'R'}, {var,1,'S'}], [], [{atom,1,ok}]}]},
    ?assertError(invalid_hls_pending_calls, hls_service_contract:from_forms([Two | Forms])),
    ok.

%% A handle counter at its limit fails instead of silently reusing the first activation handle.
-spec handle_exhaustion_test() -> ok.
handle_exhaustion_test() ->
    {ok, Contract} = hls_service_contract:from_module(hls_deferred_fixture),
    Pending = (hls_gs_deferred:new(Contract))#{next := 1 bsl 56},
    ?assertError(reply_handle_exhausted,
        hls_gs_deferred:dispatch(call, hls_deferred_fixture, {wait, 1},
            {{self(), make_ref()}, [report]}, hls_deferred_fixture:init([]), Pending)).

%% Mutate one fixture declaration while preserving its record/callback syntax.
-spec attribute([hls_source:form()], atom(), term()) -> [hls_source:form()].
attribute(Forms, Name, Value) ->
    [case F of {attribute, L, Name, _} -> {attribute, L, Name, Value}; _ -> F end || F <- Forms].
