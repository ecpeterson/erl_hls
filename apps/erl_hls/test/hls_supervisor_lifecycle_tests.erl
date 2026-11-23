-module(hls_supervisor_lifecycle_tests).
-moduledoc "Finite transition witnesses for compiled static supervision; backend completion observations are explicit test inputs.".
-include_lib("eunit/include/eunit.hrl").
-include_lib("hls_runtime/include/hls_supervisor_lifecycle.hrl").

%% Initial starts are ordered and do not consume the restart-intensity allowance.
-spec ordered_startup_and_one_for_one_test() -> ok.
ordered_startup_and_one_for_one_test() ->
    S0 = start(2, 2, 10, 100, 110),
    #supervisor_output{command_valid = false, child = #supervisor_child{phase = fresh}} = tick(S0, #supervisor_child{}, #domain_state{}, 1, 0),
    {S1, A, DA} = boot(S0, #supervisor_child{}, #domain_state{}, 0, 0),
    ?assertEqual(starting, S1#supervisor_state.phase),
    {S2, B, DB} = boot(S1, #supervisor_child{}, #domain_state{}, 1, 0),
    ?assertEqual(running, S2#supervisor_state.phase),
    ?assertEqual(0, S2#supervisor_state.count),
    ?assertEqual({100,101}, {DA#domain_state.current, DB#domain_state.current}),
    {S3, A1, DA1} = boot(S2, A, fail(DA), 0, 2),
    ?assertEqual(102, DA1#domain_state.current),
    ?assertEqual(1, S3#supervisor_state.count),
    #supervisor_output{child = B, command_valid = false} = tick(S3, B, DB, 1, 2),
    ?assertEqual(running, A1#supervisor_child.phase).

%% An earlier child's exit during later synchronous startup is handled after startup, as OTP queues it.
-spec initialized_child_failure_waits_for_startup_test() -> ok.
initialized_child_failure_waits_for_startup_test() ->
    {S1,A,DA} = boot(start(2,2,10,10,30), #supervisor_child{}, #domain_state{}, 0, 0),
    #supervisor_output{state = Waiting, child = A, command_valid = false} = tick(S1,A,fail(DA),0,1),
    ?assertEqual(S1#supervisor_state{last_time = 1}, Waiting),
    {S2,_B,_DB} = boot(Waiting,#supervisor_child{},#domain_state{},1,1),
    {S3,_A1,DA1} = boot(S2,A,fail(DA),0,1),
    ?assertEqual(running,S3#supervisor_state.phase),
    ?assertEqual(1,S3#supervisor_state.count),
    ?assertEqual(12,DA1#domain_state.current).

%% Failed starts before the supervisor becomes ready stop all initialized children.
-spec initialization_failure_stops_subtree_test() -> ok.
initialization_failure_stops_subtree_test() ->
    {S1,A,DA} = boot(start(2, 3, 10, 10, 30), #supervisor_child{}, #domain_state{}, 0, 0),
    O = tick(S1, #supervisor_child{}, #domain_state{}, 1, 0),
    B = O#supervisor_output.child,
    DB = #domain_state{phase = failed, current = 11, target = 11, transition = 11},
    F = tick(O#supervisor_output.state, B, DB, 1, 1),
    ?assertEqual(initialization_failure, (F#supervisor_output.state)#supervisor_state.reason),
    ?assertEqual(stop, (F#supervisor_output.command)#domain_input.op),
    #supervisor_output{state = SF, child = BF} = retire(F#supervisor_output.state, F#supervisor_output.child, DB, 1, 1),
    #supervisor_output{state = Done} = retire(SF, A, DA, 0, 1),
    ?assertEqual(failed, Done#supervisor_state.phase),
    ?assertEqual(retired, BF#supervisor_child.phase),
    ?assertEqual(0, Done#supervisor_state.count).

%% Restarts from all children share one inclusive OTP-style time window.
-spec intensity_includes_boundary_and_other_children_test() -> ok.
intensity_includes_boundary_and_other_children_test() ->
    {S0,A,DA,B,DB} = pair(2, 10),
    {S1,A1,DA1} = boot(S0, A, fail(DA), 0, 1),
    {S2,B1,DB1} = boot(S1, B, fail(DB), 1, 2),
    F = tick(S2, A1, fail(DA1), 0, 11),
    ?assertEqual(intensity_exhausted, (F#supervisor_output.state)#supervisor_state.reason),
    ?assertNot(F#supervisor_output.command_valid),
    #supervisor_output{state = S3} = retire(F#supervisor_output.state, B1, DB1, 1, 11),
    #supervisor_output{state = S4} = retire(S3, F#supervisor_output.child, fail(DA1), 0, 11),
    ?assertEqual(failed, S4#supervisor_state.phase).

%% An expired oldest restart may be replaced; an invocation at the same timestamp remains finite.
-spec restart_window_expires_test() -> ok.
restart_window_expires_test() ->
    {S0,A,DA} = boot(start(1, 1, 10, 20, 40), #supervisor_child{}, #domain_state{}, 0, 0),
    {S1,A1,DA1} = boot(S0, A, fail(DA), 0, 1),
    {S2,A2,DA2} = boot(S1, A1, fail(DA1), 0, 12),
    ?assertEqual(running, S2#supervisor_state.phase),
    ?assertEqual(1, S2#supervisor_state.count),
    F = tick(S2, A2, fail(DA2), 0, 12),
    ?assertEqual(intensity_exhausted, (F#supervisor_output.state)#supervisor_state.reason).

%% An identity interval is consumed once and exhaustion never wraps or reuses an incarnation.
-spec finite_grant_exhaustion_test() -> ok.
finite_grant_exhaustion_test() ->
    {S,A,DA} = boot(start(1, 3, 10, 25, 25), #supervisor_child{}, #domain_state{}, 0, 0),
    F = tick(S, A, fail(DA), 0, 1),
    ?assertEqual(identities_exhausted, (F#supervisor_output.state)#supervisor_state.reason),
    ?assertEqual(26, (F#supervisor_output.state)#supervisor_state.next),
    ?assertEqual(stop, (F#supervisor_output.command)#domain_input.op).

%% Lost command acceptance repeats the exact reserved tuple; completion edges are not starved.
-spec stable_command_until_acceptance_test() -> ok.
stable_command_until_acceptance_test() ->
    S = start(1, 1, 10, 30, 40),
    A = tick(S, #supervisor_child{}, #domain_state{}, 0, 0),
    B = tick(A#supervisor_output.state, A#supervisor_output.child, #domain_state{}, 0, 0),
    ?assertEqual(A#supervisor_output.command, B#supervisor_output.command),
    ?assertEqual(A#supervisor_output.state, B#supervisor_output.state),
    #domain_output{state = Accepted} = hls_domain_lifecycle:step(A#supervisor_output.command, #domain_state{}),
    C = tick(B#supervisor_output.state, B#supervisor_output.child, Accepted, 0, 0),
    ?assertNot(C#supervisor_output.command_valid).

%% Exact repeated grants are observational and stale stop/grant inputs cannot change running policy.
-spec duplicate_grant_and_stale_stop_test() -> ok.
duplicate_grant_and_stale_stop_test() ->
    {S,A,_DA} = boot(start(1, 2, 10, 40, 60), #supervisor_child{}, #domain_state{}, 0, 0),
    Input = (grant(1,2,10,40,60))#supervisor_input{child = A},
    ?assertMatch(#supervisor_output{status = replay, state = S}, hls_supervisor_lifecycle:step(Input, S)),
    ?assertMatch(#supervisor_output{status = stale, state = S}, hls_supervisor_lifecycle:step(Input#supervisor_input{first = 39}, S)),
    ?assertMatch(#supervisor_output{status = stale, state = S}, hls_supervisor_lifecycle:step(Input#supervisor_input{op = stop, epoch = 99}, S)).

%% Registered observation lag cannot hide a startup already sent toward the child.
-spec stop_after_emitted_start_retains_ownership_test() -> ok.
stop_after_emitted_start_retains_ownership_test() ->
    S = start(1, 2, 10, 50, 60),
    O = tick(S, #supervisor_child{}, #domain_state{}, 0, 0),
    #supervisor_output{state = Stopping} = hls_supervisor_lifecycle:step(
        #supervisor_input{op = stop, epoch = 7}, O#supervisor_output.state),
    Lag = tick(Stopping, O#supervisor_output.child, #domain_state{}, 0, 1),
    ?assertEqual(O#supervisor_output.command, Lag#supervisor_output.command),
    ?assert(Lag#supervisor_output.command_valid),
    ?assertEqual(0, (Lag#supervisor_output.state)#supervisor_state.retired),
    #domain_output{state = Accepted} = hls_domain_lifecycle:step(O#supervisor_output.command, #domain_state{}),
    #supervisor_output{state = Done} = retire(Lag#supervisor_output.state,
        Lag#supervisor_output.child, complete(Accepted), 0, 1),
    ?assertEqual(stopped, Done#supervisor_state.phase).

%% A pending accepted startup cannot be discarded; its eventual ready incarnation is stopped.
-spec stop_during_initialization_waits_for_retirement_test() -> ok.
stop_during_initialization_waits_for_retirement_test() ->
    S = start(1, 2, 10, 50, 60),
    O = tick(S, #supervisor_child{}, #domain_state{}, 0, 0),
    D = #domain_state{phase = initializing, current = 50, target = 50, transition = 50},
    #supervisor_output{state = Stopping} = hls_supervisor_lifecycle:step(#supervisor_input{op = stop, epoch = 7}, O#supervisor_output.state),
    Wait = tick(Stopping, O#supervisor_output.child, D, 0, 1),
    ?assertNot(Wait#supervisor_output.command_valid),
    ?assertEqual(stopping, (Wait#supervisor_output.state)#supervisor_state.phase),
    #supervisor_output{state = Done} = retire(Wait#supervisor_output.state, Wait#supervisor_output.child, D#domain_state{phase = ready}, 0, 1),
    ?assertEqual(stopped, Done#supervisor_state.phase).

%% A command never accepted by the synchronous child boundary can be suppressed without inventing a fence.
-spec stop_before_first_start_test() -> ok.
stop_before_first_start_test() ->
    S = start(2, 0, 10, 60, 70),
    #supervisor_output{state = Stopping} = hls_supervisor_lifecycle:step(#supervisor_input{op = stop, epoch = 7}, S),
    #supervisor_output{state = Stopping} = tick(Stopping, #supervisor_child{}, #domain_state{}, 0, 0),
    #supervisor_output{state = S1} = tick(Stopping, #supervisor_child{}, #domain_state{}, 1, 0),
    #supervisor_output{state = Done, command_valid = false} = tick(S1, #supervisor_child{}, #domain_state{}, 0, 0),
    ?assertEqual(stopped, Done#supervisor_state.phase),
    ?assertEqual(60, Done#supervisor_state.next).

%% Restart initialization failures consume intensity instead of looping without bound.
-spec failed_restart_attempt_counts_test() -> ok.
failed_restart_attempt_counts_test() ->
    {S,A,DA} = boot(start(1,1,10,70,90), #supervisor_child{}, #domain_state{}, 0, 0),
    R = tick(S, A, fail(DA), 0, 1),
    FailedAttempt = #domain_state{phase = failed, current = 71, target = 71, transition = 71},
    F = tick(R#supervisor_output.state, R#supervisor_output.child, FailedAttempt, 0, 1),
    ?assertEqual(intensity_exhausted, (F#supervisor_output.state)#supervisor_state.reason).

%% A lost or exhausted local timebase cannot grant an unbounded restart allowance.
-spec clock_failure_stops_subtree_test() -> ok.
clock_failure_stops_subtree_test() ->
    {S,A,DA} = boot(start(1,2,10,80,90), #supervisor_child{}, #domain_state{}, 0, 5),
    F = tick(S, A, DA, 0, 4),
    ?assertEqual(clock_failure, (F#supervisor_output.state)#supervisor_state.reason),
    ?assertEqual(stop, (F#supervisor_output.command)#domain_input.op).

%% Malformed finite grants and an unsupported intensity are refused before any child command.
-spec invalid_configuration_test() -> ok.
invalid_configuration_test() ->
    S = hls_supervisor_lifecycle:new(),
    [begin
        O = hls_supervisor_lifecycle:step(I, S),
        ?assertEqual(invalid, O#supervisor_output.status),
        ?assertEqual(S, O#supervisor_output.state),
        ?assertNot(O#supervisor_output.command_valid)
    end || I <- [(grant(0,1,10,1,2)), (grant(1,17,10,1,2)), (grant(1,1,0,1,2)),
        (grant(1,1,10,0,2)), (grant(1,1,10,3,2)), (grant(1,1,10,1,((1 bsl 64)-1)))]], ok.

%% Two initialized child values make shared-budget behavior independent of scheduler timing.
-spec pair(non_neg_integer(), pos_integer()) -> tuple().
pair(Intensity, Period) ->
    {S1,A,DA} = boot(start(2,Intensity,Period,100,200), #supervisor_child{}, #domain_state{}, 0, 0),
    {S2,B,DB} = boot(S1, #supervisor_child{}, #domain_state{}, 1, 0),
    {S2,A,DA,B,DB}.

%% Tests install one immutable nonzero supervisor incarnation.
-spec grant(non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) -> #supervisor_input{}.
grant(Children, Intensity, Period, First, Last) ->
    #supervisor_input{op = start, epoch = 7, children = Children, intensity = Intensity,
        period = Period, first = First, last = Last}.

%% Starting policy itself emits no actor command until the first selected observation.
-spec start(pos_integer(), non_neg_integer(), pos_integer(), pos_integer(), pos_integer()) -> #supervisor_state{}.
start(Children, Intensity, Period, First, Last) ->
    #supervisor_output{status = accepted, state = S} = hls_supervisor_lifecycle:step(
        grant(Children,Intensity,Period,First,Last), hls_supervisor_lifecycle:new()), S.

%% Every test observation is current and commands directly reach the selected lifecycle.
-spec tick(#supervisor_state{}, #supervisor_child{}, #domain_state{}, non_neg_integer(), non_neg_integer()) -> #supervisor_output{}.
tick(S,C,D,Slot,Now) -> hls_supervisor_lifecycle:step(
    #supervisor_input{slot = Slot, now = Now, child = C, observed = D}, S).

%% Backend acknowledgements in this unit model certify the requested phase immediately.
-spec boot(#supervisor_state{}, #supervisor_child{}, #domain_state{}, non_neg_integer(), non_neg_integer()) -> {#supervisor_state{},#supervisor_child{},#domain_state{}}.
boot(S,C,D,Slot,Now) ->
    O = tick(S,C,D,Slot,Now),
    true = O#supervisor_output.command_valid,
    #domain_output{state = Accepted} = hls_domain_lifecycle:step(O#supervisor_output.command, D),
    Ready = complete(Accepted),
    R = tick(O#supervisor_output.state, O#supervisor_output.child, Ready, Slot, Now),
    {R#supervisor_output.state,R#supervisor_output.child,Ready}.

%% Three separate acknowledgements establish the ready phase; elapsed time supplies none.
-spec complete(#domain_state{}) -> #domain_state{}.
complete(D) ->
    lists:foldl(fun(Op, S) ->
        #domain_output{state = Next} = hls_domain_lifecycle:step(#domain_input{
            op = Op, expected = S#domain_state.previous, target = S#domain_state.target,
            transition = S#domain_state.transition}, S), Next
    end, D, [fenced, reset_done, initialized]).

%% A first source failure leaves the exact current identity observable.
-spec fail(#domain_state{}) -> #domain_state{}.
fail(D) ->
    #domain_output{state = Failed} = hls_domain_lifecycle:step(#domain_input{
        op = fault, expected = D#domain_state.current, fault = actor_failure}, D), Failed.

%% Only an actual fenced acknowledgement allows the supervisor to count a live child as retired.
-spec retire(#supervisor_state{}, #supervisor_child{}, #domain_state{}, non_neg_integer(), non_neg_integer()) -> #supervisor_output{}.
retire(S,C,D,Slot,Now) ->
    O = tick(S,C,D,Slot,Now),
    #domain_output{state = Closing} = hls_domain_lifecycle:step(O#supervisor_output.command,D),
    #domain_output{state = Stopped} = hls_domain_lifecycle:step(#domain_input{
        op = fenced, expected = Closing#domain_state.previous, target = Closing#domain_state.target,
        transition = Closing#domain_state.transition},Closing),
    tick(O#supervisor_output.state,O#supervisor_output.child,Stopped,Slot,Now).
