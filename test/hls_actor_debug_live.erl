-module(hls_actor_debug_live).
-export([inspect/3, await_completed/2]).

%% Releasing ingress is not an actor-completion fence. Synchronize this test
%% through the same public observations a host diagnostic would use, rather
%% than relying on simulator-internal state or a pipeline-specific sleep.
await_completed(Session, Kind) ->
    {Plan, Specs} = hls_actor_debug_dslx:fixture(Kind),
    Catalog = hls_debug_catalog:hardware(Plan, Specs, [], Session),
    lists:foreach(fun(Id = {family, cell, [Slot, 0]}) ->
        {ok, Actor} = hls_debug_catalog:actor(Catalog, Id),
        Expected = case Slot of 1 -> [{failed, false}, {phase, done}]; _ -> [{failed, true}, {phase, gathering}] end,
        await_outcome(Actor, Expected, 100)
    end, hls_debug_catalog:actors(Catalog)).

await_outcome(Actor, Expected, Attempts) ->
    case hls_debug:info(Actor, [Item || {Item, _} <- Expected], 10000) of
        Expected -> ok;
        _ when Attempts > 0 -> await_outcome(Actor, Expected, Attempts - 1);
        Actual -> error({actor_completion_timeout, Expected, Actual})
    end.

%% Every observation goes through hls_debug:info and the real framed transport.
inspect(Session, Stage, Moment) ->
    case file:read_file(filename:join(Stage, "actor-test")) of
        {error, enoent} -> ok;
        {ok, Bytes} ->
            Kind = case Bytes of <<"small">> -> small; <<"phi">> -> phi; <<"mailbox">> -> mailbox; <<"reduction">> -> reduction; <<"direct_reduction">> -> direct_reduction; <<"aggregate">> -> aggregate;
                <<"direct_mailbox">> -> direct_mailbox; <<"mailbox_mixed">> -> mailbox_mixed;
                <<"mixed_direct">> -> {mixed, direct}; <<"mixed_one">> -> {mixed, one};
                <<"mixed_two">> -> {mixed, two}; <<"mixed_coalesced">> -> {mixed, coalesced};
                <<"ingress_direct">> -> {ingress, direct}; <<"ingress_one">> -> {ingress, one};
                <<"ingress_two">> -> {ingress, two}; <<"ingress_coalesced">> -> {ingress, coalesced}
            end,
            {Plan, Specs} = fixture(Kind),
            Catalog = hls_debug_catalog:hardware(Plan, Specs, [], Session),
            Completion = case {Kind, Moment} of
                {{ingress, _}, released} ->
                    %% Completion is signaled by public output handshakes, not
                    %% simulator access to actor state. Preserve diagnostics on
                    %% failure just as for the closed graph's actor fence.
                    try await_application(Stage, 3000)
                    catch Class:Reason:Stack -> {failed, Class, Reason, Stack}
                    end;
                {{mixed, _}, released} ->
                    {ok, Source} = hls_debug_catalog:actor(Catalog, {actor, source}),
                    %% The four placements at two pipeline depths completed
                    %% in 171--202 polls; retain more than twice that budget.
                    try await_outcome(Source,
                        [{failed, false}, {phase, done}, {enter_pending, false}], 512)
                    catch Class:Reason:Stack -> {failed, Class, Reason, Stack}
                    end;
                _ -> ok
            end,
            Ids = hls_debug_catalog:actors(Catalog),
            Observations = [begin
                {ok, Actor} = hls_debug_catalog:actor(Catalog, Id),
                {capabilities, #{info := Fields}} = hls_debug:info(Actor, capabilities),
                MailboxFields = [mailbox_initialized, message_queue_len, postponed, free_slots, reserved,
                    in_flight, mail_candidate, entry_candidate, waiting_for_egress, egress_busy, scheduler_phase],
                case hls_debug:info(Actor, placement) of
                    {placement, #{kind := direct}} ->
                        [] = [mailbox_initialized, message_queue_len, postponed, free_slots, reserved] -- Fields,
                        [] = [F || F <- [in_flight, scheduler_phase, egress_busy], lists:member(F, Fields)];
                    _ -> ok
                end,
                Snapshot = hls_debug:info(Actor,
                    [identity, placement, phase, initialized, enter_pending, failed, failure, reduction, cycle] ++
                        [F || F <- MailboxFields, lists:member(F, Fields)], 10000),
                {Id, Actor, maps:from_list(Snapshot)}
            end || Id <- Ids],
            %% Preserve every public snapshot before checking expectations, so
            %% failures retain the other actors' state in the CI artifacts.
            Values = [V || {_, _, V} <- Observations],
            ok = file:write_file(filename:join(Stage, "actors-" ++ atom_to_list(Moment) ++ ".term"),
                io_lib:format("~p.~n", [Values])),
            case Completion of
                ok -> ok;
                {failed, FailureClass, FailureReason, FailureStack} ->
                    erlang:raise(FailureClass, FailureReason, FailureStack)
            end,
            lists:foreach(fun({Id, Actor, Snapshot}) ->
                true = maps:get(initialized, Snapshot),
                check(Kind, Moment, Id, Snapshot),
                check_mailbox(Actor, Snapshot)
            end, Observations),
            case {Kind, Moment} of
                {K, blocked} when K =:= mailbox; K =:= direct_mailbox; K =:= mailbox_mixed ->
                    true = lists:any(fun(#{message_queue_len := N, postponed := P}) -> N =:= 2 andalso P =:= 2 end, Values),
                    case K of
                        direct_mailbox -> ok;
                        _ -> true = lists:any(fun
                            (#{egress_busy := Busy, waiting_for_egress := Waiting}) -> Busy andalso Waiting;
                            (_) -> false
                        end, Values)
                    end,
                    case K of
                        mailbox -> ok;
                        _ -> true = lists:any(fun
                            (#{placement := #{kind := direct}, message_queue_len := 2,
                                postponed := 2, reserved := 1, free_slots := 0}) -> true;
                            (_) -> false
                        end, Values)
                    end;
                _ -> ok
            end,
            io:format("PASS: ~p scoped actor snapshots (~p, ~p)~n", [length(Ids), Kind, Moment])
    end.

fixture({ingress, _} = Kind) -> hls_mixed_topology_dslx:fixture(Kind);
fixture({mixed, Placement}) -> hls_mixed_topology_dslx:fixture(Placement);
fixture(Kind) -> hls_actor_debug_dslx:fixture(Kind).

%% Startup shares finite application queues with the stalled output. A later
%% actor may still be in boot; the released check requires its final outcome.
check({ingress, _}, Moment, Id, Snapshot) -> check({mixed, direct}, Moment, Id, Snapshot);
check({mixed, _}, released, Id, Snapshot) ->
    ExpectedPhase = case Id of
        {actor, source} -> done;
        {actor, collector} -> reporting;
        _ -> active
    end,
    #{phase := ExpectedPhase, failed := false, failure := none, enter_pending := false} = Snapshot,
    ok;
check({mixed, _}, blocked, _, #{failed := false, failure := none}) -> ok;
check(small, blocked, {family, cell, _}, #{phase := boot, failed := false,
        failure := none}) -> ok;
check(small, _, {family, cell, [Slot, 0]}, #{phase := Phase, failed := true,
        enter_pending := false, failure := #{kind := Kind, file := File, line := Line}})
        when Slot =/= 1, Slot =/= 7, Slot =/= 10, Slot =/= 14, Slot =/= 18 ->
    Expected = case Slot of
        0 -> {active, case_clause, <<"hls_actor_debug_helpers.hrl">>, 7};
        2 -> {active, match_failure, <<"hls_actor_debug_fixture.erl">>, 30};
        3 -> {boot, case_clause, <<"hls_actor_debug_helpers.hrl">>, 7};
        4 -> {boot, explicit_fail, <<"hls_actor_debug_fixture.erl">>, 20};
        5 -> {boot, function_clause, <<"hls_actor_debug_fixture.erl">>, 16};
        6 -> {active, if_clause, <<"hls_actor_debug_helpers.hrl">>, 11};
        8 -> {active, badarith, <<"hls_actor_debug_helpers.hrl">>, 15};
        9 -> {active, badarith, <<"hls_actor_debug_helpers.hrl">>, 19};
        11 -> {active, badarg, <<"hls_actor_debug_helpers.hrl">>, 23};
        12 -> {active, badarg, <<"hls_actor_debug_helpers.hrl">>, 27};
        13 -> {active, badarg, <<"hls_actor_debug_helpers.hrl">>, 32};
        15 -> {active, match_failure, <<"hls_actor_debug_helpers.hrl">>, 38};
        16 -> {active, function_clause, <<"hls_actor_debug_helpers.hrl">>, 42};
        17 -> {active, case_clause, <<"hls_actor_debug_helpers.hrl">>, 47}
    end,
    Expected = {Phase, Kind, File, Line},
    ok;
check(small, released, {family, cell, [Slot, 0]},
        #{phase := active, failed := false, failure := none, enter_pending := false})
        when Slot =:= 1; Slot =:= 7; Slot =:= 10; Slot =:= 14; Slot =:= 18 -> ok;
check(small, blocked, {family, cell, [Slot, 0]}, #{phase := active, failed := false, failure := none})
        when Slot =:= 1; Slot =:= 7; Slot =:= 10; Slot =:= 14; Slot =:= 18 -> ok;
check(Kind, Moment, Id, Snapshot) when Kind =:= direct_mailbox; Kind =:= mailbox_mixed ->
    check(mailbox, Moment, Id, Snapshot);
check(mailbox, released, {family, consumer, _}, #{phase := done, failed := false,
        message_queue_len := 0, postponed := 0}) -> ok;
check(mailbox, blocked, {family, producer, _}, #{phase := Phase, failed := false})
        when Phase =:= boot; Phase =:= producer -> ok;
check(mailbox, released, {family, producer, _}, #{phase := producer, failed := false}) -> ok;
check(mailbox, blocked, {family, consumer, _}, #{phase := waiting, failed := false}) -> ok;
check(direct_reduction, Moment, Id, Snapshot) ->
    %% The same reduction ownership and failure contract holds without a RAM
    %% scheduler. A blocked report has already committed the healthy outcome.
    SharedMoment = case Moment of completed -> released; _ -> Moment end,
    check(reduction, SharedMoment, Id, Snapshot);
check(Placement, blocked, {family, cell, [Slot, 0]}, #{phase := boot, failed := false, reduction := idle})
        when (Placement =:= reduction orelse Placement =:= aggregate), Slot >= 2 -> ok;
check(reduction, blocked, {family, cell, [Slot, 0]}, #{phase := gathering, failed := false, failure := none,
        reduction := #{status := open, phase := gathering, name := sum, key := 0,
            remaining := 1, received := 2, population := {count, 3}, failure := Failure}}) ->
    case Slot of
        0 -> #{kind := badarith, file := <<"hls_reduction_failure_fixture.erl">>, line := 47} = Failure;
        1 -> none = Failure
    end,
    ok;
check(aggregate, blocked, {family, cell, [Slot, 0]}, #{phase := gathering, failed := false, failure := none,
        reduction := #{status := open, remaining := 3, received := 0, failure := none}}) when Slot < 2 -> ok;
check(Placement, released, {family, cell, [1, 0]}, #{phase := done, failed := false, failure := none, reduction := idle})
        when Placement =:= reduction; Placement =:= aggregate -> ok;
check(Placement, released, {family, cell, [Slot, 0]}, #{phase := gathering, failed := true,
        enter_pending := false, failure := Failure = #{kind := Kind, file := <<"hls_reduction_failure_fixture.erl">>, line := Line},
        reduction := #{status := complete, remaining := 0, received := 3, failure := Failure}})
        when Placement =:= reduction; Placement =:= aggregate ->
    Expected = case Slot of
        0 -> {badarith, 47};
        2 -> {case_clause, 48};
        3 -> {match_failure, 49};
        4 -> {if_clause, 55}
    end,
    Expected = {Kind, Line},
    ok;
check(phi, _, _, #{failed := false, failure := none}) -> ok;
check(Kind, Moment, Id, Snapshot) -> error({actor_snapshot, Kind, Moment, Id, Snapshot}).

check_mailbox(Actor, #{mailbox_initialized := true, message_queue_len := N,
        free_slots := Free, reserved := Reserved, postponed := Postponed}) ->
    {mailbox_capacity, Capacity} = hls_debug:info(Actor, mailbox_capacity),
    true = N + Reserved + Free =:= Capacity,
    true = Postponed =< N;
check_mailbox(_, #{mailbox_initialized := false}) -> error(mailbox_not_initialized);
check_mailbox(_, _) -> ok.


await_application(_Stage, 0) -> error(application_completion_timeout);
await_application(Stage, Attempts) ->
    case file:read_file(filename:join(Stage, "application_complete")) of
        {ok, _} -> ok;
        {error, enoent} -> timer:sleep(10), await_application(Stage, Attempts - 1)
    end.
