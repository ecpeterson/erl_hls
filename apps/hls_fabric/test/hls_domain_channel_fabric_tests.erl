-module(hls_domain_channel_fabric_tests).
-include_lib("eunit/include/eunit.hrl").

%% Independent wire constants catch width, order and canonical-encoding errors.
-spec wire_exact_widths_test() -> ok.
wire_exact_widths_test() ->
    I = interface(),
    ?assertEqual({1, <<41:64/little, 7:32/little, 0:32/little, 2:64/little, 10:64/little, 20:64/little>>},
        hls_domain_channel_wire:command(41, 7, 0, {bind, 2, 10, 20}, I)),
    ?assertMatch(#{snapshot := #{generation := 3, active := true, source_incarnation := 10}},
        hls_domain_channel_wire:observation(snapshot(7, 0, 3, true, false), I)),
    ?assertError(function_clause, hls_domain_channel_wire:command(1 bsl 64, 1, 0, inspect, I)),
    ?assertError(function_clause, hls_domain_channel_wire:command(41, 1 bsl 32, 0, inspect, I)),
    ?assertException(error, _, hls_domain_channel_wire:command(41, 1, 0, {bind, 1 bsl 64, 10, 20}, I)),
    ?assertException(error, _, hls_domain_channel_wire:command(41, 1, 0, {fence, -1}, I)),
    ?assertError(function_clause, hls_domain_channel_wire:observation(<<>>, I)).

%% Stable child specifications use normal local OTP registration, without a new registry process.
-spec registered_adapter_name_test() -> ok.
registered_adapter_name_test() ->
    Parent = self(),
    Broker = spawn(fun() -> broker(Parent) end),
    Name = hls_channel_adapter_registration_fixture,
    {ok, Backend} = hls_domain_channel_fabric:start_link(#{management => Broker, session => 41}, interface(),
        #{name => Name, management_timeout_ms => 100}),
    unlink(Backend),
    try ?assertEqual(Backend, whereis(Name))
    after catch hls_domain_channel_fabric:stop(Backend), Broker ! stop end.

%% A timed-out bind retains exact intent; ordered inspection confirms it without a second bind.
-spec lost_bind_reply_reconciles_test() -> ok.
lost_bind_reply_reconciles_test() ->
    with_backend(20, fun(B, M) ->
        {ok, Authority} = hls_domain_channel_fabric:attach(B, 0, self()),
        Request = hls_domain_channel_fabric:send_request(B, {request, Authority, 0, {bind, 0, 10, 20}}),
        {1, 0, _, _} = sent(M),
        ?assertEqual({reply, {error, {outcome_unknown, {bind, 0, 10, 20}}}}, gen_server:receive_response(Request, 1000)),
        ?assertEqual({error, {outcome_unknown, {bind, 0, 10, 20}}},
            hls_domain_channel_fabric:request(B, Authority, 0, {bind, 0, 10, 20})),
        Inspect = hls_domain_channel_fabric:send_request(B, {status, 0}),
        {0, 0, Sequence, _} = sent(M),
        deliver(B, snapshot(Sequence, 0, 1, true, false)),
        ?assertMatch({reply, {ok, #{generation := 1, active := true}}}, gen_server:receive_response(Inspect, 1000)),
        ?assertMatch(#{uncertain := Unknown} when map_size(Unknown) =:= 0, hls_domain_channel_fabric:info(B)),
        no_packet(M)
    end).

%% A dead owner cannot be replaced before its transmitted bind is inspected and fenced.
-spec owner_loss_during_bind_test() -> ok.
owner_loss_during_bind_test() ->
    with_backend(100, fun(B, M) ->
        Parent = self(),
        Owner = spawn(fun() ->
            {ok, Cap} = hls_domain_channel_fabric:attach(B, 0, self()),
            _ = hls_domain_channel_fabric:send_request(B, {request, Cap, 0, {bind, 0, 10, 20}}),
            Parent ! {submitted, self()}, receive stop -> ok end
        end),
        receive {submitted, Owner} -> ok after 1000 -> error(no_submission) end,
        {1, 0, Bind, _} = sent(M),
        exit(Owner, kill),
        deliver(B, snapshot(Bind, 0, 1, true, false)),
        {0, 0, Inspect, _} = sent(M),
        ?assertEqual({error, retiring}, hls_domain_channel_fabric:attach(B, 0, self())),
        deliver(B, snapshot(Inspect, 0, 1, true, false)),
        {2, 0, Fence, <<1:64/little>>} = sent(M),
        deliver(B, snapshot(Fence, 0, 1, false, false)),
        _ = hls_domain_channel_fabric:info(B),
        ?assertMatch({ok, _}, hls_domain_channel_fabric:attach(B, 0, self()))
    end).

%% A missing retirement reply cannot starve a different channel or another retirement obligation.
-spec fair_retirement_test() -> ok.
fair_retirement_test() ->
    with_backend(20, fun(B, M) ->
        Parent = self(),
        Owner = spawn(fun() ->
            {ok, _} = hls_domain_channel_fabric:attach(B, 0, self()),
            {ok, _} = hls_domain_channel_fabric:attach(B, 1, self()),
            Parent ! {owned, self()}, receive stop -> ok end
        end),
        receive {owned, Owner} -> ok after 1000 -> error(no_owner) end,
        exit(Owner, kill),
        {0, 0, _, _} = sent(M),
        ReadOther = hls_domain_channel_fabric:send_request(B, {status, 2}),
        {0, 2, Other, _} = sent(M),
        deliver(B, snapshot(Other, 2, 0, false, false)),
        ?assertMatch({reply, {ok, _}}, gen_server:receive_response(ReadOther, 1000)),
        {0, 1, RetireOther, _} = sent(M),
        deliver(B, snapshot(RetireOther, 1, 0, false, true)),
        {0, 0, _, _} = sent(M),
        ok
    end).

%% A lost fence response is followed by inspection, not an automatic duplicate fence command.
-spec uncertain_retirement_fence_is_inspected_test() -> ok.
uncertain_retirement_fence_is_inspected_test() ->
    with_backend(20, fun(B, M) ->
        Parent = self(),
        Owner = spawn(fun() ->
            {ok, _} = hls_domain_channel_fabric:attach(B, 0, self()),
            Parent ! {owned, self()}, receive stop -> ok end
        end),
        receive {owned, Owner} -> ok after 1000 -> error(no_owner) end,
        exit(Owner, kill),
        {0, 0, Inspect, _} = sent(M),
        deliver(B, snapshot(Inspect, 0, 1, true, false)),
        {2, 0, _, _} = sent(M),
        {0, 0, Reconcile, _} = sent(M),
        deliver(B, snapshot(Reconcile, 0, 1, false, false)),
        no_packet(M)
    end).

%% Actual caller identity matters even when a capability is leaked to another process.
-spec authority_and_invalid_command_test() -> ok.
authority_and_invalid_command_test() ->
    with_backend(100, fun(B, M) ->
        {ok, Cap} = hls_domain_channel_fabric:attach(B, 0, self()),
        Parent = self(),
        spawn(fun() -> Parent ! {stranger, hls_domain_channel_fabric:request(B, Cap, 0, {fence, 0})} end),
        receive {stranger, Reply} -> ?assertEqual({error, unauthorized}, Reply) after 1000 -> error(no_reply) end,
        ?assertMatch({error, _}, hls_domain_channel_fabric:request(B, Cap, 0, {bind, 0, 1 bsl 64, 1})),
        ?assert(is_process_alive(B)),
        no_packet(M)
    end).

%% Every test owns isolated routing and timers, with no physical-device claim.
-spec with_backend(pos_integer(), fun((pid(), pid()) -> term())) -> ok.
with_backend(Timeout, Fun) ->
    Parent = self(),
    Broker = spawn(fun() -> broker(Parent) end),
    {ok, Backend} = hls_domain_channel_fabric:start_link(#{management => Broker, session => 41}, interface(), #{management_timeout_ms => Timeout}),
    unlink(Backend),
    try Fun(Backend, Broker), ok
    after catch hls_domain_channel_fabric:stop(Backend), Broker ! stop, flush(Broker) end.

%% This fixture models the public broker framing interface, not the channel kernel.
-spec broker(pid()) -> ok.
broker(Parent) ->
    receive
        {'$gen_call', From, {register_route, _, _}} -> gen_server:reply(From, ok), broker(Parent);
        {'$gen_call', From, {send, _, {Tag, 0, 0}, Payload, _}} ->
            Parent ! {wire, self(), Tag, Payload}, gen_server:reply(From, ok), broker(Parent);
        {'$gen_cast', {ack, _, _}} -> broker(Parent);
        stop -> ok
    end.

%% Receive exactly the next command so accidental duplicate mutations cannot hide in a mailbox.
-spec sent(pid()) -> {byte(), non_neg_integer(), pos_integer(), binary()}.
sent(Broker) ->
    receive {wire, Broker, Tag, <<41:64/little, Request:32/little, Channel:32/little, Tail/binary>>} ->
        {Tag, Channel, Request, Tail}
    after 1000 -> error(no_packet) end.

%% Test replies enter the same public broker-delivery path as production frames.
-spec deliver(pid(), binary()) -> ok.
deliver(Backend, Payload) ->
    gen_server:cast(Backend, {'$hls_fabric_frame', make_ref(), {0, 0}, {1, 0, 0}, Payload}).

%% Known fixture codes intentionally avoid production packing helpers.
-spec snapshot(pos_integer(), non_neg_integer(), non_neg_integer(), boolean(), boolean()) -> binary().
snapshot(Request, Channel, Generation, Active, Fault) ->
    A = case Active of true -> 1; false -> 0 end,
    F = case Fault of true -> 1; false -> 0 end,
    <<41:64/little, Request:32/little, Channel:32/little, 0:32/little, Generation:64/little,
      10:64/little, 20:64/little, 0:32/little, A:32/little, F:32/little>>.

%% Retained source enum metadata is sufficient without any compiler dependency.
-spec interface() -> hls_domain_channel_wire:interface().
interface() ->
    #{kind => domain_channel_management, management_route => {0, 0}, channels => [0, 1, 2],
      codecs => #{status => {hls_type, hls_enum, enum, [[ok, accepted, stale, invalid, busy, closed, exhausted]]}}}.

%% A quiet interval is a finite absence witness, not a delivery guarantee.
-spec no_packet(pid()) -> ok.
no_packet(Broker) -> receive {wire, Broker, Tag, _} -> error({unexpected_packet, Tag}) after 10 -> ok end.

%% Remove only fixture output; unrelated test messages remain visible.
-spec flush(pid()) -> ok.
flush(Broker) -> receive {wire, Broker, _, _} -> flush(Broker) after 0 -> ok end.
