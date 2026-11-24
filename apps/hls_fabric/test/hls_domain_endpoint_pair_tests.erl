-module(hls_domain_endpoint_pair_tests).
-moduledoc "Finite paired-management witnesses through the production shared adapter and canonical wire protocol. Fake brokers step the native endpoint kernels; owner fixtures expose status only. These tests establish neither remote progress nor physical-clock behavior.".
-include_lib("eunit/include/eunit.hrl").
-include_lib("hls_runtime/include/hls_domain_channel_endpoints.hrl").

%% RX is installed and confirmed before TX, and capability-owner death retires both.
-spec ordered_admission_and_owner_death_test() -> ok.
ordered_admission_and_owner_death_test() ->
    with_pair(#{}, fun(C) ->
        Pair = maps:get(pair, C), Binding = ready(Pair),
        ?assertEqual(binding(1, 10, 20), Binding),
        ?assertEqual([rx, tx], [Side || {Side, 1, _, _} <- events(C)]),
        ?assert(lists:member({rx, 0, Binding, ok}, events(C))),
        exit(Pair, kill),
        retired(C, tx), retired(C, rx),
        ?assertEqual([rx, tx], lists:sort([Side || {Side, 2, Binding0, accepted} <- events(C), Binding0 =:= Binding]))
    end).

%% Accepted but lost replies resolve by inspection without a second bind pulse.
-spec lost_accepted_reply_test() -> ok.
lost_accepted_reply_test() ->
    [with_pair(#{Side => drop_reply}, fun(C) ->
        Binding = ready(maps:get(pair, C)),
        ?assertEqual(binding(1, 10, 20), Binding),
        ?assertEqual(1, length(bind_events(Side, events(C)))),
        ?assertMatch([_, {Side, 0, Binding, ok} | _], after_bind(Side, events(C)))
    end) || Side <- [rx, tx]],
    ok.

%% A lost unexecuted command permits one exact retry only after ordered inspection.
-spec lost_unexecuted_reply_test() -> ok.
lost_unexecuted_reply_test() ->
    [with_pair(#{Side => drop_unexecuted}, fun(C) ->
        Binding = ready(maps:get(pair, C)),
        ?assertEqual([{Side, 1, Binding, not_executed}, {Side, 1, Binding, accepted}],
            bind_events(Side, events(C))),
        [_, Inspect | _] = after_bind(Side, events(C)),
        ?assertMatch({Side, 0, #endpoint_binding{}, closed}, Inspect)
    end) || Side <- [rx, tx]],
    ok.

%% Two unknown unexecuted binds exhaust the one-retry allowance instead of looping admission.
-spec management_retry_is_bounded_test() -> ok.
management_retry_is_bounded_test() ->
    with_pair(#{rx => drop_unexecuted_always}, fun(C) ->
        Pair = maps:get(pair, C), Monitor = monitor(process, Pair),
        receive {'DOWN', Monitor, process, Pair, _} -> ok
        after 1500 -> error(unbounded_management_retry) end,
        ?assertEqual(2, length(bind_events(rx, events(C)))),
        ?assertEqual([], bind_events(tx, events(C)))
    end).

%% A one-sided consumed generation requires both fresh incarnations and then allows a gap at TX.
-spec partial_bind_fresh_pair_test() -> ok.
partial_bind_fresh_pair_test() ->
    with_pair(#{rx => hold_reply}, fun(C) ->
        Pair = maps:get(pair, C),
        wait(fun() -> held(C, rx) end),
        ?assertEqual([], bind_events(tx, events(C))),
        exit(Pair, kill), release(C, rx),
        retired(C, rx), retired(C, tx),
        incarnation(C, tx, 11),
        {ok, Next} = start_pair(C), unlink(Next),
        try
            wait(fun() -> source_observed(C, 11) end),
            ?assertEqual(1, length(bind_events(rx, events(C)))),
            ?assertEqual([], bind_events(tx, events(C))),
            incarnation(C, rx, 21),
            ?assertEqual(binding(2, 11, 21), ready(Next)),
            ?assertEqual([binding(2, 11, 21)], [B || {tx, 1, B, accepted} <- events(C)])
        after exit(Next, kill) end
    end).

%% Fresh owner evidence after RX confirmation must still match before TX admission.
-spec domain_change_before_tx_test() -> ok.
domain_change_before_tx_test() ->
    with_pair(#{rx => hold_reply}, fun(C) ->
        Pair = maps:get(pair, C), Monitor = monitor(process, Pair),
        wait(fun() -> held(C, rx) end),
        incarnation(C, tx, 11), release(C, rx),
        receive {'DOWN', Monitor, process, Pair, _} -> ok
        after 1500 -> error(pair_adopted_changed_domain) end,
        ?assertEqual([], bind_events(tx, events(C))),
        retired(C, rx)
    end).

%% A replacement adapter PID cannot resurrect this coordinator or enable another bind.
-spec transport_loss_requires_fresh_instance_test() -> ok.
transport_loss_requires_fresh_instance_test() ->
    with_pair(#{}, fun(C) ->
        Pair = maps:get(pair, C), _ = ready(Pair),
        ok = hls_domain_channel_fabric:stop(backend(C, tx)),
        wait(fun() -> hls_domain_endpoint_pair:status(Pair) =:= {error, noconnection} end),
        retired(C, rx),
        {ok, Replacement} = adapter(tx, broker(C, tx)), unlink(Replacement),
        try
            ?assertEqual({error, noconnection}, hls_domain_endpoint_pair:status(Pair)),
            ?assertEqual(1, length(bind_events(tx, events(C)))),
            ?assertEqual(#{}, maps:get(observed, hls_domain_channel_fabric:info(Replacement)))
        after hls_domain_channel_fabric:stop(Replacement) end
    end).

%% A missing ordered read is indistinguishable from wire loss even while both local processes survive.
-spec live_adapter_read_loss_fences_peer_test() -> ok.
live_adapter_read_loss_fences_peer_test() ->
    with_pair(#{}, fun(C) ->
        Pair = maps:get(pair, C), _ = ready(Pair),
        ok = gen_server:call(broker(C, tx), {mode, drop_inspect}),
        wait(fun() -> hls_domain_endpoint_pair:status(Pair) =:= {error, noconnection} end),
        retired(C, rx),
        ?assert(is_process_alive(backend(C, tx))),
        ?assert(is_process_alive(broker(C, tx))),
        ?assertEqual({error, noconnection}, hls_domain_endpoint_pair:status(Pair)),
        ?assertEqual(1, length(bind_events(tx, events(C)))),
        ?assertEqual(1, length(bind_events(rx, events(C))))
    end).

%% Fixture lifetimes are isolated; every public request passes through a real adapter.
-spec with_pair(map(), fun((map()) -> term())) -> ok.
with_pair(Modes, Fun) ->
    Journal = spawn(fun() -> journal([]) end),
    Source = spawn(fun() -> owner(source, 10, Journal) end),
    Destination = spawn(fun() -> owner(destination, 20, Journal) end),
    TxBroker = spawn(fun() -> wire_broker(tx, 10, maps:get(tx, Modes, normal), Journal) end),
    RxBroker = spawn(fun() -> wire_broker(rx, 20, maps:get(rx, Modes, normal), Journal) end),
    {ok, Tx} = adapter(tx, TxBroker), unlink(Tx),
    {ok, Rx} = adapter(rx, RxBroker), unlink(Rx),
    C = #{tx => #{backend => Tx, broker => TxBroker, owner => Source},
        rx => #{backend => Rx, broker => RxBroker, owner => Destination}, journal => Journal},
    {ok, Pair} = start_pair(C), unlink(Pair),
    try Fun(C#{pair => Pair}), ok
    after
        exit(Pair, kill),
        catch hls_domain_channel_fabric:stop(Tx), catch hls_domain_channel_fabric:stop(Rx),
        [exit(Pid, kill) || Pid <- [TxBroker, RxBroker, Source, Destination, Journal]]
    end.

%% Finite deadlines make a dropped management response observable without synthesizing success.
-spec adapter(tx | rx, pid()) -> gen_server:start_ret().
adapter(Side, Broker) ->
    hls_domain_channel_fabric:start_link(#{management => Broker, session => 41},
        interface(Side), #{management_timeout_ms => 30}).

%% The ordinary child API takes existing deployment owners and fixed endpoint identities.
-spec start_pair(map()) -> gen_server:start_ret().
start_pair(C) ->
    hls_domain_endpoint_pair:start_link({backend(C, tx), 8}, {backend(C, rx), 61},
        {maps:get(owner, maps:get(tx, C)), source}, {maps:get(owner, maps:get(rx, C)), destination},
        16#123456789abcdef0, #{poll_ms => 5, request_timeout_ms => 100}).

%% Ready evidence is checked from the public coordinator API only.
-spec ready(pid()) -> #endpoint_binding{}.
ready(Pair) ->
    wait(fun() -> is_map(hls_domain_endpoint_pair:status(Pair)) end),
    #{phase := ready, binding := Binding, tx := #{binding := Binding, active := true},
        rx := #{binding := Binding, active := true}} = hls_domain_endpoint_pair:status(Pair),
    Binding.

%% Retirement requires native inactive evidence and adapter completion of its owner-death obligation.
-spec retired(map(), tx | rx) -> ok.
retired(C, Side) ->
    wait(fun() ->
        #{active := Active} = gen_server:call(broker(C, Side), snapshot),
        #{retiring := Retiring} = hls_domain_channel_fabric:info(backend(C, Side)),
        not Active andalso map_size(Retiring) =:= 0
    end).

%% Only this finite fixture poll uses elapsed time; success still requires explicit evidence.
-spec wait(fun(() -> boolean())) -> ok.
wait(Predicate) -> wait(Predicate, 300).

%% A missing required observation fails within the EUnit case's normal deadline.
-spec wait(fun(() -> boolean()), non_neg_integer()) -> ok.
wait(_, 0) -> error(missing_endpoint_pair_evidence);
wait(Predicate, Remaining) ->
    case Predicate() of true -> ok; false -> timer:sleep(5), wait(Predicate, Remaining - 1) end.

%% Management and owner probes are serialized into one small witness log.
-spec journal([term()]) -> ok.
journal(Events) ->
    receive
        {'$gen_call', From, {event, Event}} -> gen_server:reply(From, ok), journal([Event | Events]);
        {'$gen_call', From, events} -> gen_server:reply(From, lists:reverse(Events)), journal(Events)
    end.

%% Domain fixtures implement the existing status request and reject any lifecycle mutation.
-spec owner(atom(), pos_integer(), pid()) -> ok.
owner(Domain, Incarnation, Journal) ->
    receive
        {'$gen_call', From, {status, Domain}} ->
            ok = gen_server:call(Journal, {event, {owner, Domain, Incarnation}}),
            gen_server:reply(From, {ok, #{domain => Domain, phase => ready, handle => {Domain, Incarnation},
                target => Incarnation, transition => 0, fault => none, detail => none, actors => #{}}}),
            owner(Domain, Incarnation, Journal);
        {'$gen_call', From, {incarnation, Fresh}} -> gen_server:reply(From, ok), owner(Domain, Fresh, Journal);
        {'$gen_call', From, Request} -> gen_server:reply(From, {error, {unexpected_owner_mutation, Request}}),
            error({unexpected_owner_mutation, Request})
    end.

%% Start one native state with no packet handshakes or application forwarding path.
-spec wire_broker(tx | rx, pos_integer(), atom(), pid()) -> ok.
wire_broker(Side, Incarnation, Mode, Journal) ->
    Native = case Side of tx -> hls_domain_channel_tx:new(); rx -> hls_domain_channel_rx:new() end,
    wire_loop(#{side => Side, incarnation => Incarnation, mode => Mode, journal => Journal,
        native => Native, adapter => none, held => none}).

%% Broker writes step the native kernel; only response delivery can be dropped or delayed.
-spec wire_loop(map()) -> ok.
wire_loop(State = #{side := Side, incarnation := Incarnation, native := Native}) ->
    receive
        {'$gen_call', From, {register_route, {0, 2}, Adapter}} ->
            gen_server:reply(From, ok), wire_loop(State#{adapter := Adapter});
        {'$gen_call', From, {send, {0, 2}, {Tag, 0, 0}, Payload, _}} ->
            gen_server:reply(From, ok), wire_loop(wire_step(Tag, Payload, State));
        {'$gen_cast', {ack, _, _}} -> wire_loop(State);
        {'$gen_call', From, snapshot} ->
            {_, Snapshot} = native(Side, tick, #endpoint_binding{}, Incarnation, Native),
            gen_server:reply(From, Snapshot), wire_loop(State);
        {'$gen_call', From, held} -> gen_server:reply(From, maps:get(held, State) =/= none), wire_loop(State);
        {'$gen_call', From, release} ->
            {Adapter, Payload} = maps:get(held, State), deliver(Adapter, Payload),
            gen_server:reply(From, ok), wire_loop(State#{held := none});
        {'$gen_call', From, {incarnation, Fresh}} ->
            gen_server:reply(From, ok), wire_loop(State#{incarnation := Fresh});
        {'$gen_call', From, {mode, Mode}} ->
            gen_server:reply(From, ok), wire_loop(State#{mode := Mode})
    end.

%% The packet prefix and complete four-field binding are decoded independently of the production encoder.
-spec wire_step(0 | 1 | 2, binary(), map()) -> map().
wire_step(Tag, <<Session:64/little, Request:32/little, Id:32/little, Tail/binary>>,
    State = #{side := Side, incarnation := Incarnation, native := Native, mode := Mode,
        adapter := Adapter, journal := Journal}) ->
    {Operation, Binding} = case {Tag, Tail} of
        {0, <<>>} -> {tick, #endpoint_binding{}};
        {1, _} -> {bind, unpacked(Tail)};
        {2, _} -> {fence, unpacked(Tail)}
    end,
    case {Tag, Mode} of
        {1, Drop} when Drop =:= drop_unexecuted; Drop =:= drop_unexecuted_always ->
            ok = gen_server:call(Journal, {event, {Side, Tag, Binding, not_executed}}),
            NextMode = case Drop of drop_unexecuted -> normal; drop_unexecuted_always -> Drop end,
            State#{mode := NextMode};
        _ ->
            {Next, Snapshot = #{status := Status, binding := Observed}} = native(Side, Operation, Binding, Incarnation, Native),
            ok = gen_server:call(Journal, {event, {Side, Tag, Observed, Status}}),
            Payload = reply(Session, Request, Id, Snapshot, interface(Side)),
            case {Tag, Mode} of
                {0, drop_inspect} -> State#{native := Next, mode := normal};
                {1, drop_reply} -> State#{native := Next, mode := normal};
                {1, hold_reply} -> State#{native := Next, mode := normal, held := {Adapter, Payload}};
                _ -> deliver(Adapter, Payload), State#{native := Next}
            end
    end.

%% TX confirmation is the exact assertion sent by the host wire contract, never a remote ready signal.
-spec native(tx | rx, endpoint_operation(), #endpoint_binding{}, pos_integer(),
    #endpoint_tx_state{} | #endpoint_rx_state{}) ->
    {#endpoint_tx_state{} | #endpoint_rx_state{}, hls_domain_endpoint_wire:snapshot()}.
native(tx, Operation, Binding, Incarnation, Native) ->
    #endpoint_tx_output{status = Status, state = Next} = hls_domain_channel_tx:step(
        #endpoint_tx_input{op = Operation, binding = Binding, local_ready = true, local_incarnation = Incarnation,
            receiver_binding = Binding, receiver_active = true}, Native),
    {Next, #{kind => tx, status => Status, binding => Next#endpoint_tx_state.binding,
        packet_sequence => Next#endpoint_tx_state.sequence, active => Next#endpoint_tx_state.active, fault => false}};
native(rx, Operation, Binding, Incarnation, Native) ->
    #endpoint_rx_output{status = Status, state = Next} = hls_domain_channel_rx:step(
        #endpoint_rx_input{op = Operation, binding = Binding, local_ready = true, local_incarnation = Incarnation}, Native),
    {Next, #{kind => rx, status => Status, binding => Next#endpoint_rx_state.binding,
        packet_sequence => Next#endpoint_rx_state.sequence, active => Next#endpoint_rx_state.active, fault => false}}.

%% Responses use the native status codec but independently lay out the canonical management envelope.
-spec reply(hls_nums:u64(), hls_nums:u32(), hls_nums:u32(), hls_domain_endpoint_wire:snapshot(),
    hls_domain_endpoint_wire:interface()) -> binary().
reply(Session, Request, Id, #{status := Status, binding := Binding, packet_sequence := Sequence, active := Active},
    #{codecs := #{status := StatusType}}) ->
    Width = hls_type:width(StatusType), <<Code:Width>> = hls_type:pack(Status, StatusType),
    Flags = Code bor (case Active of true -> 1 bsl 8; false -> 0 end),
    Packed = packed(Binding),
    <<Session:64/little, Request:32/little, Id:32/little, Flags:32/little, Packed/binary, Sequence:32/little>>.

%% Delivery follows the production broker callback, including its complete response header.
-spec deliver(pid(), binary()) -> ok.
deliver(Adapter, Payload) ->
    gen_server:cast(Adapter, {'$hls_fabric_frame', make_ref(), {0, 2}, {129, 0, 0}, Payload}).

%% Retained codecs require no compiler modules in these runtime witnesses.
-spec interface(tx | rx) -> hls_domain_endpoint_wire:interface().
interface(Side) ->
    Id = case Side of tx -> 8; rx -> 61 end,
    #{kind => domain_endpoint_management, management_route => {0, 2}, response_tag => 129,
        endpoints => [#{id => Id, kind => Side}],
        codecs => #{operation => {hls_type, hls_enum, enum, [[tick, bind, fence]]},
            status => {hls_type, hls_enum, enum, [[ok, accepted, stale, invalid, busy, closed, exhausted]]},
            binding => {hls_type, hls_record, endpoint_binding, [{Field, hls_nums:u64()} ||
                Field <- [namespace, generation, source_incarnation, destination_incarnation]]}}}.

%% These literals exercise namespace bits above a management session's old short forms.
-spec binding(pos_integer(), pos_integer(), pos_integer()) -> #endpoint_binding{}.
binding(Generation, Source, Destination) -> #endpoint_binding{namespace = 16#123456789abcdef0,
    generation = Generation, source_incarnation = Source, destination_incarnation = Destination}.

%% Exact little-endian field packing is independent of production command construction.
-spec packed(#endpoint_binding{}) -> binary().
packed(#endpoint_binding{namespace = Namespace, generation = Generation,
    source_incarnation = Source, destination_incarnation = Destination}) ->
    <<Namespace:64/little, Generation:64/little, Source:64/little, Destination:64/little>>.

%% Mutations must contain all four identity fields and no additional bytes.
-spec unpacked(binary()) -> #endpoint_binding{}.
unpacked(<<Namespace:64/little, Generation:64/little, Source:64/little, Destination:64/little>>) ->
    #endpoint_binding{namespace = Namespace, generation = Generation,
        source_incarnation = Source, destination_incarnation = Destination}.

%% Fixture accessors retain each actual PID, matching the production coordinator's transport rule.
-spec backend(map(), tx | rx) -> pid().
backend(C, Side) -> maps:get(backend, maps:get(Side, C)).

%% Broker state is observable only inside this finite fixture.
-spec broker(map(), tx | rx) -> pid().
broker(C, Side) -> maps:get(broker, maps:get(Side, C)).

%% Query the bounded fixture event log and discard owner-read entries where endpoint order is inspected.
-spec events(map()) -> [term()].
events(C) -> gen_server:call(maps:get(journal, C), events).

%% Test control moves only the selected fixture's lifecycle, without giving the coordinator that authority.
-spec incarnation(map(), tx | rx, pos_integer()) -> ok.
incarnation(C, Side, Fresh) ->
    ok = gen_server:call(maps:get(owner, maps:get(Side, C)), {incarnation, Fresh}),
    gen_server:call(broker(C, Side), {incarnation, Fresh}).

%% A held response confirms the preceding native bind has actually executed.
-spec held(map(), tx | rx) -> boolean().
held(C, Side) -> gen_server:call(broker(C, Side), held).

%% Deliver an intentionally delayed original response; correlation remains the adapter's responsibility.
-spec release(map(), tx | rx) -> ok.
release(C, Side) -> gen_server:call(broker(C, Side), release).

%% Both retained endpoint histories must constrain a fresh coordinator even after only one bind executed.
-spec source_observed(map(), pos_integer()) -> boolean().
source_observed(C, Fresh) -> lists:member({owner, source, Fresh}, events(C)).

%% Bind pulses are counted independently of inspect traffic and status polling.
-spec bind_events(tx | rx, [term()]) -> [term()].
bind_events(Side, Events) -> [E || E = {Kind, 1, _, _} <- Events, Kind =:= Side].

%% The suffix beginning with the first attempted bind exposes the next same-endpoint operation.
-spec after_bind(tx | rx, [term()]) -> [term()].
after_bind(Side, Events) -> lists:dropwhile(fun({_, Tag, _, _}) -> Tag =/= 1 end,
    [E || E = {Kind, _, _, _} <- Events, Kind =:= Side]).
