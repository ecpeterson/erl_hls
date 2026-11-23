-module(hls_domain_channel_endpoints_tests).
-moduledoc "Finite native witnesses for independently owned mailbox endpoints. Carrier integrity, physical reset and remote liveness are assumptions, not established by these kernel tests.".
-include_lib("eunit/include/eunit.hrl").
-include_lib("hls_fabric/include/hls_domain_channel_endpoints.hrl").

%% The receiver's exact active binding must be confirmed before source admission.
-spec receiver_confirmation_test() -> ok.
receiver_confirmation_test() ->
    Binding = binding(),
    Cold = hls_domain_channel_tx:new(),
    Input = tx_bind(Binding),
    [begin
        Busy = tx(Cold, Missing),
        ?assertEqual(busy, Busy#endpoint_tx_output.status),
        ?assertEqual(Cold, Busy#endpoint_tx_output.state),
        no_tx_transfer(Busy)
    end || Missing <- [Input#endpoint_tx_input{receiver_active = false},
        Input#endpoint_tx_input{receiver_binding = Binding#endpoint_binding{generation = 2}},
        Input#endpoint_tx_input{local_ready = false},
        Input#endpoint_tx_input{local_incarnation = 11}]],
    Receive = rx(hls_domain_channel_rx:new(), rx_bind(Binding)),
    ?assertEqual(accepted, Receive#endpoint_rx_output.status),
    no_rx_transfer(Receive),
    Send = tx(Cold, Input#endpoint_tx_input{source_valid = true, data_tx_ready = true}),
    ?assertEqual(accepted, Send#endpoint_tx_output.status),
    no_tx_transfer(Send),
    ?assertEqual(Binding, (Send#endpoint_tx_output.state)#endpoint_tx_state.binding),
    %% A lost bind response is inspected; retransmitting the command cannot allocate again.
    Repeated = tx(Send#endpoint_tx_output.state, Input),
    ?assertEqual(stale, Repeated#endpoint_tx_output.status),
    ?assertEqual(Send#endpoint_tx_output.state, Repeated#endpoint_tx_output.state),
    RepeatedRx = rx(Receive#endpoint_rx_output.state, rx_bind(Binding)),
    ?assertEqual(stale, RepeatedRx#endpoint_rx_output.status),
    ?assertEqual(Receive#endpoint_rx_output.state, RepeatedRx#endpoint_rx_output.state).

%% Capture, packet handoff, native capture, ACK handoff and credit release use distinct edges.
-spec independent_handshake_edges_test() -> ok.
independent_handshake_edges_test() ->
    {Tx0, Rx0} = bound(),
    Capture = tx(Tx0, (tx_input(Tx0))#endpoint_tx_input{source_valid = true, data_tx_ready = true}),
    ?assert(Capture#endpoint_tx_output.source_take),
    ?assertNot(Capture#endpoint_tx_output.tx_valid),
    Packet = Capture#endpoint_tx_output.packet,
    ?assertEqual(packet(binding(), 1), Packet),
    Tx1 = Capture#endpoint_tx_output.state,
    Transmit = tx(Tx1, (tx_input(Tx1))#endpoint_tx_input{
        data_tx_ready = true}),
    ?assert(Transmit#endpoint_tx_output.tx_valid),
    ?assertNot(Transmit#endpoint_tx_output.credit_drop),
    Tx2 = Transmit#endpoint_tx_output.state,
    Receive = rx(Rx0, (rx_input(Rx0))#endpoint_rx_input{data_valid = true,
        data_packet = Packet, destination_ready = true, ack_tx_ready = true}),
    ?assert(Receive#endpoint_rx_output.data_take),
    ?assertNot(Receive#endpoint_rx_output.destination_take),
    ?assertNot(Receive#endpoint_rx_output.ack_valid),
    Rx1 = Receive#endpoint_rx_output.state,
    %% A duplicate never overwrites the held publication or generates another ACK.
    Duplicate = rx(Rx1, (rx_input(Rx1))#endpoint_rx_input{data_valid = true, data_packet = Packet}),
    ?assert(Duplicate#endpoint_rx_output.data_drop),
    ?assertNot(Duplicate#endpoint_rx_output.data_take),
    ?assertEqual(Rx1, Duplicate#endpoint_rx_output.state),
    Deliver = rx(Rx1, (rx_input(Rx1))#endpoint_rx_input{destination_ready = true, ack_tx_ready = true}),
    ?assert(Deliver#endpoint_rx_output.destination_take),
    ?assertNot(Deliver#endpoint_rx_output.ack_valid),
    Rx2 = Deliver#endpoint_rx_output.state,
    Ack = rx(Rx2, (rx_input(Rx2))#endpoint_rx_input{ack_tx_ready = true}),
    ?assert(Ack#endpoint_rx_output.ack_valid),
    ?assertEqual(Packet, Ack#endpoint_rx_output.packet),
    ?assertNot(Ack#endpoint_rx_output.data_drop),
    ?assertNot(Ack#endpoint_rx_output.data_take),
    Rx3 = Ack#endpoint_rx_output.state,
    Release = tx(Tx2, (tx_input(Tx2))#endpoint_tx_input{source_valid = true,
        credit_valid = true, credit_packet = Ack#endpoint_rx_output.packet}),
    ?assertNot(Release#endpoint_tx_output.credit_drop),
    ?assertNot(Release#endpoint_tx_output.source_take),
    Tx3 = Release#endpoint_tx_output.state,
    ?assertNot(Tx3#endpoint_tx_state.inflight),
    Next = tx(Tx3, (tx_input(Tx3))#endpoint_tx_input{source_valid = true}),
    ?assert(Next#endpoint_tx_output.source_take),
    ?assertEqual(packet(binding(), 2), Next#endpoint_tx_output.packet),
    OldAck = tx(Tx3, (tx_input(Tx3))#endpoint_tx_input{credit_valid = true, credit_packet = Packet}),
    ?assert(OldAck#endpoint_tx_output.credit_drop),
    OldData = rx(Rx3, (rx_input(Rx3))#endpoint_rx_input{data_valid = true, data_packet = Packet}),
    ?assert(OldData#endpoint_rx_output.data_drop),
    ?assertNot(OldData#endpoint_rx_output.ack_valid),
    ?assertEqual(Rx3, OldData#endpoint_rx_output.state).

%% Finite missing-data/ACK schedules preserve ownership without retries or invented progress.
-spec loss_and_stalls_test() -> ok.
loss_and_stalls_test() ->
    {Tx0, Rx0} = bound(),
    Capture = tx(Tx0, (tx_input(Tx0))#endpoint_tx_input{source_valid = true}),
    Tx1 = Capture#endpoint_tx_output.state,
    Packet = Capture#endpoint_tx_output.packet,
    [begin
        Held = tx(Tx1, (tx_input(Tx1))#endpoint_tx_input{source_valid = true}),
        ?assert(Held#endpoint_tx_output.tx_valid),
        ?assertNot(Held#endpoint_tx_output.source_take),
        ?assertEqual(Tx1, Held#endpoint_tx_output.state)
    end || _ <- lists:seq(1, 8)],
    Tx2 = (tx(Tx1, (tx_input(Tx1))#endpoint_tx_input{data_tx_ready = true}))#endpoint_tx_output.state,
    [begin
        Lost = tx(Tx2, (tx_input(Tx2))#endpoint_tx_input{source_valid = true}),
        ?assertNot(Lost#endpoint_tx_output.tx_valid),
        ?assertNot(Lost#endpoint_tx_output.source_take),
        ?assertEqual(Tx2, Lost#endpoint_tx_output.state),
        ?assertEqual(Rx0, (rx(Rx0, rx_input(Rx0)))#endpoint_rx_output.state)
    end || _ <- lists:seq(1, 8)],
    Rx1 = (rx(Rx0, (rx_input(Rx0))#endpoint_rx_input{data_valid = true, data_packet = Packet}))#endpoint_rx_output.state,
    [begin
        Held = rx(Rx1, rx_input(Rx1)),
        ?assert(Held#endpoint_rx_output.destination_valid),
        ?assertNot(Held#endpoint_rx_output.destination_take),
        ?assertEqual(Rx1, Held#endpoint_rx_output.state)
    end || _ <- lists:seq(1, 8)],
    Rx2 = (rx(Rx1, (rx_input(Rx1))#endpoint_rx_input{destination_ready = true}))#endpoint_rx_output.state,
    [begin
        Held = rx(Rx2, rx_input(Rx2)),
        ?assert(Held#endpoint_rx_output.ack_valid),
        ?assertNot(Held#endpoint_rx_output.destination_valid),
        ?assertEqual(Rx2, Held#endpoint_rx_output.state)
    end || _ <- lists:seq(1, 8)],
    Rx3 = (rx(Rx2, (rx_input(Rx2))#endpoint_rx_input{ack_tx_ready = true}))#endpoint_rx_output.state,
    %% Losing this ACK does not cause the receiver to retransmit it.
    ?assertNot((rx(Rx3, rx_input(Rx3)))#endpoint_rx_output.ack_valid),
    ?assertEqual(Tx2, (tx(Tx2, tx_input(Tx2)))#endpoint_tx_output.state).

%% Every identity field participates in rejection; arrival does not create a binding.
-spec wrong_identity_and_reordering_test() -> ok.
wrong_identity_and_reordering_test() ->
    {Tx0, Rx0} = bound(),
    Captured = tx(Tx0, (tx_input(Tx0))#endpoint_tx_input{source_valid = true}),
    Tx1 = Captured#endpoint_tx_output.state,
    Tx2 = (tx(Tx1, (tx_input(Tx1))#endpoint_tx_input{data_tx_ready = true}))#endpoint_tx_output.state,
    [begin
        Data = rx(Rx0, (rx_input(Rx0))#endpoint_rx_input{data_valid = true,
            data_packet = Bad, destination_ready = true}),
        ?assert(Data#endpoint_rx_output.data_ready),
        ?assert(Data#endpoint_rx_output.data_drop),
        ?assertNot(Data#endpoint_rx_output.data_take),
        ?assertEqual(Rx0, Data#endpoint_rx_output.state),
        Credit = tx(Tx2, (tx_input(Tx2))#endpoint_tx_input{credit_valid = true, credit_packet = Bad}),
        ?assert(Credit#endpoint_tx_output.credit_drop),
        ?assertEqual(Tx2, Credit#endpoint_tx_output.state)
    end || Bad <- bad_packets()],
    Cold = hls_domain_channel_rx:new(),
    Unbound = rx(Cold, #endpoint_rx_input{data_valid = true, data_packet = packet(binding(), 1)}),
    ?assert(Unbound#endpoint_rx_output.data_drop),
    ?assertEqual(Cold, Unbound#endpoint_rx_output.state).

%% Fencing any packet phase suppresses all transfers on that edge and retains tombstones.
-spec exact_fence_and_local_failure_test() -> ok.
exact_fence_and_local_failure_test() ->
    {Tx0, Rx0} = bound(),
    Tx1 = (tx(Tx0, (tx_input(Tx0))#endpoint_tx_input{source_valid = true}))#endpoint_tx_output.state,
    Tx2 = (tx(Tx1, (tx_input(Tx1))#endpoint_tx_input{data_tx_ready = true}))#endpoint_tx_output.state,
    Rx1 = (rx(Rx0, (rx_input(Rx0))#endpoint_rx_input{data_valid = true,
        data_packet = packet(binding(), 1)}))#endpoint_rx_output.state,
    Rx2 = (rx(Rx1, (rx_input(Rx1))#endpoint_rx_input{destination_ready = true}))#endpoint_rx_output.state,
    [begin
        Full = (tx_input(State))#endpoint_tx_input{source_valid = true, data_tx_ready = true,
            credit_valid = true, credit_packet = packet(binding(), 1)},
        Fenced = tx(State, Full#endpoint_tx_input{op = fence, binding = binding()}),
        ?assertEqual(accepted, Fenced#endpoint_tx_output.status),
        no_tx_transfer(Fenced),
        ?assertNot((Fenced#endpoint_tx_output.state)#endpoint_tx_state.active),
        ?assertEqual(State#endpoint_tx_state.binding,
            (Fenced#endpoint_tx_output.state)#endpoint_tx_state.binding),
        Stale = tx(State, Full#endpoint_tx_input{op = fence,
            binding = (binding())#endpoint_binding{namespace = 8}}),
        ?assertEqual(stale, Stale#endpoint_tx_output.status),
        ?assertEqual(State, Stale#endpoint_tx_output.state),
        [begin
            Closed = tx(State, Failure),
            no_tx_transfer(Closed),
            ?assertNot((Closed#endpoint_tx_output.state)#endpoint_tx_state.active)
        end || Failure <- [Full#endpoint_tx_input{local_ready = false},
            Full#endpoint_tx_input{local_incarnation = 11},
            Full#endpoint_tx_input{op = fence, local_ready = false},
            Full#endpoint_tx_input{op = bind, local_ready = false}]]
    end || State <- [Tx0, Tx1, Tx2]],
    [begin
        Full = (rx_input(State))#endpoint_rx_input{data_valid = true,
            data_packet = packet(binding(), 1), destination_ready = true, ack_tx_ready = true},
        Fenced = rx(State, Full#endpoint_rx_input{op = fence, binding = binding()}),
        ?assertEqual(accepted, Fenced#endpoint_rx_output.status),
        no_rx_transfer(Fenced),
        ?assertNot((Fenced#endpoint_rx_output.state)#endpoint_rx_state.active),
        ?assertEqual(State#endpoint_rx_state.binding,
            (Fenced#endpoint_rx_output.state)#endpoint_rx_state.binding),
        Stale = rx(State, Full#endpoint_rx_input{op = fence,
            binding = (binding())#endpoint_binding{generation = 2}}),
        ?assertEqual(stale, Stale#endpoint_rx_output.status),
        ?assertEqual(State, Stale#endpoint_rx_output.state),
        [begin
            Closed = rx(State, Failure),
            no_rx_transfer(Closed),
            ?assertNot((Closed#endpoint_rx_output.state)#endpoint_rx_state.active)
        end || Failure <- [Full#endpoint_rx_input{local_ready = false},
            Full#endpoint_rx_input{local_incarnation = 21},
            Full#endpoint_rx_input{op = fence, local_ready = false},
            Full#endpoint_rx_input{op = bind, local_ready = false}]]
    end || State <- [Rx0, Rx1, Rx2]], ok.

%% An independently replaced receiver rejects old traffic even while the source is unaware.
-spec independent_rebind_test() -> ok.
independent_rebind_test() ->
    {Tx0, Rx0} = bound(),
    Old = binding(),
    Fresh = Old#endpoint_binding{generation = 2, source_incarnation = 11, destination_incarnation = 21},
    [begin
        ?assertEqual(stale, binding_status(Bad, Old))
    end || Bad <- [Fresh#endpoint_binding{source_incarnation = 10},
        Fresh#endpoint_binding{destination_incarnation = 20},
        Fresh#endpoint_binding{namespace = 8}, Fresh#endpoint_binding{generation = 1}]],
    Rx1 = (rx(Rx0, rx_bind(Fresh)))#endpoint_rx_output.state,
    ?assertEqual(Fresh, Rx1#endpoint_rx_state.binding),
    %% The old source has no remote-ready wire; old-group uncertainty is permitted.
    OldCapture = tx(Tx0, (tx_input(Tx0))#endpoint_tx_input{source_valid = true}),
    ?assert(OldCapture#endpoint_tx_output.source_take),
    OldData = rx(Rx1, (rx_input(Rx1))#endpoint_rx_input{data_valid = true,
        data_packet = OldCapture#endpoint_tx_output.packet, destination_ready = true}),
    ?assert(OldData#endpoint_rx_output.data_drop),
    ?assertNot(OldData#endpoint_rx_output.data_take),
    Tx1 = (tx(OldCapture#endpoint_tx_output.state, tx_bind(Fresh)))#endpoint_tx_output.state,
    FreshCapture = tx(Tx1, (tx_input(Tx1))#endpoint_tx_input{source_valid = true}),
    ?assertEqual(packet(Fresh, 1), FreshCapture#endpoint_tx_output.packet),
    Tx2 = FreshCapture#endpoint_tx_output.state,
    Tx3 = (tx(Tx2, (tx_input(Tx2))#endpoint_tx_input{data_tx_ready = true}))#endpoint_tx_output.state,
    OldCredit = tx(Tx3, (tx_input(Tx3))#endpoint_tx_input{credit_valid = true,
        credit_packet = packet(Old, 1)}),
    ?assert(OldCredit#endpoint_tx_output.credit_drop),
    ?assertEqual(Tx3, OldCredit#endpoint_tx_output.state),
    FreshData = rx(Rx1, (rx_input(Rx1))#endpoint_rx_input{data_valid = true,
        data_packet = FreshCapture#endpoint_tx_output.packet}),
    ?assert(FreshData#endpoint_rx_output.data_take).

%% The final sequence can complete, but neither endpoint admits a wrapped sequence.
-spec sequence_exhaustion_test() -> ok.
sequence_exhaustion_test() ->
    {Tx0, Rx0} = bound(),
    Max = (1 bsl 32) - 1,
    NearTx = Tx0#endpoint_tx_state{sequence = Max - 1},
    NearRx = Rx0#endpoint_rx_state{sequence = Max - 1},
    Last = tx(NearTx, (tx_input(NearTx))#endpoint_tx_input{source_valid = true}),
    ?assertEqual(packet(binding(), Max), Last#endpoint_tx_output.packet),
    Tx1 = Last#endpoint_tx_output.state,
    Tx2 = (tx(Tx1, (tx_input(Tx1))#endpoint_tx_input{data_tx_ready = true}))#endpoint_tx_output.state,
    Rx1 = (rx(NearRx, (rx_input(NearRx))#endpoint_rx_input{data_valid = true,
        data_packet = Last#endpoint_tx_output.packet}))#endpoint_rx_output.state,
    Rx2 = (rx(Rx1, (rx_input(Rx1))#endpoint_rx_input{destination_ready = true}))#endpoint_rx_output.state,
    Ack = rx(Rx2, (rx_input(Rx2))#endpoint_rx_input{ack_tx_ready = true}),
    ?assert(Ack#endpoint_rx_output.ack_valid),
    Rx3 = Ack#endpoint_rx_output.state,
    Tx3 = (tx(Tx2, (tx_input(Tx2))#endpoint_tx_input{credit_valid = true,
        credit_packet = Ack#endpoint_rx_output.packet}))#endpoint_tx_output.state,
    Exhausted = tx(Tx3, (tx_input(Tx3))#endpoint_tx_input{source_valid = true}),
    ?assertEqual(exhausted, Exhausted#endpoint_tx_output.status),
    no_tx_transfer(Exhausted),
    ?assertEqual(Max, (Exhausted#endpoint_tx_output.state)#endpoint_tx_state.sequence),
    Wrapped = rx(Rx3, (rx_input(Rx3))#endpoint_rx_input{data_valid = true,
        data_packet = packet(binding(), 0), destination_ready = true}),
    ?assertEqual(exhausted, Wrapped#endpoint_rx_output.status),
    no_rx_transfer(Wrapped),
    ?assertNot((Wrapped#endpoint_rx_output.state)#endpoint_rx_state.active).

%% Namespace and incarnation zero are invalid, and exhausted generations never restart at one.
-spec invalid_and_exhausted_binding_test() -> ok.
invalid_and_exhausted_binding_test() ->
    Initial = #endpoint_binding{},
    [begin ?assertEqual(invalid, binding_status(Bad, Initial)) end ||
        Bad <- [(binding())#endpoint_binding{namespace = 0},
            (binding())#endpoint_binding{source_incarnation = 0},
            (binding())#endpoint_binding{destination_incarnation = 0}]],
    {Tx0, Rx0} = bound(),
    Old = (binding())#endpoint_binding{generation = ((1 bsl 64) - 1)},
    Fresh = Old#endpoint_binding{generation = 1, source_incarnation = 11, destination_incarnation = 21},
    Tx = tx(Tx0#endpoint_tx_state{binding = Old}, tx_bind(Fresh)),
    Rx = rx(Rx0#endpoint_rx_state{binding = Old}, rx_bind(Fresh)),
    ?assertEqual(exhausted, Tx#endpoint_tx_output.status),
    ?assertEqual(exhausted, Rx#endpoint_rx_output.status),
    ?assertNot((Tx#endpoint_tx_output.state)#endpoint_tx_state.active),
    ?assertNot((Rx#endpoint_rx_output.state)#endpoint_rx_state.active),
    no_tx_transfer(Tx), no_rx_transfer(Rx).

%% The compiler-facing services execute the same pure kernels, not alternate native policies.
-spec service_adapters_test() -> ok.
service_adapters_test() ->
    TxInput = tx_bind(binding()),
    {reply, Tx, _} = hls_domain_channel_tx:handle_call(TxInput, hls_domain_channel_tx:init([])),
    ?assertEqual(tx(hls_domain_channel_tx:new(), TxInput), Tx),
    RxInput = rx_bind(binding()),
    {reply, Rx, _} = hls_domain_channel_rx:handle_call(RxInput, hls_domain_channel_rx:init([])),
    ?assertEqual(rx(hls_domain_channel_rx:new(), RxInput), Rx).

%% Fixture lifetimes are explicit and shared only through management evidence.
-spec binding() -> #endpoint_binding{}.
binding() -> #endpoint_binding{namespace = 7, generation = 1,
    source_incarnation = 10, destination_incarnation = 20}.

%% A packet identity does not itself authorize its binding.
-spec packet(#endpoint_binding{}, hls_nums:u32()) -> #endpoint_packet{}.
packet(Binding, Sequence) -> #endpoint_packet{binding = Binding, sequence = Sequence}.

%% Initial receiver installation precedes exact source confirmation.
-spec bound() -> {#endpoint_tx_state{}, #endpoint_rx_state{}}.
bound() ->
    #endpoint_rx_output{status = accepted, state = Rx} = rx(hls_domain_channel_rx:new(), rx_bind(binding())),
    #endpoint_tx_output{status = accepted, state = Tx} = tx(hls_domain_channel_tx:new(), tx_bind(binding())),
    {Tx, Rx}.

%% Source binding is a management operation with retained receiver evidence.
-spec tx_bind(#endpoint_binding{}) -> #endpoint_tx_input{}.
tx_bind(Binding) -> #endpoint_tx_input{op = bind, binding = Binding,
    receiver_binding = Binding, receiver_active = true, local_ready = true,
    local_incarnation = Binding#endpoint_binding.source_incarnation}.

%% Receiver binding observes only its local destination lifetime.
-spec rx_bind(#endpoint_binding{}) -> #endpoint_rx_input{}.
rx_bind(Binding) -> #endpoint_rx_input{op = bind, binding = Binding,
    local_ready = true, local_incarnation = Binding#endpoint_binding.destination_incarnation}.

%% No receiver evidence is supplied on ordinary source ticks.
-spec tx_input(#endpoint_tx_state{}) -> #endpoint_tx_input{}.
tx_input(State) -> #endpoint_tx_input{local_ready = true,
    local_incarnation = (State#endpoint_tx_state.binding)#endpoint_binding.source_incarnation}.

%% The receiver never reads the source's current state.
-spec rx_input(#endpoint_rx_state{}) -> #endpoint_rx_input{}.
rx_input(State) -> #endpoint_rx_input{local_ready = true,
    local_incarnation = (State#endpoint_rx_state.binding)#endpoint_binding.destination_incarnation}.

%% Tests exercise the public pure source kernel directly.
-spec tx(#endpoint_tx_state{}, #endpoint_tx_input{}) -> #endpoint_tx_output{}.
tx(State, Input) -> hls_domain_channel_tx:step(Input, State).

%% Tests exercise the public pure destination kernel directly.
-spec rx(#endpoint_rx_state{}, #endpoint_rx_input{}) -> #endpoint_rx_output{}.
rx(State, Input) -> hls_domain_channel_rx:step(Input, State).

%% Each checked binding field and both noncurrent sequence directions are challenged.
-spec bad_packets() -> [#endpoint_packet{}].
bad_packets() ->
    Binding = binding(),
    [packet(Binding#endpoint_binding{namespace = 8}, 1),
        packet(Binding#endpoint_binding{generation = 2}, 1),
        packet(Binding#endpoint_binding{source_incarnation = 11}, 1),
        packet(Binding#endpoint_binding{destination_incarnation = 21}, 1)].

%% Fault/control edges cannot transfer payload or consume a returned acknowledgement.
-spec no_tx_transfer(#endpoint_tx_output{}) -> ok.
no_tx_transfer(Output) ->
    ?assertNot(Output#endpoint_tx_output.source_take),
    ?assertNot(Output#endpoint_tx_output.tx_valid),
    ?assertNot(Output#endpoint_tx_output.credit_ready), ok.

%% Fault/control edges cannot receive, deliver or acknowledge an application publication.
-spec no_rx_transfer(#endpoint_rx_output{}) -> ok.
no_rx_transfer(Output) ->
    ?assertNot(Output#endpoint_rx_output.data_ready),
    ?assertNot(Output#endpoint_rx_output.data_take),
    ?assertNot(Output#endpoint_rx_output.destination_valid),
    ?assertNot(Output#endpoint_rx_output.destination_take),
    ?assertNot(Output#endpoint_rx_output.ack_valid), ok.

%% Record fixtures call the same scalar helper imported by source-compiled kernels.
-spec binding_status(#endpoint_binding{}, #endpoint_binding{}) -> accepted | invalid | stale | exhausted.
binding_status(Binding, Previous) ->
    hls_domain_channel_binding:advance(
        Binding#endpoint_binding.namespace, Binding#endpoint_binding.generation,
        Binding#endpoint_binding.source_incarnation, Binding#endpoint_binding.destination_incarnation,
        Previous#endpoint_binding.namespace, Previous#endpoint_binding.generation,
        Previous#endpoint_binding.source_incarnation, Previous#endpoint_binding.destination_incarnation).

%% Impossible traffic in the current binding closes without any same-edge handoff.
-spec impossible_current_packet_test() -> ok.
impossible_current_packet_test() ->
    {Tx0, Rx0} = bound(),
    Captured = tx(Tx0, (tx_input(Tx0))#endpoint_tx_input{source_valid = true}),
    Tx1 = Captured#endpoint_tx_output.state,
    Packet = Captured#endpoint_tx_output.packet,
    [begin
        BadCredit = tx(Tx1, (tx_input(Tx1))#endpoint_tx_input{data_tx_ready = true,
            credit_valid = true, credit_packet = packet(binding(), Sequence)}),
        ?assertEqual(invalid, BadCredit#endpoint_tx_output.status),
        no_tx_transfer(BadCredit),
        ?assertNot((BadCredit#endpoint_tx_output.state)#endpoint_tx_state.active)
    end || Sequence <- [0, 1, 2]],
    [begin
        BadData = rx(Rx0, (rx_input(Rx0))#endpoint_rx_input{data_valid = true,
            data_packet = packet(binding(), Sequence), destination_ready = true}),
        ?assertEqual(invalid, BadData#endpoint_rx_output.status),
        no_rx_transfer(BadData),
        ?assertNot((BadData#endpoint_rx_output.state)#endpoint_rx_state.active)
    end || Sequence <- [0, 2]],
    Rx1 = (rx(Rx0, (rx_input(Rx0))#endpoint_rx_input{data_valid = true,
        data_packet = Packet}))#endpoint_rx_output.state,
    Rx2 = (rx(Rx1, (rx_input(Rx1))#endpoint_rx_input{destination_ready = true}))#endpoint_rx_output.state,
    [begin
        Premature = rx(Held, (rx_input(Held))#endpoint_rx_input{data_valid = true,
            data_packet = packet(binding(), 2), destination_ready = true, ack_tx_ready = true}),
        ?assertEqual(invalid, Premature#endpoint_rx_output.status),
        no_rx_transfer(Premature),
        ?assertNot((Premature#endpoint_rx_output.state)#endpoint_rx_state.active),
        Closed = Premature#endpoint_rx_output.state,
        Drain = rx(Closed, (rx_input(Closed))#endpoint_rx_input{data_valid = true,
            data_packet = packet(binding(), 2)}),
        ?assert(Drain#endpoint_rx_output.data_drop),
        ?assertNot(Drain#endpoint_rx_output.destination_valid)
    end || Held <- [Rx1, Rx2]],
    ok.


%% One consumed RX bind must not strand a still-unbound TX after both domains restart.
-spec partial_bind_generation_gap_test() -> ok.
partial_bind_generation_gap_test() ->
    Old = binding(),
    Rx0 = (rx(hls_domain_channel_rx:new(), rx_bind(Old)))#endpoint_rx_output.state,
    Rx1 = (rx(Rx0, (rx_input(Rx0))#endpoint_rx_input{op = fence, binding = Old}))#endpoint_rx_output.state,
    Fresh = Old#endpoint_binding{generation = 2, source_incarnation = 11, destination_incarnation = 21},
    Receive = rx(Rx1, rx_bind(Fresh)),
    Send = tx(hls_domain_channel_tx:new(), tx_bind(Fresh)),
    ?assertEqual(accepted, Receive#endpoint_rx_output.status),
    ?assertEqual(accepted, Send#endpoint_tx_output.status),
    ?assertEqual(Fresh, (Receive#endpoint_rx_output.state)#endpoint_rx_state.binding),
    ?assertEqual(Fresh, (Send#endpoint_tx_output.state)#endpoint_tx_state.binding),
    OldData = rx(Receive#endpoint_rx_output.state,
        (rx_input(Receive#endpoint_rx_output.state))#endpoint_rx_input{data_valid = true,
            data_packet = packet(Old, 1)}),
    ?assert(OldData#endpoint_rx_output.data_drop),
    ?assertNot(OldData#endpoint_rx_output.data_take).

%% Gaps never waive namespace, both-incarnation freshness, nonzero or exhaustion checks.
-spec monotonic_generation_gap_bounds_test() -> ok.
monotonic_generation_gap_bounds_test() ->
    Old = binding(),
    Gap = Old#endpoint_binding{generation = 100, source_incarnation = 11, destination_incarnation = 21},
    ?assertEqual(accepted, binding_status(Gap, Old)),
    [begin ?assertEqual(stale, binding_status(Bad, Old)) end || Bad <- [
        Gap#endpoint_binding{generation = 0}, Gap#endpoint_binding{generation = 1},
        Gap#endpoint_binding{namespace = 8}, Gap#endpoint_binding{source_incarnation = 10},
        Gap#endpoint_binding{destination_incarnation = 20}]],
    ?assertEqual(stale, binding_status(Gap#endpoint_binding{generation = 0}, #endpoint_binding{})),
    Max = (1 bsl 64) - 1,
    Last = Gap#endpoint_binding{generation = Max},
    ?assertEqual(accepted, binding_status(Last, Old#endpoint_binding{generation = Max - 1})),
    ?assertEqual(exhausted, binding_status(Gap, Old#endpoint_binding{generation = Max})),
    {Tx0, Rx0} = bound(),
    ?assertEqual(stale, (tx(Tx0, tx_bind(Gap#endpoint_binding{destination_incarnation = 20})))#endpoint_tx_output.status),
    ?assertEqual(stale, (rx(Rx0, rx_bind(Gap#endpoint_binding{source_incarnation = 10})))#endpoint_rx_output.status).
