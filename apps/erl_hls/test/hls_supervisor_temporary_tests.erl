-module(hls_supervisor_temporary_tests).
-moduledoc "Finite temporary-occupancy witnesses; explicit backend acknowledgements and reusable observations delimit retirement.".
-include_lib("eunit/include/eunit.hrl").
-include_lib("hls_runtime/include/hls_supervisor_lifecycle.hrl").

%% Explicit dormant templates consume no identity and are distinct from ordinary temporary specs.
-spec dormant_templates_and_initial_temporary_test() -> ok.
dormant_templates_and_initial_temporary_test() ->
    S0 = grant(2, 100, 110),
    Waiting = tick(S0, #supervisor_child{}, #domain_state{}, 0, false),
    ?assertEqual(S0, Waiting#supervisor_output.state),
    A = tick(S0, #supervisor_child{}, #domain_state{}, 0, true),
    ?assertEqual(vacant, (A#supervisor_output.child)#supervisor_child.phase),
    B = tick(A#supervisor_output.state, #supervisor_child{}, #domain_state{}, 1, true),
    ?assertEqual(running, (B#supervisor_output.state)#supervisor_state.phase),
    ?assertEqual(100, (B#supervisor_output.state)#supervisor_state.next),
    ?assertEqual(0, (B#supervisor_output.state)#supervisor_state.count),
    Initial = hls_supervisor_lifecycle:step(
        (input(#supervisor_child{}, #domain_state{}, 0))#supervisor_input{dormant = false}, grant(1, 100, 110)),
    ?assertEqual(starting, (Initial#supervisor_output.child)#supervisor_child.phase),
    ?assertEqual(100, (Initial#supervisor_output.command)#domain_input.target),
    ?assert(Initial#supervisor_output.command_valid).

%% Selected-slot reservation serializes admission without sharing one occupant between callers.
-spec concurrent_admission_capacity_and_unaffected_sibling_test() -> ok.
concurrent_admission_capacity_and_unaffected_sibling_test() ->
    {S0, Empty} = dormant(2, 100, 110),
    First = request(start_child, S0, Empty, #domain_state{}, 0),
    Again = request(start_child, First#supervisor_output.state, First#supervisor_output.child, #domain_state{}, 0),
    ?assertEqual(busy, Again#supervisor_output.status),
    ?assertEqual(First#supervisor_output.state, Again#supervisor_output.state),
    OldRequest = (input(First#supervisor_output.child, #domain_state{}, 0))#supervisor_input{
        op = start_child, expected_child = 0},
    ?assertMatch(#supervisor_output{status = busy}, hls_supervisor_lifecycle:step(OldRequest, First#supervisor_output.state)),
    {S1, A, DA} = ready(First, #domain_state{}, 0),
    {S2, B, DB} = ready(request(start_child, S1, Empty, #domain_state{}, 1), #domain_state{}, 1),
    ?assertEqual({100, 101}, {A#supervisor_child.target, B#supervisor_child.target}),
    ?assertMatch(#supervisor_output{status = busy, state = S2}, request(start_child, S2, A, DA, 0)),
    ?assertMatch(#supervisor_output{state = S2, child = B, command_valid = false}, tick(S2, B, DB, 1, false)).

%% Stopping does not release capacity until both the exact core and transport have retired.
-spec retirement_gate_reuse_and_stale_control_test() -> ok.
retirement_gate_reuse_and_stale_control_test() ->
    {S0, Empty} = dormant(1, 100, 110),
    {S1, A, DA} = ready(request(start_child, S0, Empty, #domain_state{}, 0), #domain_state{}, 0),
    Stop = request(stop_child, S1, A, DA, 0),
    ?assertEqual(accepted, Stop#supervisor_output.status),
    Stopped = stop_core(Stop, DA),
    Waiting = tick(S1, Stop#supervisor_output.child, Stopped, 0, false),
    ?assertEqual(retiring, (Waiting#supervisor_output.child)#supervisor_child.phase),
    ?assertMatch(#supervisor_output{status = busy}, request(start_child, S1, Waiting#supervisor_output.child, Stopped, 0)),
    Vacant = tick(S1, Waiting#supervisor_output.child, Stopped, 0, true),
    Tombstone = Vacant#supervisor_output.child,
    ?assertEqual({vacant, 100}, {Tombstone#supervisor_child.phase, Tombstone#supervisor_child.target}),
    Blocked = (input(Tombstone, Stopped, 0))#supervisor_input{op = start_child, reusable = false},
    ?assertMatch(#supervisor_output{status = busy, state = S1}, hls_supervisor_lifecycle:step(Blocked, S1)),
    Stale = Blocked#supervisor_input{reusable = true, expected_child = 0},
    ?assertMatch(#supervisor_output{status = stale, state = S1}, hls_supervisor_lifecycle:step(Stale, S1)),
    {S2, B, DB} = ready(request(start_child, S1, Tombstone, Stopped, 0), Stopped, 0),
    ?assertEqual(101, B#supervisor_child.target),
    OldStop = (input(B, DB, 0))#supervisor_input{op = stop_child, expected_child = 100},
    ?assertMatch(#supervisor_output{status = stale, state = S2}, hls_supervisor_lifecycle:step(OldStop, S2)),
    ?assertMatch(#domain_output{status = stale, state = DB}, hls_domain_lifecycle:step(
        #domain_input{op = fault, expected = 100, fault = actor_failure}, DB)).

%% Temporary faults retire once and never spend a restart timestamp or fresh identity.
-spec fault_does_not_restart_test() -> ok.
fault_does_not_restart_test() ->
    {S0, Empty} = dormant(1, 100, 110),
    {S1, A, DA} = ready(request(start_child, S0, Empty, #domain_state{}, 0), #domain_state{}, 0),
    #domain_output{state = Failed} = hls_domain_lifecycle:step(
        #domain_input{op = fault, expected = 100, fault = actor_failure}, DA),
    Retire = tick(S1, A, Failed, 0, false),
    ?assertEqual(stop, (Retire#supervisor_output.command)#domain_input.op),
    ?assertEqual(S1, Retire#supervisor_output.state),
    Stopped = stop_core(Retire, Failed),
    Vacant = tick(S1, Retire#supervisor_output.child, Stopped, 0, true),
    ?assertEqual(vacant, (Vacant#supervisor_output.child)#supervisor_child.phase),
    ?assertEqual({101, 0}, {S1#supervisor_state.next, S1#supervisor_state.count}),
    ?assertNot(Vacant#supervisor_output.command_valid).

%% Failed explicit initialization affects only its occupancy, while initial startup remains atomic.
-spec admission_failure_and_initial_failure_test() -> ok.
admission_failure_and_initial_failure_test() ->
    {S0, Empty} = dormant(1, 100, 110),
    Admission = request(start_child, S0, Empty, #domain_state{}, 0),
    A = Admission#supervisor_output.child,
    Failed = #domain_state{phase = failed, current = 100, target = 100, transition = 100},
    Retire = tick(Admission#supervisor_output.state, A, Failed, 0, true),
    ?assertEqual(running, (Retire#supervisor_output.state)#supervisor_state.phase),
    ?assertEqual(0, (Retire#supervisor_output.state)#supervisor_state.count),
    ?assertEqual(stop, (Retire#supervisor_output.command)#domain_input.op),
    Stopped = stop_core(Retire, Failed),
    ?assertEqual(vacant, ((tick(Retire#supervisor_output.state, Retire#supervisor_output.child, Stopped, 0, true))#supervisor_output.child)#supervisor_child.phase),
    FirstFailure = Failed#domain_state{current = 0},
    ?assertEqual(vacant, ((tick(Admission#supervisor_output.state, A, FirstFailure, 0, true))#supervisor_output.child)#supervisor_child.phase),
    Initial = hls_supervisor_lifecycle:step(
        (input(#supervisor_child{}, #domain_state{}, 0))#supervisor_input{dormant = false}, grant(1, 100, 110)),
    Shutdown = hls_supervisor_lifecycle:step(
        (input(Initial#supervisor_output.child, Failed, 0))#supervisor_input{dormant = false},
        Initial#supervisor_output.state),
    ?assertEqual(stopping, (Shutdown#supervisor_output.state)#supervisor_state.phase),
    ?assertEqual(initialization_failure, (Shutdown#supervisor_output.state)#supervisor_state.reason).

%% Stop requests retain an admitted but not-yet-observed start, then retire its eventual incarnation.
-spec stop_during_admission_test() -> ok.
stop_during_admission_test() ->
    {S0, Empty} = dormant(1, 100, 110),
    Admission = request(start_child, S0, Empty, #domain_state{}, 0),
    S1 = Admission#supervisor_output.state,
    Stop = request(stop_child, S1, Admission#supervisor_output.child, #domain_state{}, 0),
    ?assertEqual(accepted, Stop#supervisor_output.status),
    ?assertEqual(Admission#supervisor_output.command, Stop#supervisor_output.command),
    #domain_output{state = Accepted} = hls_domain_lifecycle:step(Stop#supervisor_output.command, #domain_state{}),
    Initializing = Accepted#domain_state{phase = initializing, current = 100},
    Wait = tick(S1, Stop#supervisor_output.child, Initializing, 0, true),
    ?assertNot(Wait#supervisor_output.command_valid),
    Ready = complete(Accepted),
    Retire = tick(S1, Wait#supervisor_output.child, Ready, 0, true),
    Stopped = stop_core(Retire, Ready),
    ?assertEqual(vacant, ((tick(S1, Retire#supervisor_output.child, Stopped, 0, true))#supervisor_output.child)#supervisor_child.phase).

%% Subtree shutdown counts vacant slots once, in reverse order, and waits for admitted starts.
-spec parent_shutdown_during_admission_test() -> ok.
parent_shutdown_during_admission_test() ->
    {S0, Empty} = dormant(2, 100, 110),
    Admission = request(start_child, S0, Empty, #domain_state{}, 0),
    #supervisor_output{state = Closing} = hls_supervisor_lifecycle:step(
        #supervisor_input{op = stop, epoch = 7}, Admission#supervisor_output.state),
    BeforeTurn = tick(Closing, Admission#supervisor_output.child, #domain_state{}, 0, true),
    ?assertNot(BeforeTurn#supervisor_output.command_valid),
    EmptyDone = tick(Closing, Empty, #domain_state{}, 1, true),
    ?assertEqual(1, (EmptyDone#supervisor_output.state)#supervisor_state.retired),
    Again = tick(EmptyDone#supervisor_output.state, EmptyDone#supervisor_output.child, #domain_state{}, 1, true),
    ?assertEqual(EmptyDone#supervisor_output.state, Again#supervisor_output.state),
    Pending = tick(Again#supervisor_output.state, Admission#supervisor_output.child, #domain_state{}, 0, true),
    ?assertEqual(Admission#supervisor_output.command, Pending#supervisor_output.command),
    #domain_output{state = Accepted} = hls_domain_lifecycle:step(Pending#supervisor_output.command, #domain_state{}),
    Ready = complete(Accepted),
    Retire = tick(Pending#supervisor_output.state, Pending#supervisor_output.child, Ready, 0, true),
    Stopped = stop_core(Retire, Ready),
    Done = tick(Retire#supervisor_output.state, Retire#supervisor_output.child, Stopped, 0, false),
    ?assertEqual({stopped, 2}, {(Done#supervisor_output.state)#supervisor_state.phase, (Done#supervisor_output.state)#supervisor_state.retired}).

%% Optional work may exhaust its grant without stopping another occupied slot or wrapping IDs.
-spec identity_exhaustion_keeps_sibling_test() -> ok.
identity_exhaustion_keeps_sibling_test() ->
    {S0, Empty} = dormant(2, 100, 100),
    {S1, A, DA} = ready(request(start_child, S0, Empty, #domain_state{}, 0), #domain_state{}, 0),
    Exhausted = request(start_child, S1, Empty, #domain_state{}, 1),
    ?assertEqual(exhausted, Exhausted#supervisor_output.status),
    ?assertEqual(S1, Exhausted#supervisor_output.state),
    ?assertEqual(Empty, Exhausted#supervisor_output.child),
    ?assertNot(Exhausted#supervisor_output.command_valid),
    ?assertMatch(#supervisor_output{state = S1, child = A, command_valid = false}, tick(S1, A, DA, 0, false)),
    {NearEnd, Empty2} = dormant(1, ((1 bsl 64) - 2), ((1 bsl 64) - 2)),
    Last = request(start_child, NearEnd, Empty2, #domain_state{}, 0),
    ?assertEqual(((1 bsl 64) - 1), (Last#supervisor_output.state)#supervisor_state.next).

%% Wrong parent, slot policy and stale vacancy cannot mutate the grant; no timeout frees a slot.
-spec invalid_requests_and_observations_test() -> ok.
invalid_requests_and_observations_test() ->
    {S, Empty} = dormant(1, 100, 110),
    Base = (input(Empty, #domain_state{}, 0))#supervisor_input{op = start_child},
    [begin
        #supervisor_output{status = Status, state = S, child = Empty, command_valid = false} =
            hls_supervisor_lifecycle:step(I, S)
    end || {Status, I} <- [{stale, Base#supervisor_input{epoch = 8}},
        {invalid, Base#supervisor_input{slot = 1}},
        {invalid, Base#supervisor_input{policy = permanent}},
        {stale, Base#supervisor_input{expected_child = 99}},
        {busy, Base#supervisor_input{reusable = false}}]],
    O = request(start_child, S, Empty, #domain_state{}, 0),
    FakeOldStopped = #domain_state{phase = stopped, current = 99, target = 99},
    Wait = tick(O#supervisor_output.state, (O#supervisor_output.child)#supervisor_child{phase = retiring}, FakeOldStopped, 0, true),
    ?assertNot(Wait#supervisor_output.command_valid),
    ?assertEqual(retiring, (Wait#supervisor_output.child)#supervisor_child.phase).

%% Explicit child commands cannot bypass the monotonic-clock guard used by ordinary scans.
-spec child_request_clock_guard_test() -> ok.
child_request_clock_guard_test() ->
    {S0, Empty} = dormant(2, 100, 110),
    State = S0#supervisor_state{last_time = 9},
    Base = (input(Empty, #domain_state{}, 0))#supervisor_input{op = start_child, now = 8},
    Bad = hls_supervisor_lifecycle:step(Base, State),
    ?assertEqual(invalid, Bad#supervisor_output.status),
    ?assertEqual({stopping, clock_failure, 100}, {(Bad#supervisor_output.state)#supervisor_state.phase,
        (Bad#supervisor_output.state)#supervisor_state.reason, (Bad#supervisor_output.state)#supervisor_state.next}),
    ?assertNot(Bad#supervisor_output.command_valid),
    Exhausted = hls_supervisor_lifecycle:step(Base#supervisor_input{now = ((1 bsl 64) - 1)}, State),
    ?assertEqual(clock_failure, (Exhausted#supervisor_output.state)#supervisor_state.reason),
    Valid = hls_supervisor_lifecycle:step(Base#supervisor_input{now = 10}, State),
    ?assertEqual(accepted, Valid#supervisor_output.status),
    ?assertEqual(10, (Valid#supervisor_output.state)#supervisor_state.last_time),
    Stop = hls_supervisor_lifecycle:step((input(Valid#supervisor_output.child, #domain_state{}, 0))#supervisor_input{
        op = stop_child, now = 9}, Valid#supervisor_output.state),
    ?assertEqual(invalid, Stop#supervisor_output.status),
    ?assertEqual(clock_failure, (Stop#supervisor_output.state)#supervisor_state.reason).

%% An unresolved abort before reset never becomes proof that the reserved occupant retired.
-spec abort_before_reset_retains_uncertainty_test() -> ok.
abort_before_reset_retains_uncertainty_test() ->
    {S0, Empty} = dormant(1, 100, 110),
    {S1, A, DA} = ready(request(start_child, S0, Empty, #domain_state{}, 0), #domain_state{}, 0),
    Stop = request(stop_child, S1, A, DA, 0),
    Stopped = stop_core(Stop, DA),
    Vacant = tick(S1, Stop#supervisor_output.child, Stopped, 0, true),
    Admission = request(start_child, S1, Vacant#supervisor_output.child, Stopped, 0),
    #domain_output{state = Accepted} = hls_domain_lifecycle:step(Admission#supervisor_output.command, Stopped),
    #domain_output{state = Failed} = hls_domain_lifecycle:step(#domain_input{op = abort,
        expected = 100, target = 101, transition = 101, fault = lifecycle_failure}, Accepted),
    Retiring = tick(Admission#supervisor_output.state, Admission#supervisor_output.child, Failed, 0, true),
    ?assertEqual(retiring, (Retiring#supervisor_output.child)#supervisor_child.phase),
    ?assertNot(Retiring#supervisor_output.command_valid),
    ?assertMatch(#supervisor_output{status = busy}, request(start_child, Retiring#supervisor_output.state,
        Retiring#supervisor_output.child, Failed, 0)),
    ImpossibleEmptyFailure = #domain_state{phase = failed},
    ?assertMatch(#supervisor_output{status = busy, state = S0}, request(start_child, S0, Empty, ImpossibleEmptyFailure, 0)).

%% Each fixture grant has one exact parent epoch and a zero restart allowance.
-spec grant(pos_integer(), pos_integer(), pos_integer()) -> #supervisor_state{}.
grant(Count, First, Last) ->
    #supervisor_output{status = accepted, state = S} = hls_supervisor_lifecycle:step(
        #supervisor_input{op = start, epoch = 7, children = Count, first = First, last = Last, period = 10},
        hls_supervisor_lifecycle:new()), S.

%% Every template is explicitly initially absent; all scans carry immutable slot metadata.
-spec dormant(pos_integer(), pos_integer(), pos_integer()) -> {#supervisor_state{}, #supervisor_child{}}.
dormant(Count, First, Last) ->
    S = lists:foldl(fun(Slot, State) ->
        (tick(State, #supervisor_child{}, #domain_state{}, Slot, true))#supervisor_output.state
    end, grant(Count, First, Last), lists:seq(0, Count - 1)),
    {S, #supervisor_child{phase = vacant}}.

%% Reusable is an explicit backend certificate in these finite input witnesses.
-spec input(#supervisor_child{}, #domain_state{}, non_neg_integer()) -> #supervisor_input{}.
input(Child, Core, Slot) ->
    #supervisor_input{epoch = 7, slot = Slot, policy = temporary, dormant = true,
        reusable = true, expected_child = Child#supervisor_child.target, child = Child, observed = Core}.

%% Observations advance one selected slot without sending an external command.
-spec tick(#supervisor_state{}, #supervisor_child{}, #domain_state{}, non_neg_integer(), boolean()) -> #supervisor_output{}.
tick(State, Child, Core, Slot, Reusable) ->
    hls_supervisor_lifecycle:step((input(Child, Core, Slot))#supervisor_input{reusable = Reusable}, State).

%% Start and stop requests name the observed slot incarnation and exact parent.
-spec request(start_child | stop_child, #supervisor_state{}, #supervisor_child{}, #domain_state{}, non_neg_integer()) -> #supervisor_output{}.
request(Op, State, Child, Core, Slot) ->
    hls_supervisor_lifecycle:step((input(Child, Core, Slot))#supervisor_input{op = Op}, State).

%% Complete accepted startup with three distinct explicit backend acknowledgements.
-spec ready(#supervisor_output{}, #domain_state{}, non_neg_integer()) -> {#supervisor_state{}, #supervisor_child{}, #domain_state{}}.
ready(Output, Core, Slot) ->
    accepted = Output#supervisor_output.status,
    #domain_output{state = Accepted} = hls_domain_lifecycle:step(Output#supervisor_output.command, Core),
    Ready = complete(Accepted),
    Observed = tick(Output#supervisor_output.state, Output#supervisor_output.child, Ready, Slot, false),
    {Observed#supervisor_output.state, Observed#supervisor_output.child, Ready}.

%% Backend completion timing is synthetic; this helper claims no physical reset behavior.
-spec complete(Core :: #domain_state{}) -> #domain_state{}.
complete(Core) ->
    lists:foldl(fun(Op, State) ->
        #domain_output{state = Next} = hls_domain_lifecycle:step(#domain_input{op = Op,
            expected = State#domain_state.previous, target = State#domain_state.target,
            transition = State#domain_state.transition}, State), Next
    end, Core, [fenced, reset_done, initialized]).

%% A stop command needs a matching fence acknowledgement before core retirement exists.
-spec stop_core(#supervisor_output{}, #domain_state{}) -> #domain_state{}.
stop_core(Output, Core) ->
    #domain_output{state = Closing} = hls_domain_lifecycle:step(Output#supervisor_output.command, Core),
    #domain_output{state = Stopped} = hls_domain_lifecycle:step(#domain_input{op = fenced,
        expected = Closing#domain_state.previous, target = Closing#domain_state.target,
        transition = Closing#domain_state.transition}, Closing), Stopped.
