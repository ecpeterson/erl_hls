-module(hls_domain_endpoint_fabric_tests).
-moduledoc "Finite broker-interface witnesses for the shared management adapter's independent-endpoint mode. Tests retain exact mutation identity and ordered observations; they do not establish device reset, distributed ownership or remote progress.".
-include_lib("eunit/include/eunit.hrl").
-include("hls_domain_channel_endpoints.hrl").

%% A lost bind keeps its complete identity until a later ordered status response.
-spec lost_reply_reconciles_test() -> ok.
lost_reply_reconciles_test() ->
    with_backend(30, fun(Backend, Broker) ->
        Binding = binding(),
        {ok, Cap} = hls_domain_channel_fabric:attach(Backend, 8, self()),
        Request = hls_domain_channel_fabric:send_request(Backend, {request, Cap, 8, {bind, Binding}}),
        {1, 8, BindSequence, Tail} = sent(Broker),
        ?assertEqual(packed(Binding), Tail),
        ?assertEqual({reply, {error, {outcome_unknown, {bind, Binding}}}},
            gen_server:receive_response(Request, 1000)),
        ?assertMatch(#{uncertain := #{8 := {bind, Binding}}}, hls_domain_channel_fabric:info(Backend)),
        ?assertEqual({error, {outcome_unknown, {bind, Binding}}},
            hls_domain_channel_fabric:request(Backend, Cap, 8, {fence, Binding})),
        Inspect = hls_domain_channel_fabric:send_request(Backend, {status, 8}),
        {0, 8, Sequence, <<>>} = sent(Broker),
        _ = deliver(Backend, {129, 0, 0}, reply(41, BindSequence, 8, Binding, 5, true, false)),
        _ = deliver(Backend, {129, 0, 0}, reply(41, Sequence, 8, Binding, 5, true, false)),
        ?assertMatch({reply, {ok, #{kind := tx, binding := Binding, active := true}}},
            gen_server:receive_response(Inspect, 1000)),
        ?assertMatch(#{uncertain := Unknown, ignored := 1} when map_size(Unknown) =:= 0,
            hls_domain_channel_fabric:info(Backend)),
        no_packet(Broker)
    end).

%% Owner loss reconciles a transmitted bind, fences the exact observation, then inspects a lost fence.
-spec owner_death_exact_fence_test() -> ok.
owner_death_exact_fence_test() ->
    with_backend(100, fun(Backend, Broker) ->
        Binding = binding(), Parent = self(),
        Owner = spawn(fun() ->
            {ok, Cap} = hls_domain_channel_fabric:attach(Backend, 61, self()),
            _ = hls_domain_channel_fabric:send_request(Backend, {request, Cap, 61, {bind, Binding}}),
            Parent ! {submitted, self()}, receive stop -> ok end
        end),
        receive {submitted, Owner} -> ok after 1000 -> error(no_submission) end,
        {1, 61, BindSequence, _} = sent(Broker),
        exit(Owner, kill),
        await_retiring(Backend, 61, 50),
        _ = deliver(Backend, {129, 0, 0}, reply(41, BindSequence, 61, Binding, 2, true, false)),
        {0, 61, InspectSequence, <<>>} = sent(Broker),
        ?assertEqual({error, retiring}, hls_domain_channel_fabric:attach(Backend, 61, self())),
        _ = deliver(Backend, {129, 0, 0}, reply(41, InspectSequence, 61, Binding, 2, true, false)),
        {2, 61, _FenceSequence, FenceTail} = sent(Broker),
        ?assertEqual(packed(Binding), FenceTail),
        {0, 61, Reconcile, <<>>} = sent(Broker),
        ?assertMatch(#{uncertain := #{61 := {fence, Binding}}}, hls_domain_channel_fabric:info(Backend)),
        _ = deliver(Backend, {129, 0, 0}, reply(41, Reconcile, 61, Binding, 2, false, true)),
        {0, 61, RetryInspect, <<>>} = sent(Broker),
        ?assertEqual({error, retiring}, hls_domain_channel_fabric:attach(Backend, 61, self())),
        _ = deliver(Backend, {129, 0, 0}, reply(41, RetryInspect, 61, Binding, 2, false, false)),
        ?assertMatch({ok, _}, hls_domain_channel_fabric:attach(Backend, 61, self())),
        no_packet(Broker)
    end).

%% The actual owner and exact capability are both required; endpoint mode rejects channel commands.
-spec capability_and_command_test() -> ok.
capability_and_command_test() ->
    with_backend(200, fun(Backend, Broker) ->
        Binding = binding(),
        ?assertEqual({error, unknown_channel}, hls_domain_channel_fabric:attach(Backend, 0, self())),
        {ok, Cap} = hls_domain_channel_fabric:attach(Backend, 8, self()),
        Parent = self(),
        spawn(fun() -> Parent ! {stranger,
            hls_domain_channel_fabric:request(Backend, Cap, 8, {fence, Binding})} end),
        receive {stranger, Reply} -> ?assertEqual({error, unauthorized}, Reply)
        after 1000 -> error(no_stranger_reply) end,
        ?assertEqual({error, unauthorized}, hls_domain_channel_fabric:request(Backend, make_ref(), 8, inspect)),
        [begin
            ?assertEqual({error, invalid}, hls_domain_channel_fabric:request(Backend, Cap, 8, Bad))
        end || Bad <- [{bind, 0, 10, 20}, {fence, 1}, {bind, #endpoint_binding{}},
            {fence, Binding#endpoint_binding{namespace = 1 bsl 64}},
            {bind, Binding#endpoint_binding{source_incarnation = -1}}]],
        no_packet(Broker)
    end).

%% Stale-session evidence is discarded before validating current-session header fields.
-spec stale_session_and_sequence_test() -> ok.
stale_session_and_sequence_test() ->
    with_backend(200, fun(Backend, Broker) ->
        Request = hls_domain_channel_fabric:send_request(Backend, {status, 8}),
        {0, 8, Sequence, <<>>} = sent(Broker),
        _ = deliver(Backend, {1, 9, 7}, reply(40, Sequence, 8, binding(), 0, true, false)),
        _ = deliver(Backend, {129, 0, 0}, reply(41, Sequence + 1, 8, binding(), 0, true, false)),
        ?assertMatch(#{ignored := 2}, hls_domain_channel_fabric:info(Backend)),
        _ = deliver(Backend, {129, 0, 0}, reply(41, Sequence, 8, binding(), 0, true, false)),
        ?assertMatch({reply, {ok, #{kind := tx}}}, gen_server:receive_response(Request, 1000))
    end).

%% Current protocol-tag or full-header mismatch stops the adapter and releases the broker receipt.
-spec wrong_header_test() -> ok.
wrong_header_test() ->
    [with_backend(200, fun(Backend, Broker) ->
        Monitor = monitor(process, Backend),
        _ = hls_domain_channel_fabric:send_request(Backend, {status, 8}),
        {0, 8, Sequence, <<>>} = sent(Broker),
        Receipt = deliver(Backend, Header, reply(41, Sequence, 8, binding(), 0, true, false)),
        stopped(Backend, Monitor),
        acknowledged(Broker, Receipt)
    end) || Header <- [{1, 0, 0}, {129, 1, 0}, {129, 0, 1}]],
    ok.

%% Ordered snapshots cannot adopt cold-reset namespaces, changed same-generation identities or regressed progress.
-spec monotonic_regression_test() -> ok.
monotonic_regression_test() ->
    Binding = (binding())#endpoint_binding{generation = 2, source_incarnation = 11, destination_incarnation = 21},
    Bad = [
        {Binding#endpoint_binding{namespace = 8}, 5},
        {Binding#endpoint_binding{generation = 1}, 5},
        {Binding#endpoint_binding{source_incarnation = 12}, 5},
        {Binding#endpoint_binding{generation = 3, source_incarnation = 11, destination_incarnation = 22}, 0},
        {Binding, 4},
        {#endpoint_binding{}, 0}
    ],
    [with_backend(200, fun(Backend, Broker) ->
        observe(Backend, Broker, Binding, 5),
        Monitor = monitor(process, Backend),
        _ = hls_domain_channel_fabric:send_request(Backend, {status, 8}),
        {0, 8, Sequence, <<>>} = sent(Broker),
        _ = deliver(Backend, {129, 0, 0}, reply(41, Sequence, 8, Regressed, PacketSequence, false, false)),
        stopped(Backend, Monitor)
    end) || {Regressed, PacketSequence} <- Bad],
    ok.

%% First observations permit only a wholly zero binding or a wholly nonzero identity.
-spec initial_and_advanced_binding_test() -> ok.
initial_and_advanced_binding_test() ->
    with_backend(200, fun(Backend, Broker) ->
        observe(Backend, Broker, #endpoint_binding{}, 0),
        observe(Backend, Broker, binding(), 5),
        observe(Backend, Broker, (binding())#endpoint_binding{generation = 2,
            source_incarnation = 11, destination_incarnation = 21}, 0)
    end),
    with_backend(200, fun(Backend, Broker) ->
        Monitor = monitor(process, Backend),
        _ = hls_domain_channel_fabric:send_request(Backend, {status, 8}),
        {0, 8, Sequence, <<>>} = sent(Broker),
        Partial = #endpoint_binding{namespace = 7},
        _ = deliver(Backend, {129, 0, 0}, reply(41, Sequence, 8, Partial, 0, false, false)),
        stopped(Backend, Monitor)
    end).

%% The existing ETF input boundary chooses endpoint mode from retained kind metadata.
-spec retained_interface_file_test() -> ok.
retained_interface_file_test() ->
    Path = filename:join("_build", "endpoint-fabric-" ++ integer_to_list(erlang:unique_integer([positive])) ++ ".etf"),
    ok = filelib:ensure_dir(Path),
    ok = file:write_file(Path, term_to_binary(interface()), [exclusive]),
    try with_backend(Path, 200, fun(Backend, Broker) -> observe(Backend, Broker, binding(), 0) end)
    after ok = file:delete(Path) end.

%% One successful ordered inspection is the baseline for regression checks.
-spec observe(pid(), pid(), #endpoint_binding{}, hls_nums:u32()) -> ok.
observe(Backend, Broker, Binding, PacketSequence) ->
    Request = hls_domain_channel_fabric:send_request(Backend, {status, 8}),
    {0, 8, Sequence, <<>>} = sent(Broker),
    _ = deliver(Backend, {129, 0, 0}, reply(41, Sequence, 8, Binding, PacketSequence, false, false)),
    ?assertMatch({reply, {ok, #{binding := Binding}}}, gen_server:receive_response(Request, 1000)),
    ok.

%% Wait only for the local DOWN bookkeeping, never infer a device retirement from elapsed time.
-spec await_retiring(pid(), hls_nums:u32(), non_neg_integer()) -> ok.
await_retiring(_Backend, _Id, 0) -> error(no_retirement_obligation);
await_retiring(Backend, Id, Attempts) ->
    #{retiring := Retiring} = hls_domain_channel_fabric:info(Backend),
    case maps:is_key(Id, Retiring) of
        true -> ok;
        false -> timer:sleep(1), await_retiring(Backend, Id, Attempts - 1)
    end.

%% Malformed current evidence is fatal rather than an implicit device-state replacement.
-spec stopped(pid(), reference()) -> ok.
stopped(Backend, Monitor) ->
    receive {'DOWN', Monitor, process, Backend, {invalid_channel_frame, error, _}} -> ok
    after 1000 -> error(adapter_did_not_stop) end.

%% Fatal and ignored messages must still release their broker delivery ownership.
-spec acknowledged(pid(), reference()) -> ok.
acknowledged(Broker, Receipt) ->
    receive {acknowledged, Broker, Receipt} -> ok after 1000 -> error(receipt_not_released) end.

%% Each test has an isolated fake broker and finite management deadline.
-spec with_backend(pos_integer(), fun((pid(), pid()) -> term())) -> ok.
with_backend(Timeout, Fun) -> with_backend(interface(), Timeout, Fun).

%% Only trusted metadata and the existing public broker protocol are modeled here.
-spec with_backend(hls_domain_endpoint_wire:interface() | file:filename(), pos_integer(), fun((pid(), pid()) -> term())) -> ok.
with_backend(Interface, Timeout, Fun) ->
    Parent = self(), Broker = spawn(fun() -> broker(Parent) end),
    {ok, Backend} = hls_domain_channel_fabric:start_link(#{management => Broker, session => 41},
        Interface, #{management_timeout_ms => Timeout}),
    unlink(Backend),
    try Fun(Backend, Broker), ok
    after catch hls_domain_channel_fabric:stop(Backend), Broker ! stop, flush(Broker) end.

%% This fake broker reports management writes only; there is no application data path.
-spec broker(pid()) -> ok.
broker(Parent) ->
    receive
        {'$gen_call', From, {register_route, {0, 2}, _}} -> gen_server:reply(From, ok), broker(Parent);
        {'$gen_call', From, {send, {0, 2}, {Tag, 0, 0}, Payload, _}} ->
            Parent ! {wire, self(), Tag, Payload}, gen_server:reply(From, ok), broker(Parent);
        {'$gen_cast', {ack, _Owner, Receipt}} -> Parent ! {acknowledged, self(), Receipt}, broker(Parent);
        stop -> ok
    end.

%% Decode only the fixed correlation prefix; mutation tails are compared independently.
-spec sent(pid()) -> {byte(), hls_nums:u32(), pos_integer(), binary()}.
sent(Broker) ->
    receive {wire, Broker, Tag, <<41:64/little, Request:32/little, Id:32/little, Tail/binary>>} ->
        {Tag, Id, Request, Tail}
    after 1000 -> error(no_management_packet) end.

%% Replies take the production broker-delivery route with the supplied complete header.
-spec deliver(pid(), hls_fabric:header(), binary()) -> reference().
deliver(Backend, Header, Payload) ->
    Receipt = make_ref(),
    gen_server:cast(Backend, {'$hls_fabric_frame', Receipt, {0, 2}, Header, Payload}),
    Receipt.

%% Canonical response bits are independent of the production packet encoder.
-spec reply(hls_nums:u64(), hls_nums:u32(), hls_nums:u32(), #endpoint_binding{}, hls_nums:u32(), boolean(), boolean()) -> binary().
reply(Session, Request, Id, Binding, Sequence, Active, Fault) ->
    Flags = (bit(Active) bsl 8) bor (bit(Fault) bsl 9),
    Packed = packed(Binding),
    <<Session:64/little, Request:32/little, Id:32/little, Flags:32/little,
        Packed/binary, Sequence:32/little>>.

%% Full-width identity bytes catch accidental generation-only retirement commands.
-spec packed(#endpoint_binding{}) -> binary().
packed(#endpoint_binding{namespace = Namespace, generation = Generation,
        source_incarnation = Source, destination_incarnation = Destination}) ->
    <<Namespace:64/little, Generation:64/little, Source:64/little, Destination:64/little>>.

%% The fixture intentionally uses a namespace requiring more than 32 bits.
-spec binding() -> #endpoint_binding{}.
binding() -> #endpoint_binding{namespace = 16#123456789abcdef0, generation = 1,
    source_incarnation = 10, destination_incarnation = 20}.

%% Runtime descriptors suffice; deployed management never loads compiler modules.
-spec interface() -> hls_domain_endpoint_wire:interface().
interface() ->
    #{kind => domain_endpoint_management, management_route => {0, 2}, response_tag => 129,
        endpoints => [#{id => 8, kind => tx}, #{id => 61, kind => rx}],
        codecs => #{operation => {hls_type, hls_enum, enum, [[tick, bind, fence]]},
            status => {hls_type, hls_enum, enum, [[ok, accepted, stale, invalid, busy, closed, exhausted]]},
            binding => {hls_type, hls_record, endpoint_binding,
                [{Field, hls_nums:u64()} || Field <- [namespace, generation,
                    source_incarnation, destination_incarnation]]}}}.

%% Fixture flags are true one-bit values, never an alternate status codec.
-spec bit(boolean()) -> 0 | 1.
bit(false) -> 0;
bit(true) -> 1.

%% A short quiet interval detects extra queued mutations without promising transport progress.
-spec no_packet(pid()) -> ok.
no_packet(Broker) ->
    receive {wire, Broker, Tag, _} -> error({unexpected_management_packet, Tag}) after 10 -> ok end.

%% Remove only messages belonging to the isolated fixture's broker.
-spec flush(pid()) -> ok.
flush(Broker) ->
    receive
        {wire, Broker, _, _} -> flush(Broker);
        {acknowledged, Broker, _} -> flush(Broker)
    after 0 -> ok end.
