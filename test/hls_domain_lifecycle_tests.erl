-module(hls_domain_lifecycle_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").

%% Cold reset leaves the domain unbound and admission closed.
-spec cold_start_test() -> ok.
cold_start_test() ->
    S = hls_domain_lifecycle:new(),
    ?assertEqual(unbound, S#domain_state.phase),
    ?assertNot(hls_domain_lifecycle:admitted(0, S)),
    ?assertNot(hls_domain_lifecycle:admitted(1, S)),
    ?assertEqual(none, hls_domain_lifecycle:action(S)).

%% Only matching fence, reset and initialization acknowledgements publish the requested incarnation.
-spec acknowledged_incarnation_test() -> ok.
acknowledged_incarnation_test() ->
    I = command(activate, 0, 7, 11),
    O1 = hls_domain_lifecycle:step(I, hls_domain_lifecycle:new()),
    ?assertEqual(accepted, O1#domain_output.status),
    ?assertEqual(fence, O1#domain_output.action),
    ?assertNot(O1#domain_output.admit),
    O2 = hls_domain_lifecycle:step(I, O1#domain_output.state),
    ?assertEqual(replay, O2#domain_output.status),
    ?assertEqual(O1#domain_output.state, O2#domain_output.state),
    ?assertEqual(fence, O2#domain_output.action),
    O3 = hls_domain_lifecycle:step(I#domain_input{op = fenced}, O2#domain_output.state),
    ?assertEqual(reset, O3#domain_output.action),
    ?assertEqual(0, (O3#domain_output.state)#domain_state.current),
    O4 = hls_domain_lifecycle:step(I#domain_input{op = reset_done}, O3#domain_output.state),
    ?assertEqual(initialize, O4#domain_output.action),
    ?assertEqual(7, (O4#domain_output.state)#domain_state.current),
    ?assertNot(O4#domain_output.admit),
    O5 = hls_domain_lifecycle:step(I#domain_input{op = initialized}, O4#domain_output.state),
    ?assertEqual(completed, O5#domain_output.status),
    ?assertEqual(publish, O5#domain_output.action),
    ?assert(O5#domain_output.admit),
    ?assert(hls_domain_lifecycle:admitted(7, O5#domain_output.state)),
    ?assertNot(hls_domain_lifecycle:admitted(6, O5#domain_output.state)),
    O6 = hls_domain_lifecycle:step(I, O5#domain_output.state),
    ?assertEqual(replay, O6#domain_output.status),
    ?assertEqual(none, O6#domain_output.action),
    ?assertEqual(O5#domain_output.state, O6#domain_output.state).

%% First fault is sticky and a failed initializer cannot become ready through a delayed acknowledgement.
-spec fault_and_failed_initialization_test() -> ok.
fault_and_failed_initialization_test() ->
    Ready = ready(7),
    Fault = #domain_input{op = fault, expected = 7, fault = lifecycle_failure},
    Failed = (hls_domain_lifecycle:step(Fault, Ready))#domain_output.state,
    ?assertEqual(failed, Failed#domain_state.phase),
    ?assertEqual(7, Failed#domain_state.current),
    ?assertEqual(lifecycle_failure, Failed#domain_state.fault),
    ?assertNot(hls_domain_lifecycle:admitted(7, Failed)),
    Again = (hls_domain_lifecycle:step(Fault#domain_input{fault = protocol_failure}, Failed))#domain_output.state,
    ?assertEqual(Failed, Again),
    Replace = command(replace, 7, 8, 12),
    Closing = (hls_domain_lifecycle:step(Replace, Failed))#domain_output.state,
    Isolated = complete(fenced, Closing),
    Initializing = complete(reset_done, Isolated),
    ?assertEqual(none, Initializing#domain_state.fault),
    ?assertEqual(8, Initializing#domain_state.current),
    InitFault = Fault#domain_input{expected = 8, fault = initialization_failure},
    InitFailed = (hls_domain_lifecycle:step(InitFault, Initializing))#domain_output.state,
    ?assertEqual(failed, InitFailed#domain_state.phase),
    ?assertEqual(8, InitFailed#domain_state.current),
    ?assertEqual(initialization_failure, InitFailed#domain_state.fault),
    LateAck = hls_domain_lifecycle:step(ack(initialized, InitFailed), InitFailed),
    ?assertEqual(stale, LateAck#domain_output.status),
    ?assertNot(LateAck#domain_output.admit),
    ?assertEqual(InitFailed, LateAck#domain_output.state),
    Retry = hls_domain_lifecycle:step(command(replace, 8, 9, 13), InitFailed),
    ?assertEqual(accepted, Retry#domain_output.status).

%% Conflicting, stale and out-of-phase inputs preserve the current transition.
-spec stale_and_conflicting_transition_test() -> ok.
stale_and_conflicting_transition_test() ->
    Ready = ready(1),
    Replace = command(replace, 1, 2, 3),
    Closing = (hls_domain_lifecycle:step(Replace, Ready))#domain_output.state,
    Busy = hls_domain_lifecycle:step(Replace#domain_input{target = 3}, Closing),
    ?assertEqual(busy, Busy#domain_output.status),
    ?assertEqual(Closing, Busy#domain_output.state),
    WrongAck = ack(fenced, Closing),
    Stale = hls_domain_lifecycle:step(WrongAck#domain_input{transition = 4}, Closing),
    ?assertEqual(stale, Stale#domain_output.status),
    ?assertEqual(Closing, Stale#domain_output.state),
    WrongPhase = hls_domain_lifecycle:step(ack(initialized, Closing), Closing),
    ?assertEqual(stale, WrongPhase#domain_output.status),
    ?assertEqual(Closing, WrongPhase#domain_output.state),
    NewReady = complete(initialized,
        complete(reset_done, complete(fenced, Closing))),
    Newer = (hls_domain_lifecycle:step(command(replace, 2, 3, 4), NewReady))#domain_output.state,
    Old = hls_domain_lifecycle:step(Replace, Newer),
    ?assertEqual(stale, Old#domain_output.status),
    ?assertEqual(Newer, Old#domain_output.state).

%% An abandoned target remains reserved even if its external effects are uncertain.
-spec abort_does_not_reuse_uncertain_incarnation_test() -> ok.
abort_does_not_reuse_uncertain_incarnation_test() ->
    Request = command(activate, 0, 1, 1),
    Closing = (hls_domain_lifecycle:step(Request, hls_domain_lifecycle:new()))#domain_output.state,
    Abort = Request#domain_input{op = abort, fault = lifecycle_failure},
    Failed = (hls_domain_lifecycle:step(Abort, Closing))#domain_output.state,
    ?assertEqual(failed, Failed#domain_state.phase),
    ?assertEqual(0, Failed#domain_state.current),
    ?assertEqual(1, Failed#domain_state.target),
    Repeat = hls_domain_lifecycle:step(Request, Failed),
    ?assertEqual(replay, Repeat#domain_output.status),
    ?assertEqual(none, Repeat#domain_output.action),
    Reuse = hls_domain_lifecycle:step(Request#domain_input{transition = 2}, Failed),
    ?assertEqual(invalid, Reuse#domain_output.status),
    New = hls_domain_lifecycle:step(Request#domain_input{target = 2, transition = 2}, Failed),
    ?assertEqual(accepted, New#domain_output.status),
    ?assertEqual(fence, New#domain_output.action).

%% The largest representable identity cannot wrap or be replaced with a smaller one.
-spec incarnation_exhaustion_test() -> ok.
incarnation_exhaustion_test() ->
    Maximum = (1 bsl 64) - 1,
    Ready = ready(Maximum),
    lists:foreach(fun(Target) ->
        O = hls_domain_lifecycle:step(command(replace, Maximum, Target, 2), Ready),
        ?assertEqual(invalid, O#domain_output.status),
        ?assertEqual(Ready, O#domain_output.state)
    end, [0, Maximum - 1, Maximum]).

%% Exhaust every history through eight inputs over this explicit small alphabet, merging equal states.
%% This is finite Erlang-model exploration, not a proof for all 64-bit inputs or generated hardware.
-spec eight_input_small_alphabet_test() -> ok.
eight_input_small_alphabet_test() ->
    Alphabet = alphabet(),
    {Count, _} = lists:foldl(fun(_, {PriorCount, States}) ->
        Outcomes = [begin
            O = hls_domain_lifecycle:step(I, S),
            ?assert(valid_transition(I, S, O)),
            O#domain_output.state
        end || S <- States, I <- Alphabet],
        {PriorCount + length(Outcomes), lists:usort(Outcomes)}
    end, {0, [hls_domain_lifecycle:new()]}, lists:seq(1, 8)),
    ?assert(Count > 1000).

%% Deliberately violate readiness and stale-state invariants to reject vacuous exploration.
-spec invariant_mutations_reject_test() -> ok.
invariant_mutations_reject_test() ->
    Cold = hls_domain_lifecycle:new(),
    I = command(activate, 0, 1, 1),
    Good = hls_domain_lifecycle:step(I, Cold),
    EarlyState = (Good#domain_output.state)#domain_state{phase = ready, current = 1},
    Early = Good#domain_output{state = EarlyState, admit = true, action = publish},
    ?assertNot(valid_transition(I, Cold, Early)),
    Ready = ready(1),
    StaleInput = command(replace, 9, 2, 3),
    Stale = hls_domain_lifecycle:step(StaleInput, Ready),
    Mutated = Stale#domain_output{state = Ready#domain_state{current = 2}},
    ?assertNot(valid_transition(StaleInput, Ready, Mutated)).

%% Build a finite input without deriving the expected transition from the implementation.
-spec command(hls_domain_lifecycle:operation(), hls_nums:u64(), hls_nums:u64(), hls_nums:u64()) -> hls_domain_lifecycle:input().
command(Op, Old, Target, Transition) ->
    #domain_input{op = Op, expected = Old, target = Target, transition = Transition}.

%% Correlate an explicit completion with all three retained transition identities.
-spec ack(hls_domain_lifecycle:operation(), hls_domain_lifecycle:state()) -> hls_domain_lifecycle:input().
ack(Op, State) ->
    command(Op, State#domain_state.previous, State#domain_state.target, State#domain_state.transition).

%% Apply one requested backend completion in scenario setup.
-spec complete(hls_domain_lifecycle:operation(), hls_domain_lifecycle:state()) -> hls_domain_lifecycle:state().
complete(Op, State) ->
    (hls_domain_lifecycle:step(ack(Op, State), State))#domain_output.state.

%% Construct a ready state through the real acknowledgement sequence.
-spec ready(hls_nums:u64()) -> hls_domain_lifecycle:state().
ready(Incarnation) ->
    First = (hls_domain_lifecycle:step(command(activate, 0, Incarnation, 1),
        hls_domain_lifecycle:new()))#domain_output.state,
    complete(initialized,
        complete(reset_done, complete(fenced, First))).

%% Enumerate the precise small input domain explored to the stated eight-step horizon.
-spec alphabet() -> [hls_domain_lifecycle:input()].
alphabet() ->
    Transitions = [{0, 1, 1}, {1, 2, 2}, {2, 3, 3}],
    [#domain_input{}] ++
    [command(activate, 0, 1, 1), command(activate, 0, 0, 1),
     command(replace, 1, 2, 2), command(replace, 2, 3, 3)] ++
    [#domain_input{op = fault, expected = E, fault = actor_failure} || E <- [1, 2, 3]] ++
    [command(Op, Old, Target, Id) || {Old, Target, Id} <- Transitions,
        Op <- [fenced, reset_done, initialized]] ++
    [(command(abort, Old, Target, Id))#domain_input{fault = initialization_failure}
        || {Old, Target, Id} <- Transitions].

%% Independent edge constraints: identities only install after reset and admission only after setup.
-spec valid_transition(hls_domain_lifecycle:input(), hls_domain_lifecycle:state(), hls_domain_lifecycle:output()) -> boolean().
valid_transition(Input, Before, Output) ->
    After = Output#domain_output.state,
    Admission = Output#domain_output.admit =:=
        (After#domain_state.phase =:= ready andalso After#domain_state.current =/= 0),
    Monotone = After#domain_state.current >= Before#domain_state.current andalso
        After#domain_state.target >= Before#domain_state.target,
    SameOrReset = After#domain_state.current =:= Before#domain_state.current orelse
        (Input#domain_input.op =:= reset_done andalso
            Before#domain_state.phase =:= isolated andalso
            After#domain_state.phase =:= initializing),
    ReadyEdge = After#domain_state.phase =/= ready orelse
        Before#domain_state.phase =:= ready orelse
        (Input#domain_input.op =:= initialized andalso
            Before#domain_state.phase =:= initializing),
    RejectStable = case Output#domain_output.status of
        stale -> After =:= Before;
        invalid -> After =:= Before;
        busy -> After =:= Before;
        _ -> true
    end,
    Publication = Output#domain_output.action =/= publish orelse
        (Output#domain_output.status =:= completed andalso
            Input#domain_input.op =:= initialized),
    Admission andalso Monotone andalso SameOrReset andalso ReadyEdge andalso RejectStable andalso Publication.
