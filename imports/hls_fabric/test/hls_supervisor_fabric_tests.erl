-module(hls_supervisor_fabric_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").

%% The independently specified envelope carries full-width identities and retained enum semantics.
-spec canonical_parent_wire_test() -> ok.
canonical_parent_wire_test() ->
    I = interface(),
    ?assertEqual(I, hls_supervisor_wire:load(#{parent_stream => #{interface => I}})),
    ?assertEqual({0, <<41:64/little, 7:32/little>>}, hls_supervisor_wire:command(41, 7, none, I)),
    ?assertEqual(
        {5, <<41:64/little, 8:32/little, 9:64/little, 100:64/little, 199:64/little>>},
        hls_supervisor_wire:command(41, 8, {grant, 9, 100, 199}, I)
    ),
    ?assertEqual(
        {1,
            <<41:64/little, 9:32/little, 9:32/little, 12:64/little, 12:64/little, 12:64/little,
                0:32/little>>},
        hls_supervisor_wire:command(
            41,
            9,
            #domain_input{op = stop, expected = 12, target = 12, transition = 12},
            I
        )
    ),
    ?assertMatch(
        #{
            session := 41,
            sequence := 3,
            grant_accepted := true,
            supervisor_phase := running,
            supervisor_reason := none,
            grant_next := 101,
            output := #domain_output{state = #domain_state{phase = ready, current = 9}}
        },
        hls_supervisor_wire:observation(snapshot(3, ready, 9, true), I)
    ),
    ?assertError(function_clause, hls_supervisor_wire:observation(<<>>, I)).

%% Read-only probing precedes ownership; a live endpoint is created only after attachment.
-spec ready_candidate_probe_before_attach_test() -> ok.
ready_candidate_probe_before_attach_test() ->
    with_backend(#{}, fun(B, M) ->
        ?assertMatch(
            {ok, #{state := #domain_state{phase = ready, current = 9}, actors := A}} when
                map_size(A) =:= 0,
            status(B, M, ready, 9)
        ),
        {ok, Authority} = hls_supervisor_fabric:attach(B, self()),
        {ok, Endpoint} = hls_supervisor_fabric:endpoint(B, Authority, 9, supervisor),
        ?assertEqual({error, lifecycle_only}, gen_server:call(Endpoint, application)),
        ?assertEqual(
            {error, unauthorized}, hls_supervisor_fabric:endpoint(B, Authority, 8, supervisor)
        ),
        ?assertEqual({ok, Authority}, hls_supervisor_fabric:attach(B, self()))
    end).

%% One reserved interval is installed only after actual initialization and never repeated by polls.
-spec initializing_installs_grant_once_test() -> ok.
initializing_installs_grant_once_test() ->
    with_backend(#{grant => {100, 199}}, fun(B, M) ->
        {ok, Authority} = hls_supervisor_fabric:attach(B, self()),
        ?assertMatch(
            {ok, #{state := #domain_state{phase = initializing, current = 9}}},
            status(B, M, initializing, 9)
        ),
        {_, <<41:64/little, Grant:32/little, 9:64/little, 100:64/little, 199:64/little>>} = sent(
            M, 5
        ),
        deliver(B, 1, snapshot(Grant, initializing, 9, true)),
        ?assertMatch(
            #{grant_attempted := 9, grant_result := accepted}, hls_supervisor_fabric:info(B)
        ),
        ?assertMatch(
            {ok, #{state := #domain_state{phase = initializing}}}, status(B, M, initializing, 9)
        ),
        receive
            {wire, M, _, 5, _} -> error(grant_repeated)
        after 10 -> ok
        end,
        {ok, #{actors := #{supervisor := Endpoint}}} = status(B, M, ready, 9),
        ?assertEqual({ok, Endpoint}, hls_supervisor_fabric:endpoint(B, Authority, 9, supervisor)),
        Parent = self(),
        Stranger = spawn(fun() ->
            Parent !
                {unauthorized, self(),
                    hls_supervisor_fabric:request(B, Authority, #domain_input{
                        op = stop, expected = 9
                    })}
        end),
        receive
            {unauthorized, Stranger, Reply} -> ?assertEqual({error, unauthorized}, Reply)
        after 1000 -> error(no_authority_reply)
        end,
        receive
            {wire, M, _, 1, _} -> error(stranger_changed_hardware)
        after 10 -> ok
        end
    end).

%% A rejected preallocated grant leaves hardware initialization visible and cannot trigger fresh allocation or replay.
-spec rejected_grant_is_not_retried_test() -> ok.
rejected_grant_is_not_retried_test() ->
    with_backend(#{grant => {100, 199}}, fun(B, M) ->
        {ok, _} = hls_supervisor_fabric:attach(B, self()),
        _ = status(B, M, initializing, 9),
        {_, <<41:64/little, Q:32/little, _/binary>>} = sent(M, 5),
        deliver(B, 1, snapshot(Q, initializing, 9, false)),
        ?assertMatch(#{grant_result := rejected}, hls_supervisor_fabric:info(B)),
        _ = status(B, M, initializing, 9),
        receive
            {wire, M, _, 5, _} -> error(grant_retried)
        after 10 -> ok
        end
    end).

%% Neither another session nor an old correlation may change the currently observed lifetime.
-spec stale_observations_cannot_retire_parent_test() -> ok.
stale_observations_cannot_retire_parent_test() ->
    with_backend(#{}, fun(B, M) ->
        {ok, _} = hls_supervisor_fabric:attach(B, self()),
        {ok, #{actors := #{supervisor := Endpoint}}} = status(B, M, ready, 9),
        Monitor = monitor(process, Endpoint),
        Query = gen_server:send_request(B, status),
        {_, <<41:64/little, Q:32/little>>} = sent(M, 0),
        deliver(B, 1, <<40:64/little, 255:32/little>>),
        deliver(B, 1, snapshot(Q - 1, failed, 9, false)),
        ?assertMatch(
            #{ignored := 2, state := #domain_state{phase = ready, current = 9}},
            hls_supervisor_fabric:info(B)
        ),
        ?assertEqual(timeout, gen_server:wait_response(Query, 0)),
        deliver(B, 1, snapshot(Q, ready, 9, false)),
        ?assertMatch(
            {reply, {ok, #{actors := #{supervisor := Endpoint}}}},
            gen_server:receive_response(Query, 1000)
        ),
        receive
            {'DOWN', Monitor, process, Endpoint, Reason} -> error({false_retirement, Reason})
        after 10 -> ok
        end,
        demonitor(Monitor, [flush])
    end).

%% A lost management response retires only the host observer and does not retransmit the accepted command.
-spec timeout_is_connection_uncertainty_test() -> ok.
timeout_is_connection_uncertainty_test() ->
    with_backend(#{management_timeout_ms => 50}, fun(B, M) ->
        {ok, A} = hls_supervisor_fabric:attach(B, self()),
        {ok, #{actors := #{supervisor := Endpoint}}} = status(B, M, ready, 9),
        Monitor = monitor(process, Endpoint),
        Request = gen_server:send_request(
            B, {request, A, #domain_input{op = stop, expected = 9, target = 9, transition = 9}}
        ),
        _ = sent(M, 1),
        ?assertEqual({reply, {error, noconnection}}, gen_server:receive_response(Request, 1000)),
        receive
            {'DOWN', Monitor, process, Endpoint, noconnection} -> ok
        after 1000 -> error(no_uncertainty)
        end,
        receive
            {wire, M, _, _, _} -> error(timeout_replayed)
        after 10 -> ok
        end
    end).

%% Even malformed frame headers release their broker receipt before fail-closed uncertainty.
-spec malformed_header_closes_parent_test() -> ok.
malformed_header_closes_parent_test() ->
    with_backend(#{}, fun(B, M) ->
        {ok, _} = hls_supervisor_fabric:attach(B, self()),
        {ok, #{actors := #{supervisor := Endpoint}}} = status(B, M, ready, 9),
        Monitor = monitor(process, Endpoint),
        Receipt = make_ref(),
        gen_server:cast(
            B, {'$hls_fabric_frame', Receipt, {0, 0}, {1, 1, 0}, snapshot(99, ready, 9, false)}
        ),
        receive
            {ack, M, Receipt} -> ok
        after 1000 -> error(receipt_leaked)
        end,
        receive
            {'DOWN', Monitor, process, Endpoint, noconnection} -> ok
        after 1000 -> error(no_uncertainty)
        end
    end).

%% A stopped parent cannot become a ready endpoint merely because a previous status did so.
-spec explicit_stop_retires_observer_test() -> ok.
explicit_stop_retires_observer_test() ->
    with_backend(#{}, fun(B, M) ->
        {ok, A} = hls_supervisor_fabric:attach(B, self()),
        {ok, #{actors := #{supervisor := Endpoint}}} = status(B, M, ready, 9),
        Monitor = monitor(process, Endpoint),
        Request = gen_server:send_request(
            B, {request, A, #domain_input{op = stop, expected = 9, target = 9, transition = 9}}
        ),
        {_, <<41:64/little, Q:32/little, _/binary>>} = sent(M, 1),
        deliver(B, 1, snapshot(Q, closing, 9, false)),
        ?assertMatch(
            {reply, #domain_output{state = #domain_state{phase = closing}}},
            gen_server:receive_response(Request, 1000)
        ),
        receive
            {'DOWN', Monitor, process, Endpoint, shutdown} -> ok
        after 1000 -> error(parent_not_retired)
        end,
        ?assertMatch(
            {ok, #{state := #domain_state{phase = stopped}, actors := Actors}} when
                map_size(Actors) =:= 0,
            status(B, M, stopped, 9)
        ),
        ?assertEqual({error, unauthorized}, hls_supervisor_fabric:endpoint(B, A, 9, supervisor))
    end).

%% Every case owns an isolated broker and backend; no timed poll races an explicit exchange.
-spec with_backend(map(), fun((pid(), pid()) -> term())) -> ok.
with_backend(Options, Fun) ->
    Parent = self(),
    Broker = spawn(fun() -> broker(Parent) end),
    {ok, Backend} = hls_supervisor_fabric:start_link(
        #{management => Broker, session => 41},
        interface(),
        maps:merge(#{poll_ms => 60000, management_timeout_ms => 1000}, Options)
    ),
    unlink(Backend),
    try
        Fun(Backend, Broker),
        ok
    after
        catch hls_supervisor_fabric:stop(Backend),
        Broker ! stop,
        flush(Broker)
    end.

%% This mock models broker route ownership and physical write completion, not hardware semantics.
-spec broker(pid()) -> ok.
broker(Parent) ->
    receive
        {'$gen_call', From, {register_route, _, _}} ->
            gen_server:reply(From, ok),
            broker(Parent);
        {'$gen_call', From, {send, Route, {Tag, 0, 0}, Payload, _}} ->
            Parent ! {wire, self(), Route, Tag, Payload},
            gen_server:reply(From, ok),
            broker(Parent);
        {'$gen_cast', {ack, _Owner, Receipt}} ->
            Parent ! {ack, self(), Receipt},
            broker(Parent);
        stop ->
            ok
    end.

%% Explicit fixtures produce one complete framed observation after capturing its correlation.
-spec status(pid(), pid(), hls_domain_lifecycle:phase(), pos_integer()) -> term().
status(B, M, Phase, Epoch) ->
    Request = gen_server:send_request(B, status),
    {Route, <<41:64/little, Sequence:32/little>>} = sent(M, 0),
    {0, 0} = Route,
    deliver(B, 1, snapshot(Sequence, Phase, Epoch, false)),
    {reply, Reply} = gen_server:receive_response(Request, 1000),
    Reply.

%% A missing expected packet fails the local witness rather than inferring device progress.
-spec sent(pid(), byte()) -> {hls_fabric:route(), binary()}.
sent(Broker, Tag) ->
    receive
        {wire, Broker, Route, Tag, Payload} -> {Route, Payload}
    after 1000 -> error({missing_packet, Tag})
    end.

%% Test frames use the exact public delivery message used by real brokers.
-spec deliver(pid(), byte(), binary()) -> ok.
deliver(Backend, Tag, Payload) ->
    gen_server:cast(Backend, {'$hls_fabric_frame', make_ref(), {0, 0}, {Tag, 0, 0}, Payload}).

%% Lifecycle and supervisor codes below are intentionally independent known fixture values.
-spec snapshot(non_neg_integer(), hls_domain_lifecycle:phase(), pos_integer(), boolean()) ->
    binary().
snapshot(Sequence, Phase, Epoch, Accepted) ->
    {Code, Fault, Manager, Reason} =
        case Phase of
            ready -> {1, 0, 2, 0};
            closing -> {2, 0, 3, 1};
            initializing -> {4, 0, 0, 0};
            failed -> {5, 4, 5, 3};
            stopped -> {6, 0, 4, 1}
        end,
    A =
        case Accepted of
            true -> 1;
            false -> 0
        end,
    <<41:64/little, Sequence:32/little, 0:32/little, 0:32/little, Code:32/little, Epoch:64/little,
        0:64/little, Epoch:64/little, 0:64/little, Fault:32/little, 0:96, A:32/little,
        Manager:32/little, Reason:32/little, 101:64/little>>.

%% Retained enum order is source-independent runtime metadata.
-spec interface() -> hls_supervisor_wire:interface().
interface() ->
    #{
        kind => supervisor_management,
        management_route => {0, 0},
        codecs => maps:from_list([
            {Name, {hls_type, hls_enum, enum, [Members]}}
         || {Name, Members} <- [
                {operation, [
                    inspect,
                    activate,
                    replace,
                    fault,
                    fenced,
                    reset_done,
                    initialized,
                    abort,
                    reject,
                    stop
                ]},
                {phase, [unbound, ready, closing, isolated, initializing, failed, stopped]},
                {status, [ok, accepted, replay, stale, busy, invalid, failure, completed]},
                {action, [none, fence, reset, initialize, publish]},
                {fault, [
                    none,
                    actor_failure,
                    owner_down,
                    initialization_failure,
                    lifecycle_failure,
                    protocol_failure
                ]},
                {supervisor_phase, [unbound, starting, running, stopping, stopped, failed]},
                {supervisor_reason, [
                    none,
                    requested,
                    initialization_failure,
                    intensity_exhausted,
                    identities_exhausted,
                    clock_failure,
                    child_state_failure
                ]}
            ]
        ])
    }.

%% Remove only this fixture's late broker receipts from the EUnit process mailbox.
-spec flush(pid()) -> ok.
flush(Broker) ->
    receive
        {ack, Broker, _} -> flush(Broker);
        {wire, Broker, _, _, _} -> flush(Broker)
    after 0 -> ok
    end.
