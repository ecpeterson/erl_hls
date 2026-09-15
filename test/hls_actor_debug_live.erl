-module(hls_actor_debug_live).
-export([inspect/3]).

%% Every observation goes through hls_debug:info and the real framed transport.
inspect(Session, Stage, Moment) ->
    case file:read_file(filename:join(Stage, "actor-test")) of
        {error, enoent} -> ok;
        {ok, Bytes} ->
            Kind = case Bytes of <<"small">> -> small; <<"phi">> -> phi; <<"mailbox">> -> mailbox; <<"reduction">> -> reduction; <<"aggregate">> -> aggregate end,
            {Plan, Specs} = hls_actor_debug_dslx:fixture(Kind),
            Catalog = hls_debug_catalog:hardware(Plan, Specs, [], Session),
            Ids = hls_debug_catalog:actors(Catalog),
            Observations = [begin
                {ok, Actor} = hls_debug_catalog:actor(Catalog, Id),
                {capabilities, #{info := Fields}} = hls_debug:info(Actor, capabilities),
                MailboxFields = [mailbox_initialized, message_queue_len, postponed, free_slots, reserved,
                    in_flight, mail_candidate, entry_candidate, waiting_for_egress, egress_busy, scheduler_phase],
                Snapshot = hls_debug:info(Actor,
                    [identity, placement, phase, initialized, enter_pending, failed, failure, cycle] ++
                        [F || F <- MailboxFields, lists:member(F, Fields)], 10000),
                {Id, Actor, maps:from_list(Snapshot)}
            end || Id <- Ids],
            %% Preserve every public snapshot before checking expectations, so
            %% failures retain the other actors' state in the CI artifacts.
            Values = [V || {_, _, V} <- Observations],
            ok = file:write_file(filename:join(Stage, "actors-" ++ atom_to_list(Moment) ++ ".term"),
                io_lib:format("~p.~n", [Values])),
            lists:foreach(fun({Id, Actor, Snapshot}) ->
                true = maps:get(initialized, Snapshot),
                check(Kind, Moment, Id, Snapshot),
                check_mailbox(Actor, Snapshot)
            end, Observations),
            case {Kind, Moment} of
                {mailbox, blocked} ->
                    true = lists:any(fun(#{message_queue_len := N, postponed := P}) -> N =:= 2 andalso P =:= 2 end, Values),
                    true = lists:any(fun(#{egress_busy := Busy, waiting_for_egress := Waiting}) -> Busy andalso Waiting end, Values);
                _ -> ok
            end,
            io:format("PASS: ~p scoped actor snapshots (~p, ~p)~n", [length(Ids), Kind, Moment])
    end.

%% Startup shares finite application queues with the stalled output. A later
%% actor may still be in boot; the released check requires its final outcome.
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
check(mailbox, released, {family, consumer, _}, #{phase := done, failed := false,
        message_queue_len := 0, postponed := 0}) -> ok;
check(mailbox, blocked, {family, producer, _}, #{phase := Phase, failed := false})
        when Phase =:= boot; Phase =:= producer -> ok;
check(mailbox, released, {family, producer, _}, #{phase := producer, failed := false}) -> ok;
check(mailbox, blocked, {family, consumer, _}, #{phase := waiting, failed := false}) -> ok;
check(Placement, _, {family, cell, [1, 0]}, #{phase := done, failed := false, failure := none})
        when Placement =:= reduction; Placement =:= aggregate -> ok;
check(Placement, _, {family, cell, [Slot, 0]}, #{phase := gathering, failed := true,
        enter_pending := false, failure := #{kind := Kind, file := <<"hls_reduction_failure_fixture.erl">>, line := Line}})
        when Placement =:= reduction; Placement =:= aggregate ->
    Expected = case Slot of
        0 -> {badarith, 45};
        2 -> {case_clause, 46};
        3 -> {match_failure, 47};
        4 -> {if_clause, 53}
    end,
    Expected = {Kind, Line},
    ok;
check(phi, _, _, #{failed := false, failure := none}) -> ok;
check(Kind, Moment, Id, Snapshot) -> error({actor_snapshot, Kind, Moment, Id, Snapshot}).

check_mailbox(Actor, #{mailbox_initialized := true, message_queue_len := N,
        free_slots := Free, reserved := 0, postponed := Postponed}) ->
    {mailbox_capacity, Capacity} = hls_debug:info(Actor, mailbox_capacity),
    true = N + Free =:= Capacity,
    true = Postponed =< N;
check_mailbox(_, #{mailbox_initialized := false}) -> error(mailbox_not_initialized);
check_mailbox(_, _) -> ok.
