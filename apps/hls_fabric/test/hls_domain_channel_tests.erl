-module(hls_domain_channel_tests).
-moduledoc "Finite channel ownership witnesses; transport and lifecycle observations are explicit inputs, not physical reset evidence.".
-include_lib("eunit/include/eunit.hrl").
-include_lib("hls_fabric/include/hls_domain_channel.hrl").

%% Each accepted handshake has a distinct edge, including credit return and next source capture.
-spec held_data_and_credit_test() -> ok.
held_data_and_credit_test() ->
    S0 = bound(10, 20),
    Capture = step(S0, (input(S0))#channel_input{source_valid = true, data_tx_ready = true}),
    ?assert(Capture#channel_output.source_take),
    ?assertNot(Capture#channel_output.tx_valid),
    ?assertEqual({1, 1}, {Capture#channel_output.generation, Capture#channel_output.sequence}),
    S1 = Capture#channel_output.state,
    [begin
        Hold = step(S1, (input(S1))#channel_input{source_valid = true}),
        ?assert(Hold#channel_output.tx_valid),
        ?assertNot(Hold#channel_output.source_take),
        ?assertEqual(S1, Hold#channel_output.state)
    end || _ <- lists:seq(1, 4)],
    Tx = step(S1, (input(S1))#channel_input{data_tx_ready = true}),
    ?assert(Tx#channel_output.tx_valid),
    S2 = Tx#channel_output.state,
    Blocked = step(S2, data(S2)),
    ?assert(Blocked#channel_output.destination_valid),
    ?assertNot(Blocked#channel_output.data_ready),
    ?assertNot(Blocked#channel_output.destination_take),
    ?assertEqual(S2, Blocked#channel_output.state),
    Receive = step(S2, (data(S2))#channel_input{destination_ready = true, ack_tx_ready = true}),
    ?assert(Receive#channel_output.destination_take),
    ?assertNot(Receive#channel_output.ack_valid),
    S3 = Receive#channel_output.state,
    Early = step(S3, credit(S3)),
    ?assert(Early#channel_output.ack_valid),
    ?assert(Early#channel_output.credit_drop),
    ?assertEqual(S3, Early#channel_output.state),
    Ack = step(S3, (credit(S3))#channel_input{ack_tx_ready = true}),
    ?assert(Ack#channel_output.ack_valid),
    ?assert(Ack#channel_output.credit_drop),
    S4 = Ack#channel_output.state,
    ?assert(S4#channel_state.inflight),
    Release = step(S4, (credit(S4))#channel_input{source_valid = true}),
    ?assert(Release#channel_output.credit_ready),
    ?assertNot(Release#channel_output.credit_drop),
    ?assertNot(Release#channel_output.source_take),
    S5 = Release#channel_output.state,
    ?assertNot(S5#channel_state.inflight),
    Next = step(S5, (input(S5))#channel_input{source_valid = true}),
    ?assert(Next#channel_output.source_take),
    ?assertEqual(2, Next#channel_output.sequence).

%% Stale, duplicate and prematurely returned traffic cannot capture or release ownership.
-spec stale_duplicate_and_premature_packets_test() -> ok.
stale_duplicate_and_premature_packets_test() ->
    S0 = captured(),
    Premature = step(S0, (data(S0))#channel_input{destination_ready = true,
        credit_valid = true, credit_generation = 1, credit_sequence = 1}),
    ?assert(Premature#channel_output.data_drop),
    ?assert(Premature#channel_output.credit_drop),
    ?assertNot(Premature#channel_output.destination_take),
    ?assertEqual(S0, Premature#channel_output.state),
    S1 = (step(S0, (input(S0))#channel_input{data_tx_ready = true}))#channel_output.state,
    [begin
        Dropped = step(S1, Bad),
        ?assert(Dropped#channel_output.data_ready),
        ?assert(Dropped#channel_output.data_drop),
        ?assertNot(Dropped#channel_output.destination_valid),
        ?assertEqual(S1, Dropped#channel_output.state)
    end || Bad <- [(data(S1))#channel_input{data_generation = 0},
        (data(S1))#channel_input{data_sequence = 0}, (data(S1))#channel_input{data_sequence = 2}]],
    S2 = (step(S1, (data(S1))#channel_input{destination_ready = true}))#channel_output.state,
    Duplicate = step(S2, (data(S2))#channel_input{destination_ready = true}),
    ?assert(Duplicate#channel_output.data_drop),
    ?assertNot(Duplicate#channel_output.destination_take),
    ?assertEqual(S2, Duplicate#channel_output.state),
    S3 = (step(S2, (input(S2))#channel_input{ack_tx_ready = true}))#channel_output.state,
    WrongCredit = step(S3, (credit(S3))#channel_input{credit_generation = 2}),
    ?assert(WrongCredit#channel_output.credit_drop),
    ?assertEqual(S3, WrongCredit#channel_output.state),
    S4 = (step(S3, credit(S3)))#channel_output.state,
    DuplicateCredit = step(S4, credit(S4)),
    ?assert(DuplicateCredit#channel_output.credit_drop),
    ?assertEqual(S4, DuplicateCredit#channel_output.state).

%% Every in-flight phase can be fenced without a last data or credit transfer on that edge.
-spec fence_each_packet_phase_test() -> ok.
fence_each_packet_phase_test() ->
    S0 = captured(),
    S1 = (step(S0, (input(S0))#channel_input{data_tx_ready = true}))#channel_output.state,
    S2 = (step(S1, (data(S1))#channel_input{destination_ready = true}))#channel_output.state,
    S3 = (step(S2, (input(S2))#channel_input{ack_tx_ready = true}))#channel_output.state,
    [begin
        Fenced = step(S, (all_ready(S))#channel_input{op = fence, expected_generation = 1}),
        ?assertEqual(accepted, Fenced#channel_output.status),
        no_transfer(Fenced),
        Closed = Fenced#channel_output.state,
        ?assertEqual({false, false, false, false, false}, flags(Closed)),
        ?assertEqual({10, 20, 1, 1}, identities(Closed)),
        Drain = step(Closed, all_ready(Closed)),
        ?assert(Drain#channel_output.data_ready),
        ?assert(Drain#channel_output.data_drop),
        ?assert(Drain#channel_output.credit_ready),
        ?assert(Drain#channel_output.credit_drop),
        ?assertNot(Drain#channel_output.destination_take),
        ?assertNot(Drain#channel_output.source_take)
    end || S <- [S0, S1, S2, S3]], ok.

%% Current endpoint observations fence before a coincident source, receiver or credit handshake.
-spec endpoint_loss_or_identity_change_test() -> ok.
endpoint_loss_or_identity_change_test() ->
    S0 = captured(),
    S = (step(S0, (input(S0))#channel_input{data_tx_ready = true}))#channel_output.state,
    Base = all_ready(S),
    [begin
        Closed = step(S, Bad),
        ?assertEqual(closed, Closed#channel_output.status),
        no_transfer(Closed),
        ?assertEqual({false, false, false, false, false}, flags(Closed#channel_output.state)),
        ?assertEqual(identities(S), identities(Closed#channel_output.state))
    end || Bad <- [Base#channel_input{source_ready = false},
        Base#channel_input{destination_live = false}, Base#channel_input{source_incarnation = 11},
        Base#channel_input{destination_incarnation = 21}]], ok.

%% A fresh destination alone cannot reinterpret the old source's untagged outbox.
-spec explicit_fresh_pair_rebind_test() -> ok.
explicit_fresh_pair_rebind_test() ->
    S0 = captured(),
    Bad = step(S0, (input(S0))#channel_input{op = bind, expected_generation = 1, destination_incarnation = 21}),
    ?assertEqual(stale, Bad#channel_output.status),
    ?assertNot((Bad#channel_output.state)#channel_state.active),
    no_transfer(Bad),
    Closed = Bad#channel_output.state,
    StaleControl = step(Closed, (input(Closed))#channel_input{op = bind, expected_generation = 0,
        source_incarnation = 11, destination_incarnation = 21}),
    ?assertEqual(stale, StaleControl#channel_output.status),
    ?assertEqual(Closed, StaleControl#channel_output.state),
    Bound = step(Closed, (all_ready(Closed))#channel_input{op = bind, expected_generation = 1,
        source_incarnation = 11, destination_incarnation = 21}),
    ?assertEqual(accepted, Bound#channel_output.status),
    no_transfer(Bound),
    S1 = Bound#channel_output.state,
    ?assertEqual({11, 21, 2, 0}, identities(S1)),
    ?assertEqual({true, false, false, false, false}, flags(S1)),
    Old = step(S1, (input(S1))#channel_input{data_valid = true, data_generation = 1, data_sequence = 1,
        credit_valid = true, credit_generation = 1, credit_sequence = 1, destination_ready = true}),
    ?assert(Old#channel_output.data_drop),
    ?assert(Old#channel_output.credit_drop),
    ?assertNot(Old#channel_output.destination_take),
    ?assertEqual(S1, Old#channel_output.state).

%% Repeated bindings are not reconnection and a stale fence cannot close a valid current binding.
-spec invalid_binding_and_stale_fence_test() -> ok.
invalid_binding_and_stale_fence_test() ->
    Cold = hls_domain_channel:new(),
    ZeroPair = step(Cold, #channel_input{op = bind, source_ready = true, destination_live = true}),
    ?assertEqual(stale, ZeroPair#channel_output.status),
    ?assertEqual(Cold, ZeroPair#channel_output.state),
    Unready = step(Cold, #channel_input{op = bind, source_incarnation = 10, destination_incarnation = 20}),
    ?assertEqual(busy, Unready#channel_output.status),
    ?assertEqual(Cold, Unready#channel_output.state),
    S = bound(10, 20),
    Repeated = step(S, (input(S))#channel_input{op = bind, expected_generation = 1}),
    ?assertEqual(stale, Repeated#channel_output.status),
    ?assertEqual(S, Repeated#channel_output.state),
    StaleFence = step(S, (all_ready(S))#channel_input{op = fence, expected_generation = 0}),
    ?assertEqual(stale, StaleFence#channel_output.status),
    ?assertEqual(S, StaleFence#channel_output.state),
    no_transfer(StaleFence),
    Lost = step(S, (input(S))#channel_input{op = fence, expected_generation = 0, source_ready = false}),
    ?assertEqual(stale, Lost#channel_output.status),
    ?assertNot((Lost#channel_output.state)#channel_state.active).

%% Sequence exhaustion waits for the last packet's completion and never wraps to an old packet ID.
-spec sequence_exhaustion_test() -> ok.
sequence_exhaustion_test() ->
    S0 = (bound(10, 20))#channel_state{sequence = ((1 bsl 32) - 2)},
    Last = step(S0, (input(S0))#channel_input{source_valid = true}),
    ?assert(Last#channel_output.source_take),
    ?assertEqual(((1 bsl 32) - 1), Last#channel_output.sequence),
    S1 = Last#channel_output.state,
    ?assert((step(S1, (input(S1))#channel_input{source_valid = true}))#channel_output.tx_valid),
    S2 = (step(S1, (input(S1))#channel_input{data_tx_ready = true}))#channel_output.state,
    S3 = (step(S2, (data(S2))#channel_input{destination_ready = true}))#channel_output.state,
    S4 = (step(S3, (input(S3))#channel_input{ack_tx_ready = true}))#channel_output.state,
    S5 = (step(S4, credit(S4)))#channel_output.state,
    Exhausted = step(S5, (all_ready(S5))#channel_input{source_valid = true}),
    ?assertEqual(exhausted, Exhausted#channel_output.status),
    ?assertEqual(((1 bsl 32) - 1), (Exhausted#channel_output.state)#channel_state.sequence),
    ?assertNot((Exhausted#channel_output.state)#channel_state.active),
    no_transfer(Exhausted),
    Fresh = step(Exhausted#channel_output.state, #channel_input{op = bind, expected_generation = 1,
        source_ready = true, destination_live = true, source_incarnation = 11, destination_incarnation = 21}),
    ?assertEqual({accepted, 2, 0}, {Fresh#channel_output.status, Fresh#channel_output.generation, Fresh#channel_output.sequence}).

%% The last channel generation may run, but no subsequent pair can acquire a wrapped namespace.
-spec generation_exhaustion_test() -> ok.
generation_exhaustion_test() ->
    S = (bound(10, 20))#channel_state{generation = ((1 bsl 64) - 1)},
    Exhausted = step(S, (all_ready(S))#channel_input{op = bind, expected_generation = ((1 bsl 64) - 1),
        source_incarnation = 11, destination_incarnation = 21}),
    ?assertEqual(exhausted, Exhausted#channel_output.status),
    ?assertEqual({10, 20, ((1 bsl 64) - 1), 0}, identities(Exhausted#channel_output.state)),
    ?assertNot((Exhausted#channel_output.state)#channel_state.active),
    no_transfer(Exhausted).

%% Two independent directed channels carry no global credit or reset coupling.
-spec unaffected_channel_test() -> ok.
unaffected_channel_test() ->
    A = captured(),
    C = bound(30, 40),
    _ = step(A, (input(A))#channel_input{destination_live = false}),
    Progress = step(C, (input(C))#channel_input{source_valid = true}),
    ?assert(Progress#channel_output.source_take),
    ?assert((Progress#channel_output.state)#channel_state.active).

%% A fixture binding is explicitly accepted; no ready observation opens a channel by itself.
-spec bound(pos_integer(), pos_integer()) -> #channel_state{}.
bound(Source, Destination) ->
    #channel_output{status = accepted, state = State} = hls_domain_channel:step(
        #channel_input{op = bind, source_incarnation = Source, destination_incarnation = Destination,
            source_ready = true, destination_live = true}, hls_domain_channel:new()), State.

%% One source frame has been captured but not yet transmitted.
-spec captured() -> #channel_state{}.
captured() ->
    State = bound(10, 20),
    (step(State, (input(State))#channel_input{source_valid = true}))#channel_output.state.

%% Every fixture tick supplies exact current endpoint observations.
-spec input(#channel_state{}) -> #channel_input{}.
input(State) -> #channel_input{source_incarnation = State#channel_state.source_incarnation,
    destination_incarnation = State#channel_state.destination_incarnation, source_ready = true, destination_live = true}.

%% Data arrives with the one current packet identity and independent mailbox readiness.
-spec data(#channel_state{}) -> #channel_input{}.
data(State) -> (input(State))#channel_input{data_valid = true,
    data_generation = State#channel_state.generation, data_sequence = State#channel_state.sequence}.

%% Returning credit must carry the same channel generation and packet sequence.
-spec credit(#channel_state{}) -> #channel_input{}.
credit(State) -> (input(State))#channel_input{credit_valid = true,
    credit_generation = State#channel_state.generation, credit_sequence = State#channel_state.sequence}.

%% Coincident readiness deliberately challenges the no-transfer lifecycle priority.
-spec all_ready(#channel_state{}) -> #channel_input{}.
all_ready(State) -> (data(State))#channel_input{source_valid = true, data_tx_ready = true,
    destination_ready = true, ack_tx_ready = true, credit_valid = true,
    credit_generation = State#channel_state.generation, credit_sequence = State#channel_state.sequence}.

%% The pure kernel alone receives the ordered stimulus in these tests.
-spec step(#channel_state{}, #channel_input{}) -> #channel_output{}.
step(State, Input) -> hls_domain_channel:step(Input, State).

%% Control/fence edges must not read or write either transport or application endpoint.
-spec no_transfer(#channel_output{}) -> ok.
no_transfer(Output) ->
    ?assertEqual({false, false, false, false, false, false, false},
        {Output#channel_output.source_take, Output#channel_output.tx_valid,
         Output#channel_output.data_ready, Output#channel_output.destination_valid,
         Output#channel_output.destination_take, Output#channel_output.ack_valid,
         Output#channel_output.credit_ready}).

%% The five ownership flags are asserted together to catch partial cancellation.
-spec flags(#channel_state{}) -> {boolean(), boolean(), boolean(), boolean(), boolean()}.
flags(State) -> {State#channel_state.active, State#channel_state.inflight, State#channel_state.received,
    State#channel_state.tx_pending, State#channel_state.ack_pending}.

%% Fencing preserves both endpoint tombstones and all packet namespace counters.
-spec identities(#channel_state{}) -> {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}.
identities(State) -> {State#channel_state.source_incarnation, State#channel_state.destination_incarnation,
    State#channel_state.generation, State#channel_state.sequence}.
